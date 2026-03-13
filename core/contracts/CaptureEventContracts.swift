import Foundation

// MARK: - Raw Capture Event

public struct RawEvent: Codable, Equatable {
    public let schemaVersion: String
    public let eventId: String
    public let sessionId: String
    public let timestamp: String
    public let source: RawEventSource
    public let action: RawEventAction
    public let pointer: PointerLocation
    public let contextSnapshot: ContextSnapshot
    public let modifiers: [KeyboardModifier]
    public let keyboard: KeyboardEventPayload?

    public init(
        schemaVersion: String = "capture.raw.v0",
        eventId: String,
        sessionId: String,
        timestamp: String,
        source: RawEventSource,
        action: RawEventAction,
        pointer: PointerLocation,
        contextSnapshot: ContextSnapshot,
        modifiers: [KeyboardModifier] = [],
        keyboard: KeyboardEventPayload? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.eventId = eventId
        self.sessionId = sessionId
        self.timestamp = timestamp
        self.source = source
        self.action = action
        self.pointer = pointer
        self.contextSnapshot = contextSnapshot
        self.modifiers = modifiers
        self.keyboard = keyboard
    }
}

public enum RawEventSource: String, Codable {
    case mouse
    case keyboard
}

public enum RawEventAction: String, Codable {
    case leftClick
    case rightClick
    case doubleClick
    case keyDown

    public var source: RawEventSource {
        switch self {
        case .leftClick, .rightClick, .doubleClick:
            return .mouse
        case .keyDown:
            return .keyboard
        }
    }
}

public enum KeyboardModifier: String, Codable {
    case command
    case shift
    case option
    case control
}

public struct KeyboardEventPayload: Codable, Equatable {
    public let keyCode: Int
    public let characters: String?
    public let charactersIgnoringModifiers: String?
    public let isRepeat: Bool

    public init(
        keyCode: Int,
        characters: String?,
        charactersIgnoringModifiers: String?,
        isRepeat: Bool
    ) {
        self.keyCode = keyCode
        self.characters = characters
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
        self.isRepeat = isRepeat
    }
}

public struct PointerLocation: Codable, Equatable {
    public let x: Int
    public let y: Int
    public let coordinateSpace: CoordinateSpace

    public init(x: Int, y: Int, coordinateSpace: CoordinateSpace = .screen) {
        self.x = x
        self.y = y
        self.coordinateSpace = coordinateSpace
    }
}

public enum CoordinateSpace: String, Codable {
    case screen
}

// MARK: - Context Snapshot

public struct ContextSnapshot: Codable, Equatable {
    public let appName: String
    public let appBundleId: String
    public let windowTitle: String?
    public let windowId: String?
    public let isFrontmost: Bool

    public init(
        appName: String,
        appBundleId: String,
        windowTitle: String?,
        windowId: String?,
        isFrontmost: Bool = true
    ) {
        self.appName = appName
        self.appBundleId = appBundleId
        self.windowTitle = windowTitle
        self.windowId = windowId
        self.isFrontmost = isFrontmost
    }
}

// MARK: - Normalized Event

public struct NormalizedEvent: Codable, Equatable {
    public let schemaVersion: String
    public let normalizedEventId: String
    public let sourceEventId: String
    public let sessionId: String
    public let timestamp: String
    public let eventType: NormalizedEventType
    public let target: EventTarget
    public let contextSnapshot: ContextSnapshot
    public let confidence: Double
    public let normalizerVersion: String

    public init(
        schemaVersion: String = "capture.normalized.v0",
        normalizedEventId: String,
        sourceEventId: String,
        sessionId: String,
        timestamp: String,
        eventType: NormalizedEventType,
        target: EventTarget,
        contextSnapshot: ContextSnapshot,
        confidence: Double,
        normalizerVersion: String
    ) {
        self.schemaVersion = schemaVersion
        self.normalizedEventId = normalizedEventId
        self.sourceEventId = sourceEventId
        self.sessionId = sessionId
        self.timestamp = timestamp
        self.eventType = eventType
        self.target = target
        self.contextSnapshot = contextSnapshot
        self.confidence = confidence
        self.normalizerVersion = normalizerVersion
    }
}

public enum NormalizedEventType: String, Codable {
    case click
}

public struct EventTarget: Codable, Equatable {
    public let kind: EventTargetKind
    public let coordinate: PointerLocation
    public let semanticTargets: [SemanticTarget]
    public let preferredLocatorType: SemanticLocatorType?

    private enum CodingKeys: String, CodingKey {
        case kind
        case coordinate
        case semanticTargets
        case preferredLocatorType
    }

    public init(
        kind: EventTargetKind = .coordinate,
        coordinate: PointerLocation,
        semanticTargets: [SemanticTarget] = [],
        preferredLocatorType: SemanticLocatorType? = nil
    ) {
        self.kind = kind
        self.coordinate = coordinate
        self.semanticTargets = semanticTargets
        self.preferredLocatorType = preferredLocatorType
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try container.decode(EventTargetKind.self, forKey: .kind)
        self.coordinate = try container.decode(PointerLocation.self, forKey: .coordinate)
        self.semanticTargets = try container.decodeIfPresent([SemanticTarget].self, forKey: .semanticTargets) ?? []
        self.preferredLocatorType = try container.decodeIfPresent(SemanticLocatorType.self, forKey: .preferredLocatorType)
    }
}

public enum EventTargetKind: String, Codable {
    case coordinate
}
