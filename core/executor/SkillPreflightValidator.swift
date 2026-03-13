import Foundation

public struct SkillBundlePayload: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let skillName: String
    public let knowledgeItemId: String
    public let taskId: String
    public let sessionId: String
    public let llmOutputAccepted: Bool
    public let createdAt: String
    public let mappedOutput: SkillBundleMappedOutput
    public let provenance: SkillBundleProvenance?

    public init(
        schemaVersion: String,
        skillName: String,
        knowledgeItemId: String,
        taskId: String,
        sessionId: String,
        llmOutputAccepted: Bool,
        createdAt: String,
        mappedOutput: SkillBundleMappedOutput,
        provenance: SkillBundleProvenance? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.skillName = skillName
        self.knowledgeItemId = knowledgeItemId
        self.taskId = taskId
        self.sessionId = sessionId
        self.llmOutputAccepted = llmOutputAccepted
        self.createdAt = createdAt
        self.mappedOutput = mappedOutput
        self.provenance = provenance
    }
}

public struct SkillBundleMappedOutput: Codable, Equatable, Sendable {
    public let objective: String
    public let context: SkillBundleContext
    public let executionPlan: SkillBundleExecutionPlan
    public let safetyNotes: [String]
    public let confidence: Double

    public init(
        objective: String,
        context: SkillBundleContext,
        executionPlan: SkillBundleExecutionPlan,
        safetyNotes: [String],
        confidence: Double
    ) {
        self.objective = objective
        self.context = context
        self.executionPlan = executionPlan
        self.safetyNotes = safetyNotes
        self.confidence = confidence
    }
}

public struct SkillBundleContext: Codable, Equatable, Sendable {
    public let appName: String
    public let appBundleId: String
    public let windowTitle: String?

    public init(appName: String, appBundleId: String, windowTitle: String? = nil) {
        self.appName = appName
        self.appBundleId = appBundleId
        self.windowTitle = windowTitle
    }
}

public struct SkillBundleExecutionPlan: Codable, Equatable, Sendable {
    public let requiresTeacherConfirmation: Bool
    public let steps: [SkillBundleExecutionStep]
    public let completionCriteria: SkillBundleCompletionCriteria

    public init(
        requiresTeacherConfirmation: Bool,
        steps: [SkillBundleExecutionStep],
        completionCriteria: SkillBundleCompletionCriteria
    ) {
        self.requiresTeacherConfirmation = requiresTeacherConfirmation
        self.steps = steps
        self.completionCriteria = completionCriteria
    }
}

public struct SkillBundleCompletionCriteria: Codable, Equatable, Sendable {
    public let expectedStepCount: Int
    public let requiredFrontmostAppBundleId: String

    public init(expectedStepCount: Int, requiredFrontmostAppBundleId: String) {
        self.expectedStepCount = expectedStepCount
        self.requiredFrontmostAppBundleId = requiredFrontmostAppBundleId
    }
}

public struct SkillBundleExecutionStep: Codable, Equatable, Sendable {
    public let stepId: String
    public let actionType: String
    public let instruction: String
    public let target: String
    public let sourceEventIds: [String]

    public init(
        stepId: String,
        actionType: String,
        instruction: String,
        target: String,
        sourceEventIds: [String]
    ) {
        self.stepId = stepId
        self.actionType = actionType
        self.instruction = instruction
        self.target = target
        self.sourceEventIds = sourceEventIds
    }
}

public struct SkillBundleProvenance: Codable, Equatable, Sendable {
    public let skillBuild: SkillBundleSkillBuild?
    public let stepMappings: [SkillBundleStepMapping]

    public init(skillBuild: SkillBundleSkillBuild? = nil, stepMappings: [SkillBundleStepMapping]) {
        self.skillBuild = skillBuild
        self.stepMappings = stepMappings
    }
}

public struct SkillBundleSkillBuild: Codable, Equatable, Sendable {
    public let repairVersion: Int?

    public init(repairVersion: Int? = nil) {
        self.repairVersion = repairVersion
    }
}

public struct SkillBundleStepMapping: Codable, Equatable, Sendable {
    public let skillStepId: String
    public let knowledgeStepId: String?
    public let instruction: String?
    public let sourceEventIds: [String]
    public let preferredLocatorType: SkillBundleLocatorType?
    public let coordinate: SkillBundleCoordinate?
    public let semanticTargets: [SkillBundleSemanticTarget]

    public init(
        skillStepId: String,
        knowledgeStepId: String? = nil,
        instruction: String? = nil,
        sourceEventIds: [String],
        preferredLocatorType: SkillBundleLocatorType? = nil,
        coordinate: SkillBundleCoordinate? = nil,
        semanticTargets: [SkillBundleSemanticTarget]
    ) {
        self.skillStepId = skillStepId
        self.knowledgeStepId = knowledgeStepId
        self.instruction = instruction
        self.sourceEventIds = sourceEventIds
        self.preferredLocatorType = preferredLocatorType
        self.coordinate = coordinate
        self.semanticTargets = semanticTargets
    }
}

public struct SkillBundleCoordinate: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let coordinateSpace: String

    public init(x: Double, y: Double, coordinateSpace: String) {
        self.x = x
        self.y = y
        self.coordinateSpace = coordinateSpace
    }
}

public struct SkillBundleSemanticTarget: Codable, Equatable, Sendable {
    public let locatorType: SkillBundleLocatorType
    public let appBundleId: String?
    public let windowTitlePattern: String?
    public let elementRole: String?
    public let elementTitle: String?
    public let elementIdentifier: String?
    public let axPath: String?
    public let textAnchor: String?
    public let imageAnchor: SkillBundleImageAnchor?
    public let boundingRect: SkillBundleBoundingRect?
    public let confidence: Double
    public let source: String

    public init(
        locatorType: SkillBundleLocatorType,
        appBundleId: String? = nil,
        windowTitlePattern: String? = nil,
        elementRole: String? = nil,
        elementTitle: String? = nil,
        elementIdentifier: String? = nil,
        axPath: String? = nil,
        textAnchor: String? = nil,
        imageAnchor: SkillBundleImageAnchor? = nil,
        boundingRect: SkillBundleBoundingRect? = nil,
        confidence: Double,
        source: String
    ) {
        self.locatorType = locatorType
        self.appBundleId = appBundleId
        self.windowTitlePattern = windowTitlePattern
        self.elementRole = elementRole
        self.elementTitle = elementTitle
        self.elementIdentifier = elementIdentifier
        self.axPath = axPath
        self.textAnchor = textAnchor
        self.imageAnchor = imageAnchor
        self.boundingRect = boundingRect
        self.confidence = confidence
        self.source = source
    }
}

public struct SkillBundleBoundingRect: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let coordinateSpace: String

    public init(
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        coordinateSpace: String
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.coordinateSpace = coordinateSpace
    }
}

public struct SkillBundleImageAnchor: Codable, Equatable, Sendable {
    public let pixelHash: String
    public let averageLuma: Double

    public init(pixelHash: String, averageLuma: Double) {
        self.pixelHash = pixelHash
        self.averageLuma = averageLuma
    }
}

public enum SkillBundleLocatorType: String, Codable, Equatable, Sendable {
    case axPath
    case roleAndTitle
    case textAnchor
    case imageAnchor
    case coordinateFallback
}

public enum SkillPreflightStatus: String, Codable, Equatable, Sendable {
    case passed
    case needsTeacherConfirmation = "needs_teacher_confirmation"
    case failed

    public var displayName: String {
        switch self {
        case .passed:
            return "通过"
        case .needsTeacherConfirmation:
            return "需老师确认"
        case .failed:
            return "失败"
        }
    }
}

public enum SkillPreflightIssueSeverity: String, Codable, Equatable, Sendable {
    case warning
    case error
}

public enum SkillPreflightIssueCode: String, Codable, Equatable, Sendable {
    case skillBundleUnreadable = "SPF-SKILL-BUNDLE-UNREADABLE"
    case skillBundleDecodeFailed = "SPF-SKILL-BUNDLE-DECODE-FAILED"
    case unsupportedSchemaVersion = "SPF-UNSUPPORTED-SCHEMA-VERSION"
    case emptyExecutionPlan = "SPF-EMPTY-EXECUTION-PLAN"
    case expectedStepCountMismatch = "SPF-EXPECTED-STEP-COUNT-MISMATCH"
    case missingContextApp = "SPF-MISSING-CONTEXT-APP"
    case emptyAppAllowlist = "SPF-EMPTY-APP-ALLOWLIST"
    case manualConfirmationRequired = "SPF-MANUAL-CONFIRMATION-REQUIRED"
    case unknownActionType = "SPF-UNKNOWN-ACTION-TYPE"
    case missingSourceEventIds = "SPF-MISSING-SOURCE-EVENT-IDS"
    case missingStepMapping = "SPF-MISSING-STEP-MAPPING"
    case invalidLocator = "SPF-INVALID-LOCATOR"
    case missingLocator = "SPF-MISSING-LOCATOR"
    case coordinateOnlyFallback = "SPF-COORDINATE-ONLY-FALLBACK"
    case targetAppNotAllowed = "SPF-TARGET-APP-NOT-ALLOWED"
    case highRiskAction = "SPF-HIGH-RISK-ACTION"
    case lowConfidence = "SPF-LOW-CONFIDENCE"
}

public enum SkillPreflightLocatorStatus: String, Codable, Equatable, Sendable {
    case notRequired = "not_required"
    case resolved
    case degraded
    case missing
}

public struct SkillPreflightIssue: Codable, Equatable, Sendable {
    public let severity: SkillPreflightIssueSeverity
    public let code: SkillPreflightIssueCode
    public let message: String
    public let stepId: String?

    public init(
        severity: SkillPreflightIssueSeverity,
        code: SkillPreflightIssueCode,
        message: String,
        stepId: String? = nil
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.stepId = stepId
    }
}

public struct SkillPreflightStepReport: Codable, Equatable, Sendable {
    public let stepId: String
    public let actionType: String
    public let confidence: Double
    public let locatorStatus: SkillPreflightLocatorStatus
    public let targetAppBundleIds: [String]
    public let highRisk: Bool
    public let lowConfidence: Bool
    public let requiresTeacherConfirmation: Bool
    public let issues: [SkillPreflightIssue]

    public init(
        stepId: String,
        actionType: String,
        confidence: Double,
        locatorStatus: SkillPreflightLocatorStatus,
        targetAppBundleIds: [String],
        highRisk: Bool,
        lowConfidence: Bool,
        requiresTeacherConfirmation: Bool,
        issues: [SkillPreflightIssue]
    ) {
        self.stepId = stepId
        self.actionType = actionType
        self.confidence = confidence
        self.locatorStatus = locatorStatus
        self.targetAppBundleIds = targetAppBundleIds
        self.highRisk = highRisk
        self.lowConfidence = lowConfidence
        self.requiresTeacherConfirmation = requiresTeacherConfirmation
        self.issues = issues
    }
}

public struct SkillPreflightReport: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let skillName: String
    public let skillDirectoryPath: String?
    public let status: SkillPreflightStatus
    public let summary: String
    public let requiresTeacherConfirmation: Bool
    public let isAutoRunnable: Bool
    public let allowedAppBundleIds: [String]
    public let issues: [SkillPreflightIssue]
    public let steps: [SkillPreflightStepReport]

    public init(
        schemaVersion: String = "openstaff.skill-preflight-report.v0",
        skillName: String,
        skillDirectoryPath: String? = nil,
        status: SkillPreflightStatus,
        summary: String,
        requiresTeacherConfirmation: Bool,
        isAutoRunnable: Bool,
        allowedAppBundleIds: [String],
        issues: [SkillPreflightIssue],
        steps: [SkillPreflightStepReport]
    ) {
        self.schemaVersion = schemaVersion
        self.skillName = skillName
        self.skillDirectoryPath = skillDirectoryPath
        self.status = status
        self.summary = summary
        self.requiresTeacherConfirmation = requiresTeacherConfirmation
        self.isAutoRunnable = isAutoRunnable
        self.allowedAppBundleIds = allowedAppBundleIds
        self.issues = issues
        self.steps = steps
    }

    public var userFacingIssueMessages: [String] {
        issues.map(\.message)
    }
}

public struct SkillPreflightOptions: Equatable, Sendable {
    public let lowConfidenceThreshold: Double
    public let highRiskKeywords: [String]
    public let highRiskRegexPatterns: [String]
    public let extraAllowedAppBundleIds: [String]

    public init(
        lowConfidenceThreshold: Double = 0.80,
        highRiskKeywords: [String] = [
            "删除",
            "移除",
            "支付",
            "转账",
            "系统设置",
            "格式化",
            "抹掉",
            "重置",
            "sudo",
            "rm -rf"
        ],
        highRiskRegexPatterns: [String] = [
            #"(?i)\brm\s+-rf\b"#,
            #"(?i)\bsudo\s+"#,
            #"(?i)\bshutdown\b|\breboot\b"#,
            #"(?i)\bdd\s+if="#
        ],
        extraAllowedAppBundleIds: [String] = []
    ) {
        self.lowConfidenceThreshold = lowConfidenceThreshold
        self.highRiskKeywords = highRiskKeywords
        self.highRiskRegexPatterns = highRiskRegexPatterns
        self.extraAllowedAppBundleIds = extraAllowedAppBundleIds
    }
}

public enum SkillBundleLoadError: LocalizedError {
    case missingSkillBundle(String)
    case unreadable(String, underlying: Error)
    case decodeFailed(String, underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .missingSkillBundle(let path):
            return "未找到技能文件：\(path)"
        case .unreadable(let path, let underlying):
            return "读取技能文件失败：\(path) (\(underlying.localizedDescription))"
        case .decodeFailed(let path, let underlying):
            return "解析技能文件失败：\(path) (\(underlying.localizedDescription))"
        }
    }
}

public struct SkillPreflightValidator {
    private static let supportedSchemaVersions = Set([
        "openstaff.openclaw-skill.v0",
        "openstaff.openclaw-skill.v1"
    ])

    private static let executableActionTypes = Set([
        "click",
        "shortcut",
        "input",
        "openApp",
        "wait"
    ])

    private let fileManager: FileManager
    private let decoder: JSONDecoder

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.decoder = JSONDecoder()
    }

    public func loadSkillBundle(from skillDirectoryURL: URL) throws -> SkillBundlePayload {
        let payloadURL = skillDirectoryURL.appendingPathComponent("openstaff-skill.json", isDirectory: false)
        guard fileManager.fileExists(atPath: payloadURL.path) else {
            throw SkillBundleLoadError.missingSkillBundle(payloadURL.path)
        }

        let data: Data
        do {
            data = try Data(contentsOf: payloadURL)
        } catch {
            throw SkillBundleLoadError.unreadable(payloadURL.path, underlying: error)
        }

        do {
            return try decoder.decode(SkillBundlePayload.self, from: data)
        } catch {
            throw SkillBundleLoadError.decodeFailed(payloadURL.path, underlying: error)
        }
    }

    public func validateSkillDirectory(
        at skillDirectoryURL: URL,
        options: SkillPreflightOptions = SkillPreflightOptions()
    ) -> SkillPreflightReport {
        do {
            let payload = try loadSkillBundle(from: skillDirectoryURL)
            return validate(
                payload: payload,
                skillDirectoryPath: skillDirectoryURL.path,
                options: options
            )
        } catch let error as SkillBundleLoadError {
            let message = error.localizedDescription
            let issue = SkillPreflightIssue(
                severity: .error,
                code: errorCode(for: error),
                message: message
            )
            return SkillPreflightReport(
                skillName: skillDirectoryURL.lastPathComponent,
                skillDirectoryPath: skillDirectoryURL.path,
                status: .failed,
                summary: message,
                requiresTeacherConfirmation: false,
                isAutoRunnable: false,
                allowedAppBundleIds: [],
                issues: [issue],
                steps: []
            )
        } catch {
            let message = error.localizedDescription
            let issue = SkillPreflightIssue(
                severity: .error,
                code: .skillBundleDecodeFailed,
                message: message
            )
            return SkillPreflightReport(
                skillName: skillDirectoryURL.lastPathComponent,
                skillDirectoryPath: skillDirectoryURL.path,
                status: .failed,
                summary: message,
                requiresTeacherConfirmation: false,
                isAutoRunnable: false,
                allowedAppBundleIds: [],
                issues: [issue],
                steps: []
            )
        }
    }

    public func validate(
        payload: SkillBundlePayload,
        skillDirectoryPath: String? = nil,
        options: SkillPreflightOptions = SkillPreflightOptions()
    ) -> SkillPreflightReport {
        var issues: [SkillPreflightIssue] = []
        var stepReports: [SkillPreflightStepReport] = []

        if !Self.supportedSchemaVersions.contains(payload.schemaVersion) {
            issues.append(
                SkillPreflightIssue(
                    severity: .error,
                    code: .unsupportedSchemaVersion,
                    message: "skill schemaVersion=\(payload.schemaVersion) 不受支持。"
                )
            )
        }

        let plan = payload.mappedOutput.executionPlan
        let contextAppBundleId = normalized(payload.mappedOutput.context.appBundleId)
        let requiredFrontmostAppBundleId = normalized(plan.completionCriteria.requiredFrontmostAppBundleId)
        let allowedAppBundleIds = derivedAllowedAppBundleIds(
            contextAppBundleId: contextAppBundleId,
            requiredFrontmostAppBundleId: requiredFrontmostAppBundleId,
            options: options
        )

        if contextAppBundleId.isEmpty || contextAppBundleId == "unknown" {
            issues.append(
                SkillPreflightIssue(
                    severity: .error,
                    code: .missingContextApp,
                    message: "skill 未声明有效的目标应用 bundleId。"
                )
            )
        }

        if allowedAppBundleIds.isEmpty {
            issues.append(
                SkillPreflightIssue(
                    severity: .error,
                    code: .emptyAppAllowlist,
                    message: "skill 无法导出目标 App 白名单，已阻止执行。"
                )
            )
        }

        if plan.steps.isEmpty {
            issues.append(
                SkillPreflightIssue(
                    severity: .error,
                    code: .emptyExecutionPlan,
                    message: "skill 不包含可执行步骤。"
                )
            )
        }

        if plan.completionCriteria.expectedStepCount != plan.steps.count {
            issues.append(
                SkillPreflightIssue(
                    severity: .error,
                    code: .expectedStepCountMismatch,
                    message: "completionCriteria.expectedStepCount 与 steps 数量不一致。"
                )
            )
        }

        if plan.requiresTeacherConfirmation {
            issues.append(
                SkillPreflightIssue(
                    severity: .warning,
                    code: .manualConfirmationRequired,
                    message: "skill 标记为 requiresTeacherConfirmation=true，不能直接自动执行。"
                )
            )
        }

        let orderedStepMappings = payload.provenance?.stepMappings ?? []
        var stepMappingsById: [String: SkillBundleStepMapping] = [:]
        for stepMapping in orderedStepMappings {
            stepMappingsById[stepMapping.skillStepId] = stepMapping
        }

        for (index, step) in plan.steps.enumerated() {
            let stepIssues = validateStep(
                step: step,
                stepIndex: index,
                mapping: stepMappingsById[step.stepId] ?? orderedStepMappings[safe: index],
                payload: payload,
                allowedAppBundleIds: allowedAppBundleIds,
                options: options,
                planRequiresTeacherConfirmation: plan.requiresTeacherConfirmation
            )
            issues.append(contentsOf: stepIssues.issues)
            stepReports.append(stepIssues.report)
        }

        let hasError = issues.contains(where: { $0.severity == .error })
        let requiresTeacherConfirmation = stepReports.contains(where: { $0.requiresTeacherConfirmation })
            || plan.requiresTeacherConfirmation
        let status: SkillPreflightStatus
        if hasError {
            status = .failed
        } else if requiresTeacherConfirmation {
            status = .needsTeacherConfirmation
        } else {
            status = .passed
        }

        let summary = buildSummary(
            skillName: payload.skillName,
            status: status,
            stepReports: stepReports,
            issues: issues
        )

        return SkillPreflightReport(
            skillName: payload.skillName,
            skillDirectoryPath: skillDirectoryPath,
            status: status,
            summary: summary,
            requiresTeacherConfirmation: requiresTeacherConfirmation,
            isAutoRunnable: status == .passed,
            allowedAppBundleIds: allowedAppBundleIds,
            issues: issues,
            steps: stepReports
        )
    }

    private func validateStep(
        step: SkillBundleExecutionStep,
        stepIndex: Int,
        mapping: SkillBundleStepMapping?,
        payload: SkillBundlePayload,
        allowedAppBundleIds: [String],
        options: SkillPreflightOptions,
        planRequiresTeacherConfirmation: Bool
    ) -> (report: SkillPreflightStepReport, issues: [SkillPreflightIssue]) {
        let actionType = normalized(step.actionType)
        let stepId = normalized(step.stepId, fallback: "step-\(stepIndex + 1)")
        var issues: [SkillPreflightIssue] = []

        if !Self.executableActionTypes.contains(actionType) {
            issues.append(
                SkillPreflightIssue(
                    severity: .error,
                    code: .unknownActionType,
                    message: "步骤 \(stepId) 的 actionType=\(step.actionType) 不可执行。",
                    stepId: stepId
                )
            )
        }

        let sourceEventIds = step.sourceEventIds.filter { !normalized($0).isEmpty && normalized($0) != "unknown" }
        if sourceEventIds.isEmpty {
            issues.append(
                SkillPreflightIssue(
                    severity: .error,
                    code: .missingSourceEventIds,
                    message: "步骤 \(stepId) 缺少有效的 sourceEventIds。",
                    stepId: stepId
                )
            )
        }

        let targetAppBundleIds = stepTargetAppBundleIds(
            step: step,
            mapping: mapping,
            fallbackContextAppBundleId: payload.mappedOutput.context.appBundleId
        )
        for bundleId in targetAppBundleIds where !allowedAppBundleIds.contains(bundleId) {
            issues.append(
                SkillPreflightIssue(
                    severity: .error,
                    code: .targetAppNotAllowed,
                    message: "步骤 \(stepId) 命中了非白名单应用 \(bundleId)。允许列表：\(allowedAppBundleIds.joined(separator: ", "))",
                    stepId: stepId
                )
            )
        }

        let stepConfidence = derivedStepConfidence(mapping: mapping, fallback: payload.mappedOutput.confidence)
        let lowConfidence = stepConfidence < options.lowConfidenceThreshold
        if lowConfidence {
            issues.append(
                SkillPreflightIssue(
                    severity: .warning,
                    code: .lowConfidence,
                    message: "步骤 \(stepId) 置信度 \(String(format: "%.2f", stepConfidence)) 低于阈值 \(String(format: "%.2f", options.lowConfidenceThreshold))，需要老师确认。",
                    stepId: stepId
                )
            )
        }

        let highRisk = isHighRiskStep(
            step: step,
            targetAppBundleIds: targetAppBundleIds,
            keywords: options.highRiskKeywords,
            regexPatterns: options.highRiskRegexPatterns
        )
        if highRisk {
            issues.append(
                SkillPreflightIssue(
                    severity: .warning,
                    code: .highRiskAction,
                    message: "步骤 \(stepId) 被识别为高风险动作，需要老师确认。",
                    stepId: stepId
                )
            )
        }

        let locatorOutcome = validateLocator(
            for: step,
            stepId: stepId,
            mapping: mapping
        )
        issues.append(contentsOf: locatorOutcome.issues)

        let requiresTeacherConfirmation = planRequiresTeacherConfirmation
            || highRisk
            || lowConfidence
            || locatorOutcome.locatorStatus == .degraded

        return (
            report: SkillPreflightStepReport(
                stepId: stepId,
                actionType: actionType,
                confidence: stepConfidence,
                locatorStatus: locatorOutcome.locatorStatus,
                targetAppBundleIds: targetAppBundleIds,
                highRisk: highRisk,
                lowConfidence: lowConfidence,
                requiresTeacherConfirmation: requiresTeacherConfirmation,
                issues: issues
            ),
            issues: issues
        )
    }

    private func validateLocator(
        for step: SkillBundleExecutionStep,
        stepId: String,
        mapping: SkillBundleStepMapping?
    ) -> (locatorStatus: SkillPreflightLocatorStatus, issues: [SkillPreflightIssue]) {
        let actionType = normalized(step.actionType)
        guard actionType == "click" else {
            return (.notRequired, [])
        }

        guard let mapping else {
            if parseCoordinateTarget(step.target) != nil {
                return (
                    .degraded,
                    [
                        SkillPreflightIssue(
                            severity: .warning,
                            code: .coordinateOnlyFallback,
                            message: "步骤 \(stepId) 仅能依赖 target 中的旧坐标回退，需要老师确认。",
                            stepId: stepId
                        )
                    ]
                )
            }
            return (
                .missing,
                [
                    SkillPreflightIssue(
                        severity: .error,
                        code: .missingStepMapping,
                        message: "步骤 \(stepId) 缺少 provenance.stepMappings，无法做 locator 预检。",
                        stepId: stepId
                    ),
                    SkillPreflightIssue(
                        severity: .error,
                        code: .missingLocator,
                        message: "步骤 \(stepId) 不存在可解析 locator。",
                        stepId: stepId
                    )
                ]
            )
        }

        let semanticTargets = mapping.semanticTargets
        let validTargets = semanticTargets.filter { semanticTargetIsValid($0) }
        if semanticTargets.count != validTargets.count {
            return (
                validTargets.isEmpty && mapping.coordinate == nil ? .missing : .degraded,
                [
                    SkillPreflightIssue(
                        severity: validTargets.isEmpty && mapping.coordinate == nil ? .error : .warning,
                        code: .invalidLocator,
                        message: "步骤 \(stepId) 的 semanticTargets 存在不可解析 locator。",
                        stepId: stepId
                    )
                ]
            )
        }

        if validTargets.contains(where: { $0.locatorType != .coordinateFallback }) {
            return (.resolved, [])
        }

        if mapping.coordinate != nil || validTargets.contains(where: { $0.locatorType == .coordinateFallback }) {
            return (
                .degraded,
                [
                    SkillPreflightIssue(
                        severity: .warning,
                        code: .coordinateOnlyFallback,
                        message: "步骤 \(stepId) 仅剩 coordinateFallback，不能直接自动执行。",
                        stepId: stepId
                    )
                ]
            )
        }

        return (
            .missing,
            [
                SkillPreflightIssue(
                    severity: .error,
                    code: .missingLocator,
                    message: "步骤 \(stepId) 不存在可解析 locator。",
                    stepId: stepId
                )
            ]
        )
    }

    private func semanticTargetIsValid(_ target: SkillBundleSemanticTarget) -> Bool {
        switch target.locatorType {
        case .axPath:
            return !normalized(target.axPath).isEmpty
        case .roleAndTitle:
            return !normalized(target.elementRole).isEmpty
                || !normalized(target.elementTitle).isEmpty
                || !normalized(target.elementIdentifier).isEmpty
        case .textAnchor:
            return !normalized(target.textAnchor).isEmpty || !normalized(target.elementTitle).isEmpty
        case .imageAnchor:
            return target.imageAnchor != nil && target.boundingRect != nil
        case .coordinateFallback:
            return target.boundingRect != nil
        }
    }

    private func derivedAllowedAppBundleIds(
        contextAppBundleId: String,
        requiredFrontmostAppBundleId: String,
        options: SkillPreflightOptions
    ) -> [String] {
        var values = [contextAppBundleId, requiredFrontmostAppBundleId]
        values.append(contentsOf: options.extraAllowedAppBundleIds)

        var ordered: [String] = []
        var seen = Set<String>()
        for value in values {
            let normalizedValue = normalized(value)
            guard !normalizedValue.isEmpty, normalizedValue != "unknown" else {
                continue
            }
            if seen.insert(normalizedValue).inserted {
                ordered.append(normalizedValue)
            }
        }
        return ordered
    }

    private func stepTargetAppBundleIds(
        step: SkillBundleExecutionStep,
        mapping: SkillBundleStepMapping?,
        fallbackContextAppBundleId: String
    ) -> [String] {
        var values: [String] = []
        if let targetBundleId = parseBundleTarget(step.target) {
            values.append(targetBundleId)
        }

        if let mapping {
            values.append(contentsOf: mapping.semanticTargets.compactMap(\.appBundleId))
        }

        let fallback = normalized(fallbackContextAppBundleId)
        if values.isEmpty, !fallback.isEmpty, fallback != "unknown" {
            values.append(fallback)
        }

        var ordered: [String] = []
        var seen = Set<String>()
        for value in values {
            let normalizedValue = normalized(value)
            guard !normalizedValue.isEmpty, normalizedValue != "unknown" else {
                continue
            }
            if seen.insert(normalizedValue).inserted {
                ordered.append(normalizedValue)
            }
        }
        return ordered
    }

    private func derivedStepConfidence(
        mapping: SkillBundleStepMapping?,
        fallback: Double
    ) -> Double {
        let semanticMax = mapping?.semanticTargets.map(\.confidence).max()
        let value = semanticMax ?? fallback
        return max(0.0, min(1.0, value))
    }

    private func isHighRiskStep(
        step: SkillBundleExecutionStep,
        targetAppBundleIds: [String],
        keywords: [String],
        regexPatterns: [String]
    ) -> Bool {
        let actionType = normalized(step.actionType)
        let joinedText = "\(step.instruction)\n\(step.target)"

        if targetAppBundleIds.contains("com.apple.Terminal"), actionType == "input" {
            return true
        }

        for keyword in keywords where !keyword.isEmpty {
            if joinedText.localizedCaseInsensitiveContains(keyword) {
                return true
            }
        }

        for pattern in regexPatterns {
            if joinedText.range(of: pattern, options: [.regularExpression]) != nil {
                return true
            }
        }

        if actionType == "openApp",
           let bundleId = parseBundleTarget(step.target),
           bundleId.localizedCaseInsensitiveContains("systemsettings") {
            return true
        }

        return false
    }

    private func buildSummary(
        skillName: String,
        status: SkillPreflightStatus,
        stepReports: [SkillPreflightStepReport],
        issues: [SkillPreflightIssue]
    ) -> String {
        let errorCount = issues.filter { $0.severity == .error }.count
        let warningCount = issues.filter { $0.severity == .warning }.count
        let autoRunnableSteps = stepReports.filter { !$0.requiresTeacherConfirmation }.count
        return "skill \(skillName) 预检\(status.displayName)：步骤 \(stepReports.count)，可直接自动执行 \(autoRunnableSteps)，错误 \(errorCount)，告警 \(warningCount)。"
    }

    private func parseBundleTarget(_ target: String) -> String? {
        let normalizedTarget = normalized(target)
        guard normalizedTarget.hasPrefix("bundle:") else {
            return nil
        }
        let value = String(normalizedTarget.dropFirst("bundle:".count))
        return value.isEmpty ? nil : value
    }

    private func parseCoordinateTarget(_ target: String) -> SkillBundleCoordinate? {
        let normalizedTarget = normalized(target)
        guard normalizedTarget.hasPrefix("coordinate:") else {
            return nil
        }
        let raw = String(normalizedTarget.dropFirst("coordinate:".count))
        let parts = raw.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let x = Double(parts[0].trimmingCharacters(in: .whitespacesAndNewlines)),
              let y = Double(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return SkillBundleCoordinate(x: x, y: y, coordinateSpace: "screen")
    }

    private func errorCode(for error: SkillBundleLoadError) -> SkillPreflightIssueCode {
        switch error {
        case .missingSkillBundle, .unreadable:
            return .skillBundleUnreadable
        case .decodeFailed:
            return .skillBundleDecodeFailed
        }
    }

    private func normalized(_ value: String?, fallback: String = "") -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else {
            return nil
        }
        return self[index]
    }
}
