import AppKit
import Foundation

final class MouseCaptureEngine {
    private let sessionId: String
    private let maxEvents: Int?
    private let printJSON: Bool
    private let queue: RawEventQueue
    private let contextResolver: FrontmostContextResolver
    private let timestampFormatter: ISO8601DateFormatter
    private let eventSink: RawEventFileSink

    private var monitorToken: Any?
    private let encoder = JSONEncoder()
    private var hasFatalError = false

    var onStopRequested: (() -> Void)?
    var onFatalError: ((Error) -> Void)?

    init(
        sessionId: String,
        maxEvents: Int?,
        printJSON: Bool,
        eventSink: RawEventFileSink,
        queue: RawEventQueue = RawEventQueue(),
        contextResolver: FrontmostContextResolver = FrontmostContextResolver()
    ) {
        self.sessionId = sessionId
        self.maxEvents = maxEvents
        self.printJSON = printJSON
        self.eventSink = eventSink
        self.queue = queue
        self.contextResolver = contextResolver

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.timestampFormatter = formatter
    }

    var capturedCount: Int {
        queue.count
    }

    func start() throws {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .keyDown]
        guard let monitorToken = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handleEvent(_:)) else {
            throw CaptureEngineError.globalMonitorUnavailable
        }

        self.monitorToken = monitorToken
    }

    func stop() {
        if let monitorToken {
            NSEvent.removeMonitor(monitorToken)
            self.monitorToken = nil
        }

        if let closeError = tryCloseSink() {
            print("[STO-IO-CLOSE-FAILED] \(closeError.localizedDescription)")
        }
    }

    private func handleEvent(_ event: NSEvent) {
        guard let action = mapAction(event) else {
            return
        }

        let pointer = PointerLocation(
            x: Int(event.locationInWindow.x.rounded()),
            y: Int(event.locationInWindow.y.rounded())
        )
        let contextSnapshot = contextResolver.snapshot(
            pointer: pointer,
            action: action
        )

        let rawEvent = RawEvent(
            eventId: UUID().uuidString.lowercased(),
            sessionId: sessionId,
            timestamp: timestampFormatter.string(from: Date()),
            source: action.source,
            action: action,
            pointer: pointer,
            contextSnapshot: contextSnapshot,
            modifiers: keyboardModifiers(from: event),
            keyboard: keyboardPayload(
                from: event,
                action: action,
                contextSnapshot: contextSnapshot
            )
        )

        do {
            try eventSink.append(rawEvent)
        } catch {
            emitFatalErrorOnce(CaptureEngineError.storageWriteFailed(error))
            return
        }

        let count = queue.enqueue(rawEvent)

        if printJSON {
            if let line = encodeJSONLine(rawEvent) {
                print(line)
            }
        } else {
            let windowTitle = rawEvent.contextSnapshot.windowTitle ?? "<no-window-title>"
            print("[captured=\(count)] \(rawEvent.action.rawValue) app=\(rawEvent.contextSnapshot.appName) window=\(windowTitle) point=(\(rawEvent.pointer.x),\(rawEvent.pointer.y))")
        }

        if let maxEvents, count >= maxEvents {
            onStopRequested?()
        }
    }

    private func tryCloseSink() -> Error? {
        do {
            try eventSink.close()
            return nil
        } catch {
            return CaptureEngineError.storageCloseFailed(error)
        }
    }

    private func emitFatalErrorOnce(_ error: Error) {
        guard !hasFatalError else {
            return
        }

        hasFatalError = true
        onFatalError?(error)
    }

    private func mapAction(_ event: NSEvent) -> RawEventAction? {
        switch event.type {
        case .leftMouseDown:
            return event.clickCount >= 2 ? .doubleClick : .leftClick
        case .rightMouseDown:
            return .rightClick
        case .keyDown:
            return .keyDown
        default:
            return nil
        }
    }

    private func keyboardModifiers(from event: NSEvent) -> [KeyboardModifier] {
        var modifiers: [KeyboardModifier] = []

        if event.modifierFlags.contains(.command) {
            modifiers.append(.command)
        }
        if event.modifierFlags.contains(.shift) {
            modifiers.append(.shift)
        }
        if event.modifierFlags.contains(.option) {
            modifiers.append(.option)
        }
        if event.modifierFlags.contains(.control) {
            modifiers.append(.control)
        }

        return modifiers
    }

    private func keyboardPayload(
        from event: NSEvent,
        action: RawEventAction,
        contextSnapshot: ContextSnapshot
    ) -> KeyboardEventPayload? {
        guard action == .keyDown else {
            return nil
        }

        let shouldRedact = contextSnapshot.focusedElement?.valueRedacted == true

        return KeyboardEventPayload(
            keyCode: Int(event.keyCode),
            characters: shouldRedact ? nil : event.characters,
            charactersIgnoringModifiers: shouldRedact ? nil : event.charactersIgnoringModifiers,
            isRepeat: event.isARepeat,
            isSensitiveInput: shouldRedact,
            redactionReason: shouldRedact ? "secureTextField" : nil
        )
    }

    private func encodeJSONLine(_ event: RawEvent) -> String? {
        guard let data = try? encoder.encode(event) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }
}

enum CaptureEngineError: LocalizedError {
    case globalMonitorUnavailable
    case storageWriteFailed(Error)
    case storageCloseFailed(Error)

    var errorDescription: String? {
        switch self {
        case .globalMonitorUnavailable:
            return "Failed to start global mouse/keyboard monitor."
        case .storageWriteFailed(let error):
            return "Failed to persist captured event: \(error.localizedDescription)"
        case .storageCloseFailed(let error):
            return "Failed to close event sink: \(error.localizedDescription)"
        }
    }
}
