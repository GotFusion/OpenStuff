import Foundation

// MARK: - Knowledge Item (Task -> Reusable Knowledge)

public struct KnowledgeItem: Codable, Equatable {
    public let schemaVersion: String
    public let knowledgeItemId: String
    public let taskId: String
    public let sessionId: String
    public let goal: String
    public let summary: String
    public let steps: [KnowledgeStep]
    public let context: KnowledgeContext
    public let constraints: [KnowledgeConstraint]
    public let source: KnowledgeSource
    public let createdAt: String
    public let generatorVersion: String

    public init(
        schemaVersion: String = "knowledge.item.v0",
        knowledgeItemId: String,
        taskId: String,
        sessionId: String,
        goal: String,
        summary: String,
        steps: [KnowledgeStep],
        context: KnowledgeContext,
        constraints: [KnowledgeConstraint],
        source: KnowledgeSource,
        createdAt: String,
        generatorVersion: String = "rule-v0"
    ) {
        self.schemaVersion = schemaVersion
        self.knowledgeItemId = knowledgeItemId
        self.taskId = taskId
        self.sessionId = sessionId
        self.goal = goal
        self.summary = summary
        self.steps = steps
        self.context = context
        self.constraints = constraints
        self.source = source
        self.createdAt = createdAt
        self.generatorVersion = generatorVersion
    }
}

public struct KnowledgeStep: Codable, Equatable {
    public let stepId: String
    public let instruction: String
    public let sourceEventIds: [String]
    public let target: KnowledgeStepTarget?

    public init(
        stepId: String,
        instruction: String,
        sourceEventIds: [String],
        target: KnowledgeStepTarget? = nil
    ) {
        self.stepId = stepId
        self.instruction = instruction
        self.sourceEventIds = sourceEventIds
        self.target = target
    }
}

public struct KnowledgeStepTarget: Codable, Equatable {
    public let coordinate: PointerLocation?
    public let semanticTargets: [SemanticTarget]
    public let preferredLocatorType: SemanticLocatorType?

    private enum CodingKeys: String, CodingKey {
        case coordinate
        case semanticTargets
        case preferredLocatorType
    }

    public init(
        coordinate: PointerLocation? = nil,
        semanticTargets: [SemanticTarget] = [],
        preferredLocatorType: SemanticLocatorType? = nil
    ) {
        self.coordinate = coordinate
        self.semanticTargets = semanticTargets
        self.preferredLocatorType = preferredLocatorType
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.coordinate = try container.decodeIfPresent(PointerLocation.self, forKey: .coordinate)
        self.semanticTargets = try container.decodeIfPresent([SemanticTarget].self, forKey: .semanticTargets) ?? []
        self.preferredLocatorType = try container.decodeIfPresent(SemanticLocatorType.self, forKey: .preferredLocatorType)
    }
}

public struct KnowledgeContext: Codable, Equatable {
    public let appName: String
    public let appBundleId: String
    public let windowTitle: String?
    public let windowId: String?

    public init(
        appName: String,
        appBundleId: String,
        windowTitle: String?,
        windowId: String?
    ) {
        self.appName = appName
        self.appBundleId = appBundleId
        self.windowTitle = windowTitle
        self.windowId = windowId
    }
}

public struct KnowledgeConstraint: Codable, Equatable {
    public let type: KnowledgeConstraintType
    public let description: String

    public init(type: KnowledgeConstraintType, description: String) {
        self.type = type
        self.description = description
    }
}

public enum KnowledgeConstraintType: String, Codable {
    case frontmostAppMustMatch
    case manualConfirmationRequired
    case coordinateTargetMayDrift
}

public struct KnowledgeSource: Codable, Equatable {
    public let taskChunkSchemaVersion: String
    public let startTimestamp: String
    public let endTimestamp: String
    public let eventCount: Int
    public let boundaryReason: TaskBoundaryReason

    public init(
        taskChunkSchemaVersion: String,
        startTimestamp: String,
        endTimestamp: String,
        eventCount: Int,
        boundaryReason: TaskBoundaryReason
    ) {
        self.taskChunkSchemaVersion = taskChunkSchemaVersion
        self.startTimestamp = startTimestamp
        self.endTimestamp = endTimestamp
        self.eventCount = eventCount
        self.boundaryReason = boundaryReason
    }
}
