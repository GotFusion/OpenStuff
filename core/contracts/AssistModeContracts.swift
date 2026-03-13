import Foundation

// MARK: - Prediction

public enum AssistPredictionStrategy: String, Codable, Sendable {
    case ruleV0
    case retrievalV1
    case modelV1Placeholder
}

public enum AssistActionType: String, Codable, Sendable {
    case click
    case input
    case shortcut
    case generic
}

public struct AssistSuggestedAction: Codable, Equatable, Sendable {
    public let type: AssistActionType
    public let instruction: String
    public let reason: String

    public init(type: AssistActionType, instruction: String, reason: String) {
        self.type = type
        self.instruction = instruction
        self.reason = reason
    }
}

public struct AssistSuggestion: Codable, Equatable, Sendable {
    public let suggestionId: String
    public let knowledgeItemId: String
    public let taskId: String
    public let stepId: String
    public let action: AssistSuggestedAction
    public let confidence: Double
    public let evidence: [AssistPredictionEvidence]
    public let predictorVersion: String

    public init(
        suggestionId: String,
        knowledgeItemId: String,
        taskId: String,
        stepId: String,
        action: AssistSuggestedAction,
        confidence: Double,
        evidence: [AssistPredictionEvidence] = [],
        predictorVersion: String = AssistPredictionStrategy.ruleV0.rawValue
    ) {
        self.suggestionId = suggestionId
        self.knowledgeItemId = knowledgeItemId
        self.taskId = taskId
        self.stepId = stepId
        self.action = action
        self.confidence = confidence
        self.evidence = evidence
        self.predictorVersion = predictorVersion
    }
}

// MARK: - Confirmation

public enum AssistConfirmationSource: String, Codable, Sendable {
    case popupMock
    case cliFlag
}

public struct AssistConfirmationDecision: Codable, Equatable, Sendable {
    public let confirmed: Bool
    public let source: AssistConfirmationSource
    public let respondedAt: String

    public init(confirmed: Bool, source: AssistConfirmationSource, respondedAt: String) {
        self.confirmed = confirmed
        self.source = source
        self.respondedAt = respondedAt
    }
}

// MARK: - Execution

public enum AssistExecutionStatus: String, Codable, Sendable {
    case succeeded
    case failed
    case blocked
}

public struct AssistExecutionOutcome: Codable, Equatable, Sendable {
    public let status: AssistExecutionStatus
    public let output: String
    public let executedAt: String
    public let errorCode: AssistLoopErrorCode?

    public init(
        status: AssistExecutionStatus,
        output: String,
        executedAt: String,
        errorCode: AssistLoopErrorCode? = nil
    ) {
        self.status = status
        self.output = output
        self.executedAt = executedAt
        self.errorCode = errorCode
    }
}

// MARK: - Result

public enum AssistLoopFinalStatus: String, Codable, Sendable {
    case completed
    case skippedByTeacher
    case noSuggestion
    case blockedByState
    case executionFailed
}

public struct AssistLoopRunResult: Codable, Equatable, Sendable {
    public let finalStatus: AssistLoopFinalStatus
    public let suggestion: AssistSuggestion?
    public let confirmation: AssistConfirmationDecision?
    public let execution: AssistExecutionOutcome?
    public let logFilePath: String
    public let message: String

    public init(
        finalStatus: AssistLoopFinalStatus,
        suggestion: AssistSuggestion?,
        confirmation: AssistConfirmationDecision?,
        execution: AssistExecutionOutcome?,
        logFilePath: String,
        message: String
    ) {
        self.finalStatus = finalStatus
        self.suggestion = suggestion
        self.confirmation = confirmation
        self.execution = execution
        self.logFilePath = logFilePath
        self.message = message
    }
}

// MARK: - Status and Error Code

public enum AssistLoopStatusCode: String, Codable, Sendable {
    case predicted = "STATUS_ORC_ASSIST_PREDICTED"
    case waitingConfirmation = "STATUS_ORC_WAITING_CONFIRMATION"
    case confirmationAccepted = "STATUS_ORC_ASSIST_CONFIRMATION_ACCEPTED"
    case confirmationRejected = "STATUS_ORC_ASSIST_CONFIRMATION_REJECTED"
    case executionStarted = "STATUS_EXE_ASSIST_EXECUTION_STARTED"
    case executionCompleted = "STATUS_EXE_ASSIST_EXECUTION_COMPLETED"
    case executionFailed = "STATUS_EXE_ASSIST_EXECUTION_FAILED"
}

public enum AssistLoopErrorCode: String, Codable, Sendable {
    case predictionNotFound = "ORC-PREDICTION-NOT-FOUND"
    case confirmationRejected = "ORC-CONFIRMATION-REJECTED"
    case blockedAction = "EXE-ACTION-BLOCKED"
    case executionFailed = "EXE-ACTION-FAILED"
    case modeTransitionRejected = "ORC-STATE-TRANSITION-DENIED"
}

public struct AssistLoopLogEntry: Codable, Equatable, Sendable {
    public let timestamp: String
    public let traceId: String
    public let sessionId: String
    public let taskId: String?
    public let component: String
    public let status: String
    public let errorCode: String?
    public let message: String
    public let suggestionId: String?
    public let knowledgeItemId: String?
    public let stepId: String?

    public init(
        timestamp: String,
        traceId: String,
        sessionId: String,
        taskId: String?,
        component: String = "assist.loop",
        status: String,
        errorCode: String? = nil,
        message: String,
        suggestionId: String? = nil,
        knowledgeItemId: String? = nil,
        stepId: String? = nil
    ) {
        self.timestamp = timestamp
        self.traceId = traceId
        self.sessionId = sessionId
        self.taskId = taskId
        self.component = component
        self.status = status
        self.errorCode = errorCode
        self.message = message
        self.suggestionId = suggestionId
        self.knowledgeItemId = knowledgeItemId
        self.stepId = stepId
    }
}
