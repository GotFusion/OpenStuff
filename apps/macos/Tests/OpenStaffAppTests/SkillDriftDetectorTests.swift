import Foundation
import XCTest
@testable import OpenStaffApp

final class SkillDriftDetectorTests: XCTestCase {
    func testDetectorClassifiesUITextChangeAndPlannerSuggestsUpdatingLocator() {
        let payload = makePayload(
            stepMappings: [
                makeStepMapping(
                    stepId: "step-001",
                    locatorType: .textAnchor,
                    title: "Save",
                    identifier: "save-button",
                    textAnchor: "Save"
                )
            ]
        )
        let snapshot = makeSnapshot(
            windowTitle: "Main",
            visibleElements: [
                ReplayElementSnapshot(
                    axPath: "AXWindow/AXButton[0]",
                    role: "AXButton",
                    title: "提交",
                    identifier: "save-button",
                    boundingRect: SemanticBoundingRect(x: 200, y: 100, width: 80, height: 30)
                )
            ]
        )

        let report = SkillDriftDetector(
            resolver: SemanticTargetResolver(fingerprintCapture: TestFingerprintCapture(anchor: nil)),
            nowProvider: fixedNow
        ).detect(payload: payload, snapshot: snapshot)
        let plan = SkillRepairPlanner().buildPlan(report: report)

        XCTAssertEqual(report.status, .driftDetected)
        XCTAssertEqual(report.dominantDriftKind, .uiTextChanged)
        XCTAssertEqual(report.findings[0].driftKind, .uiTextChanged)
        XCTAssertEqual(report.findings[0].failureReason, .textAnchorChanged)
        XCTAssertTrue(plan.actions.contains(where: { $0.type == .updateSkillLocator }))
    }

    func testDetectorClassifiesCoordinateFallbackAsElementPositionDrift() {
        let payload = makePayload(
            stepMappings: [
                makeStepMapping(
                    stepId: "step-001",
                    locatorType: .coordinateFallback,
                    title: nil,
                    identifier: nil,
                    textAnchor: nil
                )
            ]
        )
        let snapshot = makeSnapshot(windowTitle: "Main")

        let report = SkillDriftDetector(
            resolver: SemanticTargetResolver(fingerprintCapture: TestFingerprintCapture(anchor: nil)),
            nowProvider: fixedNow
        ).detect(payload: payload, snapshot: snapshot)
        let plan = SkillRepairPlanner().buildPlan(report: report)

        XCTAssertEqual(report.dominantDriftKind, .elementPositionChanged)
        XCTAssertEqual(report.findings[0].failureReason, .coordinateFallbackOnly)
        XCTAssertTrue(plan.actions.contains(where: { $0.type == .relocalize }))
    }

    func testDetectorClassifiesWindowMismatchAsWindowStructureChanged() {
        let payload = makePayload(
            stepMappings: [
                makeStepMapping(
                    stepId: "step-001",
                    locatorType: .roleAndTitle,
                    title: "Open",
                    identifier: "open-button",
                    textAnchor: nil
                )
            ]
        )
        let snapshot = makeSnapshot(
            windowTitle: "Preferences",
            visibleElements: [
                ReplayElementSnapshot(
                    axPath: "AXWindow/AXButton[0]",
                    role: "AXButton",
                    title: "Open",
                    identifier: "open-button",
                    boundingRect: SemanticBoundingRect(x: 200, y: 100, width: 80, height: 30)
                )
            ]
        )

        let report = SkillDriftDetector(
            resolver: SemanticTargetResolver(fingerprintCapture: TestFingerprintCapture(anchor: nil)),
            nowProvider: fixedNow
        ).detect(payload: payload, snapshot: snapshot)
        let plan = SkillRepairPlanner().buildPlan(report: report)

        XCTAssertEqual(report.dominantDriftKind, .windowStructureChanged)
        XCTAssertEqual(report.findings[0].failureReason, .windowMismatch)
        XCTAssertTrue(plan.actions.contains(where: { $0.type == .reteachCurrentStep }))
    }

    func testDetectorEscalatesMultiStepRegressionToAppVersionChanged() {
        let payload = makePayload(
            stepMappings: [
                makeStepMapping(
                    stepId: "step-001",
                    locatorType: .roleAndTitle,
                    title: "Open",
                    identifier: "open-button",
                    textAnchor: nil
                ),
                makeStepMapping(
                    stepId: "step-002",
                    locatorType: .textAnchor,
                    title: "Save",
                    identifier: "save-button",
                    textAnchor: "Save"
                )
            ]
        )
        let snapshot = makeSnapshot(
            windowTitle: "Main v2",
            visibleElements: [
                ReplayElementSnapshot(
                    axPath: "AXWindow/AXButton[0]",
                    role: "AXButton",
                    title: "存储",
                    identifier: "save-button",
                    boundingRect: SemanticBoundingRect(x: 220, y: 110, width: 88, height: 30)
                )
            ]
        )

        let report = SkillDriftDetector(
            resolver: SemanticTargetResolver(fingerprintCapture: TestFingerprintCapture(anchor: nil)),
            nowProvider: fixedNow
        ).detect(payload: payload, snapshot: snapshot)
        let plan = SkillRepairPlanner().buildPlan(report: report)

        XCTAssertEqual(report.status, .driftDetected)
        XCTAssertEqual(report.dominantDriftKind, .appVersionChanged)
        XCTAssertTrue(plan.actions.contains(where: { $0.actionId == "repair-app-version-refresh" }))
        XCTAssertEqual(plan.recommendedRepairVersion, 1)
    }

    private func makePayload(stepMappings: [SkillBundleStepMapping]) -> SkillBundlePayload {
        SkillBundlePayload(
            schemaVersion: "openstaff.openclaw-skill.v1",
            skillName: "skill-test",
            knowledgeItemId: "knowledge-001",
            taskId: "task-001",
            sessionId: "session-001",
            llmOutputAccepted: true,
            createdAt: "2026-03-13T10:00:00Z",
            mappedOutput: SkillBundleMappedOutput(
                objective: "点击按钮",
                context: SkillBundleContext(
                    appName: "TestApp",
                    appBundleId: "com.test.app",
                    windowTitle: "Main"
                ),
                executionPlan: SkillBundleExecutionPlan(
                    requiresTeacherConfirmation: false,
                    steps: stepMappings.enumerated().map { index, mapping in
                        SkillBundleExecutionStep(
                            stepId: mapping.skillStepId,
                            actionType: "click",
                            instruction: "点击按钮 \(index + 1)",
                            target: "unknown",
                            sourceEventIds: ["evt-\(index + 1)"]
                        )
                    },
                    completionCriteria: SkillBundleCompletionCriteria(
                        expectedStepCount: stepMappings.count,
                        requiredFrontmostAppBundleId: "com.test.app"
                    )
                ),
                safetyNotes: ["note"],
                confidence: 0.9
            ),
            provenance: SkillBundleProvenance(
                skillBuild: SkillBundleSkillBuild(repairVersion: 0),
                stepMappings: stepMappings
            )
        )
    }

    private func makeStepMapping(
        stepId: String,
        locatorType: SkillBundleLocatorType,
        title: String?,
        identifier: String?,
        textAnchor: String?
    ) -> SkillBundleStepMapping {
        let semanticTargets: [SkillBundleSemanticTarget]
        switch locatorType {
        case .coordinateFallback:
            semanticTargets = [
                SkillBundleSemanticTarget(
                    locatorType: .coordinateFallback,
                    appBundleId: "com.test.app",
                    windowTitlePattern: "^Main$",
                    boundingRect: SkillBundleBoundingRect(
                        x: 320,
                        y: 240,
                        width: 1,
                        height: 1,
                        coordinateSpace: "screen"
                    ),
                    confidence: 0.24,
                    source: "capture"
                )
            ]
        default:
            semanticTargets = [
                SkillBundleSemanticTarget(
                    locatorType: locatorType,
                    appBundleId: "com.test.app",
                    windowTitlePattern: "^Main$",
                    elementRole: "AXButton",
                    elementTitle: title,
                    elementIdentifier: identifier,
                    textAnchor: textAnchor,
                    confidence: 0.91,
                    source: "capture"
                )
            ]
        }

        return SkillBundleStepMapping(
            skillStepId: stepId,
            knowledgeStepId: "knowledge-\(stepId)",
            instruction: "点击 \(title ?? "按钮")",
            sourceEventIds: ["evt-\(stepId)"],
            preferredLocatorType: locatorType,
            coordinate: SkillBundleCoordinate(x: 320, y: 240, coordinateSpace: "screen"),
            semanticTargets: semanticTargets
        )
    }

    private func makeSnapshot(
        windowTitle: String,
        visibleElements: [ReplayElementSnapshot] = []
    ) -> ReplayEnvironmentSnapshot {
        ReplayEnvironmentSnapshot(
            capturedAt: "2026-03-13T10:05:00Z",
            appName: "TestApp",
            appBundleId: "com.test.app",
            windowTitle: windowTitle,
            windowId: "1",
            windowSignature: WindowSignature(
                signature: "window-signature-\(windowTitle)",
                normalizedTitle: windowTitle.lowercased(),
                role: "AXWindow",
                subrole: "AXStandardWindow",
                sizeBucket: "12x8"
            ),
            focusedElement: visibleElements.first,
            visibleElements: visibleElements
        )
    }

    private func fixedNow() -> Date {
        Date(timeIntervalSince1970: 1_741_862_400)
    }
}

private struct TestFingerprintCapture: SemanticScreenFingerprintCapturing {
    let anchor: SemanticImageAnchor?

    func capture(rect: SemanticBoundingRect) -> SemanticImageAnchor? {
        anchor
    }
}
