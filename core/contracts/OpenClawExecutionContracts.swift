import Foundation

public enum OpenClawExecutionStatus: String, Codable, Sendable {
    case succeeded
    case failed
    case blocked
}

public enum OpenClawExecutionErrorCode: String, Codable, Sendable {
    case runnerInvalidRequest = "OCW-RUNNER-INVALID-REQUEST"
    case runtimeExecutableMissing = "OCW-RUNNER-EXECUTABLE-MISSING"
    case processLaunchFailed = "OCW-RUNNER-LAUNCH-FAILED"
    case processTimedOut = "OCW-RUNNER-TIMED-OUT"
    case skillPreflightFailed = "OCW-SKILL-PREFLIGHT-FAILED"
    case skillConfirmationRequired = "OCW-SKILL-CONFIRMATION-REQUIRED"
    case invalidRuntimeOutput = "OCW-RUNTIME-INVALID-OUTPUT"
    case invalidSkillBundle = "OCW-SKILL-INVALID"
    case runtimeFailed = "OCW-RUNTIME-FAILED"
    case runtimeBlocked = "OCW-RUNTIME-BLOCKED"
    case logWriteFailed = "OCW-RUNNER-LOG-WRITE-FAILED"
}

public struct OpenClawExecutionRequest: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let traceId: String
    public let sessionId: String
    public let taskId: String?
    public let skillName: String
    public let skillDirectoryPath: String
    public let runtimeExecutablePath: String
    public let runtimeArguments: [String]
    public let runtimeEnvironment: [String: String]
    public let workingDirectoryPath: String?
    public let logsRootDirectoryPath: String
    public let component: String
    public let timeoutSeconds: Int?
    public let teacherConfirmed: Bool

    public init(
        schemaVersion: String = "openstaff.openclaw.execution-request.v0",
        traceId: String,
        sessionId: String,
        taskId: String? = nil,
        skillName: String,
        skillDirectoryPath: String,
        runtimeExecutablePath: String,
        runtimeArguments: [String],
        runtimeEnvironment: [String: String] = [:],
        workingDirectoryPath: String? = nil,
        logsRootDirectoryPath: String = "data/logs",
        component: String = "student.openclaw.runner",
        timeoutSeconds: Int? = 30,
        teacherConfirmed: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.traceId = traceId
        self.sessionId = sessionId
        self.taskId = taskId
        self.skillName = skillName
        self.skillDirectoryPath = skillDirectoryPath
        self.runtimeExecutablePath = runtimeExecutablePath
        self.runtimeArguments = runtimeArguments
        self.runtimeEnvironment = runtimeEnvironment
        self.workingDirectoryPath = workingDirectoryPath
        self.logsRootDirectoryPath = logsRootDirectoryPath
        self.component = component
        self.timeoutSeconds = timeoutSeconds
        self.teacherConfirmed = teacherConfirmed
    }
}

public struct OpenClawExecutionStepResult: Codable, Equatable, Sendable {
    public let stepId: String
    public let actionType: String
    public let status: OpenClawExecutionStatus
    public let startedAt: String
    public let finishedAt: String
    public let output: String
    public let errorCode: String?

    public init(
        stepId: String,
        actionType: String,
        status: OpenClawExecutionStatus,
        startedAt: String,
        finishedAt: String,
        output: String,
        errorCode: String? = nil
    ) {
        self.stepId = stepId
        self.actionType = actionType
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.output = output
        self.errorCode = errorCode
    }
}

public struct OpenClawGatewayExecutionPayload: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let traceId: String
    public let sessionId: String
    public let taskId: String?
    public let skillName: String
    public let skillDirectoryPath: String
    public let status: OpenClawExecutionStatus
    public let errorCode: String?
    public let startedAt: String
    public let finishedAt: String
    public let summary: String
    public let totalSteps: Int
    public let succeededSteps: Int
    public let failedSteps: Int
    public let blockedSteps: Int
    public let stepResults: [OpenClawExecutionStepResult]

    public init(
        schemaVersion: String = "openstaff.openclaw.gateway-result.v0",
        traceId: String,
        sessionId: String,
        taskId: String? = nil,
        skillName: String,
        skillDirectoryPath: String,
        status: OpenClawExecutionStatus,
        errorCode: String? = nil,
        startedAt: String,
        finishedAt: String,
        summary: String,
        totalSteps: Int,
        succeededSteps: Int,
        failedSteps: Int,
        blockedSteps: Int,
        stepResults: [OpenClawExecutionStepResult]
    ) {
        self.schemaVersion = schemaVersion
        self.traceId = traceId
        self.sessionId = sessionId
        self.taskId = taskId
        self.skillName = skillName
        self.skillDirectoryPath = skillDirectoryPath
        self.status = status
        self.errorCode = errorCode
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.summary = summary
        self.totalSteps = totalSteps
        self.succeededSteps = succeededSteps
        self.failedSteps = failedSteps
        self.blockedSteps = blockedSteps
        self.stepResults = stepResults
    }
}

public struct OpenClawExecutionReview: Codable, Equatable, Sendable {
    public let reviewId: String
    public let traceId: String
    public let sessionId: String
    public let taskId: String?
    public let skillName: String
    public let skillDirectoryPath: String
    public let component: String
    public let status: OpenClawExecutionStatus
    public let errorCode: String?
    public let startedAt: String
    public let finishedAt: String
    public let totalSteps: Int
    public let succeededSteps: Int
    public let failedSteps: Int
    public let blockedSteps: Int
    public let summary: String
    public let logFilePath: String
    public let exitCode: Int32?
    public let preflight: SkillPreflightReport?

    public init(
        reviewId: String,
        traceId: String,
        sessionId: String,
        taskId: String? = nil,
        skillName: String,
        skillDirectoryPath: String,
        component: String,
        status: OpenClawExecutionStatus,
        errorCode: String? = nil,
        startedAt: String,
        finishedAt: String,
        totalSteps: Int,
        succeededSteps: Int,
        failedSteps: Int,
        blockedSteps: Int,
        summary: String,
        logFilePath: String,
        exitCode: Int32? = nil,
        preflight: SkillPreflightReport? = nil
    ) {
        self.reviewId = reviewId
        self.traceId = traceId
        self.sessionId = sessionId
        self.taskId = taskId
        self.skillName = skillName
        self.skillDirectoryPath = skillDirectoryPath
        self.component = component
        self.status = status
        self.errorCode = errorCode
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.totalSteps = totalSteps
        self.succeededSteps = succeededSteps
        self.failedSteps = failedSteps
        self.blockedSteps = blockedSteps
        self.summary = summary
        self.logFilePath = logFilePath
        self.exitCode = exitCode
        self.preflight = preflight
    }
}

public struct OpenClawExecutionResult: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let traceId: String
    public let sessionId: String
    public let taskId: String?
    public let skillName: String
    public let skillDirectoryPath: String
    public let runtimeExecutablePath: String
    public let runtimeArguments: [String]
    public let status: OpenClawExecutionStatus
    public let errorCode: String?
    public let exitCode: Int32?
    public let startedAt: String
    public let finishedAt: String
    public let stdout: String
    public let stderr: String
    public let summary: String
    public let totalSteps: Int
    public let succeededSteps: Int
    public let failedSteps: Int
    public let blockedSteps: Int
    public let stepResults: [OpenClawExecutionStepResult]
    public let review: OpenClawExecutionReview?
    public let preflight: SkillPreflightReport?

    public init(
        schemaVersion: String = "openstaff.openclaw.execution-result.v0",
        traceId: String,
        sessionId: String,
        taskId: String? = nil,
        skillName: String,
        skillDirectoryPath: String,
        runtimeExecutablePath: String,
        runtimeArguments: [String],
        status: OpenClawExecutionStatus,
        errorCode: String? = nil,
        exitCode: Int32? = nil,
        startedAt: String,
        finishedAt: String,
        stdout: String,
        stderr: String,
        summary: String,
        totalSteps: Int,
        succeededSteps: Int,
        failedSteps: Int,
        blockedSteps: Int,
        stepResults: [OpenClawExecutionStepResult],
        review: OpenClawExecutionReview? = nil,
        preflight: SkillPreflightReport? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.traceId = traceId
        self.sessionId = sessionId
        self.taskId = taskId
        self.skillName = skillName
        self.skillDirectoryPath = skillDirectoryPath
        self.runtimeExecutablePath = runtimeExecutablePath
        self.runtimeArguments = runtimeArguments
        self.status = status
        self.errorCode = errorCode
        self.exitCode = exitCode
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.stdout = stdout
        self.stderr = stderr
        self.summary = summary
        self.totalSteps = totalSteps
        self.succeededSteps = succeededSteps
        self.failedSteps = failedSteps
        self.blockedSteps = blockedSteps
        self.stepResults = stepResults
        self.review = review
        self.preflight = preflight
    }
}

public struct OpenClawExecutionLogEntry: Codable, Equatable, Sendable {
    public let timestamp: String
    public let traceId: String
    public let sessionId: String
    public let taskId: String?
    public let component: String
    public let status: String
    public let errorCode: String?
    public let message: String
    public let skillName: String
    public let skillDirectoryPath: String
    public let stepId: String?
    public let actionType: String?
    public let exitCode: Int32?

    public init(
        timestamp: String,
        traceId: String,
        sessionId: String,
        taskId: String? = nil,
        component: String,
        status: String,
        errorCode: String? = nil,
        message: String,
        skillName: String,
        skillDirectoryPath: String,
        stepId: String? = nil,
        actionType: String? = nil,
        exitCode: Int32? = nil
    ) {
        self.timestamp = timestamp
        self.traceId = traceId
        self.sessionId = sessionId
        self.taskId = taskId
        self.component = component
        self.status = status
        self.errorCode = errorCode
        self.message = message
        self.skillName = skillName
        self.skillDirectoryPath = skillDirectoryPath
        self.stepId = stepId
        self.actionType = actionType
        self.exitCode = exitCode
    }
}
