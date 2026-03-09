import ApplicationServices
import AppKit
import Foundation
import SwiftUI

@main
struct OpenStaffApp: App {
    @StateObject private var viewModel = OpenStaffDashboardViewModel()
    @StateObject private var desktopWidgetViewModel = OpenStaffDesktopWidgetViewModel()

    var body: some Scene {
        Window("OpenStaff", id: OpenStaffSceneID.console) {
            OpenStaffRootView(
                viewModel: viewModel,
                desktopWidgetViewModel: desktopWidgetViewModel
            )
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1180, height: 1120)

        Window("OpenStaff 前台部件", id: OpenStaffSceneID.desktopWidget) {
            OpenStaffDesktopWidgetView(
                viewModel: desktopWidgetViewModel,
                dashboardViewModel: viewModel
            )
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 392, height: 334)

        MenuBarExtra("OpenStaff", systemImage: "graduationcap.circle") {
            OpenStaffMenuBarContentView(
                dashboardViewModel: viewModel,
                desktopWidgetViewModel: desktopWidgetViewModel
            )
        }
        .menuBarExtraStyle(.menu)
    }
}

struct OpenStaffRootView: View {
    @ObservedObject var viewModel: OpenStaffDashboardViewModel
    @ObservedObject var desktopWidgetViewModel: OpenStaffDesktopWidgetViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var hasOpenedDesktopWidget = false

    var body: some View {
        TabView {
            OpenStaffPrototypeView()
                .tabItem {
                    Label("原型体验", systemImage: "sparkles.rectangle.stack")
                }

            OpenStaffDashboardView(viewModel: viewModel)
                .tabItem {
                    Label("系统控制台", systemImage: "gauge.with.dots.needle.67percent")
                }
        }
        .task {
            guard !hasOpenedDesktopWidget else {
                return
            }
            hasOpenedDesktopWidget = true
            if desktopWidgetViewModel.isWidgetWindowVisible {
                openWindow(id: OpenStaffSceneID.desktopWidget)
            }
        }
    }
}

struct OpenStaffDashboardView: View {
    @ObservedObject var viewModel: OpenStaffDashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("OpenStaff 主界面")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("阶段 6.1：安全控制")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    if let refreshedAt = viewModel.lastRefreshedAt {
                        Text("最近刷新：\(OpenStaffDateFormatter.displayString(from: refreshedAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(viewModel.emergencyStopStatusText)
                        .font(.caption)
                        .foregroundStyle(viewModel.emergencyStopActive ? .red : .secondary)

                    HStack(spacing: 8) {
                        Button("刷新任务与权限") {
                            viewModel.refreshDashboard(promptAccessibilityPermission: false)
                        }
                        .keyboardShortcut("r", modifiers: [.command])

                        Button("申请辅助功能权限") {
                            viewModel.refreshDashboard(promptAccessibilityPermission: true)
                        }

                        Button("紧急停止") {
                            viewModel.activateEmergencyStop(source: .uiButton)
                        }
                        .keyboardShortcut(".", modifiers: [.command, .shift])
                        .buttonStyle(.borderedProminent)
                        .tint(.red)

                        Button("解除停止") {
                            viewModel.releaseEmergencyStop()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.emergencyStopActive)
                    }
                }
            }

            GroupBox("模式切换") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker(
                        "运行模式",
                        selection: Binding(
                            get: { viewModel.currentMode },
                            set: { viewModel.requestModeChange(to: $0) }
                        )
                    ) {
                        ForEach(OpenStaffMode.allCases, id: \.self) { mode in
                            Text(viewModel.modeDisplayName(for: mode)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("模式运行控制")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(OpenStaffMode.allCases, id: \.self) { mode in
                            HStack(spacing: 10) {
                                Text(viewModel.modeDisplayName(for: mode))
                                    .font(.callout)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(mode.color)
                                    .frame(width: 82, alignment: .leading)

                                Button("开始") {
                                    viewModel.startMode(mode)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(mode.color)
                                .disabled(viewModel.currentMode == mode)

                                Button("停止") {
                                    viewModel.stopMode(mode)
                                }
                                .buttonStyle(.bordered)
                                .disabled(!viewModel.canStopMode(mode))

                                Spacer(minLength: 0)

                                Text(viewModel.currentMode == mode ? "运行中" : "未运行")
                                    .font(.caption)
                                    .foregroundStyle(viewModel.currentMode == mode ? mode.color : .secondary)
                            }
                        }
                    }

                    Text("切换守卫输入")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                        GridRow {
                            Toggle("老师已确认", isOn: $viewModel.guardInputs.teacherConfirmed)
                            Toggle("知识已就绪", isOn: $viewModel.guardInputs.learnedKnowledgeReady)
                        }
                        GridRow {
                            Toggle("执行计划已就绪", isOn: $viewModel.guardInputs.executionPlanReady)
                            Toggle("存在待确认建议", isOn: $viewModel.guardInputs.pendingAssistSuggestion)
                        }
                        GridRow {
                            Toggle(
                                "紧急停止已激活",
                                isOn: Binding(
                                    get: { viewModel.guardInputs.emergencyStopActive },
                                    set: { isOn in
                                        if isOn {
                                            viewModel.activateEmergencyStop(source: .uiButton)
                                        } else {
                                            viewModel.releaseEmergencyStop()
                                        }
                                    }
                                )
                            )
                            Spacer(minLength: 0)
                        }
                    }

                    if let transitionMessage = viewModel.transitionMessage {
                        Text(transitionMessage)
                            .font(.caption)
                            .foregroundStyle(viewModel.lastTransitionAccepted ? .green : .red)
                    }
                }
                .padding(.top, 4)
            }

            HStack(alignment: .top, spacing: 12) {
                GroupBox("当前状态") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("当前模式", value: viewModel.modeDisplayName(for: viewModel.currentMode))
                        LabeledContent("状态码", value: viewModel.currentStatusCode)
                        if !viewModel.currentCapabilities.isEmpty {
                            LabeledContent("能力白名单", value: viewModel.currentCapabilities.joined(separator: ", "))
                        }
                        if !viewModel.unmetRequirementsText.isEmpty {
                            LabeledContent("未满足守卫", value: viewModel.unmetRequirementsText)
                        }
                    }
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }

                GroupBox("权限状态") {
                    VStack(alignment: .leading, spacing: 8) {
                        PermissionRow(
                            title: "辅助功能权限",
                            granted: viewModel.permissionSnapshot.accessibilityTrusted
                        )
                        PermissionRow(
                            title: "数据目录可写",
                            granted: viewModel.permissionSnapshot.dataDirectoryWritable
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
            }

            GroupBox("最近任务") {
                if viewModel.recentTasks.isEmpty {
                    Text("暂无最近任务记录。可先运行一次教学/辅助/学生流程后刷新。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    List(viewModel.recentTasks) { task in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(viewModel.modeDisplayName(for: task.mode))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(task.mode.color)
                                Text(task.taskId)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(OpenStaffDateFormatter.displayString(from: task.timestamp))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(task.message)
                                .font(.callout)
                            Text("status: \(task.status) · session: \(task.sessionId)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .listStyle(.inset)
                    .frame(minHeight: 260)
                }
            }

            GroupBox("学习记录与知识浏览") {
                if viewModel.learningSessions.isEmpty {
                    Text("暂无学习会话数据。可先运行 capture/slice/knowledge，再点击刷新。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("会话列表")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            List(
                                selection: Binding(
                                    get: { viewModel.selectedLearningSessionId },
                                    set: { viewModel.selectLearningSession($0) }
                                )
                            ) {
                                ForEach(viewModel.learningSessions) { session in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(session.sessionId)
                                            .font(.callout)
                                        Text("任务 \(session.taskCount) · 知识 \(session.knowledgeItemCount)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        if let endedAt = session.endedAt {
                                            Text("最近活动：\(OpenStaffDateFormatter.displayString(from: endedAt))")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                    .tag(session.sessionId as String?)
                                }
                            }
                            .listStyle(.inset)
                            .frame(minWidth: 260, minHeight: 280)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("任务列表")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if viewModel.tasksForSelectedSession.isEmpty {
                                Text("该会话暂无任务。")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .padding(.top, 8)
                            } else {
                                List(
                                    selection: Binding(
                                        get: { viewModel.selectedLearningTaskId },
                                        set: { viewModel.selectLearningTask($0) }
                                    )
                                ) {
                                    ForEach(viewModel.tasksForSelectedSession) { task in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(task.taskId)
                                                .font(.callout)
                                            HStack(spacing: 6) {
                                                if let eventCount = task.eventCount {
                                                    Text("事件 \(eventCount)")
                                                }
                                                if let stepCount = task.knowledgeStepCount {
                                                    Text("步骤 \(stepCount)")
                                                }
                                                if let boundary = task.boundaryReason {
                                                    Text("边界 \(boundary)")
                                                }
                                            }
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        }
                                        .padding(.vertical, 2)
                                        .tag(task.id as String?)
                                    }
                                }
                                .listStyle(.inset)
                            }
                        }
                        .frame(minWidth: 280, minHeight: 280)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("任务详情与知识条目")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let detail = viewModel.selectedTaskDetail {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 10) {
                                        LabeledContent("任务 ID", value: detail.task.taskId)
                                        LabeledContent("会话 ID", value: detail.task.sessionId)
                                        if let appName = detail.task.appName {
                                            LabeledContent("应用", value: appName)
                                        }
                                        if let startedAt = detail.task.startedAt {
                                            LabeledContent("开始时间", value: OpenStaffDateFormatter.displayString(from: startedAt))
                                        }
                                        if let endedAt = detail.task.endedAt {
                                            LabeledContent("结束时间", value: OpenStaffDateFormatter.displayString(from: endedAt))
                                        }
                                        if let boundaryReason = detail.task.boundaryReason {
                                            LabeledContent("切片边界", value: boundaryReason)
                                        }

                                        Divider()

                                        if let knowledge = detail.knowledgeItem {
                                            LabeledContent("知识条目 ID", value: knowledge.knowledgeItemId)
                                            LabeledContent("目标", value: knowledge.goal)
                                            LabeledContent("摘要", value: knowledge.summary)
                                            LabeledContent("上下文应用", value: knowledge.contextAppName)
                                            if let windowTitle = knowledge.windowTitle,
                                               !windowTitle.isEmpty {
                                                LabeledContent("窗口标题", value: windowTitle)
                                            }
                                            if let createdAt = knowledge.createdAt {
                                                LabeledContent("生成时间", value: OpenStaffDateFormatter.displayString(from: createdAt))
                                            }
                                            if !knowledge.constraints.isEmpty {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text("约束")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                    ForEach(knowledge.constraints) { constraint in
                                                        Text("• [\(constraint.type)] \(constraint.description)")
                                                            .font(.caption)
                                                    }
                                                }
                                            }
                                            if !knowledge.steps.isEmpty {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text("步骤")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                    ForEach(knowledge.steps) { step in
                                                        VStack(alignment: .leading, spacing: 2) {
                                                            Text("\(step.stepId): \(step.instruction)")
                                                                .font(.caption)
                                                            if !step.sourceEventIds.isEmpty {
                                                                Text("source: \(step.sourceEventIds.joined(separator: ", "))")
                                                                    .font(.caption2)
                                                                    .foregroundStyle(.secondary)
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        } else {
                                            Text("该任务暂无知识条目。")
                                                .font(.callout)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            } else {
                                Text("请选择一个任务查看详情。")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .padding(.top, 8)
                            }
                        }
                        .frame(minWidth: 360, minHeight: 280)
                    }
                }
            }

            GroupBox("审阅与反馈") {
                if viewModel.executionLogs.isEmpty {
                    Text("暂无执行日志。可先运行 assist/student 流程后刷新。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("执行日志")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            List(
                                selection: Binding(
                                    get: { viewModel.selectedExecutionLogId },
                                    set: { viewModel.selectExecutionLog($0) }
                                )
                            ) {
                                ForEach(viewModel.executionLogs) { log in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(viewModel.modeDisplayName(for: log.mode))
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .foregroundStyle(log.mode.color)
                                            Text(log.status)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(log.message)
                                            .font(.callout)
                                            .lineLimit(2)
                                        Text("\(log.sessionId) · \(log.taskId ?? "no-task") · \(OpenStaffDateFormatter.displayString(from: log.timestamp))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 2)
                                    .tag(log.id as String?)
                                }
                            }
                            .listStyle(.inset)
                            .frame(minWidth: 360, minHeight: 260)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("日志详情与老师反馈")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let log = viewModel.selectedExecutionLog {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 10) {
                                        LabeledContent("时间", value: OpenStaffDateFormatter.displayString(from: log.timestamp))
                                        LabeledContent("会话 ID", value: log.sessionId)
                                        LabeledContent("任务 ID", value: log.taskId ?? "no-task")
                                        LabeledContent("状态码", value: log.status)
                                        if let component = log.component {
                                            LabeledContent("组件", value: component)
                                        }
                                        if let errorCode = log.errorCode {
                                            LabeledContent("错误码", value: errorCode)
                                        }
                                        LabeledContent("日志位置", value: "\(log.sourceFilePath):\(log.lineNumber)")
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("消息")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(log.message)
                                                .font(.callout)
                                        }

                                        Divider()

                                        if let feedback = viewModel.latestFeedbackForSelectedLog {
                                            LabeledContent("最近反馈", value: feedback.decision.displayName)
                                            if let note = feedback.note, !note.isEmpty {
                                                LabeledContent("反馈备注", value: note)
                                            }
                                            LabeledContent("反馈时间", value: OpenStaffDateFormatter.displayString(from: feedback.timestamp))
                                        } else {
                                            Text("该日志暂无老师反馈。")
                                                .font(.callout)
                                                .foregroundStyle(.secondary)
                                        }

                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("填写反馈备注（修正建议可写在这里）")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            TextEditor(text: $viewModel.feedbackInput)
                                                .frame(minHeight: 84)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                                                )
                                        }

                                        HStack(spacing: 8) {
                                            Button("通过") {
                                                viewModel.submitTeacherFeedback(decision: .approved)
                                            }
                                            .buttonStyle(.borderedProminent)

                                            Button("驳回") {
                                                viewModel.submitTeacherFeedback(decision: .rejected)
                                            }
                                            .buttonStyle(.bordered)

                                            Button("修正") {
                                                viewModel.submitTeacherFeedback(decision: .needsRevision)
                                            }
                                            .buttonStyle(.bordered)
                                        }

                                        if let feedbackStatusMessage = viewModel.feedbackStatusMessage {
                                            Text(feedbackStatusMessage)
                                                .font(.caption)
                                                .foregroundStyle(viewModel.feedbackWriteSucceeded ? .green : .red)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            } else {
                                Text("请选择一条执行日志进行审阅。")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .padding(.top, 8)
                            }
                        }
                        .frame(minWidth: 520, minHeight: 260)
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 1080, minHeight: 1120)
        .task {
            viewModel.startSafetyControlsIfNeeded()
            viewModel.refreshDashboard(promptAccessibilityPermission: false)
        }
    }
}

struct PermissionRow: View {
    let title: String
    let granted: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(granted ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(title)
            Spacer()
            Text(granted ? "已授权" : "未授权")
                .foregroundStyle(granted ? .green : .red)
        }
        .font(.callout)
    }
}

enum EmergencyStopSource {
    case uiButton
    case globalHotkey

    var displayName: String {
        switch self {
        case .uiButton:
            return "UI按钮"
        case .globalHotkey:
            return "全局快捷键"
        }
    }
}

final class EmergencyStopHotkeyMonitor {
    private let handler: () -> Void
    private var globalMonitorToken: Any?
    private var localMonitorToken: Any?

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    func start() {
        guard globalMonitorToken == nil, localMonitorToken == nil else {
            return
        }

        globalMonitorToken = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return
            }
            if self.isEmergencyStopShortcut(event: event) {
                self.handler()
            }
        }

        localMonitorToken = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }
            if self.isEmergencyStopShortcut(event: event) {
                self.handler()
                return nil
            }
            return event
        }
    }

    func stop() {
        if let globalMonitorToken {
            NSEvent.removeMonitor(globalMonitorToken)
            self.globalMonitorToken = nil
        }
        if let localMonitorToken {
            NSEvent.removeMonitor(localMonitorToken)
            self.localMonitorToken = nil
        }
    }

    private func isEmergencyStopShortcut(event: NSEvent) -> Bool {
        let requiredFlags: NSEvent.ModifierFlags = [.command, .shift]
        let modifiersMatch = event.modifierFlags.intersection(requiredFlags) == requiredFlags
        guard modifiersMatch else {
            return false
        }

        let character = event.charactersIgnoringModifiers ?? ""
        if character == "." {
            return true
        }

        return event.keyCode == 47
    }
}

@MainActor
final class OpenStaffDashboardViewModel: ObservableObject {
    @Published var currentMode: OpenStaffMode
    @Published var guardInputs = ModeGuardInput()
    @Published private(set) var transitionMessage: String?
    @Published private(set) var lastDecision: ModeTransitionDecision?
    @Published private(set) var permissionSnapshot: PermissionSnapshot
    @Published private(set) var recentTasks: [RecentTaskSummary]
    @Published private(set) var learningSessions: [LearningSessionSummary]
    @Published var selectedLearningSessionId: String?
    @Published var selectedLearningTaskId: String?
    @Published private(set) var executionLogs: [ExecutionLogSummary]
    @Published var selectedExecutionLogId: String?
    @Published var feedbackInput = ""
    @Published private(set) var latestFeedbackForSelectedLog: TeacherFeedbackSummary?
    @Published private(set) var feedbackStatusMessage: String?
    @Published private(set) var feedbackWriteSucceeded = false
    @Published private(set) var emergencyStopActive = false
    @Published private(set) var emergencyStopActivatedAt: Date?
    @Published private(set) var emergencyStopSource: EmergencyStopSource?
    @Published private(set) var lastRefreshedAt: Date?

    private let logger = InMemoryOrchestratorStateLogger()
    private let stateMachine: ModeStateMachine
    private let sessionId: String
    private var traceSequence = 0
    private var learningSnapshot = LearningSnapshot.empty
    private var executionReviewSnapshot = ExecutionReviewSnapshot.empty
    private var safetyControlsStarted = false
    private lazy var emergencyStopHotkeyMonitor = EmergencyStopHotkeyMonitor { [weak self] in
        DispatchQueue.main.async { [weak self] in
            self?.activateEmergencyStop(source: .globalHotkey)
        }
    }

    init(initialMode: OpenStaffMode = .teaching) {
        self.currentMode = initialMode
        self.permissionSnapshot = .unknown
        self.recentTasks = []
        self.learningSessions = []
        self.executionLogs = []
        self.stateMachine = ModeStateMachine(initialMode: initialMode, logger: logger)
        self.sessionId = "session-gui-\(UUID().uuidString.prefix(8).lowercased())"
    }

    var lastTransitionAccepted: Bool {
        lastDecision?.accepted ?? true
    }

    var currentStatusCode: String {
        if let lastDecision {
            return lastDecision.status.rawValue
        }
        return OrchestratorStatusCode.modeStable.rawValue
    }

    var currentCapabilities: [String] {
        stateMachine.allowedCapabilities(for: currentMode).map(\.rawValue).sorted()
    }

    var unmetRequirementsText: String {
        guard let lastDecision, !lastDecision.unmetRequirements.isEmpty else {
            return ""
        }
        return lastDecision.unmetRequirements.map(\.rawValue).joined(separator: ", ")
    }

    var tasksForSelectedSession: [LearningTaskSummary] {
        guard let selectedLearningSessionId else {
            return []
        }
        return learningSnapshot.tasksBySession[selectedLearningSessionId] ?? []
    }

    var selectedTaskDetail: LearningTaskDetail? {
        guard let selectedLearningTaskId else {
            return nil
        }
        return learningSnapshot.taskDetailsById[selectedLearningTaskId]
    }

    var selectedExecutionLog: ExecutionLogSummary? {
        guard let selectedExecutionLogId else {
            return nil
        }
        return executionReviewSnapshot.logById[selectedExecutionLogId]
    }

    var emergencyStopStatusText: String {
        guard emergencyStopActive else {
            return "紧急停止：未激活（全局快捷键 Cmd+Shift+.）"
        }

        let activatedAt = emergencyStopActivatedAt.map(OpenStaffDateFormatter.displayString(from:)) ?? "unknown-time"
        let sourceText = emergencyStopSource?.displayName ?? "unknown-source"
        return "紧急停止：已激活（\(sourceText) @ \(activatedAt)）"
    }

    func modeDisplayName(for mode: OpenStaffMode) -> String {
        switch mode {
        case .teaching:
            return "教学模式"
        case .assist:
            return "辅助模式"
        case .student:
            return "学生模式"
        }
    }

    func requestModeChange(to targetMode: OpenStaffMode) {
        guard targetMode != currentMode else {
            return
        }

        traceSequence += 1
        let timestamp = OpenStaffDateFormatter.iso8601String(from: Date())
        let context = ModeTransitionContext(
            traceId: "trace-gui-\(traceSequence)",
            sessionId: sessionId,
            timestamp: timestamp,
            teacherConfirmed: guardInputs.teacherConfirmed,
            learnedKnowledgeReady: guardInputs.learnedKnowledgeReady,
            executionPlanReady: guardInputs.executionPlanReady,
            pendingAssistSuggestion: guardInputs.pendingAssistSuggestion,
            emergencyStopActive: guardInputs.emergencyStopActive
        )
        let decision = stateMachine.transition(to: targetMode, context: context)
        lastDecision = decision
        currentMode = stateMachine.currentMode
        transitionMessage = decision.message
    }

    func startMode(_ mode: OpenStaffMode) {
        if currentMode == mode {
            applySyntheticDecision(
                fromMode: mode,
                toMode: mode,
                accepted: true,
                status: .modeStable,
                message: "\(modeDisplayName(for: mode))已在运行。"
            )
            return
        }
        requestModeChange(to: mode)
    }

    func stopMode(_ mode: OpenStaffMode) {
        guard currentMode == mode else {
            applySyntheticDecision(
                fromMode: currentMode,
                toMode: mode,
                accepted: false,
                status: .modeTransitionRejected,
                errorCode: .transitionDenied,
                message: "\(modeDisplayName(for: mode))当前未运行。"
            )
            return
        }

        if mode == .teaching {
            applySyntheticDecision(
                fromMode: .teaching,
                toMode: .teaching,
                accepted: true,
                status: .modeStable,
                message: "教学模式已停止，当前处于待机。"
            )
            return
        }

        requestModeChange(to: .teaching)
        if lastTransitionAccepted {
            transitionMessage = "\(modeDisplayName(for: mode))已停止，已回到教学模式。"
        }
    }

    func canStopMode(_ mode: OpenStaffMode) -> Bool {
        currentMode == mode
    }

    func refreshDashboard(promptAccessibilityPermission: Bool) {
        permissionSnapshot = PermissionSnapshot.capture(promptAccessibilityPermission: promptAccessibilityPermission)
        recentTasks = RecentTaskRepository.loadRecentTasks(limit: 8)
        learningSnapshot = LearningRecordRepository.loadLearningSnapshot()
        learningSessions = learningSnapshot.sessions
        reconcileLearningSelection()
        refreshExecutionReview()
        lastRefreshedAt = Date()
    }

    func selectLearningSession(_ sessionId: String?) {
        selectedLearningSessionId = sessionId
        reconcileTaskSelectionForCurrentSession()
    }

    func selectLearningTask(_ taskId: String?) {
        selectedLearningTaskId = taskId
    }

    func selectExecutionLog(_ logId: String?) {
        selectedExecutionLogId = logId
        feedbackStatusMessage = nil
        refreshSelectedLogFeedback()
    }

    func submitTeacherFeedback(decision: TeacherFeedbackDecision) {
        guard let selectedExecutionLog else {
            feedbackWriteSucceeded = false
            feedbackStatusMessage = "未选择执行日志，无法提交反馈。"
            return
        }

        let trimmedNote = feedbackInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if decision == .needsRevision && trimmedNote.isEmpty {
            feedbackWriteSucceeded = false
            feedbackStatusMessage = "修正反馈需填写备注。"
            return
        }

        let entry = TeacherFeedbackWriteEntry(
            feedbackId: "feedback-\(UUID().uuidString.lowercased())",
            timestamp: OpenStaffDateFormatter.iso8601String(from: Date()),
            decision: decision,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            sessionId: selectedExecutionLog.sessionId,
            taskId: selectedExecutionLog.taskId,
            logEntryId: selectedExecutionLog.id,
            logStatus: selectedExecutionLog.status,
            logMessage: selectedExecutionLog.message,
            component: selectedExecutionLog.component
        )

        do {
            try TeacherFeedbackWriter.append(entry)
            feedbackInput = ""
            feedbackWriteSucceeded = true
            feedbackStatusMessage = "反馈已保存：\(decision.displayName)"
            refreshExecutionReview()
        } catch {
            feedbackWriteSucceeded = false
            feedbackStatusMessage = "反馈保存失败：\(error.localizedDescription)"
        }
    }

    func startSafetyControlsIfNeeded() {
        guard !safetyControlsStarted else {
            return
        }
        safetyControlsStarted = true
        emergencyStopHotkeyMonitor.start()
    }

    func activateEmergencyStop(source: EmergencyStopSource) {
        emergencyStopActive = true
        emergencyStopActivatedAt = Date()
        emergencyStopSource = source
        guardInputs.emergencyStopActive = true

        feedbackWriteSucceeded = true
        feedbackStatusMessage = "安全控制：紧急停止已激活。"
    }

    func releaseEmergencyStop() {
        emergencyStopActive = false
        emergencyStopActivatedAt = nil
        emergencyStopSource = nil
        guardInputs.emergencyStopActive = false

        feedbackWriteSucceeded = true
        feedbackStatusMessage = "安全控制：紧急停止已解除。"
    }

    private func applySyntheticDecision(
        fromMode: OpenStaffMode,
        toMode: OpenStaffMode,
        accepted: Bool,
        status: OrchestratorStatusCode,
        errorCode: OrchestratorErrorCode? = nil,
        message: String
    ) {
        let decision = ModeTransitionDecision(
            fromMode: fromMode,
            toMode: toMode,
            accepted: accepted,
            status: status,
            errorCode: errorCode,
            message: message
        )
        lastDecision = decision
        transitionMessage = decision.message
    }

    private func reconcileLearningSelection() {
        let sessionIds = Set(learningSessions.map(\.sessionId))
        if let selectedLearningSessionId, !sessionIds.contains(selectedLearningSessionId) {
            self.selectedLearningSessionId = nil
        }
        if self.selectedLearningSessionId == nil {
            self.selectedLearningSessionId = learningSessions.first?.sessionId
        }
        reconcileTaskSelectionForCurrentSession()
    }

    private func reconcileTaskSelectionForCurrentSession() {
        let tasks = tasksForSelectedSession
        let taskIds = Set(tasks.map(\.id))
        if let selectedLearningTaskId, !taskIds.contains(selectedLearningTaskId) {
            self.selectedLearningTaskId = nil
        }
        if self.selectedLearningTaskId == nil {
            self.selectedLearningTaskId = tasks.first?.id
        }
    }

    private func refreshExecutionReview() {
        executionReviewSnapshot = ExecutionReviewRepository.loadExecutionSnapshot(limit: 120)
        executionLogs = executionReviewSnapshot.logs
        reconcileExecutionSelection()
        refreshSelectedLogFeedback()
    }

    private func reconcileExecutionSelection() {
        let logIds = Set(executionLogs.map(\.id))
        if let selectedExecutionLogId, !logIds.contains(selectedExecutionLogId) {
            self.selectedExecutionLogId = nil
        }
        if self.selectedExecutionLogId == nil {
            self.selectedExecutionLogId = executionLogs.first?.id
        }
    }

    private func refreshSelectedLogFeedback() {
        guard let selectedExecutionLogId else {
            latestFeedbackForSelectedLog = nil
            return
        }
        latestFeedbackForSelectedLog = executionReviewSnapshot.latestFeedbackByLogId[selectedExecutionLogId]
    }
}

struct ModeGuardInput {
    var teacherConfirmed = true
    var learnedKnowledgeReady = true
    var executionPlanReady = true
    var pendingAssistSuggestion = false
    var emergencyStopActive = false
}

struct PermissionSnapshot {
    let accessibilityTrusted: Bool
    let dataDirectoryWritable: Bool

    static let unknown = PermissionSnapshot(accessibilityTrusted: false, dataDirectoryWritable: false)

    static func capture(promptAccessibilityPermission: Bool) -> PermissionSnapshot {
        let checker = AccessibilityPermissionChecker()
        let trusted = checker.isTrusted(prompt: promptAccessibilityPermission)
        let writable = OpenStaffWorkspacePaths.ensureDataDirectoryWritable()
        return PermissionSnapshot(accessibilityTrusted: trusted, dataDirectoryWritable: writable)
    }
}

struct AccessibilityPermissionChecker {
    func isTrusted(prompt: Bool) -> Bool {
        let promptKey = "AXTrustedCheckOptionPrompt"
        let options = [promptKey: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

struct RecentTaskSummary: Identifiable {
    let mode: OpenStaffMode
    let sessionId: String
    let taskId: String
    let status: String
    let message: String
    let timestamp: Date

    var id: String {
        "\(mode.rawValue)|\(sessionId)|\(taskId)|\(status)"
    }
}

enum RecentTaskRepository {
    private static let decoder = JSONDecoder()

    static func loadRecentTasks(limit: Int) -> [RecentTaskSummary] {
        let logTasks = loadRecentTasksFromLogs()
        let knowledgeTasks = loadRecentTasksFromKnowledge()
        let merged = mergeLatestByTask(logTasks + knowledgeTasks)
        return Array(merged.prefix(limit))
    }

    private static func loadRecentTasksFromLogs() -> [RecentTaskSummary] {
        let logsRoot = OpenStaffWorkspacePaths.logsDirectory
        let logFiles = listFiles(withExtension: "log", under: logsRoot)
        guard !logFiles.isEmpty else {
            return []
        }

        var tasks: [RecentTaskSummary] = []
        tasks.reserveCapacity(64)

        for fileURL in logFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }
            for line in content.split(whereSeparator: \.isNewline) {
                guard let data = line.data(using: .utf8),
                      let logEntry = try? decoder.decode(RecentTaskLogEntry.self, from: data),
                      let taskId = logEntry.taskId,
                      let timestamp = OpenStaffDateFormatter.date(from: logEntry.timestamp) else {
                    continue
                }

                let mode = inferMode(component: logEntry.component)
                let summary = RecentTaskSummary(
                    mode: mode,
                    sessionId: logEntry.sessionId,
                    taskId: taskId,
                    status: logEntry.status,
                    message: logEntry.message,
                    timestamp: timestamp
                )
                tasks.append(summary)
            }
        }

        return tasks
    }

    private static func loadRecentTasksFromKnowledge() -> [RecentTaskSummary] {
        let knowledgeRoot = OpenStaffWorkspacePaths.knowledgeDirectory
        let knowledgeFiles = listFiles(withExtension: "json", under: knowledgeRoot)
        guard !knowledgeFiles.isEmpty else {
            return []
        }

        var tasks: [RecentTaskSummary] = []
        tasks.reserveCapacity(16)

        for fileURL in knowledgeFiles {
            guard let data = try? Data(contentsOf: fileURL),
                  let item = try? decoder.decode(RecentKnowledgeItem.self, from: data),
                  let timestamp = OpenStaffDateFormatter.date(from: item.createdAt) else {
                continue
            }

            let summary = RecentTaskSummary(
                mode: .teaching,
                sessionId: item.sessionId,
                taskId: item.taskId,
                status: "STATUS_KNO_KNOWLEDGE_READY",
                message: item.summary,
                timestamp: timestamp
            )
            tasks.append(summary)
        }

        return tasks
    }

    private static func mergeLatestByTask(_ tasks: [RecentTaskSummary]) -> [RecentTaskSummary] {
        var latestByKey: [String: RecentTaskSummary] = [:]
        latestByKey.reserveCapacity(tasks.count)

        for task in tasks {
            let key = "\(task.mode.rawValue)|\(task.sessionId)|\(task.taskId)"
            guard let existing = latestByKey[key] else {
                latestByKey[key] = task
                continue
            }
            if task.timestamp > existing.timestamp {
                latestByKey[key] = task
            }
        }

        return latestByKey
            .values
            .sorted { lhs, rhs in
                lhs.timestamp > rhs.timestamp
            }
    }

    private static func inferMode(component: String?) -> OpenStaffMode {
        let componentValue = component ?? ""
        if componentValue.contains("student") {
            return .student
        }
        if componentValue.contains("assist") {
            return .assist
        }
        return .teaching
    }

    private static func listFiles(withExtension pathExtension: String, under root: URL) -> [URL] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.path) else {
            return []
        }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var urls: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == pathExtension {
            urls.append(fileURL)
        }
        return urls
    }
}

private struct RecentTaskLogEntry: Decodable {
    let timestamp: String
    let sessionId: String
    let taskId: String?
    let status: String
    let message: String
    let component: String?
}

private struct RecentKnowledgeItem: Decodable {
    let taskId: String
    let sessionId: String
    let summary: String
    let createdAt: String
}

struct LearningSessionSummary: Identifiable {
    let sessionId: String
    let startedAt: Date?
    let endedAt: Date?
    let taskCount: Int
    let knowledgeItemCount: Int

    var id: String {
        sessionId
    }
}

struct LearningTaskSummary: Identifiable {
    let taskId: String
    let sessionId: String
    let startedAt: Date?
    let endedAt: Date?
    let eventCount: Int?
    let boundaryReason: String?
    let appName: String?
    let knowledgeStepCount: Int?

    var id: String {
        "\(sessionId)|\(taskId)"
    }
}

struct LearningTaskDetail {
    let task: LearningTaskSummary
    let knowledgeItem: LearningKnowledgeItemDetail?
}

struct LearningKnowledgeItemDetail {
    let knowledgeItemId: String
    let goal: String
    let summary: String
    let contextAppName: String
    let contextBundleId: String
    let windowTitle: String?
    let createdAt: Date?
    let constraints: [LearningKnowledgeConstraint]
    let steps: [LearningKnowledgeStep]
}

struct LearningKnowledgeConstraint: Identifiable {
    let type: String
    let description: String

    var id: String {
        "\(type)|\(description)"
    }
}

struct LearningKnowledgeStep: Identifiable {
    let stepId: String
    let instruction: String
    let sourceEventIds: [String]

    var id: String {
        stepId
    }
}

struct LearningSnapshot {
    let sessions: [LearningSessionSummary]
    let tasksBySession: [String: [LearningTaskSummary]]
    let taskDetailsById: [String: LearningTaskDetail]

    static let empty = LearningSnapshot(sessions: [], tasksBySession: [:], taskDetailsById: [:])
}

struct ExecutionLogSummary: Identifiable {
    let id: String
    let mode: OpenStaffMode
    let timestamp: Date
    let sessionId: String
    let taskId: String?
    let status: String
    let message: String
    let component: String?
    let errorCode: String?
    let sourceFilePath: String
    let lineNumber: Int
}

enum TeacherFeedbackDecision: String, Codable, CaseIterable {
    case approved
    case rejected
    case needsRevision

    var displayName: String {
        switch self {
        case .approved:
            return "通过"
        case .rejected:
            return "驳回"
        case .needsRevision:
            return "修正"
        }
    }
}

struct TeacherFeedbackSummary {
    let feedbackId: String
    let timestamp: Date
    let decision: TeacherFeedbackDecision
    let note: String?
}

struct ExecutionReviewSnapshot {
    let logs: [ExecutionLogSummary]
    let logById: [String: ExecutionLogSummary]
    let latestFeedbackByLogId: [String: TeacherFeedbackSummary]

    static let empty = ExecutionReviewSnapshot(logs: [], logById: [:], latestFeedbackByLogId: [:])
}

enum ExecutionReviewRepository {
    private static let decoder = JSONDecoder()

    static func loadExecutionSnapshot(limit: Int) -> ExecutionReviewSnapshot {
        let logs = loadLogs(limit: limit)
        var logById: [String: ExecutionLogSummary] = [:]
        logById.reserveCapacity(logs.count)
        for log in logs {
            logById[log.id] = log
        }

        let latestFeedbackByLogId = loadLatestFeedbackByLogId()
        return ExecutionReviewSnapshot(logs: logs, logById: logById, latestFeedbackByLogId: latestFeedbackByLogId)
    }

    private static func loadLogs(limit: Int) -> [ExecutionLogSummary] {
        let logFiles = listFiles(withExtension: "log", under: OpenStaffWorkspacePaths.logsDirectory)
        guard !logFiles.isEmpty else {
            return []
        }

        var logs: [ExecutionLogSummary] = []
        logs.reserveCapacity(256)

        for fileURL in logFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }
            let fileName = fileURL.lastPathComponent.lowercased()
            let defaultMode = inferMode(fromFileName: fileName)

            for (index, line) in content.split(whereSeparator: \.isNewline).enumerated() {
                guard let data = line.data(using: .utf8),
                      let record = try? decoder.decode(ExecutionLogRecord.self, from: data),
                      let timestamp = OpenStaffDateFormatter.date(from: record.timestamp) else {
                    continue
                }

                let inferredMode = inferMode(component: record.component) ?? defaultMode
                let lineNumber = index + 1
                let logId = "\(fileURL.path)#L\(lineNumber)"
                let item = ExecutionLogSummary(
                    id: logId,
                    mode: inferredMode,
                    timestamp: timestamp,
                    sessionId: record.sessionId,
                    taskId: record.taskId,
                    status: record.status,
                    message: record.message,
                    component: record.component,
                    errorCode: record.errorCode,
                    sourceFilePath: fileURL.path,
                    lineNumber: lineNumber
                )
                logs.append(item)
            }
        }

        let sorted = logs.sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.id < rhs.id
            }
            return lhs.timestamp > rhs.timestamp
        }

        if sorted.count <= limit {
            return sorted
        }
        return Array(sorted.prefix(limit))
    }

    private static func loadLatestFeedbackByLogId() -> [String: TeacherFeedbackSummary] {
        let feedbackFiles = listFiles(withExtension: "jsonl", under: OpenStaffWorkspacePaths.feedbackDirectory)
        guard !feedbackFiles.isEmpty else {
            return [:]
        }

        var latestByLogId: [String: TeacherFeedbackSummary] = [:]
        latestByLogId.reserveCapacity(64)

        for fileURL in feedbackFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }

            for line in content.split(whereSeparator: \.isNewline) {
                guard let data = line.data(using: .utf8),
                      let record = try? decoder.decode(TeacherFeedbackReadRecord.self, from: data),
                      let timestamp = OpenStaffDateFormatter.date(from: record.timestamp) else {
                    continue
                }

                let summary = TeacherFeedbackSummary(
                    feedbackId: record.feedbackId,
                    timestamp: timestamp,
                    decision: record.decision,
                    note: record.note
                )

                if let existing = latestByLogId[record.logEntryId] {
                    if summary.timestamp >= existing.timestamp {
                        latestByLogId[record.logEntryId] = summary
                    }
                } else {
                    latestByLogId[record.logEntryId] = summary
                }
            }
        }

        return latestByLogId
    }

    private static func inferMode(component: String?) -> OpenStaffMode? {
        let value = component?.lowercased() ?? ""
        if value.contains("student") {
            return .student
        }
        if value.contains("assist") {
            return .assist
        }
        if value.contains("capture") || value.contains("knowledge") || value.contains("task") || value.contains("orchestrator") {
            return .teaching
        }
        return nil
    }

    private static func inferMode(fromFileName fileName: String) -> OpenStaffMode {
        if fileName.contains("student") {
            return .student
        }
        if fileName.contains("assist") {
            return .assist
        }
        return .teaching
    }

    private static func listFiles(withExtension pathExtension: String, under root: URL) -> [URL] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.path) else {
            return []
        }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var urls: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == pathExtension {
            urls.append(fileURL)
        }
        return urls
    }
}

enum TeacherFeedbackWriter {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static func append(_ entry: TeacherFeedbackWriteEntry) throws {
        let directory = OpenStaffWorkspacePaths.feedbackDirectory
            .appendingPathComponent(OpenStaffDateFormatter.dayString(from: Date()), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let safeTaskId = entry.taskId ?? "no-task"
        let fileURL = directory.appendingPathComponent("\(entry.sessionId)-\(safeTaskId)-teacher-feedback.jsonl")
        var payload = try encoder.encode(entry)
        payload.append(0x0A)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: payload)
            try handle.close()
        } else {
            try payload.write(to: fileURL, options: .atomic)
        }
    }
}

enum LearningRecordRepository {
    private static let decoder = JSONDecoder()

    static func loadLearningSnapshot() -> LearningSnapshot {
        let chunkRecords = loadTaskChunkRecords()
        let knowledgeRecords = loadKnowledgeRecords()
        let knowledgeByTask = buildKnowledgeByTask(records: knowledgeRecords)

        var tasksBySession: [String: [LearningTaskSummary]] = [:]
        var taskDetailsById: [String: LearningTaskDetail] = [:]
        var sessionAggregates: [String: LearningSessionAggregate] = [:]

        for chunk in chunkRecords {
            let knowledge = knowledgeByTask[chunk.taskId]
            let task = LearningTaskSummary(
                taskId: chunk.taskId,
                sessionId: chunk.sessionId,
                startedAt: OpenStaffDateFormatter.date(from: chunk.startTimestamp),
                endedAt: OpenStaffDateFormatter.date(from: chunk.endTimestamp),
                eventCount: chunk.eventCount,
                boundaryReason: chunk.boundaryReason,
                appName: chunk.primaryContext.appName,
                knowledgeStepCount: knowledge?.steps.count
            )
            tasksBySession[chunk.sessionId, default: []].append(task)
            taskDetailsById[task.id] = LearningTaskDetail(task: task, knowledgeItem: mapKnowledgeDetail(knowledge))

            var aggregate = sessionAggregates[chunk.sessionId] ?? LearningSessionAggregate(sessionId: chunk.sessionId)
            aggregate.include(task: task, hasKnowledgeItem: knowledge != nil)
            sessionAggregates[chunk.sessionId] = aggregate
        }

        for knowledge in knowledgeRecords where taskDetailsById["\(knowledge.sessionId)|\(knowledge.taskId)"] == nil {
            let task = LearningTaskSummary(
                taskId: knowledge.taskId,
                sessionId: knowledge.sessionId,
                startedAt: nil,
                endedAt: OpenStaffDateFormatter.date(from: knowledge.createdAt),
                eventCount: nil,
                boundaryReason: nil,
                appName: knowledge.context.appName,
                knowledgeStepCount: knowledge.steps.count
            )
            tasksBySession[knowledge.sessionId, default: []].append(task)
            taskDetailsById[task.id] = LearningTaskDetail(task: task, knowledgeItem: mapKnowledgeDetail(knowledge))

            var aggregate = sessionAggregates[knowledge.sessionId] ?? LearningSessionAggregate(sessionId: knowledge.sessionId)
            aggregate.include(task: task, hasKnowledgeItem: true)
            sessionAggregates[knowledge.sessionId] = aggregate
        }

        let sortedTasksBySession = tasksBySession.mapValues { tasks in
            tasks.sorted { lhs, rhs in
                let lhsDate = lhs.endedAt ?? lhs.startedAt ?? Date.distantPast
                let rhsDate = rhs.endedAt ?? rhs.startedAt ?? Date.distantPast
                if lhsDate == rhsDate {
                    return lhs.taskId < rhs.taskId
                }
                return lhsDate > rhsDate
            }
        }

        let sessions = sessionAggregates
            .values
            .map { aggregate in
                LearningSessionSummary(
                    sessionId: aggregate.sessionId,
                    startedAt: aggregate.startedAt,
                    endedAt: aggregate.endedAt,
                    taskCount: aggregate.taskIds.count,
                    knowledgeItemCount: aggregate.knowledgeTaskIds.count
                )
            }
            .sorted { lhs, rhs in
                let lhsDate = lhs.endedAt ?? lhs.startedAt ?? Date.distantPast
                let rhsDate = rhs.endedAt ?? rhs.startedAt ?? Date.distantPast
                if lhsDate == rhsDate {
                    return lhs.sessionId < rhs.sessionId
                }
                return lhsDate > rhsDate
            }

        return LearningSnapshot(
            sessions: sessions,
            tasksBySession: sortedTasksBySession,
            taskDetailsById: taskDetailsById
        )
    }

    private static func loadTaskChunkRecords() -> [TaskChunkRecord] {
        let chunkFiles = listFiles(withExtension: "json", under: OpenStaffWorkspacePaths.taskChunksDirectory)
        guard !chunkFiles.isEmpty else {
            return []
        }

        var records: [TaskChunkRecord] = []
        records.reserveCapacity(chunkFiles.count)

        for fileURL in chunkFiles {
            guard let data = try? Data(contentsOf: fileURL),
                  let record = try? decoder.decode(TaskChunkRecord.self, from: data) else {
                continue
            }
            records.append(record)
        }
        return records
    }

    private static func loadKnowledgeRecords() -> [KnowledgeItemRecord] {
        let files = listFiles(withExtension: "json", under: OpenStaffWorkspacePaths.knowledgeDirectory)
        guard !files.isEmpty else {
            return []
        }

        var records: [KnowledgeItemRecord] = []
        records.reserveCapacity(files.count)

        for fileURL in files {
            guard let data = try? Data(contentsOf: fileURL),
                  let record = try? decoder.decode(KnowledgeItemRecord.self, from: data) else {
                continue
            }
            records.append(record)
        }
        return records
    }

    private static func buildKnowledgeByTask(records: [KnowledgeItemRecord]) -> [String: KnowledgeItemRecord] {
        var byTask: [String: KnowledgeItemRecord] = [:]
        byTask.reserveCapacity(records.count)

        for item in records {
            guard let existing = byTask[item.taskId] else {
                byTask[item.taskId] = item
                continue
            }

            let existingDate = OpenStaffDateFormatter.date(from: existing.createdAt) ?? Date.distantPast
            let currentDate = OpenStaffDateFormatter.date(from: item.createdAt) ?? Date.distantPast
            if currentDate >= existingDate {
                byTask[item.taskId] = item
            }
        }

        return byTask
    }

    private static func mapKnowledgeDetail(_ item: KnowledgeItemRecord?) -> LearningKnowledgeItemDetail? {
        guard let item else {
            return nil
        }
        return LearningKnowledgeItemDetail(
            knowledgeItemId: item.knowledgeItemId,
            goal: item.goal,
            summary: item.summary,
            contextAppName: item.context.appName,
            contextBundleId: item.context.appBundleId,
            windowTitle: item.context.windowTitle,
            createdAt: OpenStaffDateFormatter.date(from: item.createdAt),
            constraints: item.constraints.map { constraint in
                LearningKnowledgeConstraint(type: constraint.type, description: constraint.description)
            },
            steps: item.steps.map { step in
                LearningKnowledgeStep(
                    stepId: step.stepId,
                    instruction: step.instruction,
                    sourceEventIds: step.sourceEventIds
                )
            }
        )
    }

    private static func listFiles(withExtension pathExtension: String, under root: URL) -> [URL] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.path) else {
            return []
        }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var urls: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == pathExtension {
            urls.append(fileURL)
        }
        return urls
    }
}

private struct LearningSessionAggregate {
    let sessionId: String
    var startedAt: Date?
    var endedAt: Date?
    var taskIds: Set<String> = []
    var knowledgeTaskIds: Set<String> = []

    mutating func include(task: LearningTaskSummary, hasKnowledgeItem: Bool) {
        taskIds.insert(task.taskId)
        if hasKnowledgeItem {
            knowledgeTaskIds.insert(task.taskId)
        }

        if let taskStartedAt = task.startedAt {
            if let startedAt {
                self.startedAt = min(startedAt, taskStartedAt)
            } else {
                self.startedAt = taskStartedAt
            }
        }

        let taskEndedAt = task.endedAt ?? task.startedAt
        if let taskEndedAt {
            if let endedAt {
                self.endedAt = max(endedAt, taskEndedAt)
            } else {
                self.endedAt = taskEndedAt
            }
        }
    }
}

private struct TaskChunkRecord: Decodable {
    let taskId: String
    let sessionId: String
    let startTimestamp: String
    let endTimestamp: String
    let eventCount: Int
    let boundaryReason: String
    let primaryContext: TaskContextRecord
}

private struct TaskContextRecord: Decodable {
    let appName: String
}

private struct KnowledgeItemRecord: Decodable {
    let knowledgeItemId: String
    let taskId: String
    let sessionId: String
    let goal: String
    let summary: String
    let steps: [KnowledgeStepRecord]
    let context: KnowledgeContextRecord
    let constraints: [KnowledgeConstraintRecord]
    let createdAt: String
}

private struct KnowledgeStepRecord: Decodable {
    let stepId: String
    let instruction: String
    let sourceEventIds: [String]
}

private struct KnowledgeContextRecord: Decodable {
    let appName: String
    let appBundleId: String
    let windowTitle: String?
}

private struct KnowledgeConstraintRecord: Decodable {
    let type: String
    let description: String
}

private struct ExecutionLogRecord: Decodable {
    let timestamp: String
    let sessionId: String
    let taskId: String?
    let status: String
    let message: String
    let component: String?
    let errorCode: String?
}

struct TeacherFeedbackWriteEntry: Codable {
    let schemaVersion: String
    let feedbackId: String
    let timestamp: String
    let reviewerRole: String
    let decision: TeacherFeedbackDecision
    let note: String?
    let sessionId: String
    let taskId: String?
    let logEntryId: String
    let logStatus: String
    let logMessage: String
    let component: String?

    init(
        feedbackId: String,
        timestamp: String,
        decision: TeacherFeedbackDecision,
        note: String?,
        sessionId: String,
        taskId: String?,
        logEntryId: String,
        logStatus: String,
        logMessage: String,
        component: String?
    ) {
        self.schemaVersion = "teacher.feedback.v0"
        self.feedbackId = feedbackId
        self.timestamp = timestamp
        self.reviewerRole = "teacher"
        self.decision = decision
        self.note = note
        self.sessionId = sessionId
        self.taskId = taskId
        self.logEntryId = logEntryId
        self.logStatus = logStatus
        self.logMessage = logMessage
        self.component = component
    }
}

private struct TeacherFeedbackReadRecord: Decodable {
    let feedbackId: String
    let timestamp: String
    let decision: TeacherFeedbackDecision
    let note: String?
    let logEntryId: String
}

enum OpenStaffWorkspacePaths {
    static var repositoryRoot: URL {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["OPENSTAFF_WORKSPACE_ROOT"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        let fileManager = FileManager.default
        var candidate = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)

        for _ in 0..<8 {
            let dataPath = candidate.appendingPathComponent("data", isDirectory: true).path
            let docsPath = candidate.appendingPathComponent("docs", isDirectory: true).path
            if fileManager.fileExists(atPath: dataPath),
               fileManager.fileExists(atPath: docsPath) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }

        return URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
    }

    static var dataDirectory: URL {
        repositoryRoot.appendingPathComponent("data", isDirectory: true)
    }

    static var logsDirectory: URL {
        dataDirectory.appendingPathComponent("logs", isDirectory: true)
    }

    static var knowledgeDirectory: URL {
        dataDirectory.appendingPathComponent("knowledge", isDirectory: true)
    }

    static var taskChunksDirectory: URL {
        dataDirectory.appendingPathComponent("task-chunks", isDirectory: true)
    }

    static var feedbackDirectory: URL {
        dataDirectory.appendingPathComponent("feedback", isDirectory: true)
    }

    static func ensureDataDirectoryWritable() -> Bool {
        let fileManager = FileManager.default
        let dataPath = dataDirectory.path

        do {
            try fileManager.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        } catch {
            return false
        }

        return fileManager.isWritableFile(atPath: dataPath)
    }
}

enum OpenStaffDateFormatter {
    static func dayString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func displayString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func date(from value: String) -> Date? {
        let formatterWithFractional = ISO8601DateFormatter()
        formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let fractionalDate = formatterWithFractional.date(from: value) {
            return fractionalDate
        }
        let formatterWithoutFractional = ISO8601DateFormatter()
        formatterWithoutFractional.formatOptions = [.withInternetDateTime]
        return formatterWithoutFractional.date(from: value)
    }
}

private extension OpenStaffMode {
    var color: Color {
        switch self {
        case .teaching:
            return .blue
        case .assist:
            return .orange
        case .student:
            return .green
        }
    }
}
