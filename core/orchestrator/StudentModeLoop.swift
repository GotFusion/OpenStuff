import Foundation

public struct StudentLoopInput {
    public let traceId: String
    public let sessionId: String
    public let taskId: String?
    public let timestamp: String
    public let teacherConfirmed: Bool
    public let emergencyStopActive: Bool
    public let goal: String
    public let preferredKnowledgeItemId: String?
    public let pendingAssistSuggestion: Bool
    public let knowledgeItems: [KnowledgeItem]

    public init(
        traceId: String,
        sessionId: String,
        taskId: String? = nil,
        timestamp: String,
        teacherConfirmed: Bool,
        emergencyStopActive: Bool = false,
        goal: String,
        preferredKnowledgeItemId: String? = nil,
        pendingAssistSuggestion: Bool = false,
        knowledgeItems: [KnowledgeItem]
    ) {
        self.traceId = traceId
        self.sessionId = sessionId
        self.taskId = taskId
        self.timestamp = timestamp
        self.teacherConfirmed = teacherConfirmed
        self.emergencyStopActive = emergencyStopActive
        self.goal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        self.preferredKnowledgeItemId = preferredKnowledgeItemId
        self.pendingAssistSuggestion = pendingAssistSuggestion
        self.knowledgeItems = knowledgeItems
    }
}

public struct StudentPlanningInput {
    public let goal: String
    public let preferredKnowledgeItemId: String?
    public let knowledgeItems: [KnowledgeItem]

    public init(
        goal: String,
        preferredKnowledgeItemId: String?,
        knowledgeItems: [KnowledgeItem]
    ) {
        self.goal = goal
        self.preferredKnowledgeItemId = preferredKnowledgeItemId
        self.knowledgeItems = knowledgeItems
    }
}

public protocol StudentTaskPlanning {
    func plan(input: StudentPlanningInput) -> StudentExecutionPlan?
}

public struct RuleBasedStudentTaskPlanner: StudentTaskPlanning {
    public init() {}

    public func plan(input: StudentPlanningInput) -> StudentExecutionPlan? {
        guard !input.goal.isEmpty else {
            return nil
        }

        let normalizedGoal = input.goal.lowercased()
        let ranked = input.knowledgeItems
            .filter { !$0.steps.isEmpty }
            .map { item in (item, score(item: item, normalizedGoal: normalizedGoal, preferredId: input.preferredKnowledgeItemId)) }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.knowledgeItemId < rhs.0.knowledgeItemId
                }
                return lhs.1 > rhs.1
            }

        guard let selected = ranked.first?.0 else {
            return nil
        }

        let steps = selected.steps.enumerated().map { index, step in
            let planStepId = String(format: "plan-step-%03d", index + 1)
            let skillId = "openstaff-skill-\(selected.taskId)-\(step.stepId)"
            let confidence = max(0.55, 0.86 - Double(index) * 0.03)
            return StudentPlannedStep(
                planStepId: planStepId,
                skillId: skillId,
                instruction: step.instruction,
                sourceKnowledgeItemId: selected.knowledgeItemId,
                sourceStepId: step.stepId,
                confidence: confidence
            )
        }

        return StudentExecutionPlan(
            planId: "student-plan-\(selected.taskId)",
            goal: input.goal,
            selectedKnowledgeItemId: selected.knowledgeItemId,
            selectedTaskId: selected.taskId,
            strategy: .ruleV0,
            steps: steps
        )
    }

    private func score(
        item: KnowledgeItem,
        normalizedGoal: String,
        preferredId: String?
    ) -> Int {
        var value = 0
        if preferredId == item.knowledgeItemId {
            value += 100
        }
        if normalizedGoal.contains(item.context.appName.lowercased()) {
            value += 20
        }
        if normalizedGoal.contains(item.context.appBundleId.lowercased()) {
            value += 18
        }
        if normalizedGoal.contains(item.goal.lowercased()) {
            value += 12
        }
        if let firstStep = item.steps.first?.instruction.lowercased(),
           normalizedGoal.contains(firstStep) {
            value += 8
        }
        value += min(item.steps.count, 5)
        return value
    }
}

public final class StudentModeLoopOrchestrator {
    private let modeStateMachine: ModeStateMachine
    private let planner: StudentTaskPlanning
    private let skillExecutor: StudentSkillExecuting
    private let logWriter: StudentLoopLogWriting
    private let reportWriter: StudentReviewReportWriting
    private let nowProvider: () -> Date
    private let formatter: ISO8601DateFormatter
    private let outputEncoder: JSONEncoder

    public init(
        modeStateMachine: ModeStateMachine,
        planner: StudentTaskPlanning,
        skillExecutor: StudentSkillExecuting,
        logWriter: StudentLoopLogWriting,
        reportWriter: StudentReviewReportWriting,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.modeStateMachine = modeStateMachine
        self.planner = planner
        self.skillExecutor = skillExecutor
        self.logWriter = logWriter
        self.reportWriter = reportWriter
        self.nowProvider = nowProvider

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.formatter = formatter

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.outputEncoder = encoder
    }

    public func run(
        input: StudentLoopInput,
        executionContext: StudentExecutionContext
    ) throws -> StudentLoopRunResult {
        var latestLogFile: URL?
        let startedAt = formatter.string(from: nowProvider())

        if input.emergencyStopActive || executionContext.emergencyStopActive {
            latestLogFile = try appendLog(
                input: input,
                status: StudentLoopStatusCode.executionFailed.rawValue,
                errorCode: StudentLoopErrorCode.blockedAction.rawValue,
                message: "Student loop blocked by emergency stop.",
                plan: nil,
                step: nil
            )

            return StudentLoopRunResult(
                finalStatus: .blockedByState,
                plan: nil,
                report: nil,
                logFilePath: latestLogFile?.path ?? "",
                reportFilePath: nil,
                message: "Emergency stop is active."
            )
        }

        guard let plan = planner.plan(
            input: StudentPlanningInput(
                goal: input.goal,
                preferredKnowledgeItemId: input.preferredKnowledgeItemId,
                knowledgeItems: input.knowledgeItems
            )
        ) else {
            latestLogFile = try appendLog(
                input: input,
                status: StudentLoopStatusCode.planningReady.rawValue,
                errorCode: StudentLoopErrorCode.planningNotFound.rawValue,
                message: "Rule planner failed to produce execution plan.",
                plan: nil,
                step: nil
            )

            return StudentLoopRunResult(
                finalStatus: .noPlan,
                plan: nil,
                report: nil,
                logFilePath: latestLogFile?.path ?? "",
                reportFilePath: nil,
                message: "No execution plan was generated."
            )
        }

        if modeStateMachine.currentMode != .student {
            let transitionDecision = modeStateMachine.transition(
                to: .student,
                context: ModeTransitionContext(
                    traceId: input.traceId,
                    sessionId: input.sessionId,
                    taskId: input.taskId ?? plan.selectedTaskId,
                    timestamp: input.timestamp,
                    teacherConfirmed: input.teacherConfirmed,
                    learnedKnowledgeReady: !input.knowledgeItems.isEmpty,
                    executionPlanReady: !plan.steps.isEmpty,
                    pendingAssistSuggestion: input.pendingAssistSuggestion,
                    emergencyStopActive: input.emergencyStopActive
                )
            )

            if !transitionDecision.accepted {
                latestLogFile = try appendLog(
                    input: input,
                    status: transitionDecision.status.rawValue,
                    errorCode: transitionDecision.errorCode?.rawValue ?? StudentLoopErrorCode.modeTransitionRejected.rawValue,
                    message: "Student mode transition rejected: \(transitionDecision.message)",
                    plan: plan,
                    step: nil
                )

                return StudentLoopRunResult(
                    finalStatus: .blockedByState,
                    plan: plan,
                    report: nil,
                    logFilePath: latestLogFile?.path ?? "",
                    reportFilePath: nil,
                    message: transitionDecision.message
                )
            }
        }

        latestLogFile = try appendLog(
            input: input,
            status: StudentLoopStatusCode.planningReady.rawValue,
            message: "Rule planner generated student execution plan.",
            plan: plan,
            step: nil
        )

        var stepResults: [StudentStepExecutionResult] = []
        var finalStatus: StudentLoopFinalStatus = .completed

        for (index, step) in plan.steps.enumerated() {
            latestLogFile = try appendLog(
                input: input,
                status: StudentLoopStatusCode.executionStarted.rawValue,
                message: "Executing planned skill step.",
                plan: plan,
                step: step
            )

            let result = skillExecutor.execute(step: step, stepIndex: index, context: executionContext)
            stepResults.append(result)

            switch result.status {
            case .succeeded:
                latestLogFile = try appendLog(
                    input: input,
                    status: StudentLoopStatusCode.executionCompleted.rawValue,
                    message: result.output,
                    plan: plan,
                    step: step
                )
            case .failed, .blocked:
                finalStatus = .executionFailed
                latestLogFile = try appendLog(
                    input: input,
                    status: StudentLoopStatusCode.executionFailed.rawValue,
                    errorCode: result.errorCode?.rawValue ?? StudentLoopErrorCode.executionFailed.rawValue,
                    message: result.output,
                    plan: plan,
                    step: step
                )
                break
            }

            if finalStatus == .executionFailed {
                break
            }
        }

        let report = buildReport(
            input: input,
            plan: plan,
            stepResults: stepResults,
            startedAt: startedAt,
            finishedAt: formatter.string(from: nowProvider()),
            finalStatus: finalStatus
        )
        let reportURL = try reportWriter.write(report)

        latestLogFile = try appendLog(
            input: input,
            status: StudentLoopStatusCode.reviewGenerated.rawValue,
            message: "Structured review report generated at \(reportURL.path).",
            plan: plan,
            step: nil
        )

        return StudentLoopRunResult(
            finalStatus: finalStatus,
            plan: plan,
            report: report,
            logFilePath: latestLogFile?.path ?? "",
            reportFilePath: reportURL.path,
            message: finalStatus == .completed ? "Student loop completed." : "Student loop stopped due to execution failure."
        )
    }

    private func buildReport(
        input: StudentLoopInput,
        plan: StudentExecutionPlan,
        stepResults: [StudentStepExecutionResult],
        startedAt: String,
        finishedAt: String,
        finalStatus: StudentLoopFinalStatus
    ) -> StudentReviewReport {
        let succeededSteps = stepResults.filter { $0.status == .succeeded }.count
        let failedSteps = stepResults.filter { $0.status == .failed }.count
        let blockedSteps = stepResults.filter { $0.status == .blocked }.count
        let totalSteps = plan.steps.count
        let summary = "目标：\(input.goal)；计划步骤 \(totalSteps)；成功 \(succeededSteps)；失败 \(failedSteps)；阻断 \(blockedSteps)。"

        return StudentReviewReport(
            reportId: "student-review-\(input.sessionId)-\(plan.selectedTaskId)",
            traceId: input.traceId,
            sessionId: input.sessionId,
            taskId: input.taskId ?? plan.selectedTaskId,
            goal: input.goal,
            plan: plan,
            stepResults: stepResults,
            startedAt: startedAt,
            finishedAt: finishedAt,
            totalSteps: totalSteps,
            succeededSteps: succeededSteps,
            failedSteps: failedSteps,
            blockedSteps: blockedSteps,
            finalStatus: finalStatus,
            summary: summary
        )
    }

    @discardableResult
    private func appendLog(
        input: StudentLoopInput,
        status: String,
        errorCode: String? = nil,
        message: String,
        plan: StudentExecutionPlan?,
        step: StudentPlannedStep?
    ) throws -> URL {
        let entry = StudentLoopLogEntry(
            timestamp: formatter.string(from: nowProvider()),
            traceId: input.traceId,
            sessionId: input.sessionId,
            taskId: input.taskId ?? plan?.selectedTaskId,
            status: status,
            errorCode: errorCode,
            message: message,
            planId: plan?.planId,
            skillId: step?.skillId,
            planStepId: step?.planStepId
        )

        let url = try logWriter.write(entry)
        if let data = try? outputEncoder.encode(entry),
           let line = String(data: data, encoding: .utf8) {
            print(line)
        }
        return url
    }
}
