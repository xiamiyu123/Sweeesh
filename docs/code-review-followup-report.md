# Code Review Report

## Executive summary
- 项目的主要风险并不是“到处都乱”，而是**复杂度高度集中**在少数核心协调器中，尤其是 `Sources/Swooshy/DockGestureController.swift` 与 `Sources/Swooshy/WindowManager.swift`。这类大文件承担了过多职责，后续功能演进很容易继续以条件分支和状态变量叠加的方式增长。
- `Sources/Swooshy/SettingsStore.swift` 已经从“配置存储”演化为“配置 + 联动规则 + 通知分发 + 部分策略控制”的中心节点。这里的风险主要不是 bug 明显，而是**语义隐含、变更放大、测试保护不足**。
- 配置与动作映射层存在一些**低风险但真实存在的可维护性问题**，例如重复定义默认映射、令人困惑但有意保留的 reset 语义、以及关键行为缺少专门回归测试。这些适合在不改变应用行为的前提下优先修复。
- 测试整体上比很多同体量项目更好，但保护主要集中在纯逻辑层；最复杂的运行时协调器缺少同等级直接测试，因此这轮不宜贸然触碰核心行为路径。
- 这轮建议采用“**报告 + 小步安全修复**”策略：只修复可通过测试锁定的低风险问题，暂不做架构性重写。

## High severity

### 1. `DockGestureController.swift` 是明显的高复杂度协调器
**证据**
- `Sources/Swooshy/DockGestureController.swift`
- 文件体量约 2600+ 行，且同时承担：手势识别、悬停区域探测、corner drag、延迟执行、反向取消、HUD 预览、浏览器 tab close 特判、watchdog 恢复等职责。
- 文件内存在大量隐式会话状态字段，例如：`pendingReleaseAction`、`pendingReleaseGestureKind`、`titleBarSessionHoverSource`、`activeCornerDrag*`、`smoothWindowPreviewSession`、`gestureStateWatchdog`。

**为什么危险**
- 新功能很可能继续以“再加一个状态字段 / 条件分支”的方式叠加。
- 状态重置与边界顺序问题容易演变为难以复现的交互 bug。

**这轮处理**
- 不改行为。
- 在报告中列为高风险热点，但 defer 到未来有更强集成测试支撑时再处理。

### 2. `WindowManager.swift` 职责过重且与平台行为深耦合
**证据**
- `Sources/Swooshy/WindowManager.swift`
- 文件体量约 2600+ 行，包含窗口动作执行、frame 应用顺序、AX 读取写入、preview/session、约束学习与持久化、窗口轮换等。
- 既负责策略，又直接负责与系统 Accessibility API 交互。

**为什么危险**
- 行为正确性高度依赖系统窗口与 AX 细节。
- 即使局部重构也容易引入边缘应用/窗口行为回归。

**这轮处理**
- 不改行为。
- 保持只读审查结论，不纳入本轮修复。

### 3. `SettingsStore.swift` 已成为配置、联动和通知的中心耦合点
**证据**
- `Sources/Swooshy/SettingsStore.swift`
- 属性 `didSet` 中同时承担持久化、日志、通知。
- `experimentalBrowserTabCloseEnabled` 在关闭时还会联动关闭 `smartBrowserTabCloseEnabled`。
- `notifyDidChange(_:)` 使用异步 coalescing，语义合理但隐含。

**为什么危险**
- 配置语义分散在多个属性观察器里，新人阅读成本高。
- 多个 UI / 控制器依赖 `.settingsDidChange`，一旦语义误改，影响面很广。

**这轮处理**
- 不改总体结构。
- 只补测试锁定这些现有语义，并收敛局部重复定义。

## Medium severity

### 4. Dock / Title bar 默认手势映射存在重复定义，易漂移
**证据**
- `Sources/Swooshy/DockGestureAction.swift`
- `DockGestureBindings.defaults` 与 `DockGestureBindings.fallbackBinding(for:)` 定义了同一套默认关系。
- `TitleBarGestureBindings.defaults` 与 `TitleBarGestureBindings.fallbackBinding(for:)` 也定义了两份相同规则。

**为什么危险**
- 后续新增或调整默认映射时，容易改一处忘一处。
- 这是典型“现在看着没事，时间久了就漂”的维护问题。

**这轮处理**
- 会修。
- 目标是收敛为单一事实来源，并用回归测试锁定现有顺序与行为。

### 5. reset 语义有意不一致，但缺少足够测试保护
**证据**
- `Sources/Swooshy/SettingsStore.swift:440+`
- `resetPersistedConfiguration(in:)` 明确保留 `experimentalBrowserTabCloseEnabled`。
- `resetAdvancedSettingsToDefaults()` 又会将 `experimentalBrowserTabCloseEnabled` 与 `smartBrowserTabCloseEnabled` 一并关掉。
- `Sources/Swooshy/LaunchOptions.swift` 中 `--reset-user-config` 会触发 `resetPersistedConfiguration(in:)`。

**为什么危险**
- 这不是明显 bug，而是“有意但容易被误解”的语义差异。
- 如果没有测试，后续“顺手统一 reset 行为”很容易误伤产品当前设计。

**这轮处理**
- 会修，但方式是**补测试**，不改变现有语义。

### 6. 配置级联与通知合并行为缺少更精确的回归保护
**证据**
- `SettingsStore.experimentalBrowserTabCloseEnabled` 会触发 `smartBrowserTabCloseEnabled = false`
- `notifyDidChange(_:)` 会合并同步变更
- 当前已有 `coalescesSynchronousSettingsChangeNotifications()`，但对“依赖配置级联”这一具体链路保护不足

**为什么危险**
- 这种 subtle behavior 很容易在重构时被不小心改变。
- 而 UI/控制器层又可能依赖它的当前通知行为。

**这轮处理**
- 会修，以更细粒度测试锁定当前表现。

### 7. `WindowAction` 的权威动作分组需要更强回归保护
**证据**
- `Sources/Swooshy/WindowAction.swift`
- `allCases` 手工维护，`gestureCases` 另外派生。
- `previewBehavior`、`title(...)`、`menuKeyEquivalent` 需要与动作集合保持一致。

**为什么危险**
- 增加新动作时，开发者需要记得改多个位置。
- 如果未来做整理，菜单顺序、可用动作集合、gesture-only 行为都可能被误改。

**这轮处理**
- 条件性处理：仅在能机械化整理时做轻量收敛；否则至少补测试锁定行为。

## Low severity

### 8. CI 对应用真实可运行性的保护较弱
**证据**
- `.github/workflows/ci.yml`
- `swift test --parallel`
- 打包后仅做 3 秒进程存活检查

**影响**
- 能发现明显崩溃，但对资源缺失、初始化异常、弱集成问题保护有限。

**这轮处理**
- 仅记录，不修改工作流。

### 9. Release 流程集成环节较多，维护成本偏高
**证据**
- `.github/workflows/release.yml`
- 包含 release 构建、notes 重写、SSH、tap 仓库发布等多个环节

**影响**
- 运维链路脆弱，但与本轮行为保持不变的代码清理目标无直接关系。

**这轮处理**
- defer。

## Will fix now
1. `SettingsStore` reset 语义测试补强
2. `SettingsStore` 配置级联与通知合并测试补强
3. `SettingsStore` clamp / 边界行为测试补强
4. `DockGestureBindings` / `TitleBarGestureBindings` 默认映射去重
5. `WindowAction` 仅在完全机械化前提下做轻量收敛，否则降级为 tests-only

## Deferred
1. `DockGestureController` 行为/结构整理
2. `WindowManager` 行为/结构整理
3. `NotificationCenter` 事件架构替换
4. `BrowserTabProbe` 启发式策略调整
5. CI / Release 工作流增强

## Appendix: evidence index
- `Sources/Swooshy/DockGestureController.swift`
- `Sources/Swooshy/WindowManager.swift`
- `Sources/Swooshy/SettingsStore.swift`
- `Sources/Swooshy/DockGestureAction.swift`
- `Sources/Swooshy/WindowAction.swift`
- `Sources/Swooshy/LaunchOptions.swift`
- `.github/workflows/ci.yml`
- `.github/workflows/release.yml`
- `Tests/SwooshyTests/SettingsStoreTests.swift`
- `Tests/SwooshyTests/LaunchOptionsTests.swift`
- `Tests/SwooshyTests/WindowActionTests.swift`
