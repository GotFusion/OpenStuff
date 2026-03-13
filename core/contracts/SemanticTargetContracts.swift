import Foundation

public struct SemanticTarget: Codable, Equatable {
    public let locatorType: SemanticLocatorType
    public let appBundleId: String
    public let windowTitlePattern: String?
    public let elementRole: String?
    public let elementTitle: String?
    public let elementIdentifier: String?
    public let boundingRect: SemanticBoundingRect?
    public let confidence: Double
    public let source: SemanticTargetSource

    public init(
        locatorType: SemanticLocatorType,
        appBundleId: String,
        windowTitlePattern: String? = nil,
        elementRole: String? = nil,
        elementTitle: String? = nil,
        elementIdentifier: String? = nil,
        boundingRect: SemanticBoundingRect? = nil,
        confidence: Double,
        source: SemanticTargetSource
    ) {
        self.locatorType = locatorType
        self.appBundleId = appBundleId
        self.windowTitlePattern = windowTitlePattern
        self.elementRole = elementRole
        self.elementTitle = elementTitle
        self.elementIdentifier = elementIdentifier
        self.boundingRect = boundingRect
        self.confidence = confidence
        self.source = source
    }

    public static func coordinateFallback(
        appBundleId: String,
        windowTitle: String?,
        coordinate: PointerLocation,
        confidence: Double = 0.24,
        source: SemanticTargetSource = .capture
    ) -> SemanticTarget {
        SemanticTarget(
            locatorType: .coordinateFallback,
            appBundleId: appBundleId,
            windowTitlePattern: exactWindowTitlePattern(for: windowTitle),
            boundingRect: SemanticBoundingRect(
                x: Double(coordinate.x),
                y: Double(coordinate.y),
                width: 1,
                height: 1,
                coordinateSpace: .screen
            ),
            confidence: confidence,
            source: source
        )
    }

    public static func exactWindowTitlePattern(for windowTitle: String?) -> String? {
        guard let windowTitle,
              !windowTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return "^\(NSRegularExpression.escapedPattern(for: windowTitle))$"
    }
}

public enum SemanticLocatorType: String, Codable {
    case axPath
    case roleAndTitle
    case textAnchor
    case imageAnchor
    case coordinateFallback
}

public enum SemanticTargetSource: String, Codable {
    case capture
    case inferred
    case repaired
}

public struct SemanticBoundingRect: Codable, Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let coordinateSpace: SemanticCoordinateSpace

    public init(
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        coordinateSpace: SemanticCoordinateSpace = .screen
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.coordinateSpace = coordinateSpace
    }
}

public enum SemanticCoordinateSpace: String, Codable {
    case screen
}
