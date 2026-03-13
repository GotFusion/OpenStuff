import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
VALIDATOR_PATH = REPO_ROOT / "scripts/validation/validate_skill_bundle.py"
SAMPLE_SKILL_DIR = REPO_ROOT / "scripts/skills/examples/generated/openstaff-task-session-20260307-a1-001"


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec is not None and spec.loader is not None
    spec.loader.exec_module(module)
    return module


class ValidateSkillBundleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.validator = load_module("validate_skill_bundle", VALIDATOR_PATH)

    def test_build_report_marks_sample_as_needing_teacher_confirmation(self):
        report = self.validator.build_report(SAMPLE_SKILL_DIR, [])

        self.assertEqual(report["status"], "needs_teacher_confirmation")
        self.assertFalse(report["isAutoRunnable"])
        self.assertTrue(report["requiresTeacherConfirmation"])
        self.assertTrue(any(item["code"] == "SPF-MANUAL-CONFIRMATION-REQUIRED" for item in report["issues"]))

    def test_build_report_fails_when_context_app_is_unknown(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            skill_dir = Path(tmpdir) / "skill"
            shutil.copytree(SAMPLE_SKILL_DIR, skill_dir)

            payload_path = skill_dir / "openstaff-skill.json"
            payload = json.loads(payload_path.read_text(encoding="utf-8"))
            payload["mappedOutput"]["context"]["appBundleId"] = "unknown"
            payload["mappedOutput"]["executionPlan"]["completionCriteria"]["requiredFrontmostAppBundleId"] = "unknown"
            payload_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

            report = self.validator.build_report(skill_dir, [])

            self.assertEqual(report["status"], "failed")
            self.assertTrue(any(item["code"] == "SPF-MISSING-CONTEXT-APP" for item in report["issues"]))

    def test_cli_require_auto_runnable_fails_confirmation_required_skill(self):
        completed = subprocess.run(
            [
                sys.executable,
                str(VALIDATOR_PATH),
                "--skill-dir",
                str(SAMPLE_SKILL_DIR),
                "--require-auto-runnable",
            ],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertEqual(completed.returncode, 1)
        self.assertIn("NEEDS_TEACHER_CONFIRMATION", completed.stdout)


if __name__ == "__main__":
    unittest.main()
