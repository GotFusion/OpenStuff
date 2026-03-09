import AppKit
import Foundation
import SwiftUI

enum OpenStaffSceneID {
    static let console = "openstaff-console"
    static let desktopWidget = "openstaff-desktop-widget"
}

enum DesktopWidgetDisplayMode: String, CaseIterable, Identifiable {
    case compact
    case detailed

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .compact:
            return "精简模式"
        case .detailed:
            return "详细模式"
        }
    }
}

struct DesktopWidgetSecondaryTask: Identifiable {
    let id: String
    let order: Int
    let title: String
    let timestamp: Date
    let detail: String
}

struct DesktopWidgetPrimaryTask: Identifiable {
    let id: String
    let order: Int
    let taskName: String
    let mode: OpenStaffMode
    let sessionId: String
    let timestamp: Date
    let secondaryTasks: [DesktopWidgetSecondaryTask]

    var summaryText: String {
        secondaryTasks.first?.detail ?? "暂无摘要"
    }
}

final class OpenStaffDesktopWidgetViewModel: NSObject, ObservableObject {
    @Published var displayMode: DesktopWidgetDisplayMode = .compact
    @Published private(set) var timelineTasks: [DesktopWidgetPrimaryTask] = []
    @Published private(set) var currentTaskBrief = "暂无任务"
    @Published private(set) var nextTaskBrief = "等待下一步任务"
    @Published private(set) var lastUpdatedAt: Date?
    @Published var isWidgetWindowVisible = true

    private var refreshTimer: Timer?

    override init() {
        super.init()
        refresh()
        startAutoRefresh()
    }

    deinit {
        refreshTimer?.invalidate()
    }

    func refresh() {
        let recentTasks = RecentTaskRepository.loadRecentTasks(limit: 32)
        let executionLogs = ExecutionReviewRepository.loadExecutionSnapshot(limit: 240).logs

        updateBriefTasks(from: recentTasks)
        timelineTasks = buildTimelineTasks(executionLogs: executionLogs, fallbackTasks: recentTasks)
        lastUpdatedAt = Date()
    }

    func setDisplayMode(_ mode: DesktopWidgetDisplayMode) {
        displayMode = mode
    }

    func showDetailedMode() {
        displayMode = .detailed
    }

    func showCompactMode() {
        displayMode = .compact
    }

    @objc
    private func handleRefreshTick(_ timer: Timer) {
        refresh()
    }

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(
            timeInterval: 2.0,
            target: self,
            selector: #selector(handleRefreshTick(_:)),
            userInfo: nil,
            repeats: true
        )
        if let refreshTimer {
            RunLoop.main.add(refreshTimer, forMode: .common)
        }
    }

    private func updateBriefTasks(from tasks: [RecentTaskSummary]) {
        guard let currentTask = tasks.first else {
            currentTaskBrief = "暂无任务"
            nextTaskBrief = "等待下一步任务"
            return
        }

        currentTaskBrief = compactLine(task: currentTask, scenario: .compactCurrentTask)

        if let nextTask = tasks.dropFirst().first {
            nextTaskBrief = compactLine(task: nextTask, scenario: .compactNextTask)
        } else {
            nextTaskBrief = "等待下一步任务"
        }
    }

    private func compactLine(
        task: RecentTaskSummary,
        scenario: DesktopWidgetTruncationScenario
    ) -> String {
        let text = "\(task.mode.widgetDisplayName) · \(task.taskId)"
        return DesktopWidgetTruncationRule.apply(text, scenario: scenario)
    }

    private func buildTimelineTasks(
        executionLogs: [ExecutionLogSummary],
        fallbackTasks: [RecentTaskSummary]
    ) -> [DesktopWidgetPrimaryTask] {
        if !executionLogs.isEmpty {
            return buildFromExecutionLogs(executionLogs)
        }
        return buildFromRecentTasks(fallbackTasks)
    }

    private func buildFromExecutionLogs(_ logs: [ExecutionLogSummary]) -> [DesktopWidgetPrimaryTask] {
        let grouped = Dictionary(grouping: logs) { log in
            "\(log.mode.rawValue)|\(log.sessionId)|\(log.taskId ?? "no-task")"
        }

        var groups: [(
            id: String,
            mode: OpenStaffMode,
            sessionId: String,
            taskName: String,
            timestamp: Date,
            logs: [ExecutionLogSummary]
        )] = []
        groups.reserveCapacity(grouped.count)

        for (groupId, groupLogs) in grouped {
            let sortedLogs = groupLogs.sorted { lhs, rhs in
                lhs.timestamp < rhs.timestamp
            }
            guard let firstLog = sortedLogs.first else {
                continue
            }
            groups.append((
                id: groupId,
                mode: firstLog.mode,
                sessionId: firstLog.sessionId,
                taskName: firstLog.taskId ?? "no-task",
                timestamp: firstLog.timestamp,
                logs: sortedLogs
            ))
        }

        let sortedGroups = groups.sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.id < rhs.id
            }
            return lhs.timestamp < rhs.timestamp
        }

        let limitedGroups = Array(sortedGroups.suffix(24))

        return limitedGroups.enumerated().map { index, group in
            let secondary = group.logs.enumerated().map { stepIndex, log in
                DesktopWidgetSecondaryTask(
                    id: "\(group.id)#\(stepIndex + 1)",
                    order: stepIndex + 1,
                    title: log.status,
                    timestamp: log.timestamp,
                    detail: log.message
                )
            }

            return DesktopWidgetPrimaryTask(
                id: group.id,
                order: index + 1,
                taskName: group.taskName,
                mode: group.mode,
                sessionId: group.sessionId,
                timestamp: group.timestamp,
                secondaryTasks: secondary
            )
        }
    }

    private func buildFromRecentTasks(_ tasks: [RecentTaskSummary]) -> [DesktopWidgetPrimaryTask] {
        let orderedTasks = tasks.sorted { lhs, rhs in
            lhs.timestamp < rhs.timestamp
        }

        return orderedTasks.enumerated().map { index, task in
            let secondary = DesktopWidgetSecondaryTask(
                id: "\(task.id)#1",
                order: 1,
                title: task.status,
                timestamp: task.timestamp,
                detail: task.message
            )

            return DesktopWidgetPrimaryTask(
                id: task.id,
                order: index + 1,
                taskName: task.taskId,
                mode: task.mode,
                sessionId: task.sessionId,
                timestamp: task.timestamp,
                secondaryTasks: [secondary]
            )
        }
    }
}

struct OpenStaffMenuBarContentView: View {
    @ObservedObject var dashboardViewModel: OpenStaffDashboardViewModel
    @ObservedObject var desktopWidgetViewModel: OpenStaffDesktopWidgetViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("打开控制台") {
                openConsoleWindow()
            }

            Button(desktopWidgetViewModel.isWidgetWindowVisible ? "隐藏前台部件" : "显示前台部件") {
                toggleDesktopWidgetWindow()
            }

            Divider()

            Text("部件模式")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                desktopWidgetViewModel.setDisplayMode(.compact)
                ensureWidgetWindowVisible()
            } label: {
                Label(
                    "精简模式",
                    systemImage: desktopWidgetViewModel.displayMode == .compact ? "checkmark.circle.fill" : "circle"
                )
            }

            Button {
                desktopWidgetViewModel.setDisplayMode(.detailed)
                ensureWidgetWindowVisible()
            } label: {
                Label(
                    "详细模式",
                    systemImage: desktopWidgetViewModel.displayMode == .detailed ? "checkmark.circle.fill" : "circle"
                )
            }

            Divider()

            Button("刷新任务视图") {
                desktopWidgetViewModel.refresh()
                dashboardViewModel.refreshDashboard(promptAccessibilityPermission: false)
            }

            if dashboardViewModel.emergencyStopActive {
                Button("解除紧急停止") {
                    dashboardViewModel.releaseEmergencyStop()
                }
            } else {
                Button("触发紧急停止") {
                    dashboardViewModel.activateEmergencyStop(source: .uiButton)
                }
            }

            Divider()

            Button("退出程序") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(10)
        .frame(minWidth: 220, alignment: .leading)
    }

    private func openConsoleWindow() {
        openWindow(id: OpenStaffSceneID.console)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func toggleDesktopWidgetWindow() {
        if desktopWidgetViewModel.isWidgetWindowVisible {
            closeDesktopWidgetWindowIfNeeded()
            desktopWidgetViewModel.isWidgetWindowVisible = false
        } else {
            ensureWidgetWindowVisible()
        }
    }

    private func ensureWidgetWindowVisible() {
        if !desktopWidgetViewModel.isWidgetWindowVisible {
            openWindow(id: OpenStaffSceneID.desktopWidget)
            desktopWidgetViewModel.isWidgetWindowVisible = true
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func closeDesktopWidgetWindowIfNeeded() {
        guard let widgetWindow = NSApplication.shared.windows.first(where: {
            $0.identifier?.rawValue == OpenStaffSceneID.desktopWidget
        }) else {
            return
        }
        widgetWindow.close()
    }
}

struct OpenStaffDesktopWidgetView: View {
    @ObservedObject var viewModel: OpenStaffDesktopWidgetViewModel
    @ObservedObject var dashboardViewModel: OpenStaffDashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DesktopWidgetSpacing.widgetStack) {
            compactBox

            if viewModel.displayMode == .detailed {
                detailTimeline
            }
        }
        .padding(DesktopWidgetSpacing.widgetOuterPadding)
        .frame(
            width: viewModel.displayMode == .compact ? DesktopWidgetSpacing.compactWindowWidth : DesktopWidgetSpacing.detailedWindowWidth,
            height: viewModel.displayMode == .compact ? DesktopWidgetSpacing.compactWindowHeight : DesktopWidgetSpacing.detailedWindowHeight,
            alignment: .topLeading
        )
        .background {
            if viewModel.displayMode == .detailed {
                RoundedRectangle(cornerRadius: DesktopWidgetSpacing.widgetWindowCornerRadius)
                    .fill(DesktopWidgetColorPalette.detailedWindowFill)
            }
        }
        .background(
            DesktopWidgetWindowConfigurator(windowIdentifier: OpenStaffSceneID.desktopWidget)
        )
        .onAppear {
            viewModel.isWidgetWindowVisible = true
            viewModel.refresh()
        }
        .onDisappear {
            viewModel.isWidgetWindowVisible = false
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.displayMode)
    }

    private var compactHintText: String {
        viewModel.displayMode == .compact ? "点击展开" : "点击收起"
    }

    private var compactBox: some View {
        Button {
            if viewModel.displayMode == .compact {
                viewModel.showDetailedMode()
            } else {
                viewModel.showCompactMode()
            }
        } label: {
            VStack(alignment: .leading, spacing: DesktopWidgetSpacing.compactSectionGap) {
                VStack(alignment: .leading, spacing: DesktopWidgetSpacing.compactLabelTextGap) {
                    Text("当前任务")
                        .font(DesktopWidgetTypography.compactLabel)
                        .foregroundStyle(DesktopWidgetColorPalette.compactSecondaryText)
                    Text(viewModel.currentTaskBrief)
                        .font(DesktopWidgetTypography.compactCurrentTask)
                        .foregroundStyle(DesktopWidgetColorPalette.compactPrimaryText)
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: DesktopWidgetSpacing.compactLabelTextGap) {
                    Text("下一步")
                        .font(DesktopWidgetTypography.compactLabel)
                        .foregroundStyle(DesktopWidgetColorPalette.compactSecondaryText)
                    Text(viewModel.nextTaskBrief)
                        .font(DesktopWidgetTypography.compactNextTask)
                        .foregroundStyle(DesktopWidgetColorPalette.compactSecondaryText)
                        .lineLimit(1)
                }

                HStack(spacing: DesktopWidgetSpacing.compactHintGap) {
                    Spacer(minLength: 0)
                    Text(compactHintText)
                        .font(DesktopWidgetTypography.compactHint)
                        .foregroundStyle(DesktopWidgetColorPalette.compactSecondaryText)
                    Image(systemName: viewModel.displayMode == .compact ? "arrow.right" : "arrow.down")
                        .font(DesktopWidgetTypography.compactHint)
                        .foregroundStyle(DesktopWidgetColorPalette.compactSecondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesktopWidgetSpacing.compactBoxHorizontalPadding)
            .padding(.vertical, DesktopWidgetSpacing.compactBoxVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: DesktopWidgetSpacing.compactBoxCornerRadius, style: .continuous)
                    .fill(DesktopWidgetColorPalette.compactBoxFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesktopWidgetSpacing.compactBoxCornerRadius, style: .continuous)
                            .stroke(DesktopWidgetColorPalette.compactBoxStroke, lineWidth: 1.5)
                    )
                    .shadow(
                        color: DesktopWidgetColorPalette.compactBoxShadow,
                        radius: DesktopWidgetSpacing.compactBoxShadowRadius,
                        x: 0,
                        y: DesktopWidgetSpacing.compactBoxShadowYOffset
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: DesktopWidgetSpacing.compactBoxCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var detailTimeline: some View {
        VStack(alignment: .leading, spacing: DesktopWidgetSpacing.timelineSection) {
            HStack(alignment: .firstTextBaseline) {
                Text("任务时间轴")
                    .font(DesktopWidgetTypography.timelineSectionTitle)

                Spacer()

                if let lastUpdatedAt = viewModel.lastUpdatedAt {
                    Text("更新：\(OpenStaffDateFormatter.displayString(from: lastUpdatedAt))")
                        .font(DesktopWidgetTypography.timelineMetadata)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if dashboardViewModel.emergencyStopActive {
                HStack(alignment: .center, spacing: DesktopWidgetSpacing.emergencyLineGap) {
                    Rectangle()
                        .fill(DesktopWidgetColorPalette.emergencyLine)
                        .frame(height: DesktopWidgetSpacing.emergencyLineHeight)
                    Text("紧急停止已激活")
                        .font(DesktopWidgetTypography.emergencyLabel)
                        .foregroundStyle(DesktopWidgetColorPalette.emergencyLine)
                }
            }

            if viewModel.timelineTasks.isEmpty {
                Text("暂无任务记录，可先运行教学/辅助/学生流程。")
                    .font(DesktopWidgetTypography.timelineSecondaryDetail)
                    .foregroundStyle(DesktopWidgetColorPalette.timelineSecondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, DesktopWidgetSpacing.timelineEmptyTopPadding)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DesktopWidgetSpacing.primaryGroupAdditionalSpacing) {
                        ForEach(viewModel.timelineTasks) { task in
                            DesktopWidgetTimelineTaskCard(task: task)
                        }
                    }
                    .padding(.vertical, DesktopWidgetSpacing.timelineContentVerticalPadding)
                }
            }
        }
        .padding(DesktopWidgetSpacing.timelineSectionPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct DesktopWidgetTimelineTaskCard: View {
    let task: DesktopWidgetPrimaryTask

    var body: some View {
        VStack(alignment: .leading, spacing: DesktopWidgetSpacing.primaryToSecondaryGap) {
            primaryNodeRow
            secondaryTaskRows
        }
        .frame(maxWidth: .infinity, minHeight: DesktopWidgetSpacing.primaryNodeMinHeight, alignment: .topLeading)
    }

    private var primaryNodeRow: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                Circle()
                    .fill(DesktopWidgetColorPalette.primaryNodeFill(for: task.mode))
                    .overlay(
                        Circle()
                            .stroke(DesktopWidgetColorPalette.primaryNodeStroke(for: task.mode), lineWidth: 1)
                    )
                    .frame(
                        width: DesktopWidgetSpacing.primaryNodeDotSize,
                        height: DesktopWidgetSpacing.primaryNodeDotSize
                    )
                    .padding(.top, DesktopWidgetSpacing.primaryNodeDotTopOffset)

                Rectangle()
                    .fill(DesktopWidgetColorPalette.timelineRail)
                    .frame(width: DesktopWidgetSpacing.trackWidth)
                    .frame(maxHeight: .infinity)
                    .opacity(task.secondaryTasks.isEmpty ? 0 : 1)
            }
            .frame(width: DesktopWidgetSpacing.trackLeadingSafetyWidth, alignment: .center)

            VStack(alignment: .leading, spacing: 0) {
                Text(
                    DesktopWidgetTruncationRule.timelinePrimaryTaskTitle(
                        order: task.order,
                        modeName: task.mode.widgetDisplayName,
                        taskId: task.taskName
                    )
                )
                    .font(DesktopWidgetTypography.timelinePrimaryTaskTitle)
                    .foregroundStyle(DesktopWidgetColorPalette.timelinePrimaryText)
                    .lineLimit(1)

                Text("\(task.mode.widgetDisplayName) · \(task.sessionId) · \(OpenStaffDateFormatter.displayString(from: task.timestamp))")
                    .font(DesktopWidgetTypography.timelineMetadata)
                    .foregroundStyle(DesktopWidgetColorPalette.timelineMetadataText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .padding(.top, DesktopWidgetSpacing.primaryTitleToMetadataGap)

                Text(
                    DesktopWidgetTruncationRule.apply(
                        task.summaryText,
                        scenario: .timelinePrimaryTaskSummary
                    )
                )
                    .font(DesktopWidgetTypography.timelineSecondaryDetail)
                    .foregroundStyle(DesktopWidgetColorPalette.timelineSecondaryText)
                    .lineLimit(1)
                    .padding(.top, DesktopWidgetSpacing.primaryMetadataToSummaryGap)
            }
            .padding(.leading, DesktopWidgetSpacing.trackTextStartOffset)
        }
    }

    private var secondaryTaskRows: some View {
        VStack(alignment: .leading, spacing: DesktopWidgetSpacing.secondaryTaskItemSpacing) {
            ForEach(Array(task.secondaryTasks.enumerated()), id: \.element.id) { index, secondary in
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(DesktopWidgetColorPalette.secondaryNodeFill(for: task.mode))
                            .overlay(
                                Circle()
                                    .stroke(DesktopWidgetColorPalette.secondaryNodeStroke(for: task.mode), lineWidth: 1)
                            )
                            .frame(
                                width: DesktopWidgetSpacing.secondaryNodeDotSize,
                                height: DesktopWidgetSpacing.secondaryNodeDotSize
                            )

                        Rectangle()
                            .fill(DesktopWidgetColorPalette.timelineRail)
                            .frame(width: DesktopWidgetSpacing.trackWidth, height: DesktopWidgetSpacing.secondaryConnectorHeight)
                            .opacity(index == task.secondaryTasks.count - 1 ? 0 : 1)
                    }
                    .frame(width: DesktopWidgetSpacing.trackLeadingSafetyWidth, alignment: .center)

                    VStack(alignment: .leading, spacing: DesktopWidgetSpacing.secondaryNodeTextSpacing) {
                        Text(
                            DesktopWidgetTruncationRule.timelineSecondaryTaskTitle(
                                order: secondary.order,
                                status: secondary.title
                            )
                        )
                            .font(DesktopWidgetTypography.timelineSecondaryTaskTitle)
                            .foregroundStyle(DesktopWidgetColorPalette.timelinePrimaryText)
                            .lineLimit(1)

                        Text(
                            "\(OpenStaffDateFormatter.displayString(from: secondary.timestamp)) · " +
                            DesktopWidgetTruncationRule.apply(
                                secondary.detail,
                                scenario: .timelineSecondaryTaskDetail
                            )
                        )
                            .font(DesktopWidgetTypography.timelineSecondaryDetail)
                            .foregroundStyle(DesktopWidgetColorPalette.timelineSecondaryText)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    .padding(.leading, DesktopWidgetSpacing.trackTextStartOffset)
                }
            }
        }
    }
}

private enum DesktopWidgetTypography {
    static let compactLabel = Font.system(size: 12, weight: .medium)
    static let compactCurrentTask = Font.system(size: 14, weight: .semibold)
    static let compactNextTask = Font.system(size: 13, weight: .medium)
    static let compactHint = Font.system(size: 12, weight: .medium)
    static let emergencyLabel = Font.system(size: 11, weight: .semibold)
    static let timelineSectionTitle = Font.system(size: 16, weight: .semibold)
    static let timelinePrimaryTaskTitle = Font.system(size: 16, weight: .semibold)
    static let timelineMetadata = Font.system(size: 12, weight: .medium, design: .monospaced)
    static let timelineSecondaryTaskTitle = Font.system(size: 13, weight: .medium)
    static let timelineSecondaryDetail = Font.system(size: 12, weight: .medium)
}

private enum DesktopWidgetColorPalette {
    static let compactPrimaryText = Color.white.opacity(0.92)
    static let compactSecondaryText = Color.white.opacity(0.72)
    static let compactBoxFill = Color.white.opacity(0.18)
    static let compactBoxStroke = Color.white.opacity(0.38)
    static let compactBoxShadow = Color.black.opacity(0.2)

    static let detailedWindowFill = Color.black.opacity(0.04)
    static let timelinePrimaryText = Color.white.opacity(0.94)
    static let timelineMetadataText = Color.white.opacity(0.80)
    static let timelineSecondaryText = Color.white.opacity(0.74)
    static let timelineRail = Color(red: 0.84, green: 0.89, blue: 0.93).opacity(0.82)
    static let emergencyLine = Color(red: 0.73, green: 0.11, blue: 0.11)

    static func primaryNodeFill(for mode: OpenStaffMode) -> Color {
        mode.widgetAccentColor.opacity(0.45)
    }

    static func primaryNodeStroke(for mode: OpenStaffMode) -> Color {
        mode.widgetAccentColor.opacity(0.60)
    }

    static func secondaryNodeFill(for mode: OpenStaffMode) -> Color {
        mode.widgetAccentColor.opacity(0.32)
    }

    static func secondaryNodeStroke(for mode: OpenStaffMode) -> Color {
        mode.widgetAccentColor.opacity(0.46)
    }
}

private enum DesktopWidgetSpacing {
    static let widgetStack: CGFloat = 12
    static let widgetOuterPadding: CGFloat = 12
    static let widgetWindowCornerRadius: CGFloat = 24
    static let compactWindowWidth: CGFloat = 392
    static let compactWindowHeight: CGFloat = 178
    static let detailedWindowWidth: CGFloat = 560
    static let detailedWindowHeight: CGFloat = 580

    static let compactSectionGap: CGFloat = 10
    static let compactLabelTextGap: CGFloat = 4
    static let compactHintGap: CGFloat = 6
    static let compactBoxHorizontalPadding: CGFloat = 24
    static let compactBoxVerticalPadding: CGFloat = 14
    static let compactBoxCornerRadius: CGFloat = 16
    static let compactBoxShadowRadius: CGFloat = 10
    static let compactBoxShadowYOffset: CGFloat = 8

    static let timelineSection: CGFloat = 10
    static let timelineSectionPadding: CGFloat = 10
    static let timelineEmptyTopPadding: CGFloat = 8
    static let timelineContentVerticalPadding: CGFloat = 4
    static let emergencyLineHeight: CGFloat = 2
    static let emergencyLineGap: CGFloat = 8

    static let primaryGroupAdditionalSpacing: CGFloat = 38
    static let primaryNodeMinHeight: CGFloat = 184
    static let primaryNodeDotSize: CGFloat = 10
    static let primaryNodeDotTopOffset: CGFloat = 5
    static let primaryTitleToMetadataGap: CGFloat = 22
    static let primaryMetadataToSummaryGap: CGFloat = 20
    static let primaryToSecondaryGap: CGFloat = 34
    static let secondaryTaskItemSpacing: CGFloat = 46

    static let secondaryNodeDotSize: CGFloat = 5
    static let secondaryNodeTextSpacing: CGFloat = 2
    static let secondaryConnectorHeight: CGFloat = 28

    static let trackLeadingSafetyWidth: CGFloat = 64
    static let trackTextStartOffset: CGFloat = 28
    static let trackWidth: CGFloat = 2
}

private enum DesktopWidgetTruncationScenario {
    case compactCurrentTask
    case compactNextTask
    case timelinePrimaryTaskTitle
    case timelinePrimaryTaskSummary
    case timelineSecondaryTaskTitle
    case timelineSecondaryTaskDetail
}

private enum DesktopWidgetTruncationRule {
    private static let ellipsis = "..."

    static func apply(_ text: String, scenario: DesktopWidgetTruncationScenario) -> String {
        truncate(text, maxLength: maxLength(for: scenario))
    }

    static func timelinePrimaryTaskTitle(order: Int, modeName: String, taskId: String) -> String {
        let prefix = "一级任务 \(order)：\(modeName) · "
        let rawTitle = prefix + taskId
        return truncatePreservingPrefix(rawTitle, prefix: prefix, maxLength: maxLength(for: .timelinePrimaryTaskTitle))
    }

    static func timelineSecondaryTaskTitle(order: Int, status: String) -> String {
        apply("二级任务 \(order)：\(status)", scenario: .timelineSecondaryTaskTitle)
    }

    private static func maxLength(for scenario: DesktopWidgetTruncationScenario) -> Int {
        switch scenario {
        case .compactCurrentTask:
            return 22
        case .compactNextTask:
            return 26
        case .timelinePrimaryTaskTitle:
            return 44
        case .timelinePrimaryTaskSummary:
            return 44
        case .timelineSecondaryTaskTitle:
            return 42
        case .timelineSecondaryTaskDetail:
            return 52
        }
    }

    private static func truncatePreservingPrefix(
        _ text: String,
        prefix: String,
        maxLength: Int
    ) -> String {
        guard text.count > maxLength else {
            return text
        }
        if prefix.count >= maxLength {
            return truncate(prefix, maxLength: maxLength)
        }
        let suffixBudget = maxLength - prefix.count
        let suffixStart = text.index(text.startIndex, offsetBy: prefix.count)
        let suffix = String(text[suffixStart...])
        return prefix + truncate(suffix, maxLength: suffixBudget)
    }

    private static func truncate(_ value: String, maxLength: Int) -> String {
        guard maxLength > 0 else {
            return ""
        }
        guard value.count > maxLength else {
            return value
        }
        if maxLength <= ellipsis.count {
            return String(ellipsis.prefix(maxLength))
        }
        let keepLength = maxLength - ellipsis.count
        let endIndex = value.index(value.startIndex, offsetBy: keepLength)
        return String(value[..<endIndex]) + ellipsis
    }
}

private struct DesktopWidgetWindowConfigurator: NSViewRepresentable {
    let windowIdentifier: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configureWindowIfNeeded(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindowIfNeeded(nsView.window)
        }
    }

    private func configureWindowIfNeeded(_ window: NSWindow?) {
        guard let window else {
            return
        }

        if window.identifier?.rawValue != windowIdentifier {
            window.identifier = NSUserInterfaceItemIdentifier(windowIdentifier)
        }

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.collectionBehavior.insert([.canJoinAllSpaces, .stationary, .fullScreenAuxiliary])

        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }
}

private extension OpenStaffMode {
    var widgetDisplayName: String {
        switch self {
        case .teaching:
            return "教学"
        case .assist:
            return "辅助"
        case .student:
            return "学生"
        }
    }

    var widgetAccentColor: Color {
        switch self {
        case .teaching:
            return Color(red: 0.10, green: 0.44, blue: 0.93)
        case .assist:
            return Color(red: 0.96, green: 0.50, blue: 0.09)
        case .student:
            return Color(red: 0.10, green: 0.63, blue: 0.33)
        }
    }
}
