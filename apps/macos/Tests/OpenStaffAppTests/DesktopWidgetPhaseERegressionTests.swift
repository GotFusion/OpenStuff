import Foundation
import XCTest
@testable import OpenStaffApp

final class DesktopWidgetPhaseERegressionTests: XCTestCase {
    private static let workspaceLock = NSLock()

    func testEmptyWorkspaceRefreshKeepsCompactEmptyState() throws {
        try withTemporaryWorkspace { _ in
            let viewModel = OpenStaffDesktopWidgetViewModel(autoRefreshEnabled: false)
            viewModel.refresh()

            XCTAssertTrue(viewModel.timelineTasks.isEmpty)
            XCTAssertEqual(viewModel.currentTaskBrief, "暂无任务")
            XCTAssertEqual(viewModel.nextTaskBrief, "等待下一步任务")
        }
    }

    func testLongTextTruncationRules() {
        let longText = String(repeating: "A", count: 96)

        let compactCurrent = DesktopWidgetTruncationRule.apply(longText, scenario: .compactCurrentTask)
        XCTAssertEqual(compactCurrent.count, 22)
        XCTAssertTrue(compactCurrent.hasSuffix("..."))

        let compactNext = DesktopWidgetTruncationRule.apply(longText, scenario: .compactNextTask)
        XCTAssertEqual(compactNext.count, 26)
        XCTAssertTrue(compactNext.hasSuffix("..."))

        let primaryTitle = DesktopWidgetTruncationRule.timelinePrimaryTaskTitle(
            order: 1,
            modeName: "教学",
            taskId: "task-session-20260309-a1-very-long-task-id-001"
        )
        XCTAssertTrue(primaryTitle.hasPrefix("一级任务 1：教学 · "))
        XCTAssertLessThanOrEqual(primaryTitle.count, 44)

        let primarySummary = DesktopWidgetTruncationRule.apply(longText, scenario: .timelinePrimaryTaskSummary)
        XCTAssertEqual(primarySummary.count, 44)
        XCTAssertTrue(primarySummary.hasSuffix("..."))

        let secondaryDetail = DesktopWidgetTruncationRule.apply(longText, scenario: .timelineSecondaryTaskDetail)
        XCTAssertEqual(secondaryDetail.count, 52)
        XCTAssertTrue(secondaryDetail.hasSuffix("..."))
    }

    func testTimelineTasksAreCappedForMoreThanTwentyGroups() throws {
        try withTemporaryWorkspace { workspaceRoot in
            let logsDirectory = workspaceRoot.appendingPathComponent("data/logs", isDirectory: true)
            let logFileURL = logsDirectory.appendingPathComponent("phase-e-many-tasks.log")
            try writeExecutionLogFixture(fileURL: logFileURL, taskCount: 30)

            let viewModel = OpenStaffDesktopWidgetViewModel(autoRefreshEnabled: false)
            viewModel.refresh()

            XCTAssertEqual(viewModel.timelineTasks.count, 24)
            XCTAssertEqual(viewModel.timelineTasks.first?.taskName, "task-07")
            XCTAssertEqual(viewModel.timelineTasks.last?.taskName, "task-30")
        }
    }

    func testSetModeFromMenuAutoShowsWidgetWhenHidden() throws {
        try withTemporaryWorkspace { _ in
            let viewModel = OpenStaffDesktopWidgetViewModel(autoRefreshEnabled: false)
            viewModel.isWidgetWindowVisible = false

            var openWindowCallCount = 0
            var activateCallCount = 0

            OpenStaffMenuBarActions.setModeFromMenu(
                .detailed,
                viewModel: viewModel,
                openDesktopWidgetWindow: { openWindowCallCount += 1 },
                activateApp: { activateCallCount += 1 }
            )

            XCTAssertEqual(viewModel.displayMode, .detailed)
            XCTAssertTrue(viewModel.isWidgetWindowVisible)
            XCTAssertEqual(openWindowCallCount, 1)
            XCTAssertEqual(activateCallCount, 1)
        }
    }

    func testToggleWidgetWindowHandlesHideAndShowPath() throws {
        try withTemporaryWorkspace { _ in
            let viewModel = OpenStaffDesktopWidgetViewModel(autoRefreshEnabled: false)
            viewModel.isWidgetWindowVisible = true

            var closeWindowCallCount = 0
            var openWindowCallCount = 0
            var activateCallCount = 0

            OpenStaffMenuBarActions.toggleDesktopWidgetWindow(
                viewModel: viewModel,
                closeDesktopWidgetWindowIfNeeded: { closeWindowCallCount += 1 },
                openDesktopWidgetWindow: { openWindowCallCount += 1 },
                activateApp: { activateCallCount += 1 }
            )

            XCTAssertFalse(viewModel.isWidgetWindowVisible)
            XCTAssertEqual(closeWindowCallCount, 1)
            XCTAssertEqual(openWindowCallCount, 0)
            XCTAssertEqual(activateCallCount, 0)

            OpenStaffMenuBarActions.toggleDesktopWidgetWindow(
                viewModel: viewModel,
                closeDesktopWidgetWindowIfNeeded: { closeWindowCallCount += 1 },
                openDesktopWidgetWindow: { openWindowCallCount += 1 },
                activateApp: { activateCallCount += 1 }
            )

            XCTAssertTrue(viewModel.isWidgetWindowVisible)
            XCTAssertEqual(closeWindowCallCount, 1)
            XCTAssertEqual(openWindowCallCount, 1)
            XCTAssertEqual(activateCallCount, 1)
        }
    }

    func testOpenConsoleActionTriggersOpenAndActivate() {
        var openConsoleCallCount = 0
        var activateCallCount = 0

        OpenStaffMenuBarActions.openConsoleWindow(
            openConsoleWindow: { openConsoleCallCount += 1 },
            activateApp: { activateCallCount += 1 }
        )

        XCTAssertEqual(openConsoleCallCount, 1)
        XCTAssertEqual(activateCallCount, 1)
    }

    @MainActor
    func testEmergencyStopStatusTextTransitions() {
        let dashboardViewModel = OpenStaffDashboardViewModel()
        XCTAssertTrue(dashboardViewModel.emergencyStopStatusText.contains("未激活"))

        dashboardViewModel.activateEmergencyStop(source: .uiButton)
        XCTAssertTrue(dashboardViewModel.emergencyStopStatusText.contains("已激活"))

        dashboardViewModel.releaseEmergencyStop()
        XCTAssertTrue(dashboardViewModel.emergencyStopStatusText.contains("未激活"))
    }

    private func withTemporaryWorkspace(
        _ body: (URL) throws -> Void
    ) throws {
        Self.workspaceLock.lock()
        defer { Self.workspaceLock.unlock() }

        let fileManager = FileManager.default
        let workspaceRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("openstaff-widget-phase-e-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: workspaceRoot.appendingPathComponent("docs", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: workspaceRoot.appendingPathComponent("data/logs", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: workspaceRoot.appendingPathComponent("data/knowledge", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: workspaceRoot.appendingPathComponent("data/task-chunks", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: workspaceRoot.appendingPathComponent("data/feedback", isDirectory: true),
            withIntermediateDirectories: true
        )

        let environment = ProcessInfo.processInfo.environment
        let previousOverride = environment["OPENSTAFF_WORKSPACE_ROOT"]
        setenv("OPENSTAFF_WORKSPACE_ROOT", workspaceRoot.path, 1)

        defer {
            if let previousOverride {
                setenv("OPENSTAFF_WORKSPACE_ROOT", previousOverride, 1)
            } else {
                unsetenv("OPENSTAFF_WORKSPACE_ROOT")
            }
            try? fileManager.removeItem(at: workspaceRoot)
        }

        try body(workspaceRoot)
    }

    private func writeExecutionLogFixture(fileURL: URL, taskCount: Int) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let baseTimestamp = Date(timeIntervalSince1970: 1_773_000_000)

        var lines: [String] = []
        lines.reserveCapacity(taskCount)

        for index in 1...taskCount {
            let timestamp = formatter.string(from: baseTimestamp.addingTimeInterval(TimeInterval(index)))
            let record = ExecutionLogFixture(
                timestamp: timestamp,
                sessionId: "session-phase-e",
                taskId: String(format: "task-%02d", index),
                status: "STATUS_WIDGET_PERF",
                message: "message-\(index)",
                component: "assist.mode.loop"
            )
            let data = try encoder.encode(record)
            guard let line = String(data: data, encoding: .utf8) else {
                XCTFail("Failed to encode fixture line")
                return
            }
            lines.append(line)
        }

        let content = lines.joined(separator: "\n") + "\n"
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

private struct ExecutionLogFixture: Encodable {
    let timestamp: String
    let sessionId: String
    let taskId: String
    let status: String
    let message: String
    let component: String
}
