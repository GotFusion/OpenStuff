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
    public let isSensitiveInput: Bool
    public let redactionReason: String?

    private enum CodingKeys: String, CodingKey {
        case keyCode
        case characters
        case charactersIgnoringModifiers
        case isRepeat
        case isSensitiveInput
        case redactionReason
    }

    public init(
        keyCode: Int,
        characters: String?,
        charactersIgnoringModifiers: String?,
        isRepeat: Bool,
        isSensitiveInput: Bool = false,
        redactionReason: String? = nil
    ) {
        self.keyCode = keyCode
        self.characters = characters
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
        self.isRepeat = isRepeat
        self.isSensitiveInput = isSensitiveInput
        self.redactionReason = redactionReason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.keyCode = try container.decode(Int.self, forKey: .keyCode)
        self.characters = try container.decodeIfPresent(String.self, forKey: .characters)
        self.charactersIgnoringModifiers = try container.decodeIfPresent(String.self, forKey: .charactersIgnoringModifiers)
        self.isRepeat = try container.decode(Bool.self, forKey: .isRepeat)
        self.isSensitiveInput = try container.decodeIfPresent(Bool.self, forKey: .isSensitiveInput) ?? false
        self.redactionReason = try container.decodeIfPresent(String.self, forKey: .redactionReason)
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
    public let windowSignature: WindowSignature?
    public let focusedElement: FocusedElementSnapshot?
    public let screenshotAnchors: [ScreenshotAnchor]
    public let captureDiagnostics: [ContextCaptureDiagnostic]

    private enum CodingKeys: String, CodingKey {
        case appName
        case appBundleId
        case windowTitle
        case windowId
        case isFrontmost
        case windowSignature
        case focusedElement
        case screenshotAnchors
        case captureDiagnostics
    }

    public init(
        appName: String,
        appBundleId: String,
        windowTitle: String?,
        windowId: String?,
        isFrontmost: Bool = true,
        windowSignature: WindowSignature? = nil,
        focusedElement: FocusedElementSnapshot? = nil,
        screenshotAnchors: [ScreenshotAnchor] = [],
        captureDiagnostics: [ContextCaptureDiagnostic] = []
    ) {
        self.appName = appName
        self.appBundleId = appBundleId
        self.windowTitle = windowTitle
        self.windowId = windowId
        self.isFrontmost = isFrontmost
        self.windowSignature = windowSignature
        self.focusedElement = focusedElement
        self.screenshotAnchors = screenshotAnchors
        self.captureDiagnostics = captureDiagnostics
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.appName = try container.decode(String.self, forKey: .appName)
        self.appBundleId = try container.decode(String.self, forKey: .appBundleId)
        self.windowTitle = try container.decodeIfPresent(String.self, forKey: .windowTitle)
        self.windowId = try container.decodeIfPresent(String.self, forKey: .windowId)
        self.isFrontmost = try container.decode(Bool.self, forKey: .isFrontmost)
        self.windowSignature = try container.decodeIfPresent(WindowSignature.self, forKey: .windowSignature)
        self.focusedElement = try container.decodeIfPresent(FocusedElementSnapshot.self, forKey: .focusedElement)
        self.screenshotAnchors = try container.decodeIfPresent([ScreenshotAnchor].self, forKey: .screenshotAnchors) ?? []
        self.captureDiagnostics = try container.decodeIfPresent([ContextCaptureDiagnostic].self, forKey: .captureDiagnostics) ?? []
    }
}

public struct WindowSignature: Codable, Equatable {
    public let signature: String
    public let signatureVersion: String
    public let normalizedTitle: String?
    public let role: String?
    public let subrole: String?
    public let sizeBucket: String?

    public init(
        signature: String,
        signatureVersion: String = "window-v1",
        normalizedTitle: String? = nil,
        role: String? = nil,
        subrole: String? = nil,
        sizeBucket: String? = nil
    ) {
        self.signature = signature
        self.signatureVersion = signatureVersion
        self.normalizedTitle = normalizedTitle
        self.role = role
        self.subrole = subrole
        self.sizeBucket = sizeBucket
    }
}

public struct FocusedElementSnapshot: Codable, Equatable {
    public let role: String?
    public let subrole: String?
    public let title: String?
    public let identifier: String?
    public let descriptionText: String?
    public let helpText: String?
    public let boundingRect: SemanticBoundingRect?
    public let valueRedacted: Bool

    public init(
        role: String? = nil,
        subrole: String? = nil,
        title: String? = nil,
        identifier: String? = nil,
        descriptionText: String? = nil,
        helpText: String? = nil,
        boundingRect: SemanticBoundingRect? = nil,
        valueRedacted: Bool = false
    ) {
        self.role = role
        self.subrole = subrole
        self.title = title
        self.identifier = identifier
        self.descriptionText = descriptionText
        self.helpText = helpText
        self.boundingRect = boundingRect
        self.valueRedacted = valueRedacted
    }
}

public struct ScreenshotAnchor: Codable, Equatable {
    public let phase: ScreenshotAnchorPhase
    public let boundingRect: SemanticBoundingRect
    public let sampleSize: ScreenshotAnchorSampleSize
    public let pixelHash: String
    public let averageLuma: Double
    public let redacted: Bool

    public init(
        phase: ScreenshotAnchorPhase,
        boundingRect: SemanticBoundingRect,
        sampleSize: ScreenshotAnchorSampleSize,
        pixelHash: String,
        averageLuma: Double,
        redacted: Bool = true
    ) {
        self.phase = phase
        self.boundingRect = boundingRect
        self.sampleSize = sampleSize
        self.pixelHash = pixelHash
        self.averageLuma = averageLuma
        self.redacted = redacted
    }
}

public enum ScreenshotAnchorPhase: String, Codable {
    case before
    case after
}

public struct ScreenshotAnchorSampleSize: Codable, Equatable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct ContextCaptureDiagnostic: Codable, Equatable {
    public let code: String
    public let field: String
    public let message: String

    public init(code: String, field: String, message: String) {
        self.code = code
        self.field = field
        self.message = message
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
