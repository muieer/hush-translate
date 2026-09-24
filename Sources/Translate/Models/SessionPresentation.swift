import Combine
import Foundation

struct SessionStatus: Equatable {
    let title: String
    let badge: String
    let isActive: Bool

    init(state: TranslationSessionState, now: Date) {
        switch state {
        case .off:
            title = "已关闭"; badge = ""; isActive = false
        case .always:
            title = "持续开启"; badge = "∞"; isActive = true
        case .count(let remaining):
            title = "剩余 \(remaining) 次"; badge = "\(remaining)"; isActive = true
        case .timer(let deadline):
            let minutes = ceil(max(0, deadline.timeIntervalSince(now)) / 60)
            if minutes == 0 {
                title = "已关闭"; badge = ""; isActive = false
            } else {
                // Formatting as a whole number avoids overflowing Int for large presets.
                let text = String(format: "%.0f", minutes)
                title = "剩余 \(text) 分钟"; badge = "\(text)m"; isActive = true
            }
        }
    }
}

/// Display-only minute refreshes; expiration and selection admission remain in the session store.
@MainActor
final class SessionPresentation: ObservableObject {
    @Published private(set) var status: SessionStatus
    private let now: () -> Date
    private var state: TranslationSessionState
    private var observation: AnyCancellable?
    private var minuteTimer: AnyCancellable?

    init(session: TranslationSessionStore, now: @escaping () -> Date = Date.init) {
        self.now = now
        state = session.state
        status = SessionStatus(state: session.state, now: now())
        observation = session.$state.sink { [weak self] state in
            guard let self else { return }
            // Published emits before assignment; use the supplied state, not session.state.
            self.state = state
            self.refresh()
            self.minuteTimer = nil
            if case .timer = state {
                self.minuteTimer = Timer.publish(every: 60, on: .main, in: .common)
                    .autoconnect().sink { [weak self] _ in self?.refresh() }
            }
        }
    }

    func refresh() {
        let next = SessionStatus(state: state, now: now())
        if next != status { status = next }
    }
}
