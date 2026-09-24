import AppKit

/// Only selection gestures in other applications are capture candidates.
/// A plain click or a right click must not copy unrelated content.
struct SelectionGestureTracker {
    private var dragged = false
    private var mouseDownLocation: NSPoint?

    mutating func accepts(_ type: NSEvent.EventType, clickCount: Int, shift: Bool,
                          location: NSPoint) -> Bool {
        switch type {
        case .leftMouseDown:
            dragged = false
            mouseDownLocation = location
        case .leftMouseDragged:
            dragged = true
        case .leftMouseUp:
            defer {
                dragged = false
                mouseDownLocation = nil
            }
            // Some applications do not deliver a dragged event to the global
            // monitor. The pointer displacement still identifies the gesture.
            let moved = mouseDownLocation.map {
                hypot(location.x - $0.x, location.y - $0.y) >= 3
            } ?? false
            return dragged || moved || clickCount >= 2 || shift
        default:
            break
        }
        return false
    }
}

/// Uses the existing Cmd+C / changeCount capture path, only while a session is active.
@MainActor
final class SelectionMonitor: SelectionMonitoring {
    private var monitor: Any?
    private var captureTask: Task<Void, Never>?
    private var generation = UUID()
    private var gestures = SelectionGestureTracker()
    private var shouldCapture: (() -> Bool)?
    private var onCapture: ((String) -> Void)?

    func start(shouldCapture: @escaping () -> Bool, onCapture: @escaping (String) -> Void) {
        stop()
        self.shouldCapture = shouldCapture
        self.onCapture = onCapture
        let generation = generation
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            // NSEvent invokes global monitor handlers on the main thread.
            MainActor.assumeIsolated {
                guard let self, self.generation == generation else { return }
                self.handle(event)
            }
        }
    }

    func stop() {
        generation = UUID()
        captureTask?.cancel()
        captureTask = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        shouldCapture = nil
        onCapture = nil
        gestures = SelectionGestureTracker()
    }

    private func handle(_ event: NSEvent) {
        guard gestures.accepts(event.type, clickCount: event.clickCount,
                               shift: event.modifierFlags.contains(.shift),
                               location: event.cgEvent?.location ?? event.locationInWindow),
              shouldCapture?() == true else { return }
        captureTask?.cancel()
        let generation = generation
        captureTask = Task { [weak self] in
            await self?.tryCapture(generation: generation)
        }
    }

    private func tryCapture(generation: UUID) async {
        do {
            // Allow the target application to finish updating its selection.
            try await Task.sleep(nanoseconds: 100_000_000)
            guard canContinue(generation: generation) else { return }
            let pb = NSPasteboard.general
            let old = pb.changeCount
            simulateCopy()

            // Never fall back to old clipboard text on timeout or capture failure.
            for _ in 0..<50 {
                try await Task.sleep(nanoseconds: 20_000_000)
                // After posting Cmd+C, switching apps or clicking elsewhere must
                // not discard a copy that the source app is still processing.
                guard !Task.isCancelled, self.generation == generation,
                      shouldCapture?() == true else { return }
                if pb.changeCount != old {
                    guard let text = pb.string(forType: .string),
                          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    onCapture?(text)
                    return
                }
            }
        } catch {
            // Cancellation is expected when another gesture or session supersedes this one.
        }
    }

    private func canContinue(generation: UUID) -> Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return false }
        return !Task.isCancelled && self.generation == generation &&
            frontmost.processIdentifier != NSRunningApplication.current.processIdentifier &&
            shouldCapture?() == true
    }

    private func simulateCopy() {
        let src = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false) else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
