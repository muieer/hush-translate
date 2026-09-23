import AppKit
import Combine
import Foundation

/// Product configuration uses whole minutes; running state is never persisted.
enum TranslationSessionConfiguration: Equatable {
    case always
    case count(Int)
    case timer(minutes: Int)

    static let defaultPreset: Self = .count(3)
}

enum TranslationSessionState: Equatable {
    case off
    case always
    case count(remaining: Int)
    case timer(expiresAt: Date)
}

@MainActor
final class TranslationSessionStore: ObservableObject {
    enum ConfigurationError: Error, Equatable {
        case nonPositiveCount
        case nonPositiveMinutes
    }

    /// The scheduler returns a cancellation token. Tests can deliver even cancelled
    /// callbacks to verify that an old session cannot affect its replacement.
    typealias ScheduleExpiration = (Date, @escaping @MainActor () -> Void) -> AnyCancellable

    @Published private(set) var state: TranslationSessionState = .off

    private let now: () -> Date
    private let scheduleExpiration: ScheduleExpiration
    private var expiration: AnyCancellable?
    private var wakeObservation: AnyCancellable?
    private var sessionID = UUID()

    init(
        now: @escaping () -> Date = Date.init,
        scheduleExpiration: ScheduleExpiration? = nil,
        wakeNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.now = now
        self.scheduleExpiration = scheduleExpiration ?? { deadline, callback in
            let timer = Timer(timeInterval: max(0, deadline.timeIntervalSinceNow), repeats: false) { _ in
                Task { @MainActor in callback() }
            }
            RunLoop.main.add(timer, forMode: .common)
            return AnyCancellable { timer.invalidate() }
        }
        let observer = wakeNotifications.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshExpiration() }
        }
        wakeObservation = AnyCancellable { wakeNotifications.removeObserver(observer) }
    }

    func start(configuration: TranslationSessionConfiguration) throws {
        let next: TranslationSessionState
        switch configuration {
        case .always:
            next = .always
        case .count(let count):
            guard count > 0 else { throw ConfigurationError.nonPositiveCount }
            next = .count(remaining: count)
        case .timer(let minutes):
            guard minutes > 0 else { throw ConfigurationError.nonPositiveMinutes }
            next = .timer(expiresAt: now().addingTimeInterval(Double(minutes) * 60))
        }

        expiration?.cancel()
        expiration = nil
        sessionID = UUID()
        state = next
        if case .timer(let deadline) = next {
            armExpiration(at: deadline, id: sessionID)
        }
    }

    func close() {
        expiration?.cancel()
        expiration = nil
        sessionID = UUID()
        if state != .off { state = .off }
    }

    /// Call only after obtaining a valid Selection. A true result admits one
    /// translation, regardless of whether its subsequent model request succeeds.
    @discardableResult
    func consumeValidSelection() -> Bool {
        refreshExpiration()
        switch state {
        case .off:
            return false
        case .always, .timer:
            return true
        case .count(let remaining):
            if remaining == 1 {
                close()
            } else {
                state = .count(remaining: remaining - 1)
            }
            return true
        }
    }

    func refreshExpiration() {
        if case .timer(let deadline) = state, now() >= deadline {
            close()
        }
    }

    private func armExpiration(at deadline: Date, id: UUID) {
        expiration = scheduleExpiration(deadline) { [weak self] in
            guard let self, self.sessionID == id else { return }
            self.refreshExpiration()
            // A clock adjustment or early delivery must not end a valid session.
            if self.sessionID == id, case .timer = self.state {
                self.expiration?.cancel()
                self.armExpiration(at: deadline, id: id)
            }
        }
    }
}
