import json
from pathlib import Path
import tempfile
import unittest

from tests.swift_cli_test_utils import extract_last_json_object, run_swift_target


def make_knowledge_item(
    knowledge_item_id: str,
    task_id: str,
    created_at: str,
    goal: str,
    window_title: str,
    step_titles: list[str],
) -> dict:
    steps = []
    for index, title in enumerate(step_titles, start=1):
        steps.append(
            {
                "stepId": f"step-{index:03d}",
                "instruction": f"点击 {title}",
                "sourceEventIds": [f"evt-{knowledge_item_id}-{index:03d}"],
                "target": {
                    "coordinate": {
                        "x": 300 + index,
                        "y": 400 + index,
                        "coordinateSpace": "screen",
                    },
                    "semanticTargets": [
                        {
                            "locatorType": "roleAndTitle",
                            "appBundleId": "com.apple.Safari",
                            "windowTitlePattern": "^OpenStaff\\ - GitHub$",
                            "elementRole": "AXButton",
                            "elementTitle": title,
                            "elementIdentifier": title.lower().replace(" ", "-"),
                            "confidence": 0.91,
                            "source": "capture",
                        }
                    ],
                    "preferredLocatorType": "roleAndTitle",
                },
            }
        )

    return {
        "schemaVersion": "knowledge.item.v0",
        "knowledgeItemId": knowledge_item_id,
        "taskId": task_id,
        "sessionId": f"session-{knowledge_item_id}",
        "goal": goal,
        "summary": "summary",
        "steps": steps,
        "context": {
            "appName": "Safari",
            "appBundleId": "com.apple.Safari",
            "windowTitle": window_title,
            "windowId": "1",
        },
        "constraints": [],
        "source": {
            "taskChunkSchemaVersion": "knowledge.task-chunk.v0",
            "startTimestamp": "2026-03-13T10:00:00Z",
            "endTimestamp": "2026-03-13T10:00:02Z",
            "eventCount": len(step_titles),
            "boundaryReason": "sessionEnd",
        },
        "createdAt": created_at,
        "generatorVersion": "rule-v0",
    }


class AssistRetrievalCLITests(unittest.TestCase):
    def test_assist_cli_uses_history_retrieval_and_reports_sources(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            knowledge_dir = tmp_path / "knowledge"
            logs_root = tmp_path / "logs"
            knowledge_dir.mkdir()

            items = [
                make_knowledge_item(
                    knowledge_item_id="ki-merge-002",
                    task_id="task-merge-002",
                    created_at="2026-03-13T12:00:00Z",
                    goal="在 Safari 中处理 Pull Requests",
                    window_title="OpenStaff - GitHub",
                    step_titles=["Pull Requests", "Merge"],
                ),
                make_knowledge_item(
                    knowledge_item_id="ki-merge-001",
                    task_id="task-merge-001",
                    created_at="2026-03-13T11:00:00Z",
                    goal="在 Safari 中处理 Pull Requests",
                    window_title="OpenStaff - GitHub",
                    step_titles=["Pull Requests", "Merge"],
                ),
                make_knowledge_item(
                    knowledge_item_id="ki-issue-001",
                    task_id="task-issue-001",
                    created_at="2026-03-13T10:00:00Z",
                    goal="在 Safari 中处理 Pull Requests",
                    window_title="OpenStaff - GitHub",
                    step_titles=["Issues", "New Issue"],
                ),
            ]

            for item in items:
                (knowledge_dir / f"{item['knowledgeItemId']}.json").write_text(
                    json.dumps(item, ensure_ascii=False, indent=2),
                    encoding="utf-8",
                )

            result = run_swift_target(
                "OpenStaffAssistCLI",
                [
                    "--knowledge-item",
                    str(knowledge_dir),
                    "--from",
                    "teaching",
                    "--app-name",
                    "Safari",
                    "--app-bundle-id",
                    "com.apple.Safari",
                    "--window-title",
                    "OpenStaff - GitHub",
                    "--goal",
                    "处理 Pull Requests",
                    "--recent-step",
                    "点击 Pull Requests",
                    "--completed-steps",
                    "1",
                    "--auto-confirm",
                    "yes",
                    "--logs-root",
                    str(logs_root),
                    "--trace-id",
                    "trace-e2e-assist-retrieval-001",
                    "--timestamp",
                    "2026-03-13T10:15:00+08:00",
                    "--json-result",
                ],
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)
            payload = extract_last_json_object(result.stdout)
            self.assertEqual(payload.get("finalStatus"), "completed")

            suggestion = payload.get("suggestion") or {}
            action = suggestion.get("action") or {}
            evidence = suggestion.get("evidence") or []

            self.assertEqual(suggestion.get("predictorVersion"), "retrievalV1")
            self.assertEqual(suggestion.get("knowledgeItemId"), "ki-merge-002")
            self.assertEqual(action.get("instruction"), "点击 Merge")
            self.assertIn("参考了 2 条历史知识", action.get("reason", ""))
            self.assertEqual(len(evidence), 2)
            self.assertEqual(evidence[0].get("knowledgeItemId"), "ki-merge-002")
            self.assertEqual(evidence[1].get("knowledgeItemId"), "ki-merge-001")
            self.assertTrue(Path(payload["logFilePath"]).exists())


if __name__ == "__main__":
    unittest.main()
