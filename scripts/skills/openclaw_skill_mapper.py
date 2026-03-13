#!/usr/bin/env python3
"""
Map KnowledgeItem + LLM output to OpenClaw skill folder format.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
LLM_DIR = SCRIPT_DIR.parent / "llm"
if str(LLM_DIR) not in sys.path:
    sys.path.insert(0, str(LLM_DIR))

from validate_knowledge_parse_output import extract_json_from_text, validate_output


SCHEMA_VERSION = "openstaff.openclaw-skill.v1"
GENERATOR_VERSION = "openstaff-skill-mapper-v1"
REPAIR_VERSION = 0
ACTION_TYPES = {"openApp", "click", "input", "shortcut", "wait", "unknown"}


def iso_now() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def read_text(path: Path) -> str:
    with path.open("r", encoding="utf-8") as f:
        return f.read()


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
        f.write("\n")


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        f.write(content.rstrip() + "\n")


def slugify(value: str, fallback: str) -> str:
    normalized = value.strip().lower()
    normalized = re.sub(r"[^a-z0-9_-]+", "-", normalized)
    normalized = re.sub(r"-{2,}", "-", normalized).strip("-")
    if not normalized:
        normalized = fallback
    return normalized[:64]


def sanitize_skill_name(task_id: str, override: str | None = None) -> str:
    base = override if override is not None else f"openstaff-{task_id}"
    return slugify(base, "openstaff-skill")


def infer_action_type(instruction: str) -> str:
    lower = instruction.lower()
    if "快捷键" in instruction or "shortcut" in lower:
        return "shortcut"
    if "输入" in instruction or "type" in lower:
        return "input"
    if "打开" in instruction or "open" in lower:
        return "openApp"
    if "等待" in instruction or "wait" in lower:
        return "wait"
    if "点击" in instruction or "click" in lower:
        return "click"
    return "unknown"


def infer_target(instruction: str, action_type: str, app_name: str) -> str:
    pattern_xy = re.search(r"x\s*=\s*(\d+)\s*[,，]\s*y\s*=\s*(\d+)", instruction, flags=re.IGNORECASE)
    if pattern_xy:
        return f"coordinate:{pattern_xy.group(1)},{pattern_xy.group(2)}"

    pattern_tuple = re.search(r"\((\d+)\s*,\s*(\d+)\)", instruction)
    if pattern_tuple:
        return f"coordinate:{pattern_tuple.group(1)},{pattern_tuple.group(2)}"

    if action_type == "openApp":
        return f"app:{app_name or 'unknown'}"

    return "unknown"


def manual_confirmation_required(constraints: list[dict[str, Any]]) -> bool:
    return any(c.get("type") == "manualConfirmationRequired" for c in constraints)


def normalize_string(value: Any, fallback: str = "unknown") -> str:
    if isinstance(value, str) and value.strip():
        return value.strip()
    if value is None:
        return fallback
    text = str(value).strip()
    return text or fallback


def normalize_string_list(value: Any, fallback: list[str] | None = None) -> list[str]:
    if isinstance(value, list):
        normalized = [str(item).strip() for item in value if str(item).strip()]
        if normalized:
            return normalized
    return list(fallback or ["unknown"])


def normalize_non_negative_int(value: Any, fallback: int = 0) -> int:
    try:
        return max(0, int(value))
    except (TypeError, ValueError):
        return fallback


def validate_knowledge_item(knowledge_item: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(knowledge_item, dict):
        return ["KnowledgeItem must be a JSON object."]

    required = [
        "knowledgeItemId",
        "taskId",
        "sessionId",
        "goal",
        "summary",
        "steps",
        "context",
        "constraints",
    ]
    for key in required:
        if key not in knowledge_item:
            errors.append(f"KnowledgeItem missing required key: {key}")

    steps = knowledge_item.get("steps")
    if not isinstance(steps, list) or len(steps) == 0:
        errors.append("KnowledgeItem.steps must be a non-empty array.")
    else:
        for i, step in enumerate(steps):
            if not isinstance(step, dict):
                errors.append(f"KnowledgeItem.steps[{i}] must be an object.")
                continue
            if not isinstance(step.get("stepId"), str) or not step["stepId"].strip():
                errors.append(f"KnowledgeItem.steps[{i}].stepId must be a non-empty string.")
            if not isinstance(step.get("instruction"), str) or not step["instruction"].strip():
                errors.append(f"KnowledgeItem.steps[{i}].instruction must be a non-empty string.")
            source_event_ids = step.get("sourceEventIds")
            if not isinstance(source_event_ids, list) or len(source_event_ids) == 0:
                errors.append(f"KnowledgeItem.steps[{i}].sourceEventIds must be a non-empty array.")

    context = knowledge_item.get("context")
    if not isinstance(context, dict):
        errors.append("KnowledgeItem.context must be an object.")
    else:
        if not isinstance(context.get("appName"), str) or not context["appName"].strip():
            errors.append("KnowledgeItem.context.appName must be a non-empty string.")
        if not isinstance(context.get("appBundleId"), str) or not context["appBundleId"].strip():
            errors.append("KnowledgeItem.context.appBundleId must be a non-empty string.")

    constraints = knowledge_item.get("constraints")
    if not isinstance(constraints, list) or len(constraints) == 0:
        errors.append("KnowledgeItem.constraints must be a non-empty array.")

    return errors


def looks_like_knowledge_item(payload: Any) -> bool:
    if not isinstance(payload, dict):
        return False
    keys = set(payload.keys())
    required = {"goal", "summary", "constraints", "steps", "context"}
    return required.issubset(keys)


def looks_like_json_schema(payload: Any) -> bool:
    if not isinstance(payload, dict):
        return False
    return "$schema" in payload and "properties" in payload


def parse_llm_output(llm_path: Path) -> tuple[Any | None, list[str]]:
    text = read_text(llm_path)
    diagnostics: list[str] = []
    prompt_package_markers = (
        "【OpenStaff 手动 ChatGPT 转换包】" in text
        and "=== SYSTEM PROMPT ===" in text
        and "=== USER PROMPT ===" in text
    )

    try:
        parsed = extract_json_from_text(text)
    except Exception as exc:
        if prompt_package_markers:
            diagnostics.append(
                "检测到输入包含 OpenStaff 转换包提示词。请粘贴 ChatGPT 最终返回的 JSON，不要粘贴提示词包。"
            )
        diagnostics.append(f"Failed to extract JSON from LLM output: {exc}")
        return None, diagnostics

    if looks_like_knowledge_item(parsed):
        diagnostics.append(
            "检测到输入是 KnowledgeItem/提示词数据，而不是 ChatGPT 返回的结构化 JSON。"
        )
        return parsed, diagnostics

    if looks_like_json_schema(parsed):
        diagnostics.append(
            "检测到输入是 JSON Schema，而不是 ChatGPT 返回的结构化 JSON。"
        )
        return parsed, diagnostics

    errors = validate_output(parsed)
    if errors:
        if prompt_package_markers:
            diagnostics.append(
                "检测到输入包含 OpenStaff 转换包提示词。请确认结果框中仅保留 ChatGPT 输出 JSON。"
            )
        diagnostics.extend([f"LLM output schema validation failed: {error}" for error in errors])
        return parsed, diagnostics

    return parsed, diagnostics


def normalize_execution_plan(
    knowledge_item: dict[str, Any],
    llm_output: dict[str, Any] | None,
    llm_valid: bool,
) -> tuple[dict[str, Any], list[str]]:
    diagnostics: list[str] = []
    context = knowledge_item.get("context", {})
    knowledge_steps = knowledge_item.get("steps", [])
    constraints = knowledge_item.get("constraints", [])

    llm_context = llm_output.get("context", {}) if llm_valid and llm_output else {}
    llm_plan = llm_output.get("executionPlan", {}) if llm_valid and llm_output else {}
    llm_steps = llm_plan.get("steps", []) if isinstance(llm_plan, dict) else []
    llm_steps = llm_steps if isinstance(llm_steps, list) else []

    merged_steps: list[dict[str, Any]] = []
    step_count = max(len(knowledge_steps), len(llm_steps))
    if step_count == 0:
        diagnostics.append("No steps found in either KnowledgeItem or LLM output; created one fallback step.")
        step_count = 1

    llm_fallback_count = 0
    for index in range(step_count):
        knowledge_step = knowledge_steps[index] if index < len(knowledge_steps) and isinstance(knowledge_steps[index], dict) else {}
        llm_step = llm_steps[index] if index < len(llm_steps) and isinstance(llm_steps[index], dict) else {}

        step_id = llm_step.get("stepId")
        if not isinstance(step_id, str) or not re.fullmatch(r"step-[0-9]{3}", step_id):
            step_id = knowledge_step.get("stepId")
            if not isinstance(step_id, str) or not step_id.strip():
                step_id = f"step-{index + 1:03d}"
            llm_fallback_count += 1

        instruction = llm_step.get("instruction")
        if not isinstance(instruction, str) or not instruction.strip():
            instruction = knowledge_step.get("instruction")
            if not isinstance(instruction, str) or not instruction.strip():
                instruction = "unknown"
            llm_fallback_count += 1
        instruction = instruction.strip()

        action_type = llm_step.get("actionType")
        if action_type not in ACTION_TYPES:
            action_type = infer_action_type(instruction)
            llm_fallback_count += 1

        target = llm_step.get("target")
        if not isinstance(target, str) or not target.strip():
            target = infer_target(instruction, action_type, str(context.get("appName", "unknown")))
            llm_fallback_count += 1

        source_event_ids = llm_step.get("sourceEventIds")
        if not isinstance(source_event_ids, list) or len(source_event_ids) == 0:
            source_event_ids = knowledge_step.get("sourceEventIds")
            if not isinstance(source_event_ids, list) or len(source_event_ids) == 0:
                source_event_ids = ["unknown"]
            llm_fallback_count += 1

        merged_steps.append(
            {
                "stepId": step_id,
                "actionType": action_type,
                "instruction": instruction,
                "target": target.strip(),
                "sourceEventIds": [str(v) for v in source_event_ids if str(v).strip()] or ["unknown"],
            }
        )

    if llm_fallback_count > 0:
        diagnostics.append(f"Applied fallback on {llm_fallback_count} step fields while normalizing executionPlan.")

    objective = knowledge_item.get("goal", "unknown")
    if llm_valid and isinstance(llm_output.get("objective"), str) and llm_output["objective"].strip():
        objective = llm_output["objective"].strip()
    else:
        diagnostics.append("Fallback objective from KnowledgeItem.goal.")

    app_name = context.get("appName", "unknown")
    app_bundle_id = context.get("appBundleId", "unknown")
    window_title = context.get("windowTitle")
    if llm_valid:
        if isinstance(llm_context.get("appName"), str) and llm_context["appName"].strip():
            app_name = llm_context["appName"].strip()
        if isinstance(llm_context.get("appBundleId"), str) and llm_context["appBundleId"].strip():
            app_bundle_id = llm_context["appBundleId"].strip()
        if llm_context.get("windowTitle") is None or isinstance(llm_context.get("windowTitle"), str):
            window_title = llm_context.get("windowTitle")

    safety_notes = [
        str(c.get("description", "unknown"))
        for c in constraints
        if isinstance(c, dict) and isinstance(c.get("description"), str) and c.get("description", "").strip()
    ]
    if llm_valid and isinstance(llm_output.get("safetyNotes"), list) and len(llm_output["safetyNotes"]) > 0:
        llm_notes = [str(v).strip() for v in llm_output["safetyNotes"] if str(v).strip()]
        if llm_notes:
            safety_notes = llm_notes
    if not safety_notes:
        safety_notes = ["unknown"]
        diagnostics.append("Fallback safetyNotes to ['unknown'].")

    requires_confirmation = manual_confirmation_required(constraints)
    if llm_valid and isinstance(llm_plan.get("requiresTeacherConfirmation"), bool):
        requires_confirmation = llm_plan["requiresTeacherConfirmation"]

    failure_policy = {
        "onContextMismatch": "stopAndAskTeacher",
        "onStepError": "stopAndAskTeacher",
        "onUnknownAction": "stopAndAskTeacher",
    }
    if llm_valid and isinstance(llm_plan.get("failurePolicy"), dict):
        llm_failure_policy = llm_plan["failurePolicy"]
        if (
            llm_failure_policy.get("onContextMismatch") == "stopAndAskTeacher"
            and llm_failure_policy.get("onStepError") == "stopAndAskTeacher"
            and llm_failure_policy.get("onUnknownAction") == "stopAndAskTeacher"
        ):
            failure_policy = llm_failure_policy

    confidence = 0.72
    if llm_valid and isinstance(llm_output.get("confidence"), (int, float)):
        confidence = float(llm_output["confidence"])
    confidence = max(0.0, min(1.0, round(confidence, 2)))

    normalized = {
        "objective": str(objective) if str(objective).strip() else "unknown",
        "context": {
            "appName": str(app_name) if str(app_name).strip() else "unknown",
            "appBundleId": str(app_bundle_id) if str(app_bundle_id).strip() else "unknown",
            "windowTitle": window_title if window_title is None else str(window_title),
        },
        "executionPlan": {
            "requiresTeacherConfirmation": requires_confirmation,
            "steps": merged_steps,
            "completionCriteria": {
                "expectedStepCount": len(merged_steps),
                "requiredFrontmostAppBundleId": str(app_bundle_id) if str(app_bundle_id).strip() else "unknown",
            },
            "failurePolicy": failure_policy,
        },
        "safetyNotes": safety_notes,
        "confidence": confidence,
    }
    return normalized, diagnostics


def build_provenance(
    skill_name: str,
    knowledge_item: dict[str, Any],
    mapped: dict[str, Any],
    created_at: str,
    llm_output_accepted: bool,
) -> dict[str, Any]:
    knowledge_source = knowledge_item.get("source", {})
    if not isinstance(knowledge_source, dict):
        knowledge_source = {}

    knowledge_steps = knowledge_item.get("steps", [])
    if not isinstance(knowledge_steps, list):
        knowledge_steps = []

    mapped_steps = mapped.get("executionPlan", {}).get("steps", [])
    if not isinstance(mapped_steps, list):
        mapped_steps = []

    step_mappings: list[dict[str, Any]] = []
    for index, mapped_step in enumerate(mapped_steps):
        if not isinstance(mapped_step, dict):
            continue

        knowledge_step = (
            knowledge_steps[index]
            if index < len(knowledge_steps) and isinstance(knowledge_steps[index], dict)
            else {}
        )
        target = knowledge_step.get("target", {})
        if not isinstance(target, dict):
            target = {}

        coordinate = target.get("coordinate")
        if not isinstance(coordinate, dict):
            coordinate = None

        semantic_targets = target.get("semanticTargets")
        if not isinstance(semantic_targets, list):
            semantic_targets = []

        preferred_locator_type = target.get("preferredLocatorType")
        if preferred_locator_type is not None:
            preferred_locator_type = normalize_string(preferred_locator_type)

        skill_step_id = normalize_string(mapped_step.get("stepId"), f"step-{index + 1:03d}")
        step_mappings.append(
            {
                "skillStepId": skill_step_id,
                "knowledgeStepId": normalize_string(knowledge_step.get("stepId"), skill_step_id),
                "instruction": normalize_string(
                    knowledge_step.get("instruction"),
                    normalize_string(mapped_step.get("instruction")),
                ),
                "sourceEventIds": normalize_string_list(mapped_step.get("sourceEventIds")),
                "preferredLocatorType": preferred_locator_type,
                "coordinate": coordinate,
                "semanticTargets": [item for item in semantic_targets if isinstance(item, dict)],
            }
        )

    return {
        "knowledge": {
            "knowledgeItemId": normalize_string(knowledge_item.get("knowledgeItemId")),
            "knowledgeSchemaVersion": normalize_string(knowledge_item.get("schemaVersion"), "knowledge.item.v0"),
            "taskId": normalize_string(knowledge_item.get("taskId")),
            "sessionId": normalize_string(knowledge_item.get("sessionId")),
            "knowledgeCreatedAt": normalize_string(knowledge_item.get("createdAt")),
            "knowledgeGeneratorVersion": normalize_string(
                knowledge_item.get("generatorVersion"),
                "rule-v0",
            ),
        },
        "sourceTrace": {
            "taskChunkSchemaVersion": normalize_string(
                knowledge_source.get("taskChunkSchemaVersion"),
                "knowledge.task-chunk.v0",
            ),
            "startTimestamp": normalize_string(knowledge_source.get("startTimestamp")),
            "endTimestamp": normalize_string(knowledge_source.get("endTimestamp")),
            "eventCount": normalize_non_negative_int(knowledge_source.get("eventCount", 0)),
            "boundaryReason": normalize_string(knowledge_source.get("boundaryReason")),
        },
        "skillBuild": {
            "skillName": skill_name,
            "skillSchemaVersion": SCHEMA_VERSION,
            "skillGeneratorVersion": GENERATOR_VERSION,
            "generatedAt": created_at,
            "repairVersion": REPAIR_VERSION,
            "llmOutputAccepted": llm_output_accepted,
        },
        "stepMappings": step_mappings,
    }


def render_skill_markdown(
    skill_name: str,
    mapped: dict[str, Any],
    knowledge_item: dict[str, Any],
    provenance: dict[str, Any],
) -> str:
    plan = mapped["executionPlan"]
    context = mapped["context"]
    step_mappings = provenance.get("stepMappings", [])
    step_lines: list[str] = []
    for idx, step in enumerate(plan["steps"], start=1):
        source_ids = ", ".join(step["sourceEventIds"])
        provenance_step = (
            step_mappings[idx - 1]
            if idx - 1 < len(step_mappings) and isinstance(step_mappings[idx - 1], dict)
            else {}
        )
        knowledge_step_id = normalize_string(provenance_step.get("knowledgeStepId"), step["stepId"])
        preferred_locator_type = provenance_step.get("preferredLocatorType")
        preferred_locator_text = (
            normalize_string(preferred_locator_type)
            if preferred_locator_type is not None
            else "unknown"
        )
        step_lines.extend(
            [
                f"{idx}. [{step['actionType']}] {step['instruction']}",
                f"   - knowledgeStepId: `{knowledge_step_id}`",
                f"   - target: `{step['target']}`",
                f"   - preferredLocatorType: `{preferred_locator_text}`",
                f"   - sourceEventIds: `{source_ids}`",
            ]
        )

    safety_lines = "\n".join([f"- {note}" for note in mapped["safetyNotes"]])
    summary = str(knowledge_item.get("summary", "")).strip() or "无摘要"
    requires_confirmation = "true" if plan["requiresTeacherConfirmation"] else "false"
    metadata_json = json.dumps(
        {
            "openclaw": {
                "emoji": "🎓",
                "skillKey": skill_name,
                "requires": {"config": ["openstaff.enabled"]},
            },
            "openstaff": {
                "knowledgeItemId": provenance["knowledge"]["knowledgeItemId"],
                "taskId": provenance["knowledge"]["taskId"],
                "sessionId": provenance["knowledge"]["sessionId"],
                "repairVersion": provenance["skillBuild"]["repairVersion"],
            },
        },
        ensure_ascii=False,
        separators=(",", ":"),
    )
    title = mapped["objective"]
    provenance_knowledge = provenance["knowledge"]
    provenance_trace = provenance["sourceTrace"]
    provenance_build = provenance["skillBuild"]

    return f"""---
name: {skill_name}
description: {title}
user-invocable: true
disable-model-invocation: false
metadata: {metadata_json}
---

# {title}

## Context
- appName: `{context['appName']}`
- appBundleId: `{context['appBundleId']}`
- windowTitle: `{context['windowTitle']}`

## Provenance
- sessionId: `{provenance_knowledge['sessionId']}`
- taskId: `{provenance_knowledge['taskId']}`
- knowledgeItemId: `{provenance_knowledge['knowledgeItemId']}`
- sourceTaskChunkSchemaVersion: `{provenance_trace['taskChunkSchemaVersion']}`
- sourceEventCount: `{provenance_trace['eventCount']}`
- knowledgeGeneratorVersion: `{provenance_knowledge['knowledgeGeneratorVersion']}`
- skillGeneratorVersion: `{provenance_build['skillGeneratorVersion']}`
- repairVersion: `{provenance_build['repairVersion']}`

## Teacher Summary
{summary}

## Steps
{os.linesep.join(step_lines)}

## Safety Notes
{safety_lines}

## Failure Policy
- onContextMismatch: `{plan['failurePolicy']['onContextMismatch']}`
- onStepError: `{plan['failurePolicy']['onStepError']}`
- onUnknownAction: `{plan['failurePolicy']['onUnknownAction']}`

## Runtime Requirements
- requiresTeacherConfirmation: `{requires_confirmation}`
- expectedStepCount: `{plan['completionCriteria']['expectedStepCount']}`
- requiredFrontmostAppBundleId: `{plan['completionCriteria']['requiredFrontmostAppBundleId']}`
- confidence: `{mapped['confidence']}`
"""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate OpenClaw skill from KnowledgeItem + LLM output."
    )
    parser.add_argument("--knowledge-item", required=True, type=Path, help="KnowledgeItem JSON path.")
    parser.add_argument(
        "--llm-output",
        required=True,
        type=Path,
        help="LLM output path (JSON or raw text containing JSON).",
    )
    parser.add_argument(
        "--skills-root",
        type=Path,
        default=Path("data/skills/pending"),
        help="Output root for generated skill folders.",
    )
    parser.add_argument("--skill-name", help="Override generated skill name.")
    parser.add_argument("--overwrite", action="store_true", help="Overwrite existing skill folder.")
    parser.add_argument("--report", type=Path, help="Optional output path for mapping report JSON.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    knowledge_item = read_json(args.knowledge_item)
    knowledge_errors = validate_knowledge_item(knowledge_item)
    if knowledge_errors:
        print("INVALID: KnowledgeItem validation failed.", file=sys.stderr)
        for err in knowledge_errors:
            print(f"- {err}", file=sys.stderr)
        return 1

    llm_output_any, llm_diagnostics = parse_llm_output(args.llm_output)
    llm_valid = isinstance(llm_output_any, dict) and len(llm_diagnostics) == 0
    llm_output = llm_output_any if isinstance(llm_output_any, dict) else None

    normalized, normalize_diagnostics = normalize_execution_plan(
        knowledge_item=knowledge_item,
        llm_output=llm_output,
        llm_valid=llm_valid,
    )

    skill_name = sanitize_skill_name(str(knowledge_item.get("taskId", "")), args.skill_name)
    skill_dir = args.skills_root / skill_name
    if skill_dir.exists() and not args.overwrite:
        print(
            f"FAILED: SKL-IO-SKILL-EXISTS skill directory already exists: {skill_dir}",
            file=sys.stderr,
        )
        return 1

    created_at = iso_now()
    provenance = build_provenance(
        skill_name=skill_name,
        knowledge_item=knowledge_item,
        mapped=normalized,
        created_at=created_at,
        llm_output_accepted=llm_valid,
    )
    skill_md = render_skill_markdown(skill_name, normalized, knowledge_item, provenance)
    mapped_payload = {
        "schemaVersion": SCHEMA_VERSION,
        "skillName": skill_name,
        "knowledgeItemId": knowledge_item.get("knowledgeItemId"),
        "taskId": knowledge_item.get("taskId"),
        "sessionId": knowledge_item.get("sessionId"),
        "source": {
            "knowledgeItemPath": str(args.knowledge_item),
            "llmOutputPath": str(args.llm_output),
        },
        "provenance": provenance,
        "mappedOutput": normalized,
        "diagnostics": llm_diagnostics + normalize_diagnostics,
        "llmOutputAccepted": llm_valid,
        "createdAt": created_at,
        "generatorVersion": GENERATOR_VERSION,
    }

    write_text(skill_dir / "SKILL.md", skill_md)
    write_json(skill_dir / "openstaff-skill.json", mapped_payload)

    report_payload = {
        "status": "success",
        "skillDir": str(skill_dir),
        "skillName": skill_name,
        "llmOutputAccepted": llm_valid,
        "diagnostics": mapped_payload["diagnostics"],
    }
    if args.report:
        write_json(args.report, report_payload)

    print(f"SUCCESS: generated OpenClaw skill at {skill_dir}")
    if mapped_payload["diagnostics"]:
        print("DIAGNOSTICS:")
        for line in mapped_payload["diagnostics"]:
            print(f"- {line}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
