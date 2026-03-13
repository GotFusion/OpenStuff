import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
RUNNER = REPO_ROOT / "scripts/release/run_regression.py"
OPENCLAW_EXECUTABLE = REPO_ROOT / "apps/macos/.build/debug/OpenStaffOpenClawCLI"
REPLAY_VERIFY_EXECUTABLE = REPO_ROOT / "apps/macos/.build/debug/OpenStaffReplayVerifyCLI"


class ReleaseRegressionIntegrationTests(unittest.TestCase):
    def run_cmd(self, args):
        return subprocess.run(
            args,
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_release_regression_covers_validation_replay_and_benchmark(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            output_root = Path(tmpdir) / "release"
            report_path = output_root / "report.json"
            command = [
                sys.executable,
                str(RUNNER),
                "--skip-tests",
                "--benchmark-case-limit",
                "2",
                "--output-root",
                str(output_root),
                "--report",
                str(report_path),
            ]
            if OPENCLAW_EXECUTABLE.exists():
                command.extend(["--openclaw-executable", str(OPENCLAW_EXECUTABLE)])
            if REPLAY_VERIFY_EXECUTABLE.exists():
                command.extend(["--replay-verify-executable", str(REPLAY_VERIFY_EXECUTABLE)])

            result = self.run_cmd(command)

            self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)
            self.assertTrue(report_path.exists())

            payload = json.loads(report_path.read_text(encoding="utf-8"))
            self.assertTrue(payload["passed"])
            check_names = {check["name"] for check in payload["checks"]}
            self.assertIn("raw-events-sample-strict", check_names)
            self.assertIn("knowledge-data-compat", check_names)
            self.assertIn("replay-verify-sample", check_names)
            self.assertIn("benchmark-personal-desktop", check_names)


if __name__ == "__main__":
    unittest.main()
