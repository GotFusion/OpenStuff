import Foundation

public struct AssistPredictionInput: Equatable {
    public let completedStepCount: Int
    public let currentAppName: String?
    public let currentAppBundleId: String?
    public let currentWindowTitle: String?
    public let currentTaskGoal: String?
    public let recentStepInstructions: [String]
    public let knowledgeItems: [KnowledgeItem]

    public init(
        completedStepCount: Int,
        currentAppName: String?,
        currentAppBundleId: String?,
        currentWindowTitle: String? = nil,
        currentTaskGoal: String? = nil,
        recentStepInstructions: [String] = [],
        knowledgeItems: [KnowledgeItem]
    ) {
        self.completedStepCount = max(0, completedStepCount)
        self.currentAppName = currentAppName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.currentAppBundleId = currentAppBundleId?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.currentWindowTitle = currentWindowTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.currentTaskGoal = currentTaskGoal?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.recentStepInstructions = recentStepInstructions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.knowledgeItems = knowledgeItems
    }
}

public enum AssistPredictionSignalType: String, Codable, Sendable {
    case app
    case window
    case recentSequence
    case goal
    case historicalPreference
}

public struct AssistPredictionSignalMatch: Codable, Equatable, Sendable {
    public let type: AssistPredictionSignalType
    public let score: Double
    public let detail: String

    public init(type: AssistPredictionSignalType, score: Double, detail: String) {
        self.type = type
        self.score = score
        self.detail = detail
    }
}

public struct AssistPredictionEvidence: Codable, Equatable, Sendable {
    public let knowledgeItemId: String
    public let taskId: String
    public let sessionId: String
    public let stepId: String
    public let stepInstruction: String
    public let targetDescription: String?
    public let score: Double
    public let matchedSignals: [AssistPredictionSignalMatch]
    public let reason: String

    public init(
        knowledgeItemId: String,
        taskId: String,
        sessionId: String,
        stepId: String,
        stepInstruction: String,
        targetDescription: String? = nil,
        score: Double,
        matchedSignals: [AssistPredictionSignalMatch],
        reason: String
    ) {
        self.knowledgeItemId = knowledgeItemId
        self.taskId = taskId
        self.sessionId = sessionId
        self.stepId = stepId
        self.stepInstruction = stepInstruction
        self.targetDescription = targetDescription
        self.score = score
        self.matchedSignals = matchedSignals
        self.reason = reason
    }
}

public struct AssistKnowledgeRetrievalResult: Codable, Equatable, Sendable {
    public let matches: [AssistPredictionEvidence]

    public init(matches: [AssistPredictionEvidence]) {
        self.matches = matches
    }
}
