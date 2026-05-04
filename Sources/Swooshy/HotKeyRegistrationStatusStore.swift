import Carbon.HIToolbox
import Observation

struct HotKeyRegistrationFailure: Equatable, Sendable {
    let action: WindowAction
    let binding: HotKeyBinding
    let status: OSStatus
}

@MainActor
@Observable
final class HotKeyRegistrationStatusStore {
    private(set) var failures: [WindowAction: HotKeyRegistrationFailure] = [:]
    private(set) var handlerUnavailable = false

    func failure(for action: WindowAction) -> HotKeyRegistrationFailure? {
        failures[action]
    }

    func recordFailure(_ failure: HotKeyRegistrationFailure) {
        handlerUnavailable = false
        failures[failure.action] = failure
    }

    func markHandlerUnavailable() {
        failures.removeAll()
        handlerUnavailable = true
    }

    func clear() {
        failures.removeAll()
        handlerUnavailable = false
    }
}
