import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
MAPPER = REPO_ROOT / "scripts/skills/openclaw_skill_mapper.py"
VALIDATOR = REPO_ROOT / "scripts/skills/validate_openclaw_skill.py"


class SkillPipelineIntegrationTests(unittest.TestCase):
    def run_cmd(self, args):
        return subprocess.run(
            args,
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_pipeline_with_valid_llm_output(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            skills_root = Path(tmpdir) / "skills"
            mapper = self.run_cmd(
                [
                    sys.executable,
                    str(MAPPER),
                    "--knowledge-item",
                    "core/knowledge/examples/knowledge-item.sample.json",
                    "--llm-output",
                    "scripts/llm/examples/knowledge-parse-output.sample.json",
                    "--skills-root",
                    str(skills_root),
                    "--overwrite",
                ]
            )
            self.assertEqual(mapper.returncode, 0, msg=mapper.stderr or mapper.stdout)

            skill_dir = skills_root / "openstaff-task-session-20260307-a1-001"
            self.assertTrue((skill_dir / "SKILL.md").exists())
            self.assertTrue((skill_dir / "openstaff-skill.json").exists())
            mapping = json.loads((skill_dir / "openstaff-skill.json").read_text(encoding="utf-8"))
            self.assertEqual(mapping["schemaVersion"], "openstaff.openclaw-skill.v1")
            self.assertEqual(mapping["provenance"]["knowledge"]["taskId"], mapping["taskId"])

            validator = self.run_cmd([sys.executable, str(VALIDATOR), "--skill-dir", str(skill_dir)])
            self.assertEqual(validator.returncode, 0, msg=validator.stderr or validator.stdout)

    def test_pipeline_fallback_with_invalid_llm_output(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            skills_root = Path(tmpdir) / "skills"
            mapper = self.run_cmd(
                [
                    sys.executable,
                    str(MAPPER),
                    "--knowledge-item",
                    "scripts/skills/examples/knowledge-item.sample.terminal.json",
                    "--llm-output",
                    "scripts/skills/examples/llm-output.sample.terminal-invalid.txt",
                    "--skills-root",
                    str(skills_root),
                    "--overwrite",
                ]
            )
            self.assertEqual(mapper.returncode, 0, msg=mapper.stderr or mapper.stdout)

            skill_dir = skills_root / "openstaff-task-session-20260307-c3-001"
            mapping = json.loads((skill_dir / "openstaff-skill.json").read_text(encoding="utf-8"))
            self.assertFalse(mapping["llmOutputAccepted"])
            self.assertGreater(len(mapping["diagnostics"]), 0)
            self.assertEqual(mapping["schemaVersion"], "openstaff.openclaw-skill.v1")
            self.assertEqual(mapping["provenance"]["skillBuild"]["repairVersion"], 0)

            validator = self.run_cmd([sys.executable, str(VALIDATOR), "--skill-dir", str(skill_dir)])
            self.assertEqual(validator.returncode, 0, msg=validator.stderr or validator.stdout)


if __name__ == "__main__":
    unittest.main()
