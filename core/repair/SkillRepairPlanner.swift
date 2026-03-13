import Foundation

public enum SkillRepairPlanStatus: String, Codable, Equatable {
    case noActionNeeded
    case actionRequired
}

public enum SkillRepairActionType: String, Codable, Equatable {
    case relocalize
    case reteachCurrentStep
    case updateSkillLocator
}

public struct SkillRepairAction: Codable, Equatable, @unchecked Sendable {
    public let actionId: String
    public let type: SkillRepairActionType
    public let title: String
    public let description: String
    public let reason: String
    public let affectedStepIds: [String]
    public let shouldIncrementRepairVersion: Bool

    public init(
        actionId: String,
        type: SkillRepairActionType,
        title: String,
        description: String,
        reason: String,
        affectedStepIds: [String],
        shouldIncrementRepairVersion: Bool = true
    ) {
        self.actionId = actionId
        self.type = type
        self.title = title
        self.description = description
        self.reason = reason
        self.affectedStepIds = affectedStepIds
        self.shouldIncrementRepairVersion = shouldIncrementRepairVersion
    }
}

public struct SkillRepairPlan: Codable, Equatable, @unchecked Sendable {
    public let schemaVersion: String
    public let skillName: String
    public let status: SkillRepairPlanStatus
    public let dominantDriftKind: SkillDriftKind
    public let currentRepairVersion: Int?
    public let recommendedRepairVersion: Int?
    public let summary: String
    public let actions: [SkillRepairAction]

    public init(
        schemaVersion: String = "openstaff.skill-repair-plan.v0",
        skillName: String,
        status: SkillRepairPlanStatus,
        dominantDriftKind: SkillDriftKind,
        currentRepairVersion: Int? = nil,
        recommendedRepairVersion: Int? = nil,
        summary: String,
        actions: [SkillRepairAction]
    ) {
        self.schemaVersion = schemaVersion
        self.skillName = skillName
        self.status = status
        self.dominantDriftKind = dominantDriftKind
        self.currentRepairVersion = currentRepairVersion
        self.recommendedRepairVersion = recommendedRepairVersion
        self.summary = summary
        self.actions = actions
    }
}

public struct SkillRepairPlanner {
    public init() {}

    public func buildPlan(report: SkillDriftReport) -> SkillRepairPlan {
        let driftFindings = report.findings.filter { $0.driftKind != .none }
        guard !driftFindings.isEmpty else {
            return SkillRepairPlan(
                skillName: report.skillName,
                status: .noActionNeeded,
                dominantDriftKind: .none,
                currentRepairVersion: report.currentRepairVersion,
                recommendedRepairVersion: report.currentRepairVersion,
                summary: "未检测到需要修复的 skill 漂移。",
                actions: []
            )
        }

        let currentRepairVersion = report.currentRepairVersion ?? 0
        let recommendedRepairVersion = currentRepairVersion + 1
        var actions: [SkillRepairAction] = []

        let uiTextSteps = stepIds(for: .uiTextChanged, findings: driftFindings)
        if !uiTextSteps.isEmpty {
            actions.append(
                SkillRepairAction(
                    actionId: "repair-update-locator-ui-text",
                    type: .updateSkillLocator,
                    title: "更新 skill locator",
                    description: "保留现有步骤结构，刷新 title / textAnchor / identifier 等文本相关 locator。",
                    reason: "检测到 UI 文案变化，原有结构化元素仍可能存在。",
                    affectedStepIds: uiTextSteps
                )
            )
        }

        let movedSteps = stepIds(for: .elementPositionChanged, findings: driftFindings)
        if !movedSteps.isEmpty {
            actions.append(
                SkillRepairAction(
                    actionId: "repair-relocalize-element",
                    type: .relocalize,
                    title: "重新定位受影响步骤",
                    description: "重新抓取该步骤的 locator、boundingRect 和坐标回退，降低布局/位置漂移。",
                    reason: "检测到元素位置、截图锚点或坐标回退相关漂移。",
                    affectedStepIds: movedSteps
                )
            )
        }

        let windowSteps = stepIds(for: .windowStructureChanged, findings: driftFindings)
        if !windowSteps.isEmpty {
            actions.append(
                SkillRepairAction(
                    actionId: "repair-reteach-window-structure",
                    type: .reteachCurrentStep,
                    title: "重新示教当前步骤",
                    description: "原窗口层级或 AX 路径已变化，建议老师重新执行该步骤并生成新的 skill locator。",
                    reason: "检测到窗口结构变化，旧路径可能整体失效。",
                    affectedStepIds: windowSteps
                )
            )
        }

        if report.dominantDriftKind == .appVersionChanged {
            let allDriftStepIds = driftFindings.map(\.stepId)
            actions.insert(
                SkillRepairAction(
                    actionId: "repair-app-version-refresh",
                    type: .updateSkillLocator,
                    title: "批量更新 skill",
                    description: "当前 App 内多步同时失效，建议以 repairVersion + 1 批量刷新 locator，并在必要时补充重新示教。",
                    reason: "检测到疑似 App 版本升级后的整体界面变化。",
                    affectedStepIds: Array(Set(allDriftStepIds)).sorted()
                ),
                at: 0
            )
        }

        if actions.isEmpty {
            actions.append(
                SkillRepairAction(
                    actionId: "repair-reteach-fallback",
                    type: .reteachCurrentStep,
                    title: "重新示教当前步骤",
                    description: "当前漂移无法通过稳定规则进一步分类，优先重新示教失败步骤。",
                    reason: "检测结果不足以自动判断更细粒度的修复方案。",
                    affectedStepIds: driftFindings.map(\.stepId)
                )
            )
        }

        let summary = buildSummary(
            report: report,
            actions: actions,
            recommendedRepairVersion: recommendedRepairVersion
        )

        return SkillRepairPlan(
            skillName: report.skillName,
            status: .actionRequired,
            dominantDriftKind: report.dominantDriftKind,
            currentRepairVersion: report.currentRepairVersion,
            recommendedRepairVersion: recommendedRepairVersion,
            summary: summary,
            actions: actions
        )
    }

    private func stepIds(
        for driftKind: SkillDriftKind,
        findings: [SkillDriftFinding]
    ) -> [String] {
        Array(Set(findings.filter { $0.driftKind == driftKind }.map(\.stepId))).sorted()
    }

    private func buildSummary(
        report: SkillDriftReport,
        actions: [SkillRepairAction],
        recommendedRepairVersion: Int
    ) -> String {
        let actionSummary = actions.map(\.title).joined(separator: "、")
        return "\(report.summary) 建议动作：\(actionSummary)。建议下一个 repairVersion 为 \(recommendedRepairVersion)。"
    }
}
