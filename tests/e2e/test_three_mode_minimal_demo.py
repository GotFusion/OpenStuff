import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
LLM_VALIDATE_PATH = REPO_ROOT / "scripts/llm/validate_knowledge_parse_output.py"
MAPPER_PATH = REPO_ROOT / "scripts/skills/openclaw_skill_mapper.py"
SKILL_VALIDATE_PATH = REPO_ROOT / "scripts/skills/validate_openclaw_skill.py"


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec is not None and spec.loader is not None
    spec.loader.exec_module(module)
    return module


class ThreeModeMinimalE2ETests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.llm_validate = load_module("validate_knowledge_parse_output", LLM_VALIDATE_PATH)
        cls.mapper = load_module("openclaw_skill_mapper", MAPPER_PATH)
        cls.skill_validate = load_module("validate_openclaw_skill", SKILL_VALIDATE_PATH)

        cls.knowledge_item = json.loads(
            (REPO_ROOT / "core/knowledge/examples/knowledge-item.sample.json").read_text(encoding="utf-8")
        )
        cls.llm_output = json.loads(
            (REPO_ROOT / "scripts/llm/examples/knowledge-parse-output.sample.json").read_text(encoding="utf-8")
        )

    def test_three_mode_minimal_demo(self):
        # Teaching mode: knowledge + LLM output must pass strict schema checks.
        schema_errors = self.llm_validate.validate_output(self.llm_output)
        self.assertEqual(schema_errors, [])

        # Assist mode: normalize execution plan for prediction/confirmation flow.
        mapped, diagnostics = self.mapper.normalize_execution_plan(
            knowledge_item=self.knowledge_item,
            llm_output=self.llm_output,
            llm_valid=True,
        )
        self.assertGreater(len(mapped["executionPlan"]["steps"]), 0)
        self.assertIsInstance(mapped["executionPlan"]["requiresTeacherConfirmation"], bool)

        # Student mode: render skill artifact and validate structural integrity.
        skill_name = self.mapper.sanitize_skill_name(self.knowledge_item["taskId"])
        created_at = self.mapper.iso_now()
        provenance = self.mapper.build_provenance(
            skill_name=skill_name,
            knowledge_item=self.knowledge_item,
            mapped=mapped,
            created_at=created_at,
            llm_output_accepted=True,
        )
        skill_md = self.mapper.render_skill_markdown(skill_name, mapped, self.knowledge_item, provenance)
        frontmatter, md_errors = self.skill_validate.validate_skill_markdown(skill_md)
        self.assertEqual(md_errors, [], msg="; ".join(md_errors))

        mapping_payload = {
            "schemaVersion": self.mapper.SCHEMA_VERSION,
            "skillName": skill_name,
            "knowledgeItemId": self.knowledge_item["knowledgeItemId"],
            "taskId": self.knowledge_item["taskId"],
            "sessionId": self.knowledge_item["sessionId"],
            "source": {
                "knowledgeItemPath": "core/knowledge/examples/knowledge-item.sample.json",
                "llmOutputPath": "scripts/llm/examples/knowledge-parse-output.sample.json",
            },
            "provenance": provenance,
            "mappedOutput": mapped,
            "llmOutputAccepted": True,
            "createdAt": created_at,
            "generatorVersion": self.mapper.GENERATOR_VERSION,
        }
        json_errors = self.skill_validate.validate_mapping_json(mapping_payload, frontmatter)
        self.assertEqual(json_errors, [], msg="; ".join(json_errors))

        self.assertIsInstance(diagnostics, list)


if __name__ == "__main__":
    unittest.main()
