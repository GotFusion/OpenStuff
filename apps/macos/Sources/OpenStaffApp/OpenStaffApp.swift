import ApplicationServices
import Foundation
import SwiftUI

@main
struct OpenStaffApp: App {
    @StateObject private var viewModel = OpenStaffDashboardViewModel()

    var body: some Scene {
        WindowGroup("OpenStaff") {
            OpenStaffDashboardView(viewModel: viewModel)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 960, height: 700)
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
                    Text("阶段 5.1：教学 / 辅助 / 学生三模式切换与状态展示")
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
                    HStack(spacing: 8) {
                        Button("刷新任务与权限") {
                            viewModel.refreshDashboard(promptAccessibilityPermission: false)
                        }
                        .keyboardShortcut("r", modifiers: [.command])

                        Button("申请辅助功能权限") {
                            viewModel.refreshDashboard(promptAccessibilityPermission: true)
                        }
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
                            Toggle("紧急停止已激活", isOn: $viewModel.guardInputs.emergencyStopActive)
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
        }
        .padding(20)
        .frame(minWidth: 920, minHeight: 680)
        .task {
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

@MainActor
final class OpenStaffDashboardViewModel: ObservableObject {
    @Published var currentMode: OpenStaffMode
    @Published var guardInputs = ModeGuardInput()
    @Published private(set) var transitionMessage: String?
    @Published private(set) var lastDecision: ModeTransitionDecision?
    @Published private(set) var permissionSnapshot: PermissionSnapshot
    @Published private(set) var recentTasks: [RecentTaskSummary]
    @Published private(set) var lastRefreshedAt: Date?

    private let logger = InMemoryOrchestratorStateLogger()
    private let stateMachine: ModeStateMachine
    private let sessionId: String
    private var traceSequence = 0

    init(initialMode: OpenStaffMode = .teaching) {
        self.currentMode = initialMode
        self.permissionSnapshot = .unknown
        self.recentTasks = []
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

    func refreshDashboard(promptAccessibilityPermission: Bool) {
        permissionSnapshot = PermissionSnapshot.capture(promptAccessibilityPermission: promptAccessibilityPermission)
        recentTasks = RecentTaskRepository.loadRecentTasks(limit: 8)
        lastRefreshedAt = Date()
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

enum OpenStaffWorkspacePaths {
    static var repositoryRoot: URL {
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
