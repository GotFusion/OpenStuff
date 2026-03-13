import Foundation

public enum SkillDriftStatus: String, Codable, Equatable {
    case stable
    case driftDetected
}

public enum SkillDriftKind: String, Codable, Equatable {
    case none
    case uiTextChanged
    case elementPositionChanged
    case windowStructureChanged
    case appVersionChanged
    case captureUnavailable
    case contextMismatch
}

public struct SkillDriftStat: Codable, Equatable, @unchecked Sendable {
    public let kind: SkillDriftKind
    public let count: Int

    public init(kind: SkillDriftKind, count: Int) {
        self.kind = kind
        self.count = count
    }
}

public struct SkillDriftFinding: Codable, Equatable, @unchecked Sendable {
    public let stepId: String
    public let instruction: String
    public let status: ReplayStepVerificationStatus
    public let driftKind: SkillDriftKind
    public let confidence: Double
    public let matchedLocatorType: SemanticLocatorType?
    public let failureReason: SemanticTargetFailureReason?
    public let message: String
    public let attempts: [SemanticTargetResolutionAttempt]

    public init(
        stepId: String,
        instruction: String,
        status: ReplayStepVerificationStatus,
        driftKind: SkillDriftKind,
        confidence: Double,
        matchedLocatorType: SemanticLocatorType? = nil,
        failureReason: SemanticTargetFailureReason? = nil,
        message: String,
        attempts: [SemanticTargetResolutionAttempt] = []
    ) {
        self.stepId = stepId
        self.instruction = instruction
        self.status = status
        self.driftKind = driftKind
        self.confidence = confidence
        self.matchedLocatorType = matchedLocatorType
        self.failureReason = failureReason
        self.message = message
        self.attempts = attempts
    }
}

public struct SkillDriftReport: Codable, Equatable, @unchecked Sendable {
    public let schemaVersion: String
    public let skillName: String
    public let skillDirectoryPath: String?
    public let knowledgeItemId: String
    public let taskId: String
    public let sessionId: String
    public let detectedAt: String
    public let snapshot: ReplayEnvironmentSnapshot
    public let status: SkillDriftStatus
    public let dominantDriftKind: SkillDriftKind
    public let currentRepairVersion: Int?
    public let findings: [SkillDriftFinding]
    public let stats: [SkillDriftStat]
    public let summary: String

    public init(
        schemaVersion: String = "openstaff.skill-drift-report.v0",
        skillName: String,
        skillDirectoryPath: String? = nil,
        knowledgeItemId: String,
        taskId: String,
        sessionId: String,
        detectedAt: String,
        snapshot: ReplayEnvironmentSnapshot,
        status: SkillDriftStatus,
        dominantDriftKind: SkillDriftKind,
        currentRepairVersion: Int? = nil,
        findings: [SkillDriftFinding],
        stats: [SkillDriftStat],
        summary: String
    ) {
        self.schemaVersion = schemaVersion
        self.skillName = skillName
        self.skillDirectoryPath = skillDirectoryPath
        self.knowledgeItemId = knowledgeItemId
        self.taskId = taskId
        self.sessionId = sessionId
        self.detectedAt = detectedAt
        self.snapshot = snapshot
        self.status = status
        self.dominantDriftKind = dominantDriftKind
        self.currentRepairVersion = currentRepairVersion
        self.findings = findings
        self.stats = stats
        self.summary = summary
    }
}

public struct SkillDriftDetector {
    private let resolver: SemanticTargetResolver
    private let nowProvider: () -> Date
    private let formatter: ISO8601DateFormatter

    public init(
        resolver: SemanticTargetResolver = SemanticTargetResolver(),
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.resolver = resolver
        self.nowProvider = nowProvider

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.formatter = formatter
    }

    public func detect(
        payload: SkillBundlePayload,
        snapshot: ReplayEnvironmentSnapshot,
        skillDirectoryPath: String? = nil
    ) -> SkillDriftReport {
        let findings = buildFindings(payload: payload, snapshot: snapshot)
        let stats = buildStats(findings: findings)
        let dominantDriftKind = dominantKind(
            findings: findings,
            payload: payload,
            snapshot: snapshot
        )
        let status: SkillDriftStatus = findings.contains(where: { $0.driftKind != .none }) ? .driftDetected : .stable
        let summary = buildSummary(
            findings: findings,
            dominantDriftKind: dominantDriftKind,
            payload: payload,
            snapshot: snapshot
        )

        return SkillDriftReport(
            skillName: payload.skillName,
            skillDirectoryPath: skillDirectoryPath,
            knowledgeItemId: payload.knowledgeItemId,
            taskId: payload.taskId,
            sessionId: payload.sessionId,
            detectedAt: formatter.string(from: nowProvider()),
            snapshot: snapshot,
            status: status,
            dominantDriftKind: dominantDriftKind,
            currentRepairVersion: payload.provenance?.skillBuild?.repairVersion,
            findings: findings,
            stats: stats,
            summary: summary
        )
    }

    private func buildFindings(
        payload: SkillBundlePayload,
        snapshot: ReplayEnvironmentSnapshot
    ) -> [SkillDriftFinding] {
        let stepMappings = payload.provenance?.stepMappings ?? []
        let stepMappingsById = Dictionary(uniqueKeysWithValues: stepMappings.map { ($0.skillStepId, $0) })

        return payload.mappedOutput.executionPlan.steps.enumerated().map { index, step in
            let mapping = stepMappingsById[step.stepId] ?? stepMappings[safe: index]
            return buildFinding(
                step: step,
                mapping: mapping,
                payload: payload,
                snapshot: snapshot
            )
        }
    }

    private func buildFinding(
        step: SkillBundleExecutionStep,
        mapping: SkillBundleStepMapping?,
        payload: SkillBundlePayload,
        snapshot: ReplayEnvironmentSnapshot
    ) -> SkillDriftFinding {
        guard let mapping else {
            return SkillDriftFinding(
                stepId: step.stepId,
                instruction: step.instruction,
                status: .failed,
                driftKind: .windowStructureChanged,
                confidence: 0.72,
                message: "技能缺少 provenance.stepMappings，无法验证现有 locator，建议重新示教当前步骤。"
            )
        }

        let semanticTargets = mapping.semanticTargets.map {
            toSemanticTarget($0, defaultAppBundleId: payload.mappedOutput.context.appBundleId)
        }
        let preferredLocatorType = mapping.preferredLocatorType.flatMap { SemanticLocatorType(rawValue: $0.rawValue) }
        let coordinate = mapping.coordinate.map {
            PointerLocation(
                x: Int($0.x.rounded()),
                y: Int($0.y.rounded()),
                coordinateSpace: .screen
            )
        }
        let resolution = resolver.resolve(
            targets: semanticTargets,
            preferredLocatorType: preferredLocatorType,
            coordinate: coordinate,
            in: snapshot
        )
        let classification = classify(
            resolution: resolution,
            mapping: mapping,
            payload: payload,
            snapshot: snapshot
        )

        return SkillDriftFinding(
            stepId: step.stepId,
            instruction: step.instruction,
            status: replayStatus(from: resolution.status),
            driftKind: classification.kind,
            confidence: classification.confidence,
            matchedLocatorType: resolution.matchedLocatorType,
            failureReason: resolution.failureReason,
            message: classification.message,
            attempts: resolution.attempts
        )
    }

    private func classify(
        resolution: SemanticTargetResolution,
        mapping: SkillBundleStepMapping,
        payload: SkillBundlePayload,
        snapshot: ReplayEnvironmentSnapshot
    ) -> (kind: SkillDriftKind, confidence: Double, message: String) {
        if resolution.status == .resolved {
            return (.none, 0.0, "当前 locator 仍可在现有界面中稳定解析。")
        }

        guard let failureReason = resolution.failureReason else {
            if resolution.status == .degraded {
                return (
                    .elementPositionChanged,
                    0.6,
                    "locator 已退化，建议重新定位并刷新 skill。"
                )
            }
            return (
                .none,
                0.0,
                resolution.message
            )
        }

        switch failureReason {
        case .textAnchorChanged:
            return (
                .uiTextChanged,
                0.92,
                "结构相近元素仍在，但文本锚点或按钮文案已变化，建议更新现有 skill locator。"
            )
        case .coordinateFallbackOnly:
            return (
                .elementPositionChanged,
                0.78,
                "当前只能退回坐标定位，说明元素位置或截图锚点发生漂移，建议重新定位该步骤。"
            )
        case .windowMismatch:
            return (
                .windowStructureChanged,
                0.88,
                "窗口标题或窗口层级不再匹配原始记录，建议重新示教当前步骤。"
            )
        case .imageAnchorChanged:
            return (
                .elementPositionChanged,
                0.74,
                "截图锚点无法复现，界面布局或元素位置可能已调整，建议重新定位并刷新 locator。"
            )
        case .elementMissing:
            if mapping.semanticTargets.contains(where: { $0.locatorType == .axPath || $0.locatorType == .roleAndTitle }) {
                return (
                    .windowStructureChanged,
                    0.69,
                    "原有结构化 locator 未再命中目标，窗口结构或元素层级可能发生变化，建议重新示教当前步骤。"
                )
            }
            return (
                .elementPositionChanged,
                0.62,
                "目标元素未命中，可能只是位置或局部布局变化，建议重新定位该步骤。"
            )
        case .captureUnavailable:
            return (
                .captureUnavailable,
                0.56,
                "当前环境缺少截图或 AX 采集能力，无法完成漂移判断；建议补齐权限后重新检测。"
            )
        case .appMismatch:
            if snapshot.appBundleId == payload.mappedOutput.context.appBundleId {
                return (
                    .contextMismatch,
                    0.41,
                    "前台上下文与 skill 预期不一致，请确认是否已切换到正确任务页面。"
                )
            }
            return (
                .contextMismatch,
                0.86,
                "当前前台应用不是 skill 目标应用，先切回目标 App 再做修复判断。"
            )
        case .noSemanticTargets:
            return (
                .elementPositionChanged,
                0.58,
                "缺少足够的可验证 locator，建议重新定位并补齐稳定语义目标。"
            )
        }
    }

    private func dominantKind(
        findings: [SkillDriftFinding],
        payload: SkillBundlePayload,
        snapshot: ReplayEnvironmentSnapshot
    ) -> SkillDriftKind {
        let driftFindings = findings.filter { $0.driftKind != .none }
        guard !driftFindings.isEmpty else {
            return .none
        }

        if snapshot.appBundleId == payload.mappedOutput.context.appBundleId,
           driftFindings.count >= max(2, payload.mappedOutput.executionPlan.steps.count / 2),
           driftFindings.filter({ $0.driftKind == .uiTextChanged || $0.driftKind == .windowStructureChanged || $0.driftKind == .elementPositionChanged }).count >= 2 {
            return .appVersionChanged
        }

        let counters = Dictionary(grouping: driftFindings, by: \.driftKind).mapValues(\.count)
        return counters.sorted { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key.rawValue < rhs.key.rawValue
            }
            return lhs.value > rhs.value
        }.first?.key ?? .none
    }

    private func buildStats(findings: [SkillDriftFinding]) -> [SkillDriftStat] {
        let counters = Dictionary(grouping: findings.filter { $0.driftKind != .none }, by: \.driftKind)
            .mapValues(\.count)

        return counters
            .map { SkillDriftStat(kind: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.kind.rawValue < rhs.kind.rawValue
                }
                return lhs.count > rhs.count
            }
    }

    private func buildSummary(
        findings: [SkillDriftFinding],
        dominantDriftKind: SkillDriftKind,
        payload: SkillBundlePayload,
        snapshot: ReplayEnvironmentSnapshot
    ) -> String {
        let failedSteps = findings.filter { $0.status == .failed }.count
        let degradedSteps = findings.filter { $0.status == .degraded }.count

        guard dominantDriftKind != .none else {
            return "skill \(payload.skillName) 当前未检测到明显漂移。"
        }

        let base = "skill \(payload.skillName) 在 \(snapshot.appName) 中检测到 \(failedSteps) 个失败步骤、\(degradedSteps) 个退化步骤。"
        switch dominantDriftKind {
        case .uiTextChanged:
            return "\(base) 主因判断为 UI 文案变化，建议更新现有 locator。"
        case .elementPositionChanged:
            return "\(base) 主因判断为元素位置或布局漂移，建议重新定位受影响步骤。"
        case .windowStructureChanged:
            return "\(base) 主因判断为窗口结构变化，建议重新示教当前步骤。"
        case .appVersionChanged:
            return "\(base) 多个步骤在同一 App 内同时失效，疑似 App 版本升级后界面整体变化。"
        case .captureUnavailable:
            return "\(base) 当前采集能力不足，需先补齐权限后再判断具体漂移类型。"
        case .contextMismatch:
            return "\(base) 当前前台上下文与 skill 预期不一致，需先切回目标任务界面。"
        case .none:
            return base
        }
    }

    private func replayStatus(from status: SemanticTargetResolutionStatus) -> ReplayStepVerificationStatus {
        switch status {
        case .resolved:
            return .resolved
        case .degraded:
            return .degraded
        case .unresolved:
            return .failed
        }
    }

    private func toSemanticTarget(
        _ target: SkillBundleSemanticTarget,
        defaultAppBundleId: String
    ) -> SemanticTarget {
        SemanticTarget(
            locatorType: SemanticLocatorType(rawValue: target.locatorType.rawValue) ?? .coordinateFallback,
            appBundleId: target.appBundleId ?? defaultAppBundleId,
            windowTitlePattern: target.windowTitlePattern,
            elementRole: target.elementRole,
            elementTitle: target.elementTitle,
            elementIdentifier: target.elementIdentifier,
            axPath: target.axPath,
            textAnchor: target.textAnchor,
            imageAnchor: target.imageAnchor.map {
                SemanticImageAnchor(pixelHash: $0.pixelHash, averageLuma: $0.averageLuma)
            },
            boundingRect: target.boundingRect.map {
                SemanticBoundingRect(
                    x: $0.x,
                    y: $0.y,
                    width: $0.width,
                    height: $0.height,
                    coordinateSpace: .screen
                )
            },
            confidence: target.confidence,
            source: semanticSource(from: target.source)
        )
    }

    private func semanticSource(from rawValue: String) -> SemanticTargetSource {
        SemanticTargetSource(rawValue: rawValue) ?? .inferred
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
