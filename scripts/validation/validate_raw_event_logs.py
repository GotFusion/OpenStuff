#!/usr/bin/env python3
"""
Validate raw event JSONL logs against OpenStaff capture expectations.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

from common import issue, now_iso, parse_datetime, repo_relative


UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
    flags=re.IGNORECASE,
)
SESSION_ID_RE = re.compile(r"^[a-z0-9-]+$")
ALLOWED_SOURCES = {"mouse", "keyboard"}
ALLOWED_ACTIONS = {"leftClick", "rightClick", "doubleClick", "keyDown"}
ALLOWED_MODIFIERS = {"command", "shift", "option", "control"}
ALLOWED_TOP_LEVEL_KEYS = {
    "schemaVersion",
    "eventId",
    "sessionId",
    "timestamp",
    "source",
    "action",
    "pointer",
    "contextSnapshot",
    "modifiers",
    "keyboard",
}
ALLOWED_CONTEXT_KEYS = {
    "appName",
    "appBundleId",
    "windowTitle",
    "windowId",
    "isFrontmost",
    "windowSignature",
    "focusedElement",
    "screenshotAnchors",
    "captureDiagnostics",
}
ALLOWED_WINDOW_SIGNATURE_KEYS = {
    "signature",
    "signatureVersion",
    "normalizedTitle",
    "role",
    "subrole",
    "sizeBucket",
}
ALLOWED_FOCUSED_ELEMENT_KEYS = {
    "role",
    "subrole",
    "title",
    "identifier",
    "descriptionText",
    "helpText",
    "boundingRect",
    "valueRedacted",
}
ALLOWED_BOUNDING_RECT_KEYS = {"x", "y", "width", "height", "coordinateSpace"}
ALLOWED_SCREENSHOT_KEYS = {"phase", "boundingRect", "sampleSize", "pixelHash", "averageLuma", "redacted"}
ALLOWED_SAMPLE_SIZE_KEYS = {"width", "height"}
ALLOWED_CAPTURE_DIAGNOSTIC_KEYS = {"code", "field", "message"}
ALLOWED_KEYBOARD_KEYS = {
    "keyCode",
    "characters",
    "charactersIgnoringModifiers",
    "isRepeat",
    "isSensitiveInput",
    "redactionReason",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate OpenStaff raw event JSONL logs.")
    parser.add_argument("--input", required=True, type=Path, help="Input JSONL file or directory.")
    parser.add_argument(
        "--mode",
        choices=["strict", "compat"],
        default="compat",
        help="strict enforces the full v0 payload; compat tolerates legacy keyboard fields.",
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
    line_number: int,
    issues: list[dict[str, Any]],
    max_issues: int,
    field_name: str,
) -> None:
    if value is None:
        return
    if not isinstance(value, dict):
        add_issue(
            issues,
            issue("error", "RAW-INVALID-BOUNDING-RECT", f"{field_name} must be an object.", path=path, line_number=line_number, field=field_name),
            max_issues,
        )
        return

    extra_keys = sorted(set(value.keys()) - ALLOWED_BOUNDING_RECT_KEYS)
    if extra_keys:
        add_issue(
            issues,
            issue(
                "error",
                "RAW-UNKNOWN-BOUNDING-RECT-FIELD",
                f"{field_name} contains unknown keys: {', '.join(extra_keys)}.",
                path=path,
                line_number=line_number,
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
                    "RAW-INVALID-BOUNDING-RECT-FIELD",
                    f"{field_name}.{key} must be a number.",
                    path=path,
                    line_number=line_number,
                    field=f"{field_name}.{key}",
                ),
                max_issues,
            )
    if value.get("coordinateSpace") != "screen":
        add_issue(
            issues,
            issue(
                "error",
                "RAW-INVALID-COORDINATE-SPACE",
                f"{field_name}.coordinateSpace must be 'screen'.",
                path=path,
                line_number=line_number,
                field=f"{field_name}.coordinateSpace",
            ),
            max_issues,
        )


def validate_context_snapshot(
    value: Any,
    *,
    path: Path,
    line_number: int,
    issues: list[dict[str, Any]],
    max_issues: int,
) -> None:
    if not isinstance(value, dict):
        add_issue(
            issues,
            issue("error", "RAW-MISSING-CONTEXT-SNAPSHOT", "contextSnapshot must be an object.", path=path, line_number=line_number, field="contextSnapshot"),
            max_issues,
        )
        return

    extra_keys = sorted(set(value.keys()) - ALLOWED_CONTEXT_KEYS)
    if extra_keys:
        add_issue(
            issues,
            issue(
                "error",
                "RAW-UNKNOWN-CONTEXT-FIELD",
                f"contextSnapshot contains unknown keys: {', '.join(extra_keys)}.",
                path=path,
                line_number=line_number,
                field="contextSnapshot",
            ),
            max_issues,
        )

    for key in ("appName", "appBundleId"):
        candidate = value.get(key)
        if not isinstance(candidate, str) or not candidate.strip():
            add_issue(
                issues,
                issue(
                    "error",
                    "RAW-INVALID-CONTEXT-FIELD",
                    f"contextSnapshot.{key} must be a non-empty string.",
                    path=path,
                    line_number=line_number,
                    field=f"contextSnapshot.{key}",
                ),
                max_issues,
            )

    if not isinstance(value.get("isFrontmost"), bool):
        add_issue(
            issues,
            issue(
                "error",
                "RAW-INVALID-CONTEXT-FRONTMOST",
                "contextSnapshot.isFrontmost must be a boolean.",
                path=path,
                line_number=line_number,
                field="contextSnapshot.isFrontmost",
            ),
            max_issues,
        )

    window_signature = value.get("windowSignature")
    if window_signature is not None:
        if not isinstance(window_signature, dict):
            add_issue(
                issues,
                issue("error", "RAW-INVALID-WINDOW-SIGNATURE", "windowSignature must be an object or null.", path=path, line_number=line_number, field="contextSnapshot.windowSignature"),
                max_issues,
            )
        else:
            extra_keys = sorted(set(window_signature.keys()) - ALLOWED_WINDOW_SIGNATURE_KEYS)
            if extra_keys:
                add_issue(
                    issues,
                    issue(
                        "error",
                        "RAW-UNKNOWN-WINDOW-SIGNATURE-FIELD",
                        f"windowSignature contains unknown keys: {', '.join(extra_keys)}.",
                        path=path,
                        line_number=line_number,
                        field="contextSnapshot.windowSignature",
                    ),
                    max_issues,
                )
            for key in ("signature", "signatureVersion"):
                candidate = window_signature.get(key)
                if not isinstance(candidate, str) or not candidate.strip():
                    add_issue(
                        issues,
                        issue(
                            "error",
                            "RAW-INVALID-WINDOW-SIGNATURE-FIELD",
                            f"windowSignature.{key} must be a non-empty string.",
                            path=path,
                            line_number=line_number,
                            field=f"contextSnapshot.windowSignature.{key}",
                        ),
                        max_issues,
                    )

    focused_element = value.get("focusedElement")
    if focused_element is not None:
        if not isinstance(focused_element, dict):
            add_issue(
                issues,
                issue("error", "RAW-INVALID-FOCUSED-ELEMENT", "focusedElement must be an object or null.", path=path, line_number=line_number, field="contextSnapshot.focusedElement"),
                max_issues,
            )
        else:
            extra_keys = sorted(set(focused_element.keys()) - ALLOWED_FOCUSED_ELEMENT_KEYS)
            if extra_keys:
                add_issue(
                    issues,
                    issue(
                        "error",
                        "RAW-UNKNOWN-FOCUSED-ELEMENT-FIELD",
                        f"focusedElement contains unknown keys: {', '.join(extra_keys)}.",
                        path=path,
                        line_number=line_number,
                        field="contextSnapshot.focusedElement",
                    ),
                    max_issues,
                )
            if not isinstance(focused_element.get("valueRedacted"), bool):
                add_issue(
                    issues,
                    issue(
                        "error",
                        "RAW-INVALID-FOCUSED-ELEMENT-REDACTION",
                        "focusedElement.valueRedacted must be a boolean.",
                        path=path,
                        line_number=line_number,
                        field="contextSnapshot.focusedElement.valueRedacted",
                    ),
                    max_issues,
                )
            validate_bounding_rect(
                focused_element.get("boundingRect"),
                path=path,
                line_number=line_number,
                issues=issues,
                max_issues=max_issues,
                field_name="contextSnapshot.focusedElement.boundingRect",
            )

    screenshot_anchors = value.get("screenshotAnchors", [])
    if screenshot_anchors is not None:
        if not isinstance(screenshot_anchors, list):
            add_issue(
                issues,
                issue("error", "RAW-INVALID-SCREENSHOT-ANCHORS", "screenshotAnchors must be an array.", path=path, line_number=line_number, field="contextSnapshot.screenshotAnchors"),
                max_issues,
            )
        else:
            for index, anchor in enumerate(screenshot_anchors):
                if not isinstance(anchor, dict):
                    add_issue(
                        issues,
                        issue(
                            "error",
                            "RAW-INVALID-SCREENSHOT-ANCHOR",
                            f"screenshotAnchors[{index}] must be an object.",
                            path=path,
                            line_number=line_number,
                            field=f"contextSnapshot.screenshotAnchors[{index}]",
                        ),
                        max_issues,
                    )
                    continue
                extra_keys = sorted(set(anchor.keys()) - ALLOWED_SCREENSHOT_KEYS)
                if extra_keys:
                    add_issue(
                        issues,
                        issue(
                            "error",
                            "RAW-UNKNOWN-SCREENSHOT-ANCHOR-FIELD",
                            f"screenshotAnchors[{index}] contains unknown keys: {', '.join(extra_keys)}.",
                            path=path,
                            line_number=line_number,
                            field=f"contextSnapshot.screenshotAnchors[{index}]",
                        ),
                        max_issues,
                    )
                if anchor.get("phase") not in {"before", "after"}:
                    add_issue(
                        issues,
                        issue(
                            "error",
                            "RAW-INVALID-SCREENSHOT-PHASE",
                            f"screenshotAnchors[{index}].phase must be 'before' or 'after'.",
                            path=path,
                            line_number=line_number,
                            field=f"contextSnapshot.screenshotAnchors[{index}].phase",
                        ),
                        max_issues,
                    )
                validate_bounding_rect(
                    anchor.get("boundingRect"),
                    path=path,
                    line_number=line_number,
                    issues=issues,
                    max_issues=max_issues,
                    field_name=f"contextSnapshot.screenshotAnchors[{index}].boundingRect",
                )
                sample_size = anchor.get("sampleSize")
                if not isinstance(sample_size, dict):
                    add_issue(
                        issues,
                        issue(
                            "error",
                            "RAW-INVALID-SAMPLE-SIZE",
                            f"screenshotAnchors[{index}].sampleSize must be an object.",
                            path=path,
                            line_number=line_number,
                            field=f"contextSnapshot.screenshotAnchors[{index}].sampleSize",
                        ),
                        max_issues,
                    )
                else:
                    extra_size_keys = sorted(set(sample_size.keys()) - ALLOWED_SAMPLE_SIZE_KEYS)
                    if extra_size_keys:
                        add_issue(
                            issues,
                            issue(
                                "error",
                                "RAW-UNKNOWN-SAMPLE-SIZE-FIELD",
                                f"screenshotAnchors[{index}].sampleSize contains unknown keys: {', '.join(extra_size_keys)}.",
                                path=path,
                                line_number=line_number,
                                field=f"contextSnapshot.screenshotAnchors[{index}].sampleSize",
                            ),
                            max_issues,
                        )
                    for key in ("width", "height"):
                        if not isinstance(sample_size.get(key), int) or sample_size[key] <= 0:
                            add_issue(
                                issues,
                                issue(
                                    "error",
                                    "RAW-INVALID-SAMPLE-SIZE-FIELD",
                                    f"screenshotAnchors[{index}].sampleSize.{key} must be a positive integer.",
                                    path=path,
                                    line_number=line_number,
                                    field=f"contextSnapshot.screenshotAnchors[{index}].sampleSize.{key}",
                                ),
                                max_issues,
                            )
                if not isinstance(anchor.get("pixelHash"), str) or len(anchor["pixelHash"].strip()) < 8:
                    add_issue(
                        issues,
                        issue(
                            "error",
                            "RAW-INVALID-PIXEL-HASH",
                            f"screenshotAnchors[{index}].pixelHash must be a non-empty string with length >= 8.",
                            path=path,
                            line_number=line_number,
                            field=f"contextSnapshot.screenshotAnchors[{index}].pixelHash",
                        ),
                        max_issues,
                    )
                average_luma = anchor.get("averageLuma")
                if not is_number(average_luma) or average_luma < 0 or average_luma > 1:
                    add_issue(
                        issues,
                        issue(
                            "error",
                            "RAW-INVALID-AVERAGE-LUMA",
                            f"screenshotAnchors[{index}].averageLuma must be in [0, 1].",
                            path=path,
                            line_number=line_number,
                            field=f"contextSnapshot.screenshotAnchors[{index}].averageLuma",
                        ),
                        max_issues,
                    )
                if not isinstance(anchor.get("redacted"), bool):
                    add_issue(
                        issues,
                        issue(
                            "error",
                            "RAW-INVALID-SCREENSHOT-REDACTION",
                            f"screenshotAnchors[{index}].redacted must be a boolean.",
                            path=path,
                            line_number=line_number,
                            field=f"contextSnapshot.screenshotAnchors[{index}].redacted",
                        ),
                        max_issues,
                    )

    capture_diagnostics = value.get("captureDiagnostics", [])
    if capture_diagnostics is not None:
        if not isinstance(capture_diagnostics, list):
            add_issue(
                issues,
                issue("error", "RAW-INVALID-CAPTURE-DIAGNOSTICS", "captureDiagnostics must be an array.", path=path, line_number=line_number, field="contextSnapshot.captureDiagnostics"),
                max_issues,
            )
        else:
            for index, diagnostic in enumerate(capture_diagnostics):
                if not isinstance(diagnostic, dict):
                    add_issue(
                        issues,
                        issue(
                            "error",
                            "RAW-INVALID-CAPTURE-DIAGNOSTIC",
                            f"captureDiagnostics[{index}] must be an object.",
                            path=path,
                            line_number=line_number,
                            field=f"contextSnapshot.captureDiagnostics[{index}]",
                        ),
                        max_issues,
                    )
                    continue
                extra_keys = sorted(set(diagnostic.keys()) - ALLOWED_CAPTURE_DIAGNOSTIC_KEYS)
                if extra_keys:
                    add_issue(
                        issues,
                        issue(
                            "error",
                            "RAW-UNKNOWN-CAPTURE-DIAGNOSTIC-FIELD",
                            f"captureDiagnostics[{index}] contains unknown keys: {', '.join(extra_keys)}.",
                            path=path,
                            line_number=line_number,
                            field=f"contextSnapshot.captureDiagnostics[{index}]",
                        ),
                        max_issues,
                    )
                for key in ("code", "field", "message"):
                    candidate = diagnostic.get(key)
                    if not isinstance(candidate, str) or not candidate.strip():
                        add_issue(
                            issues,
                            issue(
                                "error",
                                "RAW-INVALID-CAPTURE-DIAGNOSTIC-FIELD",
                                f"captureDiagnostics[{index}].{key} must be a non-empty string.",
                                path=path,
                                line_number=line_number,
                                field=f"contextSnapshot.captureDiagnostics[{index}].{key}",
                            ),
                            max_issues,
                        )


def validate_keyboard_payload(
    payload: dict[str, Any],
    *,
    mode: str,
    path: Path,
    line_number: int,
    issues: list[dict[str, Any]],
    max_issues: int,
) -> None:
    keyboard = payload.get("keyboard")
    source = payload.get("source")
    action = payload.get("action")

    if source == "keyboard" or action == "keyDown":
        if not isinstance(keyboard, dict):
            add_issue(
                issues,
                issue("error", "RAW-MISSING-KEYBOARD-PAYLOAD", "Keyboard events must include keyboard payload.", path=path, line_number=line_number, field="keyboard"),
                max_issues,
            )
            return
    elif keyboard is None:
        return
    elif not isinstance(keyboard, dict):
        add_issue(
            issues,
            issue("error", "RAW-INVALID-KEYBOARD-PAYLOAD", "keyboard must be an object or null.", path=path, line_number=line_number, field="keyboard"),
            max_issues,
        )
        return

    extra_keys = sorted(set(keyboard.keys()) - ALLOWED_KEYBOARD_KEYS)
    if extra_keys:
        add_issue(
            issues,
            issue(
                "error",
                "RAW-UNKNOWN-KEYBOARD-FIELD",
                f"keyboard contains unknown keys: {', '.join(extra_keys)}.",
                path=path,
                line_number=line_number,
                field="keyboard",
            ),
            max_issues,
        )

    if not isinstance(keyboard.get("keyCode"), int):
        add_issue(
            issues,
            issue("error", "RAW-INVALID-KEYCODE", "keyboard.keyCode must be an integer.", path=path, line_number=line_number, field="keyboard.keyCode"),
            max_issues,
        )

    if not isinstance(keyboard.get("isRepeat"), bool):
        add_issue(
            issues,
            issue("error", "RAW-INVALID-IS-REPEAT", "keyboard.isRepeat must be a boolean.", path=path, line_number=line_number, field="keyboard.isRepeat"),
            max_issues,
        )

    if "isSensitiveInput" not in keyboard:
        severity = "error" if mode == "strict" else "warning"
        code = "RAW-MISSING-IS-SENSITIVE-INPUT" if mode == "strict" else "RAW-LEGACY-KEYBOARD-PAYLOAD"
        add_issue(
            issues,
            issue(
                severity,
                code,
                "keyboard.isSensitiveInput is missing; this is tolerated only in compat mode for legacy captures.",
                path=path,
                line_number=line_number,
                field="keyboard.isSensitiveInput",
            ),
            max_issues,
        )
    elif not isinstance(keyboard.get("isSensitiveInput"), bool):
        add_issue(
            issues,
            issue("error", "RAW-INVALID-IS-SENSITIVE-INPUT", "keyboard.isSensitiveInput must be a boolean.", path=path, line_number=line_number, field="keyboard.isSensitiveInput"),
            max_issues,
        )

    for key in ("characters", "charactersIgnoringModifiers", "redactionReason"):
        candidate = keyboard.get(key)
        if candidate is not None and not isinstance(candidate, str):
            add_issue(
                issues,
                issue(
                    "error",
                    "RAW-INVALID-KEYBOARD-TEXT-FIELD",
                    f"keyboard.{key} must be a string or null.",
                    path=path,
                    line_number=line_number,
                    field=f"keyboard.{key}",
                ),
                max_issues,
            )


def validate_record(
    payload: Any,
    *,
    mode: str,
    path: Path,
    line_number: int,
    max_issues: int,
) -> list[dict[str, Any]]:
    issues: list[dict[str, Any]] = []
    if not isinstance(payload, dict):
        add_issue(
            issues,
            issue("error", "RAW-INVALID-JSON-TYPE", "Each JSONL record must be an object.", path=path, line_number=line_number),
            max_issues,
        )
        return issues

    extra_keys = sorted(set(payload.keys()) - ALLOWED_TOP_LEVEL_KEYS)
    if extra_keys:
        severity = "error" if mode == "strict" else "warning"
        add_issue(
            issues,
            issue(
                severity,
                "RAW-UNKNOWN-TOP-LEVEL-FIELD",
                f"Raw event contains unknown keys: {', '.join(extra_keys)}.",
                path=path,
                line_number=line_number,
            ),
            max_issues,
        )

    if payload.get("schemaVersion") != "capture.raw.v0":
        add_issue(
            issues,
            issue("error", "RAW-INVALID-SCHEMA-VERSION", "schemaVersion must be capture.raw.v0.", path=path, line_number=line_number, field="schemaVersion"),
            max_issues,
        )

    event_id = payload.get("eventId")
    if not isinstance(event_id, str) or not UUID_RE.fullmatch(event_id):
        add_issue(
            issues,
            issue("error", "RAW-INVALID-EVENT-ID", "eventId must be a UUID string.", path=path, line_number=line_number, field="eventId"),
            max_issues,
        )

    session_id = payload.get("sessionId")
    if not isinstance(session_id, str) or not SESSION_ID_RE.fullmatch(session_id):
        add_issue(
            issues,
            issue("error", "RAW-INVALID-SESSION-ID", "sessionId must match ^[a-z0-9-]+$.", path=path, line_number=line_number, field="sessionId"),
            max_issues,
        )

    if not parse_datetime(payload.get("timestamp")):
        add_issue(
            issues,
            issue("error", "RAW-INVALID-TIMESTAMP", "timestamp must be an ISO 8601 date-time string.", path=path, line_number=line_number, field="timestamp"),
            max_issues,
        )

    if payload.get("source") not in ALLOWED_SOURCES:
        add_issue(
            issues,
            issue("error", "RAW-INVALID-SOURCE", f"source must be one of {sorted(ALLOWED_SOURCES)}.", path=path, line_number=line_number, field="source"),
            max_issues,
        )
    if payload.get("action") not in ALLOWED_ACTIONS:
        add_issue(
            issues,
            issue("error", "RAW-INVALID-ACTION", f"action must be one of {sorted(ALLOWED_ACTIONS)}.", path=path, line_number=line_number, field="action"),
            max_issues,
        )

    pointer = payload.get("pointer")
    if not isinstance(pointer, dict):
        add_issue(
            issues,
            issue("error", "RAW-INVALID-POINTER", "pointer must be an object.", path=path, line_number=line_number, field="pointer"),
            max_issues,
        )
    else:
        for key in ("x", "y"):
            if not isinstance(pointer.get(key), int):
                add_issue(
                    issues,
                    issue(
                        "error",
                        "RAW-INVALID-POINTER-FIELD",
                        f"pointer.{key} must be an integer.",
                        path=path,
                        line_number=line_number,
                        field=f"pointer.{key}",
                    ),
                    max_issues,
                )
        if pointer.get("coordinateSpace") != "screen":
            add_issue(
                issues,
                issue("error", "RAW-INVALID-POINTER-SPACE", "pointer.coordinateSpace must be 'screen'.", path=path, line_number=line_number, field="pointer.coordinateSpace"),
                max_issues,
            )

    modifiers = payload.get("modifiers", [])
    if modifiers is not None:
        if not isinstance(modifiers, list):
            add_issue(
                issues,
                issue("error", "RAW-INVALID-MODIFIERS", "modifiers must be an array.", path=path, line_number=line_number, field="modifiers"),
                max_issues,
            )
        else:
            seen: set[str] = set()
            for index, modifier in enumerate(modifiers):
                if modifier not in ALLOWED_MODIFIERS:
                    add_issue(
                        issues,
                        issue(
                            "error",
                            "RAW-INVALID-MODIFIER",
                            f"modifiers[{index}] must be one of {sorted(ALLOWED_MODIFIERS)}.",
                            path=path,
                            line_number=line_number,
                            field=f"modifiers[{index}]",
                        ),
                        max_issues,
                    )
                    continue
                if modifier in seen:
                    add_issue(
                        issues,
                        issue(
                            "error",
                            "RAW-DUPLICATE-MODIFIER",
                            f"modifiers contains duplicate value '{modifier}'.",
                            path=path,
                            line_number=line_number,
                            field="modifiers",
                        ),
                        max_issues,
                    )
                seen.add(modifier)

    validate_context_snapshot(
        payload.get("contextSnapshot"),
        path=path,
        line_number=line_number,
        issues=issues,
        max_issues=max_issues,
    )
    validate_keyboard_payload(
        payload,
        mode=mode,
        path=path,
        line_number=line_number,
        issues=issues,
        max_issues=max_issues,
    )
    return issues


def collect_files(input_path: Path) -> list[Path]:
    if input_path.is_file():
        return [input_path]
    if input_path.is_dir():
        return sorted(path for path in input_path.rglob("*.jsonl") if path.is_file())
    raise FileNotFoundError(f"Input path does not exist: {input_path}")


def validate_file(path: Path, mode: str, max_issues: int) -> dict[str, Any]:
    issues: list[dict[str, Any]] = []
    event_count = 0
    with path.open("r", encoding="utf-8") as handle:
        for line_number, raw_line in enumerate(handle, start=1):
            line = raw_line.strip()
            if not line:
                continue
            event_count += 1
            try:
                payload = json.loads(line)
            except json.JSONDecodeError as exc:
                add_issue(
                    issues,
                    issue(
                        "error",
                        "RAW-JSON-DECODE-FAILED",
                        f"Invalid JSON at line {line_number}: {exc}",
                        path=path,
                        line_number=line_number,
                    ),
                    max_issues,
                )
                continue
            for item in validate_record(payload, mode=mode, path=path, line_number=line_number, max_issues=max_issues):
                add_issue(issues, item, max_issues)

    error_count = sum(1 for entry in issues if entry["severity"] == "error")
    warning_count = sum(1 for entry in issues if entry["severity"] == "warning")
    return {
        "path": repo_relative(path),
        "eventCount": event_count,
        "errorCount": error_count,
        "warningCount": warning_count,
        "issues": issues,
    }


def build_report(input_path: Path, mode: str, max_issues: int) -> dict[str, Any]:
    files = collect_files(input_path)
    reports = [validate_file(path, mode, max_issues) for path in files]
    error_count = sum(file_report["errorCount"] for file_report in reports)
    warning_count = sum(file_report["warningCount"] for file_report in reports)
    event_count = sum(file_report["eventCount"] for file_report in reports)
    passed = error_count == 0

    summary = (
        f"Validated {len(reports)} raw-event file(s), {event_count} event(s), "
        f"errors={error_count}, warnings={warning_count}, mode={mode}."
    )

    return {
        "schemaVersion": "openstaff.raw-event-validation-report.v0",
        "generatedAt": now_iso(),
        "inputPath": repo_relative(input_path.resolve()),
        "mode": mode,
        "passed": passed,
        "fileCount": len(reports),
        "eventCount": event_count,
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
            f"- {file_report['path']}: events={file_report['eventCount']} "
            f"errors={file_report['errorCount']} warnings={file_report['warningCount']}"
        )
        for item in file_report["issues"][:5]:
            location = f" line={item['lineNumber']}" if "lineNumber" in item else ""
            print(f"  [{item['severity']}] {item['code']}{location}: {item['message']}")


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
