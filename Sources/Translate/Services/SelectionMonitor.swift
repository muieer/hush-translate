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
    private var localMonitor: Any?
    private var workspaceObservation: NSObjectProtocol?
    private let actionPanel = SelectionActionPanel()
    private var selectionStart: NSPoint?
    private var candidateID = UUID()
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
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .keyDown, .scrollWheel]) { [weak self] event in
            // NSEvent invokes global monitor handlers on the main thread.
            MainActor.assumeIsolated {
                guard let self, self.generation == generation else { return }
                self.handle(event)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated {
                // The confirmation button must receive its click before dismissal.
                if self?.actionPanel.contains(event.window) != true {
                    self?.invalidateCandidate()
                }
            }
            return event
        }
        workspaceObservation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.invalidateCandidate() }
        }
    }

    func stop() {
        generation = UUID()
        invalidateCandidate()
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
        if let workspaceObservation { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObservation) }
        workspaceObservation = nil
        selectionStart = nil
        captureTask?.cancel()
        captureTask = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        shouldCapture = nil
        onCapture = nil
        gestures = SelectionGestureTracker()
    }

    private func invalidateCandidate() {
        candidateID = UUID()
        captureTask?.cancel()
        captureTask = nil
        actionPanel.dismiss()
    }

    private func handle(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            selectionStart = NSEvent.mouseLocation
        }
        if [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel].contains(event.type) {
            // Ignore our own synthetic copy shortcut.
            if event.type == .keyDown && event.keyCode == 8 && event.modifierFlags.contains(.command) { return }
            invalidateCandidate()
        }
        guard gestures.accepts(event.type, clickCount: event.clickCount,
                               shift: event.modifierFlags.contains(.shift),
                               location: event.cgEvent?.location ?? event.locationInWindow),
              shouldCapture?() == true else { return }
        captureTask?.cancel()
        let generation = generation
        let end = NSEvent.mouseLocation
        let start = selectionStart ?? end
        let fallback = NSRect(x: min(start.x, end.x), y: min(start.y, end.y),
                              width: max(1, abs(start.x - end.x)), height: max(18, abs(start.y - end.y)))
        captureTask = Task { [weak self] in
            await self?.tryCapture(generation: generation, fallback: fallback)
        }
    }

    private func tryCapture(generation: UUID, fallback: NSRect) async {
        do {
            // Allow the target application to finish updating its selection.
            try await Task.sleep(nanoseconds: 100_000_000)
            guard canContinue(generation: generation) else { return }
            let sourcePID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let bounds = selectedTextBounds() ?? fallback
            let candidate = candidateID
            let pb = NSPasteboard.general
            let old = pb.changeCount
            simulateCopy()

            // Never fall back to old clipboard text on timeout or capture failure.
            for _ in 0..<50 {
                try await Task.sleep(nanoseconds: 20_000_000)
                guard !Task.isCancelled, self.generation == generation,
                      shouldCapture?() == true else { return }
                if pb.changeCount != old {
                    guard let text = pb.string(forType: .string),
                          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    guard candidateID == candidate,
                          NSWorkspace.shared.frontmostApplication?.processIdentifier == sourcePID else { return }
                    actionPanel.show(above: bounds) { [weak self] in
                        guard let self, self.candidateID == candidate,
                              self.generation == generation,
                              NSWorkspace.shared.frontmostApplication?.processIdentifier == sourcePID,
                              self.shouldCapture?() == true else { return }
                        self.candidateID = UUID()
                        self.onCapture?(text)
                    }
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

    /// Accessibility coordinates have a top-left origin; AppKit uses bottom-left.
    private func selectedTextBounds() -> NSRect? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        var range: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
              let range else { return nil }
        var bounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                         range, &bounds) == .success,
              let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect),
              !rect.isEmpty, let primary = NSScreen.screens.first else { return nil }
        return NSRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
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
