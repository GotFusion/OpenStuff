import XCTest
@testable import OpenStaffApp

final class SkillPreflightValidatorTests: XCTestCase {
    func testPreflightMarksTeacherConfirmationRequiredSkillAsNonAutoRunnable() {
        let report = SkillPreflightValidator().validate(
            payload: makePayload(
                requiresTeacherConfirmation: true,
                stepMappings: [
                    makeStepMapping(
                        semanticTargets: [
                            SkillBundleSemanticTarget(
                                locatorType: .roleAndTitle,
                                appBundleId: "com.apple.Safari",
                                windowTitlePattern: "^Main$",
                                elementRole: "AXButton",
                                elementTitle: "Open",
                                confidence: 0.92,
                                source: "capture"
                            )
                        ]
                    )
                ]
            )
        )

        XCTAssertEqual(report.status, .needsTeacherConfirmation)
        XCTAssertFalse(report.isAutoRunnable)
        XCTAssertTrue(report.requiresTeacherConfirmation)
        XCTAssertTrue(report.issues.contains(where: { $0.code == .manualConfirmationRequired }))
    }

    func testPreflightFailsClickStepWithoutResolvableLocator() {
        let report = SkillPreflightValidator().validate(
            payload: makePayload(stepMappings: [])
        )

        XCTAssertEqual(report.status, .failed)
        XCTAssertTrue(report.issues.contains(where: { $0.code == .missingStepMapping }))
        XCTAssertTrue(report.issues.contains(where: { $0.code == .missingLocator }))
    }

    func testPreflightFailsWhenStepTargetsNonAllowlistedApp() {
        let report = SkillPreflightValidator().validate(
            payload: makePayload(
                stepMappings: [
                    makeStepMapping(
                        semanticTargets: [
                            SkillBundleSemanticTarget(
                                locatorType: .roleAndTitle,
                                appBundleId: "com.apple.Terminal",
                                windowTitlePattern: "^Main$",
                                elementRole: "AXButton",
                                elementTitle: "Open",
                                confidence: 0.92,
                                source: "capture"
                            )
                        ]
                    )
                ]
            )
        )

        XCTAssertEqual(report.status, .failed)
        XCTAssertTrue(report.issues.contains(where: { $0.code == .targetAppNotAllowed }))
    }

    private func makePayload(
        requiresTeacherConfirmation: Bool = false,
        confidence: Double = 0.86,
        stepMappings: [SkillBundleStepMapping]
    ) -> SkillBundlePayload {
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
                    appName: "Safari",
                    appBundleId: "com.apple.Safari",
                    windowTitle: "Main"
                ),
                executionPlan: SkillBundleExecutionPlan(
                    requiresTeacherConfirmation: requiresTeacherConfirmation,
                    steps: [
                        SkillBundleExecutionStep(
                            stepId: "step-001",
                            actionType: "click",
                            instruction: "点击 Open",
                            target: "unknown",
                            sourceEventIds: ["evt-1"]
                        )
                    ],
                    completionCriteria: SkillBundleCompletionCriteria(
                        expectedStepCount: 1,
                        requiredFrontmostAppBundleId: "com.apple.Safari"
                    )
                ),
                safetyNotes: ["执行前确认前台应用。"],
                confidence: confidence
            ),
            provenance: SkillBundleProvenance(
                skillBuild: SkillBundleSkillBuild(repairVersion: 0),
                stepMappings: stepMappings
            )
        )
    }

    private func makeStepMapping(
        semanticTargets: [SkillBundleSemanticTarget]
    ) -> SkillBundleStepMapping {
        SkillBundleStepMapping(
            skillStepId: "step-001",
            knowledgeStepId: "knowledge-step-001",
            instruction: "点击 Open",
            sourceEventIds: ["evt-1"],
            preferredLocatorType: .roleAndTitle,
            coordinate: SkillBundleCoordinate(x: 320, y: 240, coordinateSpace: "screen"),
            semanticTargets: semanticTargets
        )
    }
}
