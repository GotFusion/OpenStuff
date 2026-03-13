from pathlib import Path
import tempfile
import unittest

from tests.swift_cli_test_utils import extract_last_json_object, run_swift_target


REPO_ROOT = Path(__file__).resolve().parents[2]
SKILL_SAMPLE_DIRECTORIES = [
    REPO_ROOT / "scripts/skills/examples/generated/openstaff-task-session-20260307-a1-001",
    REPO_ROOT / "scripts/skills/examples/generated/openstaff-task-session-20260307-b2-001",
    REPO_ROOT / "scripts/skills/examples/generated/openstaff-task-session-20260307-c3-001",
]


class OpenClawRunnerCLITests(unittest.TestCase):
    def test_runner_executes_three_sample_skills_via_subprocess(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            logs_root = Path(tmpdir) / "logs"

            for skill_dir in SKILL_SAMPLE_DIRECTORIES:
                result = run_swift_target(
                    "OpenStaffOpenClawCLI",
                    [
                        "--skill-dir",
                        str(skill_dir),
                        "--logs-root",
                        str(logs_root),
                        "--json-result",
                    ],
                )

                self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)
                payload = extract_last_json_object(result.stdout)
                self.assertEqual(payload["status"], "succeeded")
                self.assertEqual(payload["exitCode"], 0)
                self.assertGreater(payload["totalSteps"], 0)
                self.assertEqual(payload["review"]["status"], "succeeded")
                self.assertTrue(Path(payload["review"]["logFilePath"]).exists())

    def test_runner_returns_structured_failure_when_gateway_step_fails(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            logs_root = Path(tmpdir) / "logs"
            result = run_swift_target(
                "OpenStaffOpenClawCLI",
                [
                    "--skill-dir",
                    str(SKILL_SAMPLE_DIRECTORIES[0]),
                    "--logs-root",
                    str(logs_root),
                    "--simulate-runtime-failure-step",
                    "1",
                    "--json-result",
                ],
            )

            self.assertEqual(result.returncode, 2, msg=result.stderr or result.stdout)
            payload = extract_last_json_object(result.stdout)
            self.assertEqual(payload["status"], "failed")
            self.assertEqual(payload["errorCode"], "OCW-RUNTIME-FAILED")
            self.assertEqual(payload["failedSteps"], 1)
            self.assertEqual(payload["stepResults"][0]["errorCode"], "OCW-RUNTIME-FAILED")
            self.assertIn("OpenClaw gateway error", payload["stderr"])
            self.assertTrue(Path(payload["review"]["logFilePath"]).exists())


if __name__ == "__main__":
    unittest.main()
