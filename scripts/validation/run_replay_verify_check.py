#!/usr/bin/env python3
"""
Run a replay-verify gate check and normalize the result for release preflight.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from common import PACKAGE_PATH, build_swift_env, extract_last_json_object, now_iso, repo_relative, run_command, tail


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run OpenStaff replay-verify gate checks.")
    parser.add_argument("--knowledge", type=Path, help="KnowledgeItem JSON file or directory.")
    parser.add_argument("--skill-dir", type=Path, help="OpenStaff skill bundle directory.")
    parser.add_argument("--snapshot", type=Path, help="Replay snapshot JSON file.")
    parser.add_argument(
        "--expected-exit-code",
        type=int,
        default=0,
        help="Expected exit code from ReplayVerifyCLI (default: 0).",
    )
    parser.add_argument(
        "--replay-verify-executable",
        type=str,
        help="Optional prebuilt OpenStaffReplayVerifyCLI executable path.",
    )
    parser.add_argument("--json", action="store_true", help="Emit structured JSON report.")
    return parser.parse_args()


def build_command(args: argparse.Namespace) -> list[str]:
    if bool(args.knowledge) == bool(args.skill_dir):
        raise ValueError("Exactly one of --knowledge or --skill-dir must be provided.")

    executable = args.replay_verify_executable
    if executable:
        command = [executable]
    else:
        command = ["swift", "run", "--package-path", repo_relative(PACKAGE_PATH), "OpenStaffReplayVerifyCLI"]

    if args.knowledge:
        command.extend(["--knowledge", repo_relative(args.knowledge.resolve())])
    if args.skill_dir:
        command.extend(["--skill-dir", repo_relative(args.skill_dir.resolve())])
    if args.snapshot:
        command.extend(["--snapshot", repo_relative(args.snapshot.resolve())])
    command.append("--json")
    return command


def summarize_payload(payload: Any) -> str:
    if not isinstance(payload, dict):
        return "ReplayVerifyCLI did not return a JSON object."

    if "summary" in payload and isinstance(payload["summary"], dict):
        summary = payload["summary"]
        if {"knowledgeItemCount", "resolvedSteps", "degradedSteps", "failedSteps"}.issubset(summary.keys()):
            return (
                f"knowledgeItems={summary['knowledgeItemCount']} "
                f"resolved={summary['resolvedSteps']} degraded={summary['degradedSteps']} failed={summary['failedSteps']}"
            )

    drift_report = payload.get("driftReport")
    if isinstance(drift_report, dict):
        return (
            f"skill={drift_report.get('skillName', 'unknown')} "
            f"status={drift_report.get('status', 'unknown')} "
            f"dominant={drift_report.get('dominantDriftKind', 'unknown')}"
        )

    return "ReplayVerifyCLI returned JSON, but no known summary fields were found."


def build_report(args: argparse.Namespace) -> dict[str, Any]:
    command = build_command(args)
    completed = run_command(command, env=build_swift_env())

    payload: Any = None
    parse_error: str | None = None
    if completed.stdout.strip():
        try:
            payload = extract_last_json_object(completed.stdout)
        except Exception as exc:  # noqa: BLE001
            parse_error = str(exc)

    passed = completed.returncode == args.expected_exit_code
    summary = summarize_payload(payload) if parse_error is None else f"Failed to parse ReplayVerifyCLI JSON: {parse_error}"
    report = {
        "schemaVersion": "openstaff.replay-verify-gate-report.v0",
        "generatedAt": now_iso(),
        "command": command,
        "expectedExitCode": args.expected_exit_code,
        "returncode": completed.returncode,
        "passed": passed,
        "summary": summary,
        "stdoutTail": tail(completed.stdout),
        "stderrTail": tail(completed.stderr),
        "payload": payload,
        "payloadParseError": parse_error,
    }
    return report


def print_text_report(report: dict[str, Any]) -> None:
    status = "PASS" if report["passed"] else "FAIL"
    print(f"STATUS: {status}")
    print(f"SUMMARY: {report['summary']}")
    print("CMD:", " ".join(report["command"]))
    print(f"RETURNCODE: {report['returncode']} expected={report['expectedExitCode']}")
    if report["stdoutTail"]:
        print("--- stdout (tail) ---")
        print(report["stdoutTail"])
    if report["stderrTail"]:
        print("--- stderr (tail) ---")
        print(report["stderrTail"])


def main() -> int:
    args = parse_args()
    report = build_report(args)
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print_text_report(report)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
