import Foundation
import XCTest
@testable import OpenStaffApp

final class AssistKnowledgeRetrieverTests: XCTestCase {
    func testRetrieverRanksCandidatesUsingWindowGoalAndRecentSequence() {
        let input = AssistPredictionInput(
            completedStepCount: 1,
            currentAppName: "Safari",
            currentAppBundleId: "com.apple.Safari",
            currentWindowTitle: "OpenStaff - GitHub",
            currentTaskGoal: "处理 Pull Requests",
            recentStepInstructions: ["点击 Pull Requests"],
            knowledgeItems: [
                makeKnowledgeItem(
                    knowledgeItemId: "ki-merge-002",
                    taskId: "task-merge-002",
                    createdAt: "2026-03-13T12:00:00Z",
                    goal: "在 Safari 中处理 Pull Requests",
                    windowTitle: "OpenStaff - GitHub",
                    stepTitles: ["Pull Requests", "Merge"]
                ),
                makeKnowledgeItem(
                    knowledgeItemId: "ki-merge-001",
                    taskId: "task-merge-001",
                    createdAt: "2026-03-13T11:00:00Z",
                    goal: "在 Safari 中处理 Pull Requests",
                    windowTitle: "OpenStaff - GitHub",
                    stepTitles: ["Pull Requests", "Merge"]
                ),
                makeKnowledgeItem(
                    knowledgeItemId: "ki-issue-001",
                    taskId: "task-issue-001",
                    createdAt: "2026-03-13T10:00:00Z",
                    goal: "在 Safari 中处理 Pull Requests",
                    windowTitle: "OpenStaff - GitHub",
                    stepTitles: ["Issues", "New Issue"]
                )
            ]
        )

        let matches = AssistKnowledgeRetriever(maxResults: 5).retrieve(input: input).matches

        XCTAssertGreaterThanOrEqual(matches.count, 2)
        XCTAssertEqual(matches[0].knowledgeItemId, "ki-merge-002")
        XCTAssertEqual(matches[0].targetDescription, "Merge")
        XCTAssertTrue(matches[0].matchedSignals.contains(where: { $0.type == .app }))
        XCTAssertTrue(matches[0].matchedSignals.contains(where: { $0.type == .window }))
        XCTAssertTrue(matches[0].matchedSignals.contains(where: { $0.type == .recentSequence }))
        XCTAssertTrue(matches[0].matchedSignals.contains(where: { $0.type == .goal }))
        XCTAssertTrue(matches[0].matchedSignals.contains(where: { $0.type == .historicalPreference }))
        XCTAssertEqual(matches[1].knowledgeItemId, "ki-merge-001")
        XCTAssertGreaterThan(matches[0].score, matches[2].score)
    }

    func testPredictorReturnsEvidenceAndReadableReason() {
        let input = AssistPredictionInput(
            completedStepCount: 1,
            currentAppName: "Safari",
            currentAppBundleId: "com.apple.Safari",
            currentWindowTitle: "OpenStaff - GitHub",
            currentTaskGoal: "处理 Pull Requests",
            recentStepInstructions: ["点击 Pull Requests"],
            knowledgeItems: [
                makeKnowledgeItem(
                    knowledgeItemId: "ki-merge-002",
                    taskId: "task-merge-002",
                    createdAt: "2026-03-13T12:00:00Z",
                    goal: "在 Safari 中处理 Pull Requests",
                    windowTitle: "OpenStaff - GitHub",
                    stepTitles: ["Pull Requests", "Merge"]
                ),
                makeKnowledgeItem(
                    knowledgeItemId: "ki-merge-001",
                    taskId: "task-merge-001",
                    createdAt: "2026-03-13T11:00:00Z",
                    goal: "在 Safari 中处理 Pull Requests",
                    windowTitle: "OpenStaff - GitHub",
                    stepTitles: ["Pull Requests", "Merge"]
                )
            ]
        )

        let suggestion = RetrievalBasedAssistPredictor(
            retriever: AssistKnowledgeRetriever(maxResults: 5),
            evidenceLimit: 3
        ).predict(input: input)

        XCTAssertNotNil(suggestion)
        XCTAssertEqual(suggestion?.predictorVersion, AssistPredictionStrategy.retrievalV1.rawValue)
        XCTAssertEqual(suggestion?.action.type, .click)
        XCTAssertEqual(suggestion?.knowledgeItemId, "ki-merge-002")
        XCTAssertEqual(suggestion?.evidence.count, 2)
        XCTAssertTrue(suggestion?.action.reason.contains("OpenStaff - GitHub") == true)
        XCTAssertTrue(suggestion?.action.reason.contains("参考了 2 条历史知识") == true)
        XCTAssertTrue(suggestion?.action.reason.contains("Merge") == true)
    }

    private func makeKnowledgeItem(
        knowledgeItemId: String,
        taskId: String,
        createdAt: String,
        goal: String,
        windowTitle: String,
        stepTitles: [String]
    ) -> KnowledgeItem {
        KnowledgeItem(
            knowledgeItemId: knowledgeItemId,
            taskId: taskId,
            sessionId: "session-\(knowledgeItemId)",
            goal: goal,
            summary: "summary",
            steps: stepTitles.enumerated().map { index, title in
                KnowledgeStep(
                    stepId: String(format: "step-%03d", index + 1),
                    instruction: "点击 \(title)",
                    sourceEventIds: ["evt-\(knowledgeItemId)-\(index + 1)"],
                    target: KnowledgeStepTarget(
                        coordinate: PointerLocation(x: 200 + index, y: 300 + index),
                        semanticTargets: [
                            SemanticTarget(
                                locatorType: .roleAndTitle,
                                appBundleId: "com.apple.Safari",
                                windowTitlePattern: SemanticTarget.exactWindowTitlePattern(for: windowTitle),
                                elementRole: "AXButton",
                                elementTitle: title,
                                elementIdentifier: title.lowercased().replacingOccurrences(of: " ", with: "-"),
                                confidence: 0.92,
                                source: .capture
                            )
                        ],
                        preferredLocatorType: .roleAndTitle
                    )
                )
            },
            context: KnowledgeContext(
                appName: "Safari",
                appBundleId: "com.apple.Safari",
                windowTitle: windowTitle,
                windowId: "1"
            ),
            constraints: [],
            source: KnowledgeSource(
                taskChunkSchemaVersion: "knowledge.task-chunk.v0",
                startTimestamp: "2026-03-13T10:00:00Z",
                endTimestamp: "2026-03-13T10:00:02Z",
                eventCount: stepTitles.count,
                boundaryReason: .sessionEnd
            ),
            createdAt: createdAt
        )
    }
}
