#!/usr/bin/env python3
"""
Validate generated OpenClaw skill folder.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


REQUIRED_FRONTMATTER_KEYS = {"name", "description"}
CURRENT_SCHEMA_VERSION = "openstaff.openclaw-skill.v1"
SUPPORTED_SCHEMA_VERSIONS = {"openstaff.openclaw-skill.v0", CURRENT_SCHEMA_VERSION}


def read_text(path: Path) -> str:
    with path.open("r", encoding="utf-8") as f:
        return f.read()


def read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def parse_frontmatter(markdown: str) -> tuple[dict[str, str], str, list[str]]:
    errors: list[str] = []
    lines = markdown.splitlines()
    if len(lines) < 3 or lines[0].strip() != "---":
        return {}, markdown, ["SKILL.md must start with frontmatter delimiter '---'."]

    end_index = -1
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end_index = i
            break
    if end_index == -1:
        return {}, markdown, ["SKILL.md frontmatter missing closing delimiter '---'."]

    body = "\n".join(lines[end_index + 1 :]).strip()
    fm_lines = lines[1:end_index]
    frontmatter: dict[str, str] = {}
    for i, raw in enumerate(fm_lines, start=2):
        if not raw.strip():
            continue
        if ":" not in raw:
            errors.append(f"Frontmatter line {i} must contain ':' key/value separator.")
            continue
        key, value = raw.split(":", 1)
        key = key.strip()
        value = value.strip()
        if not key:
            errors.append(f"Frontmatter line {i} has empty key.")
            continue
        if "\n" in value:
            errors.append(f"Frontmatter key '{key}' must be single-line.")
            continue
        frontmatter[key] = value

    return frontmatter, body, errors


def validate_skill_markdown(markdown: str) -> tuple[dict[str, str], list[str]]:
    frontmatter, body, errors = parse_frontmatter(markdown)
    missing = REQUIRED_FRONTMATTER_KEYS - set(frontmatter.keys())
    for key in sorted(missing):
        errors.append(f"Frontmatter missing required key: {key}")

    name = frontmatter.get("name", "")
    if name and not re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,63}", name):
        errors.append("Frontmatter name must match pattern [a-z0-9][a-z0-9_-]{0,63}.")

    description = frontmatter.get("description", "")
    if description and not description.strip():
        errors.append("Frontmatter description must be non-empty.")

    metadata = frontmatter.get("metadata")
    if metadata:
        try:
            parsed_metadata = json.loads(metadata)
            if not isinstance(parsed_metadata, dict):
                errors.append("Frontmatter metadata must be a JSON object.")
        except json.JSONDecodeError as exc:
            errors.append(f"Frontmatter metadata is not valid single-line JSON: {exc}")

    if not body:
        errors.append("SKILL.md body is empty.")

    if "## Steps" not in body:
        errors.append("SKILL.md body must include a '## Steps' section.")
    if not re.search(r"(?m)^\d+\.\s", body):
        errors.append("SKILL.md body must contain at least one numbered step.")
    if "## Safety Notes" not in body:
        errors.append("SKILL.md body should include a '## Safety Notes' section.")

    return frontmatter, errors


def validate_mapping_json(mapping: Any, frontmatter: dict[str, str]) -> list[str]:
    errors: list[str] = []
    if not isinstance(mapping, dict):
        return ["openstaff-skill.json must be a JSON object."]

    required = [
        "schemaVersion",
        "skillName",
        "knowledgeItemId",
        "taskId",
        "sessionId",
        "source",
        "mappedOutput",
        "llmOutputAccepted",
        "createdAt",
        "generatorVersion",
    ]
    for key in required:
        if key not in mapping:
            errors.append(f"openstaff-skill.json missing required key: {key}")

    schema_version = mapping.get("schemaVersion")
    if schema_version not in SUPPORTED_SCHEMA_VERSIONS:
        errors.append(
            "openstaff-skill.json schemaVersion must be one of "
            f"{', '.join(sorted(SUPPORTED_SCHEMA_VERSIONS))}."
        )

    if "skillName" in mapping and frontmatter.get("name") != mapping.get("skillName"):
        errors.append("Frontmatter name must match openstaff-skill.json skillName.")

    source = mapping.get("source")
    if not isinstance(source, dict):
        errors.append("source must be an object.")
    else:
        for key in ["knowledgeItemPath", "llmOutputPath"]:
            if not isinstance(source.get(key), str) or not source[key].strip():
                errors.append(f"source.{key} must be a non-empty string.")

    if not isinstance(mapping.get("llmOutputAccepted"), bool):
        errors.append("llmOutputAccepted must be a boolean.")

    mapped_output = mapping.get("mappedOutput")
    if not isinstance(mapped_output, dict):
        errors.append("mappedOutput must be an object.")
        return errors

    if not isinstance(mapped_output.get("objective"), str) or not mapped_output["objective"].strip():
        errors.append("mappedOutput.objective must be a non-empty string.")

    context = mapped_output.get("context")
    if not isinstance(context, dict):
        errors.append("mappedOutput.context must be an object.")
    else:
        if not isinstance(context.get("appName"), str) or not context["appName"].strip():
            errors.append("mappedOutput.context.appName must be non-empty string.")
        if not isinstance(context.get("appBundleId"), str) or not context["appBundleId"].strip():
            errors.append("mappedOutput.context.appBundleId must be non-empty string.")

    plan = mapped_output.get("executionPlan")
    if not isinstance(plan, dict):
        errors.append("mappedOutput.executionPlan must be an object.")
    else:
        steps = plan.get("steps")
        if not isinstance(steps, list) or len(steps) == 0:
            errors.append("mappedOutput.executionPlan.steps must be a non-empty array.")
        else:
            for idx, step in enumerate(steps):
                if not isinstance(step, dict):
                    errors.append(f"mappedOutput.executionPlan.steps[{idx}] must be an object.")
                    continue
                for key in ["stepId", "actionType", "instruction", "target", "sourceEventIds"]:
                    if key not in step:
                        errors.append(f"mappedOutput.executionPlan.steps[{idx}] missing key: {key}")
                if isinstance(step.get("sourceEventIds"), list) and len(step["sourceEventIds"]) == 0:
                    errors.append(
                        f"mappedOutput.executionPlan.steps[{idx}].sourceEventIds must not be empty."
                    )
        completion = plan.get("completionCriteria")
        if not isinstance(completion, dict):
            errors.append("mappedOutput.executionPlan.completionCriteria must be an object.")
        else:
            if completion.get("expectedStepCount") != len(plan.get("steps", [])):
                errors.append(
                    "mappedOutput.executionPlan.completionCriteria.expectedStepCount must equal steps length."
                )

    safety_notes = mapped_output.get("safetyNotes")
    if not isinstance(safety_notes, list) or len(safety_notes) == 0:
        errors.append("mappedOutput.safetyNotes must be a non-empty array.")

    confidence = mapped_output.get("confidence")
    if not isinstance(confidence, (int, float)) or confidence < 0 or confidence > 1:
        errors.append("mappedOutput.confidence must be in [0, 1].")

    if schema_version == CURRENT_SCHEMA_VERSION:
        provenance = mapping.get("provenance")
        if not isinstance(provenance, dict):
            errors.append("openstaff-skill.json provenance must be an object for v1 artifacts.")
            return errors

        knowledge = provenance.get("knowledge")
        if not isinstance(knowledge, dict):
            errors.append("provenance.knowledge must be an object.")
        else:
            if knowledge.get("knowledgeItemId") != mapping.get("knowledgeItemId"):
                errors.append("provenance.knowledge.knowledgeItemId must match top-level knowledgeItemId.")
            if knowledge.get("taskId") != mapping.get("taskId"):
                errors.append("provenance.knowledge.taskId must match top-level taskId.")
            if knowledge.get("sessionId") != mapping.get("sessionId"):
                errors.append("provenance.knowledge.sessionId must match top-level sessionId.")
            for key in [
                "knowledgeSchemaVersion",
                "knowledgeCreatedAt",
                "knowledgeGeneratorVersion",
            ]:
                if not isinstance(knowledge.get(key), str) or not knowledge[key].strip():
                    errors.append(f"provenance.knowledge.{key} must be a non-empty string.")

        source_trace = provenance.get("sourceTrace")
        if not isinstance(source_trace, dict):
            errors.append("provenance.sourceTrace must be an object.")
        else:
            for key in ["taskChunkSchemaVersion", "startTimestamp", "endTimestamp", "boundaryReason"]:
                if not isinstance(source_trace.get(key), str) or not source_trace[key].strip():
                    errors.append(f"provenance.sourceTrace.{key} must be a non-empty string.")
            if not isinstance(source_trace.get("eventCount"), int) or source_trace["eventCount"] < 0:
                errors.append("provenance.sourceTrace.eventCount must be a non-negative integer.")

        skill_build = provenance.get("skillBuild")
        if not isinstance(skill_build, dict):
            errors.append("provenance.skillBuild must be an object.")
        else:
            if skill_build.get("skillName") != mapping.get("skillName"):
                errors.append("provenance.skillBuild.skillName must match top-level skillName.")
            if skill_build.get("skillSchemaVersion") != CURRENT_SCHEMA_VERSION:
                errors.append(
                    "provenance.skillBuild.skillSchemaVersion must equal "
                    f"'{CURRENT_SCHEMA_VERSION}'."
                )
            if skill_build.get("skillGeneratorVersion") != mapping.get("generatorVersion"):
                errors.append(
                    "provenance.skillBuild.skillGeneratorVersion must match top-level generatorVersion."
                )
            if skill_build.get("generatedAt") != mapping.get("createdAt"):
                errors.append("provenance.skillBuild.generatedAt must match top-level createdAt.")
            if skill_build.get("llmOutputAccepted") != mapping.get("llmOutputAccepted"):
                errors.append(
                    "provenance.skillBuild.llmOutputAccepted must match top-level llmOutputAccepted."
                )
            repair_version = skill_build.get("repairVersion")
            if not isinstance(repair_version, int) or repair_version < 0:
                errors.append("provenance.skillBuild.repairVersion must be a non-negative integer.")

        step_mappings = provenance.get("stepMappings")
        if not isinstance(step_mappings, list) or len(step_mappings) == 0:
            errors.append("provenance.stepMappings must be a non-empty array.")
        else:
            plan_steps = plan.get("steps", []) if isinstance(plan, dict) else []
            if len(step_mappings) != len(plan_steps):
                errors.append("provenance.stepMappings length must equal executionPlan.steps length.")

            for idx, step_mapping in enumerate(step_mappings):
                if not isinstance(step_mapping, dict):
                    errors.append(f"provenance.stepMappings[{idx}] must be an object.")
                    continue

                for key in ["skillStepId", "knowledgeStepId", "instruction"]:
                    if not isinstance(step_mapping.get(key), str) or not step_mapping[key].strip():
                        errors.append(f"provenance.stepMappings[{idx}].{key} must be a non-empty string.")

                if idx < len(plan_steps) and step_mapping.get("skillStepId") != plan_steps[idx].get("stepId"):
                    errors.append(
                        f"provenance.stepMappings[{idx}].skillStepId must match executionPlan.steps[{idx}].stepId."
                    )

                source_event_ids = step_mapping.get("sourceEventIds")
                if not isinstance(source_event_ids, list) or len(source_event_ids) == 0:
                    errors.append(f"provenance.stepMappings[{idx}].sourceEventIds must be a non-empty array.")
                else:
                    for event_idx, value in enumerate(source_event_ids):
                        if not isinstance(value, str) or not value.strip():
                            errors.append(
                                "provenance.stepMappings"
                                f"[{idx}].sourceEventIds[{event_idx}] must be a non-empty string."
                            )

                preferred_locator_type = step_mapping.get("preferredLocatorType")
                if preferred_locator_type is not None and (
                    not isinstance(preferred_locator_type, str) or not preferred_locator_type.strip()
                ):
                    errors.append(
                        f"provenance.stepMappings[{idx}].preferredLocatorType must be string or null."
                    )

                coordinate = step_mapping.get("coordinate")
                if coordinate is not None:
                    if not isinstance(coordinate, dict):
                        errors.append(f"provenance.stepMappings[{idx}].coordinate must be object or null.")
                    else:
                        for key in ["x", "y", "coordinateSpace"]:
                            if key not in coordinate:
                                errors.append(
                                    f"provenance.stepMappings[{idx}].coordinate missing key: {key}"
                                )

                semantic_targets = step_mapping.get("semanticTargets")
                if not isinstance(semantic_targets, list):
                    errors.append(
                        f"provenance.stepMappings[{idx}].semanticTargets must be an array."
                    )
                else:
                    for target_idx, semantic_target in enumerate(semantic_targets):
                        if not isinstance(semantic_target, dict):
                            errors.append(
                                "provenance.stepMappings"
                                f"[{idx}].semanticTargets[{target_idx}] must be an object."
                            )
                            continue
                        for key in ["locatorType", "confidence", "source"]:
                            if key not in semantic_target:
                                errors.append(
                                    "provenance.stepMappings"
                                    f"[{idx}].semanticTargets[{target_idx}] missing key: {key}"
                                )

    return errors


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate OpenClaw skill output folder.")
    parser.add_argument("--skill-dir", required=True, type=Path, help="Skill directory path.")
    parser.add_argument(
        "--mapping-file",
        default="openstaff-skill.json",
        help="Mapping JSON filename inside skill-dir.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    skill_dir = args.skill_dir

    errors: list[str] = []
    if not skill_dir.exists() or not skill_dir.is_dir():
        print(f"INVALID: skill directory not found: {skill_dir}", file=sys.stderr)
        return 1

    skill_md_path = skill_dir / "SKILL.md"
    if not skill_md_path.exists():
        print(f"INVALID: missing SKILL.md in {skill_dir}", file=sys.stderr)
        return 1

    markdown = read_text(skill_md_path)
    frontmatter, md_errors = validate_skill_markdown(markdown)
    errors.extend(md_errors)

    mapping_path = skill_dir / args.mapping_file
    if not mapping_path.exists():
        errors.append(f"Missing mapping file: {mapping_path.name}")
    else:
        try:
            mapping = read_json(mapping_path)
            errors.extend(validate_mapping_json(mapping, frontmatter))
        except json.JSONDecodeError as exc:
            errors.append(f"{mapping_path.name} is not valid JSON: {exc}")

    if errors:
        print("INVALID:")
        for err in errors:
            print(f"- {err}")
        return 1

    print(f"VALID: {skill_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
