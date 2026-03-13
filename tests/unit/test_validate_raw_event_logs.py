import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "scripts/validation/validate_raw_event_logs.py"


def load_module():
    scripts_dir = str(MODULE_PATH.parent)
    if scripts_dir not in sys.path:
        sys.path.insert(0, scripts_dir)
    spec = importlib.util.spec_from_file_location("validate_raw_event_logs", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec is not None and spec.loader is not None
    spec.loader.exec_module(module)
    return module


class ValidateRawEventLogsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_module()

    def test_strict_report_passes_for_current_sample(self):
        report = self.mod.build_report(
            REPO_ROOT / "core/capture/examples/raw-events.sample.jsonl",
            "strict",
            20,
        )

        self.assertTrue(report["passed"])
        self.assertEqual(report["errorCount"], 0)

    def test_compat_mode_allows_legacy_keyboard_payload_with_warning(self):
        payload = {
            "schemaVersion": "capture.raw.v0",
            "eventId": "11111111-1111-4111-8111-111111111111",
            "sessionId": "session-legacy-a1",
            "timestamp": "2026-03-10T12:26:17.487Z",
            "source": "keyboard",
            "action": "keyDown",
            "pointer": {"x": 1, "y": 2, "coordinateSpace": "screen"},
            "contextSnapshot": {
                "appName": "Safari",
                "appBundleId": "com.apple.Safari",
                "windowTitle": "page",
                "isFrontmost": True,
            },
            "modifiers": [],
            "keyboard": {
                "keyCode": 13,
                "characters": "w",
                "charactersIgnoringModifiers": "w",
                "isRepeat": False,
            },
        }

        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "legacy.jsonl"
            path.write_text(json.dumps(payload, ensure_ascii=False) + "\n", encoding="utf-8")

            compat = self.mod.build_report(path, "compat", 20)
            strict = self.mod.build_report(path, "strict", 20)

        self.assertTrue(compat["passed"])
        self.assertEqual(compat["warningCount"], 1)
        self.assertFalse(strict["passed"])
        self.assertEqual(strict["errorCount"], 1)


if __name__ == "__main__":
    unittest.main()
