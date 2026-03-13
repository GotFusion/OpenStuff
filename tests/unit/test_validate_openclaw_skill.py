import copy
import importlib.util
import json
from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
MAPPER_PATH = REPO_ROOT / "scripts/skills/openclaw_skill_mapper.py"
VALIDATOR_PATH = REPO_ROOT / "scripts/skills/validate_openclaw_skill.py"


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec is not None and spec.loader is not None
    spec.loader.exec_module(module)
    return module


class ValidateOpenClawSkillTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mapper = load_module("openclaw_skill_mapper", MAPPER_PATH)
        cls.validator = load_module("validate_openclaw_skill", VALIDATOR_PATH)

        cls.knowledge_item = json.loads(
            (REPO_ROOT / "core/knowledge/examples/knowledge-item.sample.json").read_text(encoding="utf-8")
        )
        cls.llm_output = json.loads(
            (REPO_ROOT / "scripts/llm/examples/knowledge-parse-output.sample.json").read_text(encoding="utf-8")
        )

        cls.normalized, diagnostics = cls.mapper.normalize_execution_plan(
            knowledge_item=cls.knowledge_item,
            llm_output=cls.llm_output,
            llm_valid=True,
        )
        assert diagnostics == []

        cls.created_at = cls.mapper.iso_now()
        cls.provenance = cls.mapper.build_provenance(
            skill_name=cls.mapper.sanitize_skill_name(cls.knowledge_item["taskId"]),
            knowledge_item=cls.knowledge_item,
            mapped=cls.normalized,
            created_at=cls.created_at,
            llm_output_accepted=True,
        )

        cls.skill_name = cls.mapper.sanitize_skill_name(cls.knowledge_item["taskId"])
        cls.skill_md = cls.mapper.render_skill_markdown(
            cls.skill_name,
            cls.normalized,
            cls.knowledge_item,
            cls.provenance,
        )
        cls.frontmatter, cls.md_errors = cls.validator.validate_skill_markdown(cls.skill_md)
        assert cls.md_errors == []

    def test_validate_skill_markdown_accepts_rendered_skill(self):
        frontmatter, errors = self.validator.validate_skill_markdown(self.skill_md)
        self.assertEqual(errors, [])
        self.assertEqual(frontmatter.get("name"), self.skill_name)

    def test_validate_skill_markdown_rejects_missing_steps_section(self):
        invalid_markdown = self.skill_md.replace("## Steps", "## Procedure")
        _, errors = self.validator.validate_skill_markdown(invalid_markdown)
        self.assertTrue(any("## Steps" in err for err in errors))

    def test_validate_mapping_json_rejects_skill_name_mismatch(self):
        mapping = {
            "schemaVersion": self.mapper.SCHEMA_VERSION,
            "skillName": self.skill_name,
            "knowledgeItemId": self.knowledge_item["knowledgeItemId"],
            "taskId": self.knowledge_item["taskId"],
            "sessionId": self.knowledge_item["sessionId"],
            "source": {
                "knowledgeItemPath": "core/knowledge/examples/knowledge-item.sample.json",
                "llmOutputPath": "scripts/llm/examples/knowledge-parse-output.sample.json",
            },
            "provenance": self.provenance,
            "mappedOutput": self.normalized,
            "llmOutputAccepted": True,
            "createdAt": self.created_at,
            "generatorVersion": self.mapper.GENERATOR_VERSION,
        }

        wrong_frontmatter = copy.deepcopy(self.frontmatter)
        wrong_frontmatter["name"] = "unexpected-name"
        errors = self.validator.validate_mapping_json(mapping, wrong_frontmatter)
        self.assertTrue(any("Frontmatter name must match" in err for err in errors))

    def test_validate_mapping_json_requires_provenance_for_v1(self):
        mapping = {
            "schemaVersion": self.mapper.SCHEMA_VERSION,
            "skillName": self.skill_name,
            "knowledgeItemId": self.knowledge_item["knowledgeItemId"],
            "taskId": self.knowledge_item["taskId"],
            "sessionId": self.knowledge_item["sessionId"],
            "source": {
                "knowledgeItemPath": "core/knowledge/examples/knowledge-item.sample.json",
                "llmOutputPath": "scripts/llm/examples/knowledge-parse-output.sample.json",
            },
            "mappedOutput": self.normalized,
            "llmOutputAccepted": True,
            "createdAt": self.created_at,
            "generatorVersion": self.mapper.GENERATOR_VERSION,
        }

        errors = self.validator.validate_mapping_json(mapping, self.frontmatter)
        self.assertTrue(any("provenance" in err for err in errors))

    def test_parse_frontmatter_rejects_missing_closing_delimiter(self):
        markdown = "---\nname: a\ndescription: b\n"
        _, _, errors = self.validator.parse_frontmatter(markdown)
        self.assertTrue(any("closing delimiter" in err for err in errors))


if __name__ == "__main__":
    unittest.main()
