import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "scripts/validation/validate_knowledge_items.py"


def load_module():
    scripts_dir = str(MODULE_PATH.parent)
    if scripts_dir not in sys.path:
        sys.path.insert(0, scripts_dir)
    spec = importlib.util.spec_from_file_location("validate_knowledge_items", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec is not None and spec.loader is not None
    spec.loader.exec_module(module)
    return module


class ValidateKnowledgeItemsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_module()
        cls.sample_payload = json.loads(
            (REPO_ROOT / "core/knowledge/examples/knowledge-item.sample.json").read_text(encoding="utf-8")
        )

    def test_strict_report_passes_for_current_sample(self):
        report = self.mod.build_report(
            REPO_ROOT / "core/knowledge/examples/knowledge-item.sample.json",
            "strict",
            20,
        )

        self.assertTrue(report["passed"])
        self.assertEqual(report["errorCount"], 0)

    def test_missing_targets_emit_warning_but_not_error(self):
        payload = json.loads(json.dumps(self.sample_payload))
        for step in payload["steps"]:
            step.pop("target", None)

        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "knowledge.json"
            path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

            report = self.mod.build_report(path, "compat", 20)

        self.assertTrue(report["passed"])
        self.assertEqual(report["errorCount"], 0)
        self.assertGreaterEqual(report["warningCount"], 1)
        self.assertTrue(
            any(
                item["code"] == "KNO-MISSING-STEP-TARGETS"
                for item in report["files"][0]["issues"]
            )
        )


if __name__ == "__main__":
    unittest.main()
