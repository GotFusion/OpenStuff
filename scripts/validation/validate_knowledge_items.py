#!/usr/bin/env python3
"""
Validate KnowledgeItem JSON files against OpenStaff knowledge expectations.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

from common import issue, now_iso, parse_datetime, repo_relative


TASK_ID_RE = re.compile(r"^task-[a-z0-9-]+-[0-9]{3}$")
SESSION_ID_RE = re.compile(r"^[a-z0-9-]+$")
STEP_ID_RE = re.compile(r"^step-[0-9]{3}$")
ALLOWED_CONSTRAINT_TYPES = {
    "frontmostAppMustMatch",
    "manualConfirmationRequired",
    "coordinateTargetMayDrift",
}
ALLOWED_LOCATOR_TYPES = {
    "axPath",
    "roleAndTitle",
    "textAnchor",
    "imageAnchor",
    "coordinateFallback",
}
ALLOWED_LOCATOR_SOURCES = {"capture", "inferred", "repaired", "skill-mapper-fallback"}
ALLOWED_BOUNDARY_REASONS = {"idleGap", "contextSwitch", "sessionEnd"}
ALLOWED_TOP_LEVEL_KEYS = {
    "schemaVersion",
    "knowledgeItemId",
    "taskId",
    "sessionId",
    "goal",
    "summary",
    "steps",
    "context",
    "constraints",
    "source",
    "createdAt",
    "generatorVersion",
}
ALLOWED_CONTEXT_KEYS = {"appName", "appBundleId", "windowTitle", "windowId"}
ALLOWED_STEP_KEYS = {"stepId", "instruction", "sourceEventIds", "target"}
ALLOWED_TARGET_KEYS = {"coordinate", "semanticTargets", "preferredLocatorType"}
ALLOWED_BOUNDING_RECT_KEYS = {"x", "y", "width", "height", "coordinateSpace"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate OpenStaff KnowledgeItem JSON files.")
    parser.add_argument("--input", required=True, type=Path, help="Input JSON file or directory.")
    parser.add_argument(
        "--mode",
        choices=["strict", "compat"],
        default="compat",
        help="compat keeps warnings for missing semantic targets in legacy knowledge items.",
    )
    parser.add_argument("--json", action="store_true", help="Emit structured JSON report.")
    parser.add_argument(
        "--max-issues-per-file",
        type=int,
        default=50,
        help="Cap issues retained per file in the report (default: 50).",
    )
    return parser.parse_args()


def add_issue(issues: list[dict[str, Any]], payload: dict[str, Any], max_issues: int) -> None:
    if len(issues) < max_issues:
        issues.append(payload)


def is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def validate_bounding_rect(
    value: Any,
    *,
    path: Path,
    issues: list[dict[str, Any]],
    max_issues: int,
    field_name: str,
) -> None:
    if value is None:
        return
    if not isinstance(value, dict):
        add_issue(
            issues,
            issue("error", "KNO-INVALID-BOUNDING-RECT", f"{field_name} must be an object.", path=path, field=field_name),
            max_issues,
        )
        return

    extra_keys = sorted(set(value.keys()) - ALLOWED_BOUNDING_RECT_KEYS)
    if extra_keys:
        add_issue(
            issues,
            issue(
                "error",
                "KNO-UNKNOWN-BOUNDING-RECT-FIELD",
                f"{field_name} contains unknown keys: {', '.join(extra_keys)}.",
                path=path,
                field=field_name,
            ),
            max_issues,
        )

    for key in ("x", "y", "width", "height"):
        if key not in value or not is_number(value.get(key)):
            add_issue(
                issues,
                issue(
                    "error",
                    "KNO-INVALID-BOUNDING-RECT-FIELD",
                    f"{field_name}.{key} must be a number.",
                    path=path,
                    field=f"{field_name}.{key}",
                ),
                max_issues,
            )
    if value.get("coordinateSpace") != "screen":
        add_issue(
            issues,
            issue(
                "error",
                "KNO-INVALID-COORDINATE-SPACE",
                f"{field_name}.coordinateSpace must be 'screen'.",
                path=path,
                field=f"{field_name}.coordinateSpace",
            ),
            max_issues,
        )


def validate_semantic_target(
    target: Any,
    *,
    path: Path,
    issues: list[dict[str, Any]],
    max_issues: int,
    field_name: str,
) -> None:
    if not isinstance(target, dict):
        add_issue(
            issues,
            issue("error", "KNO-INVALID-SEMANTIC-TARGET", f"{field_name} must be an object.", path=path, field=field_name),
            max_issues,
        )
        return

    locator_type = target.get("locatorType")
    if locator_type not in ALLOWED_LOCATOR_TYPES:
        add_issue(
            issues,
            issue(
                "error",
                "KNO-INVALID-LOCATOR-TYPE",
                f"{field_name}.locatorType must be one of {sorted(ALLOWED_LOCATOR_TYPES)}.",
                path=path,
                field=f"{field_name}.locatorType",
            ),
            max_issues,
        )

    app_bundle_id = target.get("appBundleId")
    if not isinstance(app_bundle_id, str) or not app_bundle_id.strip():
        add_issue(
            issues,
            issue(
                "error",
                "KNO-INVALID-LOCATOR-APP",
                f"{field_name}.appBundleId must be a non-empty string.",
                path=path,
                field=f"{field_name}.appBundleId",
            ),
            max_issues,
        )

    confidence = target.get("confidence")
    if not is_number(confidence) or confidence < 0 or confidence > 1:
        add_issue(
            issues,
            issue(
                "error",
                "KNO-INVALID-LOCATOR-CONFIDENCE",
                f"{field_name}.confidence must be in [0, 1].",
                path=path,
                field=f"{field_name}.confidence",
            ),
            max_issues,
        )

    source = target.get("source")
    if source not in ALLOWED_LOCATOR_SOURCES:
        add_issue(
            issues,
            issue(
                "error",
                "KNO-INVALID-LOCATOR-SOURCE",
                f"{field_name}.source must be one of {sorted(ALLOWED_LOCATOR_SOURCES)}.",
                path=path,
                field=f"{field_name}.source",
            ),
            max_issues,
        )

    validate_bounding_rect(
        target.get("boundingRect"),
        path=path,
        issues=issues,
        max_issues=max_issues,
        field_name=f"{field_name}.boundingRect",
    )


def validate_step_target(
    target: Any,
    *,
    path: Path,
    issues: list[dict[str, Any]],
    max_issues: int,
    field_name: str,
) -> None:
    if not isinstance(target, dict):
        add_issue(
            issues,
            issue("error", "KNO-INVALID-STEP-TARGET", f"{field_name} must be an object.", path=path, field=field_name),
            max_issues,
        )
        return

    extra_keys = sorted(set(target.keys()) - ALLOWED_TARGET_KEYS)
    if extra_keys:
        add_issue(
            issues,
            issue(
                "error",
                "KNO-UNKNOWN-STEP-TARGET-FIELD",
                f"{field_name} contains unknown keys: {', '.join(extra_keys)}.",
                path=path,
                field=field_name,
            ),
            max_issues,
        )

    coordinate = target.get("coordinate")
    if coordinate is not None:
        validate_bounding_rect(
            {
                "x": coordinate.get("x") if isinstance(coordinate, dict) else None,
                "y": coordinate.get("y") if isinstance(coordinate, dict) else None,
                "width": 1,
                "height": 1,
                "coordinateSpace": coordinate.get("coordinateSpace") if isinstance(coordinate, dict) else None,
            }
            if isinstance(coordinate, dict)
            else coordinate,
            path=path,
            issues=issues,
            max_issues=max_issues,
            field_name=f"{field_name}.coordinate",
        )

    semantic_targets = target.get("semanticTargets")
    if not isinstance(semantic_targets, list) or not semantic_targets:
        add_issue(
            issues,
            issue(
                "error",
                "KNO-MISSING-SEMANTIC-TARGETS",
                f"{field_name}.semanticTargets must be a non-empty array.",
                path=path,
                field=f"{field_name}.semanticTargets",
            ),
            max_issues,
        )
    else:
        for index, semantic_target in enumerate(semantic_targets):
            validate_semantic_target(
                semantic_target,
                path=path,
                issues=issues,
                max_issues=max_issues,
                field_name=f"{field_name}.semanticTargets[{index}]",
            )

    preferred_locator_type = target.get("preferredLocatorType")
    if preferred_locator_type is not None and preferred_locator_type not in ALLOWED_LOCATOR_TYPES:
        add_issue(
            issues,
            issue(
                "error",
                "KNO-INVALID-PREFERRED-LOCATOR",
                f"{field_name}.preferredLocatorType must be one of {sorted(ALLOWED_LOCATOR_TYPES)}.",
                path=path,
                field=f"{field_name}.preferredLocatorType",
            ),
            max_issues,
        )


def collect_files(input_path: Path) -> list[Path]:
    if input_path.is_file():
        return [input_path]
    if input_path.is_dir():
        return sorted(path for path in input_path.rglob("*.json") if path.is_file())
    raise FileNotFoundError(f"Input path does not exist: {input_path}")


def validate_payload(path: Path, payload: Any, mode: str, max_issues: int) -> list[dict[str, Any]]:
    issues: list[dict[str, Any]] = []
    if not isinstance(payload, dict):
        add_issue(issues, issue("error", "KNO-INVALID-JSON-TYPE", "KnowledgeItem must be a JSON object.", path=path), max_issues)
        return issues

    extra_keys = sorted(set(payload.keys()) - ALLOWED_TOP_LEVEL_KEYS)
    if extra_keys:
        severity = "error" if mode == "strict" else "warning"
        add_issue(
            issues,
            issue(
                severity,
                "KNO-UNKNOWN-TOP-LEVEL-FIELD",
                f"KnowledgeItem contains unknown keys: {', '.join(extra_keys)}.",
                path=path,
            ),
            max_issues,
        )

    if payload.get("schemaVersion") != "knowledge.item.v0":
        add_issue(issues, issue("error", "KNO-INVALID-SCHEMA-VERSION", "schemaVersion must be knowledge.item.v0.", path=path, field="schemaVersion"), max_issues)

    for key in ("knowledgeItemId", "goal", "summary", "generatorVersion"):
        candidate = payload.get(key)
        if not isinstance(candidate, str) or not candidate.strip():
            add_issue(
                issues,
                issue(
                    "error",
                    "KNO-INVALID-STRING-FIELD",
                    f"{key} must be a non-empty string.",
                    path=path,
                    field=key,
                ),
                max_issues,
            )

    task_id = payload.get("taskId")
    if not isinstance(task_id, str) or not TASK_ID_RE.fullmatch(task_id):
        add_issue(issues, issue("error", "KNO-INVALID-TASK-ID", "taskId must match ^task-[a-z0-9-]+-[0-9]{3}$.", path=path, field="taskId"), max_issues)

    session_id = payload.get("sessionId")
    if not isinstance(session_id, str) or not SESSION_ID_RE.fullmatch(session_id):
        add_issue(issues, issue("error", "KNO-INVALID-SESSION-ID", "sessionId must match ^[a-z0-9-]+$.", path=path, field="sessionId"), max_issues)

    if not parse_datetime(payload.get("createdAt")):
        add_issue(issues, issue("error", "KNO-INVALID-CREATED-AT", "createdAt must be an ISO 8601 date-time string.", path=path, field="createdAt"), max_issues)

    context = payload.get("context")
    if not isinstance(context, dict):
        add_issue(issues, issue("error", "KNO-MISSING-CONTEXT", "context must be an object.", path=path, field="context"), max_issues)
    else:
        extra_keys = sorted(set(context.keys()) - ALLOWED_CONTEXT_KEYS)
        if extra_keys:
            severity = "error" if mode == "strict" else "warning"
            add_issue(
                issues,
                issue(
                    severity,
                    "KNO-UNKNOWN-CONTEXT-FIELD",
                    f"context contains unknown keys: {', '.join(extra_keys)}.",
                    path=path,
                    field="context",
                ),
                max_issues,
            )
        for key in ("appName", "appBundleId"):
            candidate = context.get(key)
            if not isinstance(candidate, str) or not candidate.strip():
                add_issue(
                    issues,
                    issue(
                        "error",
                        "KNO-INVALID-CONTEXT-FIELD",
                        f"context.{key} must be a non-empty string.",
                        path=path,
                        field=f"context.{key}",
                    ),
                    max_issues,
                )

    constraints = payload.get("constraints")
    if not isinstance(constraints, list) or not constraints:
        add_issue(issues, issue("error", "KNO-INVALID-CONSTRAINTS", "constraints must be a non-empty array.", path=path, field="constraints"), max_issues)
    else:
        for index, constraint in enumerate(constraints):
            if not isinstance(constraint, dict):
                add_issue(
                    issues,
                    issue(
                        "error",
                        "KNO-INVALID-CONSTRAINT",
                        f"constraints[{index}] must be an object.",
                        path=path,
                        field=f"constraints[{index}]",
                    ),
                    max_issues,
                )
                continue
            if constraint.get("type") not in ALLOWED_CONSTRAINT_TYPES:
                add_issue(
                    issues,
                    issue(
                        "error",
                        "KNO-INVALID-CONSTRAINT-TYPE",
                        f"constraints[{index}].type must be one of {sorted(ALLOWED_CONSTRAINT_TYPES)}.",
                        path=path,
                        field=f"constraints[{index}].type",
                    ),
                    max_issues,
                )
            description = constraint.get("description")
            if not isinstance(description, str) or not description.strip():
                add_issue(
                    issues,
                    issue(
                        "error",
                        "KNO-INVALID-CONSTRAINT-DESCRIPTION",
                        f"constraints[{index}].description must be a non-empty string.",
                        path=path,
                        field=f"constraints[{index}].description",
                    ),
                    max_issues,
                )

    source = payload.get("source")
    if not isinstance(source, dict):
        add_issue(issues, issue("error", "KNO-MISSING-SOURCE", "source must be an object.", path=path, field="source"), max_issues)
    else:
        if source.get("taskChunkSchemaVersion") != "knowledge.task-chunk.v0":
            add_issue(
                issues,
                issue(
                    "error",
                    "KNO-INVALID-TASK-CHUNK-SCHEMA",
                    "source.taskChunkSchemaVersion must be knowledge.task-chunk.v0.",
                    path=path,
                    field="source.taskChunkSchemaVersion",
                ),
                max_issues,
            )
        for key in ("startTimestamp", "endTimestamp"):
            if not parse_datetime(source.get(key)):
                add_issue(
                    issues,
                    issue(
                        "error",
                        "KNO-INVALID-SOURCE-TIMESTAMP",
                        f"source.{key} must be an ISO 8601 date-time string.",
                        path=path,
                        field=f"source.{key}",
                    ),
                    max_issues,
                )
        if not isinstance(source.get("eventCount"), int) or source["eventCount"] < 0:
            add_issue(
                issues,
                issue(
                    "error",
                    "KNO-INVALID-SOURCE-EVENT-COUNT",
                    "source.eventCount must be a non-negative integer.",
                    path=path,
                    field="source.eventCount",
                ),
                max_issues,
            )
        if source.get("boundaryReason") not in ALLOWED_BOUNDARY_REASONS:
            add_issue(
                issues,
                issue(
                    "error",
                    "KNO-INVALID-BOUNDARY-REASON",
                    f"source.boundaryReason must be one of {sorted(ALLOWED_BOUNDARY_REASONS)}.",
                    path=path,
                    field="source.boundaryReason",
                ),
                max_issues,
            )

    steps = payload.get("steps")
    if not isinstance(steps, list) or not steps:
        add_issue(issues, issue("error", "KNO-INVALID-STEPS", "steps must be a non-empty array.", path=path, field="steps"), max_issues)
        return issues

    missing_targets = 0
    for index, step in enumerate(steps):
        if not isinstance(step, dict):
            add_issue(
                issues,
                issue(
                    "error",
                    "KNO-INVALID-STEP",
                    f"steps[{index}] must be an object.",
                    path=path,
                    field=f"steps[{index}]",
                ),
                max_issues,
            )
            continue
        extra_keys = sorted(set(step.keys()) - ALLOWED_STEP_KEYS)
        if extra_keys:
            severity = "error" if mode == "strict" else "warning"
            add_issue(
                issues,
                issue(
                    severity,
                    "KNO-UNKNOWN-STEP-FIELD",
                    f"steps[{index}] contains unknown keys: {', '.join(extra_keys)}.",
                    path=path,
                    field=f"steps[{index}]",
                ),
                max_issues,
            )

        step_id = step.get("stepId")
        if not isinstance(step_id, str) or not STEP_ID_RE.fullmatch(step_id):
            add_issue(
                issues,
                issue(
                    "error",
                    "KNO-INVALID-STEP-ID",
                    f"steps[{index}].stepId must match ^step-[0-9]{{3}}$.",
                    path=path,
                    field=f"steps[{index}].stepId",
                ),
                max_issues,
            )
        instruction = step.get("instruction")
        if not isinstance(instruction, str) or not instruction.strip():
            add_issue(
                issues,
                issue(
                    "error",
                    "KNO-INVALID-STEP-INSTRUCTION",
                    f"steps[{index}].instruction must be a non-empty string.",
                    path=path,
                    field=f"steps[{index}].instruction",
                ),
                max_issues,
            )
        source_event_ids = step.get("sourceEventIds")
        if not isinstance(source_event_ids, list) or not source_event_ids:
            add_issue(
                issues,
                issue(
                    "error",
                    "KNO-INVALID-SOURCE-EVENT-IDS",
                    f"steps[{index}].sourceEventIds must be a non-empty array.",
                    path=path,
                    field=f"steps[{index}].sourceEventIds",
                ),
                max_issues,
            )
        else:
            for source_index, source_event_id in enumerate(source_event_ids):
                if not isinstance(source_event_id, str) or not source_event_id.strip():
                    add_issue(
                        issues,
                        issue(
                            "error",
                            "KNO-INVALID-SOURCE-EVENT-ID",
                            f"steps[{index}].sourceEventIds[{source_index}] must be a non-empty string.",
                            path=path,
                            field=f"steps[{index}].sourceEventIds[{source_index}]",
                        ),
                        max_issues,
                    )

        if "target" in step:
            validate_step_target(
                step.get("target"),
                path=path,
                issues=issues,
                max_issues=max_issues,
                field_name=f"steps[{index}].target",
            )
        else:
            missing_targets += 1

    if missing_targets:
        add_issue(
            issues,
            issue(
                "warning",
                "KNO-MISSING-STEP-TARGETS",
                f"{missing_targets} step(s) do not contain target metadata; replay/auto-execution may degrade to instruction-only fallback.",
                path=path,
                field="steps",
            ),
            max_issues,
        )

    return issues


def validate_file(path: Path, mode: str, max_issues: int) -> dict[str, Any]:
    issues: list[dict[str, Any]] = []
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        add_issue(
            issues,
            issue("error", "KNO-JSON-DECODE-FAILED", f"Invalid JSON: {exc}", path=path),
            max_issues,
        )
        return {
            "path": repo_relative(path),
            "errorCount": 1,
            "warningCount": 0,
            "issues": issues,
        }

    for item in validate_payload(path, payload, mode, max_issues):
        add_issue(issues, item, max_issues)

    error_count = sum(1 for entry in issues if entry["severity"] == "error")
    warning_count = sum(1 for entry in issues if entry["severity"] == "warning")
    return {
        "path": repo_relative(path),
        "errorCount": error_count,
        "warningCount": warning_count,
        "issues": issues,
    }


def build_report(input_path: Path, mode: str, max_issues: int) -> dict[str, Any]:
    files = collect_files(input_path)
    reports = [validate_file(path, mode, max_issues) for path in files]
    error_count = sum(file_report["errorCount"] for file_report in reports)
    warning_count = sum(file_report["warningCount"] for file_report in reports)
    passed = error_count == 0
    summary = (
        f"Validated {len(reports)} knowledge file(s), "
        f"errors={error_count}, warnings={warning_count}, mode={mode}."
    )

    return {
        "schemaVersion": "openstaff.knowledge-validation-report.v0",
        "generatedAt": now_iso(),
        "inputPath": repo_relative(input_path.resolve()),
        "mode": mode,
        "passed": passed,
        "fileCount": len(reports),
        "errorCount": error_count,
        "warningCount": warning_count,
        "summary": summary,
        "files": reports,
    }


def print_text_report(report: dict[str, Any]) -> None:
    status = "PASS" if report["passed"] else "FAIL"
    print(f"STATUS: {status}")
    print(f"SUMMARY: {report['summary']}")
    for file_report in report["files"]:
        print(
            f"- {file_report['path']}: errors={file_report['errorCount']} "
            f"warnings={file_report['warningCount']}"
        )
        for item in file_report["issues"][:5]:
            print(f"  [{item['severity']}] {item['code']}: {item['message']}")


def main() -> int:
    args = parse_args()
    report = build_report(args.input.resolve(), args.mode, args.max_issues_per_file)
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print_text_report(report)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
