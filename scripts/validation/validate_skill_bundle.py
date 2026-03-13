#!/usr/bin/env python3
"""
Static skill preflight validator for OpenStaff/OpenClaw bundles.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
SKILL_VALIDATOR_PATH = REPO_ROOT / "scripts/skills/validate_openclaw_skill.py"
SUPPORTED_SCHEMA_VERSIONS = {
    "openstaff.openclaw-skill.v0",
    "openstaff.openclaw-skill.v1",
}
EXECUTABLE_ACTION_TYPES = {"click", "shortcut", "input", "openApp", "wait"}
LOW_CONFIDENCE_THRESHOLD = 0.80
HIGH_RISK_KEYWORDS = [
    "删除",
    "移除",
    "支付",
    "转账",
    "系统设置",
    "格式化",
    "抹掉",
    "重置",
    "sudo",
    "rm -rf",
]
HIGH_RISK_REGEX_PATTERNS = [
    r"(?i)\brm\s+-rf\b",
    r"(?i)\bsudo\s+",
    r"(?i)\bshutdown\b|\breboot\b",
    r"(?i)\bdd\s+if=",
]


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec is not None and spec.loader is not None
    spec.loader.exec_module(module)
    return module


SKILL_VALIDATOR = load_module("validate_openclaw_skill", SKILL_VALIDATOR_PATH)


def normalize(value: Any, fallback: str = "") -> str:
    text = str(value).strip() if value is not None else ""
    return text or fallback


def issue(severity: str, code: str, message: str, step_id: str | None = None) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "severity": severity,
        "code": code,
        "message": message,
    }
    if step_id:
        payload["stepId"] = step_id
    return payload


def semantic_target_valid(target: dict[str, Any]) -> bool:
    locator_type = normalize(target.get("locatorType"))
    if locator_type == "axPath":
        return bool(normalize(target.get("axPath")))
    if locator_type == "roleAndTitle":
        return any(
            normalize(target.get(key))
            for key in ("elementRole", "elementTitle", "elementIdentifier")
        )
    if locator_type == "textAnchor":
        return bool(normalize(target.get("textAnchor")) or normalize(target.get("elementTitle")))
    if locator_type == "imageAnchor":
        return isinstance(target.get("imageAnchor"), dict) and isinstance(target.get("boundingRect"), dict)
    if locator_type == "coordinateFallback":
        return isinstance(target.get("boundingRect"), dict)
    return False


def parse_bundle_target(target: str) -> str | None:
    normalized_target = normalize(target)
    if not normalized_target.startswith("bundle:"):
        return None
    bundle_id = normalized_target[len("bundle:") :].strip()
    return bundle_id or None


def parse_coordinate_target(target: str) -> tuple[float, float] | None:
    normalized_target = normalize(target)
    if not normalized_target.startswith("coordinate:"):
        return None
    raw = normalized_target[len("coordinate:") :]
    parts = [part.strip() for part in raw.split(",")]
    if len(parts) != 2:
        return None
    try:
        return float(parts[0]), float(parts[1])
    except ValueError:
        return None


def derived_allowed_app_bundle_ids(mapping: dict[str, Any], extra_allowed: list[str]) -> list[str]:
    context_bundle_id = normalize(mapping.get("mappedOutput", {}).get("context", {}).get("appBundleId"))
    frontmost_bundle_id = normalize(
        mapping.get("mappedOutput", {})
        .get("executionPlan", {})
        .get("completionCriteria", {})
        .get("requiredFrontmostAppBundleId")
    )
    values = [context_bundle_id, frontmost_bundle_id, *extra_allowed]
    ordered: list[str] = []
    seen: set[str] = set()
    for value in values:
        if not value or value == "unknown":
            continue
        if value not in seen:
            seen.add(value)
            ordered.append(value)
    return ordered


def derived_step_confidence(step_mapping: dict[str, Any] | None, fallback: float) -> float:
    if step_mapping:
        semantic_targets = step_mapping.get("semanticTargets", [])
        if isinstance(semantic_targets, list) and semantic_targets:
            candidates = [
                float(target.get("confidence"))
                for target in semantic_targets
                if isinstance(target, dict) and isinstance(target.get("confidence"), (int, float))
            ]
            if candidates:
                return max(0.0, min(1.0, max(candidates)))
    return max(0.0, min(1.0, fallback))


def step_target_app_bundle_ids(
    step: dict[str, Any],
    step_mapping: dict[str, Any] | None,
    fallback_context_app_bundle_id: str,
) -> list[str]:
    values: list[str] = []
    target_bundle_id = parse_bundle_target(normalize(step.get("target")))
    if target_bundle_id:
        values.append(target_bundle_id)

    if step_mapping:
        for semantic_target in step_mapping.get("semanticTargets", []):
            if isinstance(semantic_target, dict):
                app_bundle_id = normalize(semantic_target.get("appBundleId"))
                if app_bundle_id:
                    values.append(app_bundle_id)

    if not values and fallback_context_app_bundle_id and fallback_context_app_bundle_id != "unknown":
        values.append(fallback_context_app_bundle_id)

    ordered: list[str] = []
    seen: set[str] = set()
    for value in values:
        if not value or value == "unknown":
            continue
        if value not in seen:
            seen.add(value)
            ordered.append(value)
    return ordered


def is_high_risk_step(step: dict[str, Any], target_app_bundle_ids: list[str]) -> bool:
    action_type = normalize(step.get("actionType"))
    joined = f"{normalize(step.get('instruction'))}\n{normalize(step.get('target'))}"

    if "com.apple.Terminal" in target_app_bundle_ids and action_type == "input":
        return True
    if action_type == "openApp":
        bundle_id = parse_bundle_target(normalize(step.get("target")))
        if bundle_id and "systemsettings" in bundle_id.lower():
            return True

    if any(keyword.lower() in joined.lower() for keyword in HIGH_RISK_KEYWORDS if keyword):
        return True
    return any(re.search(pattern, joined) for pattern in HIGH_RISK_REGEX_PATTERNS)


def validate_locator(step: dict[str, Any], step_mapping: dict[str, Any] | None, step_id: str) -> tuple[str, list[dict[str, Any]]]:
    if normalize(step.get("actionType")) != "click":
        return "not_required", []

    if step_mapping is None:
        if parse_coordinate_target(normalize(step.get("target"))) is not None:
            return "degraded", [
                issue("warning", "SPF-COORDINATE-ONLY-FALLBACK", f"步骤 {step_id} 仅能依赖 target 中的旧坐标回退，需要老师确认。", step_id),
            ]
        return "missing", [
            issue("error", "SPF-MISSING-STEP-MAPPING", f"步骤 {step_id} 缺少 provenance.stepMappings，无法做 locator 预检。", step_id),
            issue("error", "SPF-MISSING-LOCATOR", f"步骤 {step_id} 不存在可解析 locator。", step_id),
        ]

    semantic_targets = step_mapping.get("semanticTargets", [])
    valid_targets = [
        target
        for target in semantic_targets
        if isinstance(target, dict) and semantic_target_valid(target)
    ]
    if len(valid_targets) != len(semantic_targets):
        severity = "error" if not valid_targets and not isinstance(step_mapping.get("coordinate"), dict) else "warning"
        return ("missing" if severity == "error" else "degraded"), [
            issue(severity, "SPF-INVALID-LOCATOR", f"步骤 {step_id} 的 semanticTargets 存在不可解析 locator。", step_id)
        ]

    if any(normalize(target.get("locatorType")) != "coordinateFallback" for target in valid_targets):
        return "resolved", []

    if isinstance(step_mapping.get("coordinate"), dict) or any(
        normalize(target.get("locatorType")) == "coordinateFallback" for target in valid_targets
    ):
        return "degraded", [
            issue("warning", "SPF-COORDINATE-ONLY-FALLBACK", f"步骤 {step_id} 仅剩 coordinateFallback，不能直接自动执行。", step_id)
        ]

    return "missing", [
        issue("error", "SPF-MISSING-LOCATOR", f"步骤 {step_id} 不存在可解析 locator。", step_id)
    ]


def validate_structure(skill_dir: Path, mapping: dict[str, Any]) -> list[dict[str, Any]]:
    issues: list[dict[str, Any]] = []
    skill_md_path = skill_dir / "SKILL.md"
    if skill_md_path.exists():
        markdown = SKILL_VALIDATOR.read_text(skill_md_path)
        frontmatter, md_errors = SKILL_VALIDATOR.validate_skill_markdown(markdown)
        for error in md_errors:
            issues.append(issue("error", "SPF-SKILL-MARKDOWN-INVALID", error))
        for error in SKILL_VALIDATOR.validate_mapping_json(mapping, frontmatter):
            issues.append(issue("error", "SPF-SKILL-MAPPING-INVALID", error))
    else:
        issues.append(issue("error", "SPF-SKILL-MARKDOWN-MISSING", f"缺少 {skill_md_path.name}"))
    return issues


def build_report(skill_dir: Path, extra_allowed: list[str]) -> dict[str, Any]:
    mapping_path = skill_dir / "openstaff-skill.json"
    if not mapping_path.exists():
        issues = [issue("error", "SPF-SKILL-BUNDLE-UNREADABLE", f"未找到技能文件：{mapping_path}")]
        return {
            "schemaVersion": "openstaff.skill-preflight-report.v0",
            "skillName": skill_dir.name,
            "skillDirectoryPath": str(skill_dir),
            "status": "failed",
            "summary": issues[0]["message"],
            "requiresTeacherConfirmation": False,
            "isAutoRunnable": False,
            "allowedAppBundleIds": [],
            "issues": issues,
            "steps": [],
        }

    try:
        mapping = json.loads(mapping_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        message = f"解析技能文件失败：{mapping_path} ({exc})"
        issues = [issue("error", "SPF-SKILL-BUNDLE-DECODE-FAILED", message)]
        return {
            "schemaVersion": "openstaff.skill-preflight-report.v0",
            "skillName": skill_dir.name,
            "skillDirectoryPath": str(skill_dir),
            "status": "failed",
            "summary": message,
            "requiresTeacherConfirmation": False,
            "isAutoRunnable": False,
            "allowedAppBundleIds": [],
            "issues": issues,
            "steps": [],
        }

    skill_name = normalize(mapping.get("skillName"), skill_dir.name)
    issues = validate_structure(skill_dir, mapping)
    steps: list[dict[str, Any]] = []

    if normalize(mapping.get("schemaVersion")) not in SUPPORTED_SCHEMA_VERSIONS:
        issues.append(
            issue("error", "SPF-UNSUPPORTED-SCHEMA-VERSION", f"skill schemaVersion={mapping.get('schemaVersion')} 不受支持。")
        )

    mapped_output = mapping.get("mappedOutput", {})
    execution_plan = mapped_output.get("executionPlan", {})
    plan_steps = execution_plan.get("steps", [])
    expected_step_count = execution_plan.get("completionCriteria", {}).get("expectedStepCount")
    context_app_bundle_id = normalize(mapped_output.get("context", {}).get("appBundleId"))
    allowed_app_bundle_ids = derived_allowed_app_bundle_ids(mapping, extra_allowed)

    if not context_app_bundle_id or context_app_bundle_id == "unknown":
        issues.append(issue("error", "SPF-MISSING-CONTEXT-APP", "skill 未声明有效的目标应用 bundleId。"))
    if not allowed_app_bundle_ids:
        issues.append(issue("error", "SPF-EMPTY-APP-ALLOWLIST", "skill 无法导出目标 App 白名单，已阻止执行。"))
    if not isinstance(plan_steps, list) or not plan_steps:
        issues.append(issue("error", "SPF-EMPTY-EXECUTION-PLAN", "skill 不包含可执行步骤。"))
        plan_steps = []
    if expected_step_count != len(plan_steps):
        issues.append(issue("error", "SPF-EXPECTED-STEP-COUNT-MISMATCH", "completionCriteria.expectedStepCount 与 steps 数量不一致。"))

    requires_teacher_confirmation = bool(execution_plan.get("requiresTeacherConfirmation"))
    if requires_teacher_confirmation:
        issues.append(
            issue("warning", "SPF-MANUAL-CONFIRMATION-REQUIRED", "skill 标记为 requiresTeacherConfirmation=true，不能直接自动执行。")
        )

    provenance = mapping.get("provenance", {})
    ordered_step_mappings = provenance.get("stepMappings", []) if isinstance(provenance, dict) else []
    step_mapping_by_id = {
        normalize(step_mapping.get("skillStepId")): step_mapping
        for step_mapping in ordered_step_mappings
        if isinstance(step_mapping, dict)
    }

    fallback_confidence = float(mapped_output.get("confidence", 0.0)) if isinstance(mapped_output.get("confidence"), (int, float)) else 0.0

    for index, step in enumerate(plan_steps):
        if not isinstance(step, dict):
            issues.append(issue("error", "SPF-INVALID-STEP", f"executionPlan.steps[{index}] 必须是对象。"))
            continue

        step_id = normalize(step.get("stepId"), f"step-{index + 1:03d}")
        step_issues: list[dict[str, Any]] = []
        action_type = normalize(step.get("actionType"))
        if action_type not in EXECUTABLE_ACTION_TYPES:
            step_issues.append(issue("error", "SPF-UNKNOWN-ACTION-TYPE", f"步骤 {step_id} 的 actionType={action_type} 不可执行。", step_id))

        source_event_ids = [normalize(value) for value in step.get("sourceEventIds", []) if normalize(value) and normalize(value) != "unknown"]
        if not source_event_ids:
            step_issues.append(issue("error", "SPF-MISSING-SOURCE-EVENT-IDS", f"步骤 {step_id} 缺少有效的 sourceEventIds。", step_id))

        step_mapping = step_mapping_by_id.get(step_id)
        if step_mapping is None and index < len(ordered_step_mappings):
            maybe_step_mapping = ordered_step_mappings[index]
            if isinstance(maybe_step_mapping, dict):
                step_mapping = maybe_step_mapping

        target_app_bundle_ids = step_target_app_bundle_ids(step, step_mapping, context_app_bundle_id)
        for bundle_id in target_app_bundle_ids:
            if bundle_id not in allowed_app_bundle_ids:
                step_issues.append(
                    issue(
                        "error",
                        "SPF-TARGET-APP-NOT-ALLOWED",
                        f"步骤 {step_id} 命中了非白名单应用 {bundle_id}。允许列表：{', '.join(allowed_app_bundle_ids)}",
                        step_id,
                    )
                )

        confidence = derived_step_confidence(step_mapping, fallback_confidence)
        low_confidence = confidence < LOW_CONFIDENCE_THRESHOLD
        if low_confidence:
            step_issues.append(
                issue(
                    "warning",
                    "SPF-LOW-CONFIDENCE",
                    f"步骤 {step_id} 置信度 {confidence:.2f} 低于阈值 {LOW_CONFIDENCE_THRESHOLD:.2f}，需要老师确认。",
                    step_id,
                )
            )

        high_risk = is_high_risk_step(step, target_app_bundle_ids)
        if high_risk:
            step_issues.append(
                issue("warning", "SPF-HIGH-RISK-ACTION", f"步骤 {step_id} 被识别为高风险动作，需要老师确认。", step_id)
            )

        locator_status, locator_issues = validate_locator(step, step_mapping, step_id)
        step_issues.extend(locator_issues)

        step_requires_confirmation = (
            requires_teacher_confirmation
            or high_risk
            or low_confidence
            or locator_status == "degraded"
        )
        steps.append(
            {
                "stepId": step_id,
                "actionType": action_type,
                "confidence": confidence,
                "locatorStatus": locator_status,
                "targetAppBundleIds": target_app_bundle_ids,
                "highRisk": high_risk,
                "lowConfidence": low_confidence,
                "requiresTeacherConfirmation": step_requires_confirmation,
                "issues": step_issues,
            }
        )
        issues.extend(step_issues)

    error_count = sum(1 for item in issues if item["severity"] == "error")
    warning_count = sum(1 for item in issues if item["severity"] == "warning")
    auto_runnable_steps = sum(1 for step in steps if not step["requiresTeacherConfirmation"])
    status = "failed" if error_count > 0 else ("needs_teacher_confirmation" if any(step["requiresTeacherConfirmation"] for step in steps) or requires_teacher_confirmation else "passed")
    summary = (
        f"skill {skill_name} 预检"
        f"{'通过' if status == 'passed' else '需老师确认' if status == 'needs_teacher_confirmation' else '失败'}："
        f"步骤 {len(steps)}，可直接自动执行 {auto_runnable_steps}，错误 {error_count}，告警 {warning_count}。"
    )

    return {
        "schemaVersion": "openstaff.skill-preflight-report.v0",
        "skillName": skill_name,
        "skillDirectoryPath": str(skill_dir),
        "status": status,
        "summary": summary,
        "requiresTeacherConfirmation": any(step["requiresTeacherConfirmation"] for step in steps) or requires_teacher_confirmation,
        "isAutoRunnable": status == "passed",
        "allowedAppBundleIds": allowed_app_bundle_ids,
        "issues": issues,
        "steps": steps,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run static skill bundle preflight checks.")
    parser.add_argument("--skill-dir", required=True, type=Path, help="Skill directory path.")
    parser.add_argument(
        "--allow-app-bundle-id",
        action="append",
        default=[],
        help="Additional allowed app bundle ID. May be specified multiple times.",
    )
    parser.add_argument(
        "--require-auto-runnable",
        action="store_true",
        help="Treat confirmation-required skills as failure for CI gating.",
    )
    parser.add_argument("--json", action="store_true", help="Emit structured JSON report.")
    return parser.parse_args()


def print_text_report(report: dict[str, Any]) -> None:
    print(f"STATUS: {report['status'].upper()}")
    print(f"SUMMARY: {report['summary']}")
    if report["allowedAppBundleIds"]:
        print("ALLOWLIST:", ", ".join(report["allowedAppBundleIds"]))
    if report["issues"]:
        print("ISSUES:")
        for item in report["issues"]:
            step_suffix = f" step={item['stepId']}" if "stepId" in item else ""
            print(f"- [{item['severity']}] {item['code']}{step_suffix}: {item['message']}")


def main() -> int:
    args = parse_args()
    report = build_report(args.skill_dir, args.allow_app_bundle_id)
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print_text_report(report)

    if report["status"] == "failed":
        return 1
    if args.require_auto_runnable and report["status"] != "passed":
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
