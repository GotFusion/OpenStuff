import json
from pathlib import Path
import tempfile
import unittest

from tests.swift_cli_test_utils import extract_last_json_object, run_swift_target


def build_skill_payload() -> dict:
    return {
        "schemaVersion": "openstaff.openclaw-skill.v1",
        "skillName": "skill-test",
        "knowledgeItemId": "knowledge-001",
        "taskId": "task-001",
        "sessionId": "session-001",
        "llmOutputAccepted": True,
        "createdAt": "2026-03-13T10:00:00Z",
        "mappedOutput": {
            "objective": "点击按钮",
            "context": {
                "appName": "TestApp",
                "appBundleId": "com.test.app",
                "windowTitle": "Main",
            },
            "executionPlan": {
                "requiresTeacherConfirmation": False,
                "steps": [
                    {
                        "stepId": "step-001",
                        "actionType": "click",
                        "instruction": "点击 Save",
                        "target": "unknown",
                        "sourceEventIds": ["evt-1"],
                    }
                ],
                "completionCriteria": {
                    "expectedStepCount": 1,
                    "requiredFrontmostAppBundleId": "com.test.app",
                },
            },
            "safetyNotes": ["note"],
            "confidence": 0.9,
        },
        "provenance": {
            "skillBuild": {
                "repairVersion": 0,
            },
            "stepMappings": [
                {
                    "skillStepId": "step-001",
                    "knowledgeStepId": "knowledge-step-001",
                    "instruction": "点击 Save",
                    "sourceEventIds": ["evt-1"],
                    "preferredLocatorType": "textAnchor",
                    "coordinate": {
                        "x": 320,
                        "y": 240,
                        "coordinateSpace": "screen",
                    },
                    "semanticTargets": [
                        {
                            "locatorType": "textAnchor",
                            "appBundleId": "com.test.app",
                            "windowTitlePattern": "^Main$",
                            "elementRole": "AXButton",
                            "elementTitle": "Save",
                            "elementIdentifier": "save-button",
                            "textAnchor": "Save",
                            "confidence": 0.91,
                            "source": "capture",
                        }
                    ],
                }
            ],
        },
    }


def build_snapshot_payload() -> dict:
    return {
        "capturedAt": "2026-03-13T10:05:00Z",
        "appName": "TestApp",
        "appBundleId": "com.test.app",
        "windowTitle": "Main",
        "windowId": "1",
        "windowSignature": {
            "signature": "window-signature-main",
            "signatureVersion": "window-v1",
            "normalizedTitle": "main",
            "role": "AXWindow",
            "subrole": "AXStandardWindow",
            "sizeBucket": "12x8",
        },
        "focusedElement": {
            "axPath": "AXWindow/AXButton[0]",
            "role": "AXButton",
            "title": "提交",
            "identifier": "save-button",
            "boundingRect": {
                "x": 220,
                "y": 100,
                "width": 80,
                "height": 30,
                "coordinateSpace": "screen",
            },
        },
        "visibleElements": [
            {
                "axPath": "AXWindow/AXButton[0]",
                "role": "AXButton",
                "title": "提交",
                "identifier": "save-button",
                "boundingRect": {
                    "x": 220,
                    "y": 100,
                    "width": 80,
                    "height": 30,
                    "coordinateSpace": "screen",
                },
            }
        ],
        "screenshotAnchors": [],
        "captureDiagnostics": [],
    }


class ReplaySkillDriftCLITests(unittest.TestCase):
    def test_replay_verify_cli_reports_skill_drift_and_repair_plan(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            skill_dir = tmp_path / "skill-test"
            skill_dir.mkdir()
            snapshot_path = tmp_path / "snapshot.json"

            (skill_dir / "openstaff-skill.json").write_text(
                json.dumps(build_skill_payload(), ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
            snapshot_path.write_text(
                json.dumps(build_snapshot_payload(), ensure_ascii=False, indent=2),
                encoding="utf-8",
            )

            result = run_swift_target(
                "OpenStaffReplayVerifyCLI",
                [
                    "--skill-dir",
                    str(skill_dir),
                    "--snapshot",
                    str(snapshot_path),
                    "--json",
                ],
            )

            self.assertEqual(result.returncode, 2, msg=result.stderr or result.stdout)
            payload = extract_last_json_object(result.stdout)
            drift_report = payload["driftReport"]
            repair_plan = payload["repairPlan"]

            self.assertEqual(drift_report["status"], "driftDetected")
            self.assertEqual(drift_report["dominantDriftKind"], "uiTextChanged")
            self.assertEqual(drift_report["findings"][0]["failureReason"], "textAnchorChanged")
            self.assertTrue(any(action["type"] == "updateSkillLocator" for action in repair_plan["actions"]))


if __name__ == "__main__":
    unittest.main()
