import Foundation

public struct AssistLoopInput {
    public let traceId: String
    public let sessionId: String
    public let taskId: String?
    public let timestamp: String
    public let teacherConfirmed: Bool
    public let emergencyStopActive: Bool
    public let completedStepCount: Int
    public let currentAppName: String?
    public let currentAppBundleId: String?
    public let knowledgeItems: [KnowledgeItem]

    public init(
        traceId: String,
        sessionId: String,
        taskId: String? = nil,
        timestamp: String,
        teacherConfirmed: Bool,
        emergencyStopActive: Bool = false,
        completedStepCount: Int,
        currentAppName: String?,
        currentAppBundleId: String?,
        knowledgeItems: [KnowledgeItem]
    ) {
        self.traceId = traceId
        self.sessionId = sessionId
        self.taskId = taskId
        self.timestamp = timestamp
        self.teacherConfirmed = teacherConfirmed
        self.emergencyStopActive = emergencyStopActive
        self.completedStepCount = max(0, completedStepCount)
        self.currentAppName = currentAppName
        self.currentAppBundleId = currentAppBundleId
        self.knowledgeItems = knowledgeItems
    }
}

public struct AssistPredictionInput {
    public let completedStepCount: Int
    public let currentAppName: String?
    public let currentAppBundleId: String?
    public let knowledgeItems: [KnowledgeItem]

    public init(
        completedStepCount: Int,
        currentAppName: String?,
        currentAppBundleId: String?,
        knowledgeItems: [KnowledgeItem]
    ) {
        self.completedStepCount = completedStepCount
        self.currentAppName = currentAppName
        self.currentAppBundleId = currentAppBundleId
        self.knowledgeItems = knowledgeItems
    }
}

public protocol AssistNextActionPredicting {
    func predict(input: AssistPredictionInput) -> AssistSuggestion?
}

public struct RuleBasedAssistNextActionPredictor: AssistNextActionPredicting {
    public init() {}

    public func predict(input: AssistPredictionInput) -> AssistSuggestion? {
        let appBundle = input.currentAppBundleId?.lowercased()

        let appMatchedItems: [KnowledgeItem]
        if let appBundle, !appBundle.isEmpty {
            appMatchedItems = input.knowledgeItems.filter { $0.context.appBundleId.lowercased() == appBundle }
        } else {
            appMatchedItems = []
        }

        if let suggestion = buildSuggestion(
            from: appMatchedItems,
            completedStepCount: input.completedStepCount,
            confidence: 0.82,
            reasonPrefix: "Rule matched frontmost app"
        ) {
            return suggestion
        }

        return buildSuggestion(
            from: input.knowledgeItems,
            completedStepCount: input.completedStepCount,
            confidence: 0.66,
            reasonPrefix: "Rule fallback to first available knowledge item"
        )
    }

    private func buildSuggestion(
        from items: [KnowledgeItem],
        completedStepCount: Int,
        confidence: Double,
        reasonPrefix: String
    ) -> AssistSuggestion? {
        for item in items {
            guard completedStepCount < item.steps.count else {
                continue
            }

            let step = item.steps[completedStepCount]
            let action = AssistSuggestedAction(
                type: inferActionType(from: step.instruction),
                instruction: step.instruction,
                reason: "\(reasonPrefix): \(item.context.appName)"
            )

            return AssistSuggestion(
                suggestionId: "assist-\(item.taskId)-\(step.stepId)",
                knowledgeItemId: item.knowledgeItemId,
                taskId: item.taskId,
                stepId: step.stepId,
                action: action,
                confidence: confidence
            )
        }

        return nil
    }

    private func inferActionType(from instruction: String) -> AssistActionType {
        if instruction.contains("点击") {
            return .click
        }
        if instruction.contains("输入") {
            return .input
        }
        if instruction.contains("快捷键") {
            return .shortcut
        }
        return .generic
    }
}

public protocol AssistConfirmationPrompting {
    func requestConfirmation(for suggestion: AssistSuggestion) -> AssistConfirmationDecision
}

public struct AssistPopupConfirmationPrompter: AssistConfirmationPrompting {
    private let forcedDecision: Bool?
    private let nowProvider: () -> Date
    private let formatter: ISO8601DateFormatter

    public init(
        forcedDecision: Bool? = nil,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.forcedDecision = forcedDecision
        self.nowProvider = nowProvider

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.formatter = formatter
    }

    public func requestConfirmation(for suggestion: AssistSuggestion) -> AssistConfirmationDecision {
        let timestamp = formatter.string(from: nowProvider())

        if let forcedDecision {
            print("Assist Popup (mock): \(suggestion.action.instruction)")
            print("Teacher response from CLI flag: \(forcedDecision ? "confirm" : "reject")")
            return AssistConfirmationDecision(
                confirmed: forcedDecision,
                source: .cliFlag,
                respondedAt: timestamp
            )
        }

        print("Assist Popup (mock):")
        print("预测下一步：\(suggestion.action.instruction)")
        print("是否确认执行？输入 y/yes 确认，其他输入拒绝。")
        let raw = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let confirmed = raw == "y" || raw == "yes"
        return AssistConfirmationDecision(
            confirmed: confirmed,
            source: .popupMock,
            respondedAt: timestamp
        )
    }
}

public final class AssistModeLoopOrchestrator {
    private let modeStateMachine: ModeStateMachine
    private let predictor: AssistNextActionPredicting
    private let confirmationPrompter: AssistConfirmationPrompting
    private let actionExecutor: AssistActionExecuting
    private let logWriter: AssistLoopLogWriting
    private let nowProvider: () -> Date
    private let formatter: ISO8601DateFormatter
    private let outputEncoder: JSONEncoder

    public init(
        modeStateMachine: ModeStateMachine,
        predictor: AssistNextActionPredicting,
        confirmationPrompter: AssistConfirmationPrompting,
        actionExecutor: AssistActionExecuting,
        logWriter: AssistLoopLogWriting,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.modeStateMachine = modeStateMachine
        self.predictor = predictor
        self.confirmationPrompter = confirmationPrompter
        self.actionExecutor = actionExecutor
        self.logWriter = logWriter
        self.nowProvider = nowProvider

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.formatter = formatter

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.outputEncoder = encoder
    }

    public func run(
        input: AssistLoopInput,
        executionContext: AssistExecutionContext
    ) throws -> AssistLoopRunResult {
        var latestLogFile: URL?

        if input.emergencyStopActive || executionContext.emergencyStopActive {
            latestLogFile = try appendLog(
                input: input,
                status: AssistLoopStatusCode.executionFailed.rawValue,
                errorCode: AssistLoopErrorCode.blockedAction.rawValue,
                message: "Assist loop blocked by emergency stop.",
                suggestion: nil
            )

            return AssistLoopRunResult(
                finalStatus: .blockedByState,
                suggestion: nil,
                confirmation: nil,
                execution: nil,
                logFilePath: latestLogFile?.path ?? "",
                message: "Emergency stop is active."
            )
        }

        if modeStateMachine.currentMode != .assist {
            let transitionDecision = modeStateMachine.transition(
                to: .assist,
                context: ModeTransitionContext(
                    traceId: input.traceId,
                    sessionId: input.sessionId,
                    taskId: input.taskId,
                    timestamp: input.timestamp,
                    teacherConfirmed: input.teacherConfirmed,
                    learnedKnowledgeReady: !input.knowledgeItems.isEmpty,
                    emergencyStopActive: input.emergencyStopActive
                )
            )

            if !transitionDecision.accepted {
                latestLogFile = try appendLog(
                    input: input,
                    status: transitionDecision.status.rawValue,
                    errorCode: transitionDecision.errorCode?.rawValue ?? AssistLoopErrorCode.modeTransitionRejected.rawValue,
                    message: "Assist mode transition rejected: \(transitionDecision.message)",
                    suggestion: nil
                )

                return AssistLoopRunResult(
                    finalStatus: .blockedByState,
                    suggestion: nil,
                    confirmation: nil,
                    execution: nil,
                    logFilePath: latestLogFile?.path ?? "",
                    message: transitionDecision.message
                )
            }
        }

        let prediction = predictor.predict(
            input: AssistPredictionInput(
                completedStepCount: input.completedStepCount,
                currentAppName: input.currentAppName,
                currentAppBundleId: input.currentAppBundleId,
                knowledgeItems: input.knowledgeItems
            )
        )

        guard let suggestion = prediction else {
            latestLogFile = try appendLog(
                input: input,
                status: AssistLoopStatusCode.predicted.rawValue,
                errorCode: AssistLoopErrorCode.predictionNotFound.rawValue,
                message: "No next action was predicted by rule strategy.",
                suggestion: nil
            )

            return AssistLoopRunResult(
                finalStatus: .noSuggestion,
                suggestion: nil,
                confirmation: nil,
                execution: nil,
                logFilePath: latestLogFile?.path ?? "",
                message: "No suggestion available."
            )
        }

        latestLogFile = try appendLog(
            input: input,
            status: AssistLoopStatusCode.predicted.rawValue,
            message: "Predicted next action by rule strategy.",
            suggestion: suggestion
        )

        latestLogFile = try appendLog(
            input: input,
            status: AssistLoopStatusCode.waitingConfirmation.rawValue,
            message: "Waiting for teacher confirmation.",
            suggestion: suggestion
        )

        let confirmation = confirmationPrompter.requestConfirmation(for: suggestion)
        if !confirmation.confirmed {
            latestLogFile = try appendLog(
                input: input,
                status: AssistLoopStatusCode.confirmationRejected.rawValue,
                errorCode: AssistLoopErrorCode.confirmationRejected.rawValue,
                message: "Teacher rejected the assist suggestion.",
                suggestion: suggestion
            )

            return AssistLoopRunResult(
                finalStatus: .skippedByTeacher,
                suggestion: suggestion,
                confirmation: confirmation,
                execution: nil,
                logFilePath: latestLogFile?.path ?? "",
                message: "Teacher rejected suggestion."
            )
        }

        latestLogFile = try appendLog(
            input: input,
            status: AssistLoopStatusCode.confirmationAccepted.rawValue,
            message: "Teacher confirmed the assist suggestion.",
            suggestion: suggestion
        )

        latestLogFile = try appendLog(
            input: input,
            status: AssistLoopStatusCode.executionStarted.rawValue,
            message: "Executing assist suggestion.",
            suggestion: suggestion
        )

        let execution = actionExecutor.execute(suggestion: suggestion, context: executionContext)
        switch execution.status {
        case .succeeded:
            latestLogFile = try appendLog(
                input: input,
                status: AssistLoopStatusCode.executionCompleted.rawValue,
                message: execution.output,
                suggestion: suggestion
            )

            return AssistLoopRunResult(
                finalStatus: .completed,
                suggestion: suggestion,
                confirmation: confirmation,
                execution: execution,
                logFilePath: latestLogFile?.path ?? "",
                message: "Assist loop completed."
            )
        case .failed, .blocked:
            latestLogFile = try appendLog(
                input: input,
                status: AssistLoopStatusCode.executionFailed.rawValue,
                errorCode: execution.errorCode?.rawValue ?? AssistLoopErrorCode.executionFailed.rawValue,
                message: execution.output,
                suggestion: suggestion
            )

            return AssistLoopRunResult(
                finalStatus: .executionFailed,
                suggestion: suggestion,
                confirmation: confirmation,
                execution: execution,
                logFilePath: latestLogFile?.path ?? "",
                message: "Assist execution failed."
            )
        }
    }

    @discardableResult
    private func appendLog(
        input: AssistLoopInput,
        status: String,
        errorCode: String? = nil,
        message: String,
        suggestion: AssistSuggestion?
    ) throws -> URL {
        let entry = AssistLoopLogEntry(
            timestamp: formatter.string(from: nowProvider()),
            traceId: input.traceId,
            sessionId: input.sessionId,
            taskId: input.taskId,
            status: status,
            errorCode: errorCode,
            message: message,
            suggestionId: suggestion?.suggestionId,
            knowledgeItemId: suggestion?.knowledgeItemId,
            stepId: suggestion?.stepId
        )

        let url = try logWriter.write(entry)
        if let data = try? outputEncoder.encode(entry),
           let line = String(data: data, encoding: .utf8) {
            print(line)
        }
        return url
    }
}
