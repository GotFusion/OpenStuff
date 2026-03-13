#!/usr/bin/env python3
"""
Run release regression checks (TODO 6.3).
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT_ROOT = Path("/tmp/openstaff-release-regression")


@dataclass
class CheckResult:
    name: str
    command: list[str]
    returncode: int
    durationSeconds: float
    stdoutTail: str
    stderrTail: str

    @property
    def passed(self) -> bool:
        return self.returncode == 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run OpenStaff release regression checks.")
    parser.add_argument(
        "--output-root",
        type=Path,
        default=DEFAULT_OUTPUT_ROOT,
        help=f"Output directory root (default: {DEFAULT_OUTPUT_ROOT}).",
    )
    parser.add_argument(
        "--suite",
        choices=["all", "unit", "integration", "e2e"],
        default="all",
        help="Test suite to run via scripts/tests/run_all.py.",
    )
    parser.add_argument(
        "--skip-tests",
        action="store_true",
        help="Skip tests/run_all.py execution.",
    )
    parser.add_argument(
        "--report",
        type=Path,
        help="Optional explicit report path. Default: <run-dir>/regression-report.json",
    )
    return parser.parse_args()


def now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def tail(text: str, max_lines: int = 40) -> str:
    lines = text.strip().splitlines()
    if len(lines) <= max_lines:
        return "\n".join(lines)
    return "\n".join(lines[-max_lines:])


def run_check(name: str, command: list[str]) -> CheckResult:
    print(f"\n=== CHECK: {name} ===")
    print("CMD:", " ".join(command))
    started = time.monotonic()
    completed = subprocess.run(
        command,
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    duration = round(time.monotonic() - started, 3)
    result = CheckResult(
        name=name,
        command=command,
        returncode=completed.returncode,
        durationSeconds=duration,
        stdoutTail=tail(completed.stdout),
        stderrTail=tail(completed.stderr),
    )

    status = "PASS" if result.passed else "FAIL"
    print(f"STATUS: {status} duration={duration}s returncode={result.returncode}")
    if result.stdoutTail:
        print("--- stdout (tail) ---")
        print(result.stdoutTail)
    if result.stderrTail:
        print("--- stderr (tail) ---")
        print(result.stderrTail)
    return result


def append_skill_pipeline_checks(results: list[CheckResult], skills_root: Path) -> None:
    cases = [
        {
            "name": "a1-valid",
            "knowledge": "core/knowledge/examples/knowledge-item.sample.json",
            "llm": "scripts/llm/examples/knowledge-parse-output.sample.json",
            "skillDir": "openstaff-task-session-20260307-a1-001",
        },
        {
            "name": "b2-valid",
            "knowledge": "scripts/skills/examples/knowledge-item.sample.finder.json",
            "llm": "scripts/skills/examples/llm-output.sample.finder.json",
            "skillDir": "openstaff-task-session-20260307-b2-001",
        },
        {
            "name": "c3-fallback",
            "knowledge": "scripts/skills/examples/knowledge-item.sample.terminal.json",
            "llm": "scripts/skills/examples/llm-output.sample.terminal-invalid.txt",
            "skillDir": "openstaff-task-session-20260307-c3-001",
        },
    ]

    for case in cases:
        results.append(
            run_check(
                name=f"skill-map-{case['name']}",
                command=[
                    sys.executable,
                    str(REPO_ROOT / "scripts/skills/openclaw_skill_mapper.py"),
                    "--knowledge-item",
                    str(REPO_ROOT / case["knowledge"]),
                    "--llm-output",
                    str(REPO_ROOT / case["llm"]),
                    "--skills-root",
                    str(skills_root),
                    "--overwrite",
                ],
            )
        )

        results.append(
            run_check(
                name=f"skill-validate-{case['name']}",
                command=[
                    sys.executable,
                    str(REPO_ROOT / "scripts/skills/validate_openclaw_skill.py"),
                    "--skill-dir",
                    str(skills_root / case["skillDir"]),
                ],
            )
        )

        results.append(
            run_check(
                name=f"skill-preflight-{case['name']}",
                command=[
                    sys.executable,
                    str(REPO_ROOT / "scripts/validation/validate_skill_bundle.py"),
                    "--skill-dir",
                    str(skills_root / case["skillDir"]),
                ],
            )
        )


def main() -> int:
    args = parse_args()
    run_id = datetime.now().strftime("run-%Y%m%d-%H%M%S")
    run_dir = args.output_root.resolve() / run_id
    run_dir.mkdir(parents=True, exist_ok=True)
    skills_root = run_dir / "skills-sample"
    report_path = args.report.resolve() if args.report else run_dir / "regression-report.json"

    results: list[CheckResult] = []
    results.append(
        run_check(
            name="llm-validate-sample",
            command=[
                sys.executable,
                str(REPO_ROOT / "scripts/llm/validate_knowledge_parse_output.py"),
                "--input",
                str(REPO_ROOT / "scripts/llm/examples/knowledge-parse-output.sample.json"),
                "--knowledge-item",
                str(REPO_ROOT / "core/knowledge/examples/knowledge-item.sample.json"),
            ],
        )
    )

    append_skill_pipeline_checks(results, skills_root)

    if not args.skip_tests:
        results.append(
            run_check(
                name=f"tests-{args.suite}",
                command=[
                    sys.executable,
                    str(REPO_ROOT / "scripts/tests/run_all.py"),
                    "--suite",
                    args.suite,
                ],
            )
        )

    failed = [item for item in results if not item.passed]
    summary = {
        "schemaVersion": "openstaff.release-regression-report.v0",
        "generatedAt": now_iso(),
        "runDir": str(run_dir),
        "reportPath": str(report_path),
        "passed": len(failed) == 0,
        "totalChecks": len(results),
        "failedChecks": [item.name for item in failed],
        "checks": [asdict(item) for item in results],
    }

    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print("\n=== Release Regression Summary ===")
    for item in results:
        status = "PASS" if item.passed else "FAIL"
        print(f"[{status}] {item.name} ({item.durationSeconds}s)")
    print(f"REPORT: {report_path}")

    return 0 if len(failed) == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
