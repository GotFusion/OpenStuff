import Foundation

public struct AssistExecutionContext: Sendable {
    public let traceId: String
    public let sessionId: String
    public let taskId: String?
    public let dryRun: Bool
    public let simulateFailure: Bool
    public let emergencyStopActive: Bool
    public let blockedKeywords: [String]
    public let blockedRegexPatterns: [String]

    public init(
        traceId: String,
        sessionId: String,
        taskId: String? = nil,
        dryRun: Bool = true,
        simulateFailure: Bool = false,
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
        self.simulateFailure = simulateFailure
        self.emergencyStopActive = emergencyStopActive
        self.blockedKeywords = blockedKeywords
        self.blockedRegexPatterns = blockedRegexPatterns
    }
}

public protocol AssistActionExecuting {
    func execute(suggestion: AssistSuggestion, context: AssistExecutionContext) -> AssistExecutionOutcome
}

public struct AssistActionExecutor: AssistActionExecuting {
    private let nowProvider: () -> Date
    private let formatter: ISO8601DateFormatter

    public init(nowProvider: @escaping () -> Date = Date.init) {
        self.nowProvider = nowProvider

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.formatter = formatter
    }

    public func execute(suggestion: AssistSuggestion, context: AssistExecutionContext) -> AssistExecutionOutcome {
        let timestamp = formatter.string(from: nowProvider())
        let instruction = suggestion.action.instruction

        if context.emergencyStopActive {
            return AssistExecutionOutcome(
                status: .blocked,
                output: "Blocked by emergency stop.",
                executedAt: timestamp,
                errorCode: .blockedAction
            )
        }

        if let blockedKeyword = context.blockedKeywords.first(where: { instruction.localizedCaseInsensitiveContains($0) }) {
            return AssistExecutionOutcome(
                status: .blocked,
                output: "Blocked by safety rule. keyword=\(blockedKeyword)",
                executedAt: timestamp,
                errorCode: .blockedAction
            )
        }

        if let blockedPattern = firstMatchingPattern(in: instruction, patterns: context.blockedRegexPatterns) {
            return AssistExecutionOutcome(
                status: .blocked,
                output: "Blocked by safety rule. pattern=\(blockedPattern)",
                executedAt: timestamp,
                errorCode: .blockedAction
            )
        }

        if context.simulateFailure {
            return AssistExecutionOutcome(
                status: .failed,
                output: "Execution failed in simulated executor.",
                executedAt: timestamp,
                errorCode: .executionFailed
            )
        }

        let modeText = context.dryRun ? "dry-run" : "simulated"
        return AssistExecutionOutcome(
            status: .succeeded,
            output: "Assist action \(modeText) executed: \(instruction)",
            executedAt: timestamp
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
