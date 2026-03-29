import AppKit
import Foundation

@MainActor
protocol GestureFeedbackPresenting {
    func show(
        gesture: DockGestureKind,
        gestureTitle: String,
        actionTitle: String,
        anchor: CGPoint?
    )
}

@MainActor
final class GestureFeedbackController: GestureFeedbackPresenting {
    private let settingsStore: SettingsStore
    private let panel: NSPanel
    private let messageLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let glyphView = GestureGlyphView(frame: .zero)
    private let glyphBadgeView = NSView(frame: .zero)
    private var dismissTask: Task<Void, Never>?
    private var hideGeneration: UInt64 = 0
    private var currentStyle: GestureHUDStyle?
    private var currentPanelSize = NSSize(width: 208, height: 42)

    private let verticalOffset: CGFloat = 18
    private let sideMargin: CGFloat = 10
    private let dismissalDelay: UInt64 = 700_000_000

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: currentPanelSize),
            styleMask: [.nonactivatingPanel, .hudWindow, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        configureContent(for: settingsStore.gestureHUDStyle)
    }

    func show(
        gesture: DockGestureKind,
        gestureTitle: String,
        actionTitle: String,
        anchor: CGPoint? = nil
    ) {
        configureContent(for: settingsStore.gestureHUDStyle)
        messageLabel.stringValue = "\(gestureTitle) · \(actionTitle)"
        titleLabel.stringValue = actionTitle
        subtitleLabel.stringValue = gestureTitle
        glyphView.gesture = gesture

        let anchorPoint = anchor ?? NSEvent.mouseLocation
        panel.setFrame(frame(for: anchorPoint), display: false)

        hideGeneration &+= 1
        dismissTask?.cancel()
        panel.orderFrontRegardless()

        panel.animator().alphaValue = 1

        let delay = self.dismissalDelay
        let generation = hideGeneration

        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self?.hide(expectedGeneration: generation)
            }
        }
    }

    private func configureContent(for style: GestureHUDStyle) {
        guard currentStyle != style || panel.contentView == nil else { return }

        currentStyle = style
        panel.hasShadow = style != .minimal
        currentPanelSize = panelSize(for: style)
        panel.setContentSize(currentPanelSize)

        let contentRoot = NSVisualEffectView(frame: NSRect(origin: .zero, size: currentPanelSize))
        contentRoot.material = material(for: style)
        contentRoot.blendingMode = blendingMode(for: style)
        contentRoot.state = .active
        contentRoot.wantsLayer = true
        contentRoot.layer?.cornerRadius = cornerRadius(for: style)
        contentRoot.layer?.masksToBounds = true
        contentRoot.layer?.backgroundColor = backgroundColor(for: style).cgColor
        contentRoot.layer?.borderColor = borderColor(for: style).cgColor
        contentRoot.layer?.borderWidth = borderWidth(for: style)
        contentRoot.translatesAutoresizingMaskIntoConstraints = false

        messageLabel.font = .systemFont(ofSize: 12, weight: .medium)
        messageLabel.textColor = .labelColor
        messageLabel.alignment = .center
        messageLabel.maximumNumberOfLines = 1
        messageLabel.lineBreakMode = .byTruncatingMiddle
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: style == .elegant ? 12 : 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 1
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        glyphView.translatesAutoresizingMaskIntoConstraints = false
        glyphView.glyphStyle = .minimal
        glyphView.primaryColor = glyphColor(for: style)
        glyphView.secondaryColor = glyphSecondaryColor(for: style)
        glyphView.lineWidth = glyphLineWidth(for: style)
        glyphView.glowLineWidth = glyphGlowLineWidth(for: style)

        glyphBadgeView.translatesAutoresizingMaskIntoConstraints = false
        glyphBadgeView.wantsLayer = true
        glyphBadgeView.layer?.cornerRadius = glyphBadgeCornerRadius(for: style)
        glyphBadgeView.layer?.masksToBounds = true
        glyphBadgeView.layer?.backgroundColor = glyphBadgeBackgroundColor(for: style).cgColor
        glyphBadgeView.layer?.borderColor = glyphBadgeBorderColor(for: style).cgColor
        glyphBadgeView.layer?.borderWidth = glyphBadgeBorderWidth(for: style)
        glyphBadgeView.subviews.forEach { $0.removeFromSuperview() }

        switch style {
        case .classic:
            contentRoot.addSubview(messageLabel)
            NSLayoutConstraint.activate([
                messageLabel.leadingAnchor.constraint(equalTo: contentRoot.leadingAnchor, constant: 12),
                messageLabel.trailingAnchor.constraint(equalTo: contentRoot.trailingAnchor, constant: -12),
                messageLabel.topAnchor.constraint(equalTo: contentRoot.topAnchor, constant: 10),
                messageLabel.bottomAnchor.constraint(equalTo: contentRoot.bottomAnchor, constant: -10),
            ])
        case .elegant:
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 10
            row.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
            row.alignment = .centerY
            row.translatesAutoresizingMaskIntoConstraints = false

            let textStack = NSStackView(views: [titleLabel])
            textStack.orientation = .vertical
            textStack.alignment = .leading
            textStack.translatesAutoresizingMaskIntoConstraints = false

            glyphBadgeView.addSubview(glyphView)
            row.addArrangedSubview(glyphBadgeView)
            row.addArrangedSubview(textStack)
            contentRoot.addSubview(row)

            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: contentRoot.leadingAnchor),
                row.trailingAnchor.constraint(equalTo: contentRoot.trailingAnchor),
                row.topAnchor.constraint(equalTo: contentRoot.topAnchor),
                row.bottomAnchor.constraint(equalTo: contentRoot.bottomAnchor),
                glyphBadgeView.widthAnchor.constraint(equalToConstant: 24),
                glyphBadgeView.heightAnchor.constraint(equalToConstant: 24),
                glyphView.centerXAnchor.constraint(equalTo: glyphBadgeView.centerXAnchor),
                glyphView.centerYAnchor.constraint(equalTo: glyphBadgeView.centerYAnchor),
                glyphView.widthAnchor.constraint(equalToConstant: 22),
                glyphView.heightAnchor.constraint(equalToConstant: 22),
            ])
        case .minimal:
            glyphBadgeView.addSubview(glyphView)
            contentRoot.addSubview(glyphBadgeView)

            NSLayoutConstraint.activate([
                glyphBadgeView.centerXAnchor.constraint(equalTo: contentRoot.centerXAnchor),
                glyphBadgeView.centerYAnchor.constraint(equalTo: contentRoot.centerYAnchor),
                glyphBadgeView.widthAnchor.constraint(equalToConstant: 20),
                glyphBadgeView.heightAnchor.constraint(equalToConstant: 20),
                glyphView.centerXAnchor.constraint(equalTo: glyphBadgeView.centerXAnchor),
                glyphView.centerYAnchor.constraint(equalTo: glyphBadgeView.centerYAnchor),
                glyphView.widthAnchor.constraint(equalToConstant: 18),
                glyphView.heightAnchor.constraint(equalToConstant: 18),
            ])
        }

        panel.contentView = contentRoot
        panel.alphaValue = 0
    }

    private func frame(for anchorPoint: CGPoint) -> NSRect {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(anchorPoint) }) ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        let width = currentPanelSize.width
        let height = currentPanelSize.height
        let desiredX = anchorPoint.x - (width / 2)
        let desiredY = anchorPoint.y + verticalOffset

        let minX = visibleFrame.minX + sideMargin
        let maxX = visibleFrame.maxX - width - sideMargin
        let minY = visibleFrame.minY + sideMargin
        let maxY = visibleFrame.maxY - height - sideMargin

        let clampedX = min(max(desiredX, minX), maxX)
        let clampedY = min(max(desiredY, minY), maxY)

        return NSRect(x: clampedX, y: clampedY, width: width, height: height)
    }

    private func hide(expectedGeneration: UInt64) {
        guard expectedGeneration == hideGeneration else { return }

        dismissTask?.cancel()
        dismissTask = nil

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                guard expectedGeneration == self.hideGeneration else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    private func panelSize(for style: GestureHUDStyle) -> NSSize {
        switch style {
        case .classic:
            return NSSize(width: 208, height: 42)
        case .elegant:
            return NSSize(width: 182, height: 40)
        case .minimal:
            return NSSize(width: 40, height: 40)
        }
    }

    private func cornerRadius(for style: GestureHUDStyle) -> CGFloat {
        switch style {
        case .classic:
            return 14
        case .elegant:
            return 12
        case .minimal:
            return 10
        }
    }

    private func backgroundColor(for style: GestureHUDStyle) -> NSColor {
        switch style {
        case .classic, .elegant, .minimal:
            return .clear
        }
    }

    private func borderColor(for style: GestureHUDStyle) -> NSColor {
        switch style {
        case .classic, .elegant, .minimal:
            return .clear
        }
    }

    private func borderWidth(for style: GestureHUDStyle) -> CGFloat {
        switch style {
        case .classic, .elegant, .minimal:
            return 0
        }
    }

    private func material(for style: GestureHUDStyle) -> NSVisualEffectView.Material {
        switch style {
        case .classic, .elegant:
            return .hudWindow
        case .minimal:
            return .hudWindow
        }
    }

    private func blendingMode(for style: GestureHUDStyle) -> NSVisualEffectView.BlendingMode {
        switch style {
        case .classic, .elegant:
            return .behindWindow
        case .minimal:
            return .behindWindow
        }
    }

    private func glyphColor(for style: GestureHUDStyle) -> NSColor {
        switch style {
        case .classic:
            return NSColor.labelColor.withAlphaComponent(0.9)
        case .elegant, .minimal:
            return NSColor.white.withAlphaComponent(0.95)
        }
    }

    private func glyphSecondaryColor(for style: GestureHUDStyle) -> NSColor {
        switch style {
        case .classic, .elegant, .minimal:
            return NSColor.labelColor.withAlphaComponent(0.16)
        }
    }

    private func glyphBadgeBackgroundColor(for style: GestureHUDStyle) -> NSColor {
        switch style {
        case .classic, .elegant, .minimal:
            return .clear
        }
    }

    private func glyphBadgeBorderColor(for style: GestureHUDStyle) -> NSColor {
        switch style {
        case .classic, .elegant, .minimal:
            return .clear
        }
    }

    private func glyphBadgeBorderWidth(for style: GestureHUDStyle) -> CGFloat {
        switch style {
        case .classic, .elegant, .minimal:
            return 0
        }
    }

    private func glyphBadgeCornerRadius(for style: GestureHUDStyle) -> CGFloat {
        switch style {
        case .classic:
            return 0
        case .elegant, .minimal:
            return 8
        }
    }

    private func glyphLineWidth(for style: GestureHUDStyle) -> CGFloat {
        switch style {
        case .classic, .elegant:
            return 2.2
        case .minimal:
            return 2.2
        }
    }

    private func glyphGlowLineWidth(for style: GestureHUDStyle) -> CGFloat {
        switch style {
        case .classic:
            return 0
        case .elegant, .minimal:
            return 4.8
        }
    }
}

private final class GestureGlyphView: NSView {
    enum Style {
        case minimal
        case trackpad
    }

    var gesture: DockGestureKind = .swipeLeft {
        didSet { needsDisplay = true }
    }

    var glyphStyle: Style = .minimal {
        didSet { needsDisplay = true }
    }

    var primaryColor: NSColor = NSColor.labelColor.withAlphaComponent(0.9) {
        didSet { needsDisplay = true }
    }

    var secondaryColor: NSColor = NSColor.labelColor.withAlphaComponent(0.16) {
        didSet { needsDisplay = true }
    }

    var lineWidth: CGFloat = 2.2 {
        didSet { needsDisplay = true }
    }

    var glowLineWidth: CGFloat = 4.8 {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.saveGState()
        defer { context.restoreGState() }

        switch glyphStyle {
        case .minimal:
            drawMinimalGlyph(in: bounds)
        case .trackpad:
            drawTrackpadGlyph(in: bounds)
        }
    }

    private func drawMinimalGlyph(in rect: NSRect) {
        let strokePadding = max(glowLineWidth, lineWidth) / 2
        let glyphRect = sanitizedRect(
            from: rect.insetBy(dx: strokePadding + 0.5, dy: strokePadding + 0.5),
            minimumSize: 8
        )
        guard glyphRect.isEmpty == false else { return }

        if secondaryColor.alphaComponent > 0.01, glowLineWidth > lineWidth {
            let glowPath = gestureArrowPath(in: glyphRect, lineWidth: glowLineWidth)
            secondaryColor.setStroke()
            glowPath.stroke()
        }

        let path = gestureArrowPath(in: glyphRect, lineWidth: lineWidth)
        primaryColor.setStroke()
        path.stroke()
    }

    private func drawTrackpadGlyph(in rect: NSRect) {
        let trackpadRect = sanitizedRect(from: rect.insetBy(dx: 3, dy: 5), minimumSize: 18)
        guard trackpadRect.isEmpty == false else { return }

        let platePath = NSBezierPath(roundedRect: trackpadRect, xRadius: 8, yRadius: 8)
        secondaryColor.setFill()
        platePath.fill()

        secondaryColor.withAlphaComponent(0.85).setStroke()
        platePath.lineWidth = 1
        platePath.stroke()

        let arrowRect = sanitizedRect(from: trackpadRect.insetBy(dx: 4, dy: 4), minimumSize: 10)
        guard arrowRect.isEmpty == false else { return }

        let arrow = gestureArrowPath(in: arrowRect, lineWidth: 2.3)
        primaryColor.setStroke()
        arrow.stroke()
    }

    private func gestureArrowPath(in rect: NSRect, lineWidth: CGFloat) -> NSBezierPath {
        let rect = rect.standardized
        let path = CGMutablePath()

        switch gesture {
        case .swipeLeft:
            let tip = point(in: rect, x: 0.18, y: 0.5)
            let tail = point(in: rect, x: 0.84, y: 0.5)
            let wingTop = point(in: rect, x: 0.42, y: 0.26)
            let wingBottom = point(in: rect, x: 0.42, y: 0.74)
            addLine(to: path, from: tail, to: tip)
            addLine(to: path, from: tip, to: wingTop)
            addLine(to: path, from: tip, to: wingBottom)
        case .swipeRight:
            let tip = point(in: rect, x: 0.82, y: 0.5)
            let tail = point(in: rect, x: 0.16, y: 0.5)
            let wingTop = point(in: rect, x: 0.58, y: 0.26)
            let wingBottom = point(in: rect, x: 0.58, y: 0.74)
            addLine(to: path, from: tail, to: tip)
            addLine(to: path, from: tip, to: wingTop)
            addLine(to: path, from: tip, to: wingBottom)
        case .swipeUp:
            let tip = point(in: rect, x: 0.5, y: 0.18)
            let tail = point(in: rect, x: 0.5, y: 0.84)
            let wingLeft = point(in: rect, x: 0.26, y: 0.42)
            let wingRight = point(in: rect, x: 0.74, y: 0.42)
            addLine(to: path, from: tail, to: tip)
            addLine(to: path, from: tip, to: wingLeft)
            addLine(to: path, from: tip, to: wingRight)
        case .swipeDown:
            let tip = point(in: rect, x: 0.5, y: 0.82)
            let tail = point(in: rect, x: 0.5, y: 0.16)
            let wingLeft = point(in: rect, x: 0.26, y: 0.58)
            let wingRight = point(in: rect, x: 0.74, y: 0.58)
            addLine(to: path, from: tail, to: tip)
            addLine(to: path, from: tip, to: wingLeft)
            addLine(to: path, from: tip, to: wingRight)
        case .pinchIn:
            addLine(to: path, from: point(in: rect, x: 0.12, y: 0.18), to: point(in: rect, x: 0.38, y: 0.4))
            addLine(to: path, from: point(in: rect, x: 0.88, y: 0.18), to: point(in: rect, x: 0.62, y: 0.4))
            addLine(to: path, from: point(in: rect, x: 0.12, y: 0.82), to: point(in: rect, x: 0.38, y: 0.6))
            addLine(to: path, from: point(in: rect, x: 0.88, y: 0.82), to: point(in: rect, x: 0.62, y: 0.6))
        }

        let bezierPath = NSBezierPath(cgPath: path)
        bezierPath.lineCapStyle = .round
        bezierPath.lineJoinStyle = .round
        bezierPath.lineWidth = lineWidth

        let pathBounds = bezierPath.bounds
        guard pathBounds.isEmpty == false else { return bezierPath }

        let transform = AffineTransform(
            translationByX: rect.midX - pathBounds.midX,
            byY: rect.midY - pathBounds.midY
        )
        bezierPath.transform(using: transform)
        return bezierPath
    }

    private func sanitizedRect(from rect: NSRect, minimumSize: CGFloat) -> NSRect {
        guard
            rect.origin.x.isFinite,
            rect.origin.y.isFinite,
            rect.size.width.isFinite,
            rect.size.height.isFinite
        else {
            return .zero
        }

        let standardized = rect.standardized
        guard standardized.width >= minimumSize, standardized.height >= minimumSize else {
            return .zero
        }

        return standardized
    }

    private func addLine(to path: CGMutablePath, from start: CGPoint, to end: CGPoint) {
        guard
            start.x.isFinite,
            start.y.isFinite,
            end.x.isFinite,
            end.y.isFinite
        else {
            return
        }

        path.move(to: start)
        path.addLine(to: end)
    }

    private func point(in rect: NSRect, x: CGFloat, y: CGFloat) -> CGPoint {
        CGPoint(
            x: rect.minX + (rect.width * x),
            y: rect.minY + (rect.height * y)
        )
    }
}

private final class GlassHighlightView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            NSColor.white.withAlphaComponent(0.34).cgColor,
            NSColor.white.withAlphaComponent(0.10).cgColor,
            NSColor.clear.cgColor,
        ]
        gradientLayer.locations = [0, 0.38, 1]
        gradientLayer.startPoint = CGPoint(x: 0.18, y: 1)
        gradientLayer.endPoint = CGPoint(x: 0.82, y: 0)
        gradientLayer.cornerRadius = 21
        layer = gradientLayer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        layer?.frame = bounds
        layer?.cornerRadius = bounds.height / 2
    }
}
