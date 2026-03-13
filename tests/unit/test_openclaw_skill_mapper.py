import importlib.util
import json
import tempfile
from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "scripts/skills/openclaw_skill_mapper.py"


def load_module():
    spec = importlib.util.spec_from_file_location("openclaw_skill_mapper", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec is not None and spec.loader is not None
    spec.loader.exec_module(module)
    return module


class OpenClawSkillMapperTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_module()
        cls.sample_knowledge = json.loads(
            (REPO_ROOT / "core/knowledge/examples/knowledge-item.sample.json").read_text(encoding="utf-8")
        )
        cls.sample_llm = json.loads(
            (REPO_ROOT / "scripts/llm/examples/knowledge-parse-output.sample.json").read_text(encoding="utf-8")
        )

    def test_sanitize_skill_name_uses_slug_and_limit(self):
        skill_name = self.mod.sanitize_skill_name("task-session-20260307-a1-001", "  Bad Name/With Spaces  ")
        self.assertEqual(skill_name, "bad-name-with-spaces")

    def test_parse_llm_output_invalid_text_produces_diagnostic(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            raw = Path(tmpdir) / "invalid.txt"
            raw.write_text("not a json output", encoding="utf-8")

            parsed, diagnostics = self.mod.parse_llm_output(raw)

        self.assertIsNone(parsed)
        self.assertTrue(any("Failed to extract JSON" in d for d in diagnostics))

    def test_normalize_execution_plan_fallbacks_when_llm_invalid(self):
        normalized, diagnostics = self.mod.normalize_execution_plan(
            knowledge_item=self.sample_knowledge,
            llm_output=None,
            llm_valid=False,
        )

        self.assertGreater(len(normalized["executionPlan"]["steps"]), 0)
        self.assertTrue(any("Fallback objective" in d for d in diagnostics))

    def test_build_provenance_contains_step_level_traceability(self):
        normalized, _ = self.mod.normalize_execution_plan(
            knowledge_item=self.sample_knowledge,
            llm_output=self.sample_llm,
            llm_valid=True,
        )

        provenance = self.mod.build_provenance(
            skill_name="openstaff-task-session-20260307-a1-001",
            knowledge_item=self.sample_knowledge,
            mapped=normalized,
            created_at=self.mod.iso_now(),
            llm_output_accepted=True,
        )

        self.assertEqual(provenance["knowledge"]["knowledgeItemId"], self.sample_knowledge["knowledgeItemId"])
        self.assertEqual(len(provenance["stepMappings"]), len(normalized["executionPlan"]["steps"]))
        self.assertEqual(provenance["stepMappings"][0]["knowledgeStepId"], "step-001")
        self.assertGreater(len(provenance["stepMappings"][0]["semanticTargets"]), 0)

    def test_validate_knowledge_item_detects_missing_steps(self):
        broken = dict(self.sample_knowledge)
        broken["steps"] = []

        errors = self.mod.validate_knowledge_item(broken)

        self.assertTrue(any("steps" in err for err in errors))


if __name__ == "__main__":
    unittest.main()
