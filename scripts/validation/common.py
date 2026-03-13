#!/usr/bin/env python3
"""
Shared helpers for validation and release scripts.
"""

from __future__ import annotations

import json
import os
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
PACKAGE_PATH = REPO_ROOT / "apps/macos"
XCODE_DEVELOPER_DIR = Path("/Applications/Xcode.app/Contents/Developer")


def now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def tail(text: str, max_lines: int = 40) -> str:
    lines = text.strip().splitlines()
    if len(lines) <= max_lines:
        return "\n".join(lines)
    return "\n".join(lines[-max_lines:])


def repo_relative(path: Path) -> str:
    resolved = path.resolve()
    try:
        return resolved.relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return str(resolved)


def build_swift_env() -> dict[str, str]:
    env = os.environ.copy()
    env["HOME"] = "/tmp"

    if XCODE_DEVELOPER_DIR.exists():
        env["DEVELOPER_DIR"] = str(XCODE_DEVELOPER_DIR)

    module_cache = REPO_ROOT / ".build/module-cache"
    clang_module_cache = REPO_ROOT / ".build/clang-module-cache"
    module_cache.mkdir(parents=True, exist_ok=True)
    clang_module_cache.mkdir(parents=True, exist_ok=True)
    env["SWIFTPM_MODULECACHE_OVERRIDE"] = str(module_cache)
    env["CLANG_MODULE_CACHE_PATH"] = str(clang_module_cache)
    return env


def run_command(
    command: list[str],
    *,
    cwd: Path = REPO_ROOT,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )


def parse_datetime(value: Any) -> bool:
    if not isinstance(value, str) or not value.strip():
        return False

    candidate = value.replace("Z", "+00:00")
    try:
        datetime.fromisoformat(candidate)
    except ValueError:
        return False
    return True


def extract_last_json_object(text: str) -> Any:
    stripped = text.strip()
    if not stripped:
        raise ValueError("No JSON object found in empty output.")

    try:
        return json.loads(stripped)
    except json.JSONDecodeError:
        end = stripped.rfind("}")
        if end == -1:
            raise ValueError(f"No JSON object found in output: {stripped}") from None

        for start in range(end, -1, -1):
            if stripped[start] != "{":
                continue
            candidate = stripped[start : end + 1]
            try:
                return json.loads(candidate)
            except json.JSONDecodeError:
                continue
        raise ValueError(f"No JSON object found in output: {stripped}") from None


def issue(
    severity: str,
    code: str,
    message: str,
    *,
    path: Path | None = None,
    line_number: int | None = None,
    record_id: str | None = None,
    field: str | None = None,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "severity": severity,
        "code": code,
        "message": message,
    }
    if path is not None:
        payload["path"] = repo_relative(path)
    if line_number is not None:
        payload["lineNumber"] = line_number
    if record_id is not None:
        payload["recordId"] = record_id
    if field is not None:
        payload["field"] = field
    return payload
