import Foundation

public struct StudentExecutionContext: Sendable {
    public let traceId: String
    public let sessionId: String
    public let taskId: String?
    public let dryRun: Bool
    public let simulateFailureAtStepIndex: Int?
    public let emergencyStopActive: Bool
    public let blockedKeywords: [String]
    public let blockedRegexPatterns: [String]

    public init(
        traceId: String,
        sessionId: String,
        taskId: String? = nil,
        dryRun: Bool = true,
        simulateFailureAtStepIndex: Int? = nil,
        emergencyStopActive: Bool = false,
        blockedKeywords: [String] = ["删除", "移除", "支付", "转账", "系统设置", "格式化", "抹掉", "重置", "sudo", "rm -rf"],
        blockedRegexPatterns: [String] = [
            #"(?i)\brm\s+-rf\b"#,
            #"(?i)\bsudo\s+"#,
            #"(?i)\bshutdown\b|\breboot\b"#,
            #"(?i)\bdd\s+if="#
        ]
    ) {
        self.traceId = traceId
        self.sessionId = sessionId
        self.taskId = taskId
        self.dryRun = dryRun
        self.simulateFailureAtStepIndex = simulateFailureAtStepIndex
        self.emergencyStopActive = emergencyStopActive
        self.blockedKeywords = blockedKeywords
        self.blockedRegexPatterns = blockedRegexPatterns
    }
}

public protocol StudentSkillExecuting {
    func execute(
        step: StudentPlannedStep,
        stepIndex: Int,
        context: StudentExecutionContext
    ) -> StudentStepExecutionResult
}

public struct StudentSkillExecutor: StudentSkillExecuting {
    private let nowProvider: () -> Date
    private let formatter: ISO8601DateFormatter

    public init(nowProvider: @escaping () -> Date = Date.init) {
        self.nowProvider = nowProvider

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.formatter = formatter
    }

    public func execute(
        step: StudentPlannedStep,
        stepIndex: Int,
        context: StudentExecutionContext
    ) -> StudentStepExecutionResult {
        let startedAt = formatter.string(from: nowProvider())
        let instruction = step.instruction

        if context.emergencyStopActive {
            let finishedAt = formatter.string(from: nowProvider())
            return StudentStepExecutionResult(
                planStepId: step.planStepId,
                skillId: step.skillId,
                status: .blocked,
                startedAt: startedAt,
                finishedAt: finishedAt,
                output: "Blocked by emergency stop.",
                errorCode: .blockedAction
            )
        }

        if let blockedKeyword = context.blockedKeywords.first(where: { instruction.localizedCaseInsensitiveContains($0) }) {
            let finishedAt = formatter.string(from: nowProvider())
            return StudentStepExecutionResult(
                planStepId: step.planStepId,
                skillId: step.skillId,
                status: .blocked,
                startedAt: startedAt,
                finishedAt: finishedAt,
                output: "Blocked by safety rule. keyword=\(blockedKeyword)",
                errorCode: .blockedAction
            )
        }

        if let blockedPattern = firstMatchingPattern(in: instruction, patterns: context.blockedRegexPatterns) {
            let finishedAt = formatter.string(from: nowProvider())
            return StudentStepExecutionResult(
                planStepId: step.planStepId,
                skillId: step.skillId,
                status: .blocked,
                startedAt: startedAt,
                finishedAt: finishedAt,
                output: "Blocked by safety rule. pattern=\(blockedPattern)",
                errorCode: .blockedAction
            )
        }

        if context.simulateFailureAtStepIndex == stepIndex {
            let finishedAt = formatter.string(from: nowProvider())
            return StudentStepExecutionResult(
                planStepId: step.planStepId,
                skillId: step.skillId,
                status: .failed,
                startedAt: startedAt,
                finishedAt: finishedAt,
                output: "Skill execution failed in simulated runtime.",
                errorCode: .executionFailed
            )
        }

        let modeText = context.dryRun ? "dry-run" : "simulated"
        let finishedAt = formatter.string(from: nowProvider())
        return StudentStepExecutionResult(
            planStepId: step.planStepId,
            skillId: step.skillId,
            status: .succeeded,
            startedAt: startedAt,
            finishedAt: finishedAt,
            output: "OpenClaw skill \(modeText) executed: \(step.skillId) :: \(instruction)"
        )
    }

    private func firstMatchingPattern(in text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            if text.range(of: pattern, options: [.regularExpression]) != nil {
                return pattern
            }
        }
        return nil
    }
}
