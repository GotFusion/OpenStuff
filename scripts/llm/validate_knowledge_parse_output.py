#!/usr/bin/env python3
"""
Validate LLM parse output for TODO 3.1.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


TOP_LEVEL_KEYS = {
    "schemaVersion",
    "knowledgeItemId",
    "taskId",
    "sessionId",
    "objective",
    "context",
    "executionPlan",
    "safetyNotes",
    "confidence",
}
CONTEXT_KEYS = {"appName", "appBundleId", "windowTitle"}
PLAN_KEYS = {
    "requiresTeacherConfirmation",
    "steps",
    "completionCriteria",
    "failurePolicy",
}
STEP_KEYS = {"stepId", "actionType", "instruction", "target", "sourceEventIds"}
COMPLETION_KEYS = {"expectedStepCount", "requiredFrontmostAppBundleId"}
FAILURE_KEYS = {"onContextMismatch", "onStepError", "onUnknownAction"}
ACTION_TYPES = {"openApp", "click", "input", "shortcut", "wait", "unknown"}


def is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def load_text(path: Path) -> str:
    with path.open("r", encoding="utf-8") as f:
        return f.read()


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def extract_json_from_text(text: str) -> Any:
    stripped = text.strip()

    try:
        return json.loads(stripped)
    except json.JSONDecodeError:
        pass

    fenced = re.search(r"```(?:json)?\s*(\{[\s\S]*?\})\s*```", text, flags=re.IGNORECASE)
    if fenced:
        return json.loads(fenced.group(1))

    candidate = extract_first_balanced_object(text)
    if candidate is None:
        raise ValueError("Cannot find JSON object in input text.")
    return json.loads(candidate)


def extract_first_balanced_object(text: str) -> str | None:
    starts = [i for i, ch in enumerate(text) if ch == "{"]
    for start in starts:
        depth = 0
        in_string = False
        escaping = False
        for idx in range(start, len(text)):
            ch = text[idx]
            if in_string:
                if escaping:
                    escaping = False
                elif ch == "\\":
                    escaping = True
                elif ch == '"':
                    in_string = False
                continue

            if ch == '"':
                in_string = True
                continue
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    return text[start : idx + 1]
    return None


def require_exact_keys(obj: Any, keys: set[str], path: str, errors: list[str]) -> None:
    if not isinstance(obj, dict):
        errors.append(f"{path} must be an object.")
        return
    current = set(obj.keys())
    missing = sorted(keys - current)
    extra = sorted(current - keys)
    if missing:
        errors.append(f"{path} missing keys: {', '.join(missing)}")
    if extra:
        errors.append(f"{path} has extra keys: {', '.join(extra)}")


def validate_output(data: Any) -> list[str]:
    errors: list[str] = []

    require_exact_keys(data, TOP_LEVEL_KEYS, "$", errors)
    if not isinstance(data, dict):
        return errors

    schema_version = data.get("schemaVersion")
    if schema_version != "llm.knowledge-parse.v0":
        errors.append("$.schemaVersion must equal 'llm.knowledge-parse.v0'.")

    if not isinstance(data.get("knowledgeItemId"), str) or not data["knowledgeItemId"]:
        errors.append("$.knowledgeItemId must be a non-empty string.")

    task_id = data.get("taskId")
    if not isinstance(task_id, str) or not re.fullmatch(r"task-[a-z0-9-]+-[0-9]{3}", task_id):
        errors.append("$.taskId format is invalid.")

    session_id = data.get("sessionId")
    if not isinstance(session_id, str) or not re.fullmatch(r"[a-z0-9-]+", session_id):
        errors.append("$.sessionId format is invalid.")

    if not isinstance(data.get("objective"), str) or not data["objective"].strip():
        errors.append("$.objective must be a non-empty string.")

    context = data.get("context")
    require_exact_keys(context, CONTEXT_KEYS, "$.context", errors)
    if isinstance(context, dict):
        if not isinstance(context.get("appName"), str) or not context["appName"].strip():
            errors.append("$.context.appName must be a non-empty string.")
        if not isinstance(context.get("appBundleId"), str) or not context["appBundleId"].strip():
            errors.append("$.context.appBundleId must be a non-empty string.")
        if context.get("windowTitle") is not None and not isinstance(
            context.get("windowTitle"), str
        ):
            errors.append("$.context.windowTitle must be string or null.")

    plan = data.get("executionPlan")
    require_exact_keys(plan, PLAN_KEYS, "$.executionPlan", errors)
    steps: list[dict[str, Any]] = []
    if isinstance(plan, dict):
        if not isinstance(plan.get("requiresTeacherConfirmation"), bool):
            errors.append("$.executionPlan.requiresTeacherConfirmation must be boolean.")

        raw_steps = plan.get("steps")
        if not isinstance(raw_steps, list) or len(raw_steps) == 0:
            errors.append("$.executionPlan.steps must be a non-empty array.")
        else:
            for idx, step in enumerate(raw_steps):
                step_path = f"$.executionPlan.steps[{idx}]"
                require_exact_keys(step, STEP_KEYS, step_path, errors)
                if not isinstance(step, dict):
                    continue

                step_id = step.get("stepId")
                if not isinstance(step_id, str) or not re.fullmatch(r"step-[0-9]{3}", step_id):
                    errors.append(f"{step_path}.stepId format is invalid.")

                action_type = step.get("actionType")
                if action_type not in ACTION_TYPES:
                    errors.append(
                        f"{step_path}.actionType must be one of: {', '.join(sorted(ACTION_TYPES))}."
                    )

                instruction = step.get("instruction")
                if not isinstance(instruction, str) or not instruction.strip():
                    errors.append(f"{step_path}.instruction must be a non-empty string.")

                target = step.get("target")
                if not isinstance(target, str) or not target.strip():
                    errors.append(f"{step_path}.target must be a non-empty string.")

                source_event_ids = step.get("sourceEventIds")
                if not isinstance(source_event_ids, list) or len(source_event_ids) == 0:
                    errors.append(f"{step_path}.sourceEventIds must be a non-empty array.")
                else:
                    for event_idx, event_id in enumerate(source_event_ids):
                        if not isinstance(event_id, str) or not event_id.strip():
                            errors.append(
                                f"{step_path}.sourceEventIds[{event_idx}] must be a non-empty string."
                            )
                steps.append(step)

        completion = plan.get("completionCriteria")
        require_exact_keys(completion, COMPLETION_KEYS, "$.executionPlan.completionCriteria", errors)
        if isinstance(completion, dict):
            expected_step_count = completion.get("expectedStepCount")
            if not isinstance(expected_step_count, int) or expected_step_count < 1:
                errors.append("$.executionPlan.completionCriteria.expectedStepCount must be >= 1.")
            elif isinstance(raw_steps, list) and len(raw_steps) > 0 and expected_step_count != len(
                raw_steps
            ):
                errors.append(
                    "$.executionPlan.completionCriteria.expectedStepCount must equal steps length."
                )

            required_bundle = completion.get("requiredFrontmostAppBundleId")
            if not isinstance(required_bundle, str) or not required_bundle.strip():
                errors.append(
                    "$.executionPlan.completionCriteria.requiredFrontmostAppBundleId must be non-empty string."
                )

        failure_policy = plan.get("failurePolicy")
        require_exact_keys(failure_policy, FAILURE_KEYS, "$.executionPlan.failurePolicy", errors)
        if isinstance(failure_policy, dict):
            for field in sorted(FAILURE_KEYS):
                if failure_policy.get(field) != "stopAndAskTeacher":
                    errors.append(
                        f"$.executionPlan.failurePolicy.{field} must equal 'stopAndAskTeacher'."
                    )

    safety_notes = data.get("safetyNotes")
    if not isinstance(safety_notes, list) or len(safety_notes) == 0:
        errors.append("$.safetyNotes must be a non-empty array.")
    else:
        for idx, note in enumerate(safety_notes):
            if not isinstance(note, str) or not note.strip():
                errors.append(f"$.safetyNotes[{idx}] must be a non-empty string.")

    confidence = data.get("confidence")
    if not is_number(confidence) or confidence < 0 or confidence > 1:
        errors.append("$.confidence must be a number in [0, 1].")

    return errors


def validate_with_knowledge_item(data: dict[str, Any], knowledge_item: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(knowledge_item, dict):
        return ["KnowledgeItem must be a JSON object."]

    if data.get("knowledgeItemId") != knowledge_item.get("knowledgeItemId"):
        errors.append("knowledgeItemId mismatch with input KnowledgeItem.")
    if data.get("taskId") != knowledge_item.get("taskId"):
        errors.append("taskId mismatch with input KnowledgeItem.")
    if data.get("sessionId") != knowledge_item.get("sessionId"):
        errors.append("sessionId mismatch with input KnowledgeItem.")
    if data.get("objective") != knowledge_item.get("goal"):
        errors.append("objective must equal KnowledgeItem.goal for deterministic output.")

    context = data.get("context", {})
    source_context = knowledge_item.get("context", {})
    if context.get("appName") != source_context.get("appName"):
        errors.append("context.appName mismatch with KnowledgeItem.context.appName.")
    if context.get("appBundleId") != source_context.get("appBundleId"):
        errors.append("context.appBundleId mismatch with KnowledgeItem.context.appBundleId.")
    if context.get("windowTitle") != source_context.get("windowTitle"):
        errors.append("context.windowTitle mismatch with KnowledgeItem.context.windowTitle.")

    source_steps = knowledge_item.get("steps", [])
    output_steps = data.get("executionPlan", {}).get("steps", [])
    if len(source_steps) != len(output_steps):
        errors.append("steps length mismatch with KnowledgeItem.steps.")
    else:
        for idx, source_step in enumerate(source_steps):
            out_step = output_steps[idx]
            if out_step.get("stepId") != source_step.get("stepId"):
                errors.append(f"steps[{idx}].stepId mismatch with KnowledgeItem.")
            if out_step.get("instruction") != source_step.get("instruction"):
                errors.append(f"steps[{idx}].instruction mismatch with KnowledgeItem.")
            if out_step.get("sourceEventIds") != source_step.get("sourceEventIds"):
                errors.append(f"steps[{idx}].sourceEventIds mismatch with KnowledgeItem.")

    source_notes = [
        c.get("description")
        for c in knowledge_item.get("constraints", [])
        if isinstance(c, dict)
    ]
    if data.get("safetyNotes") != source_notes:
        errors.append("safetyNotes must equal KnowledgeItem.constraints[].description in order.")

    source_has_manual_confirm = any(
        isinstance(c, dict) and c.get("type") == "manualConfirmationRequired"
        for c in knowledge_item.get("constraints", [])
    )
    output_requires_confirm = data.get("executionPlan", {}).get("requiresTeacherConfirmation")
    if output_requires_confirm != source_has_manual_confirm:
        errors.append(
            "executionPlan.requiresTeacherConfirmation mismatch with constraint manualConfirmationRequired."
        )

    completion = data.get("executionPlan", {}).get("completionCriteria", {})
    if completion.get("requiredFrontmostAppBundleId") != source_context.get("appBundleId"):
        errors.append(
            "completionCriteria.requiredFrontmostAppBundleId must equal KnowledgeItem.context.appBundleId."
        )
    if completion.get("expectedStepCount") != len(source_steps):
        errors.append(
            "completionCriteria.expectedStepCount must equal KnowledgeItem.steps length."
        )

    return errors


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate LLM structured parse output JSON."
    )
    parser.add_argument(
        "--input",
        required=True,
        type=Path,
        help="Path to LLM output file (pure JSON or text containing JSON).",
    )
    parser.add_argument(
        "--knowledge-item",
        type=Path,
        help="Optional: input KnowledgeItem file for deterministic cross-check.",
    )
    parser.add_argument(
        "--normalized-output",
        type=Path,
        help="Optional: write extracted normalized JSON here if valid.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    raw_text = load_text(args.input)
    try:
        data = extract_json_from_text(raw_text)
    except (ValueError, json.JSONDecodeError) as exc:
        print(f"INVALID: {exc}")
        return 1

    errors = validate_output(data)
    if args.knowledge_item:
        knowledge_item = load_json(args.knowledge_item)
        if isinstance(data, dict):
            errors.extend(validate_with_knowledge_item(data, knowledge_item))
        else:
            errors.append("Output JSON must be an object.")

    if errors:
        print("INVALID:")
        for error in errors:
            print(f"- {error}")
        return 1

    if args.normalized_output:
        args.normalized_output.parent.mkdir(parents=True, exist_ok=True)
        with args.normalized_output.open("w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
            f.write("\n")

    print("VALID: output passed strict checks.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
