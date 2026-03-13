#!/usr/bin/env python3
"""
Run release regression and validation gates (TODO 6.3 / TODO 10.2).
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
        "--skip-benchmark",
        action="store_true",
        help="Skip personal benchmark execution.",
    )
    parser.add_argument(
        "--benchmark-case-limit",
        type=int,
        help="Optional limit forwarded to the benchmark runner.",
    )
    parser.add_argument(
        "--openclaw-executable",
        type=str,
        help="Optional prebuilt OpenStaffOpenClawCLI executable path for benchmark execution.",
    )
    parser.add_argument(
        "--replay-verify-executable",
        type=str,
        help="Optional prebuilt OpenStaffReplayVerifyCLI executable path for replay-verify checks.",
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


def append_data_validation_checks(results: list[CheckResult]) -> None:
    results.append(
        run_check(
            name="raw-events-sample-strict",
            command=[
                sys.executable,
                str(REPO_ROOT / "scripts/validation/validate_raw_event_logs.py"),
                "--input",
                str(REPO_ROOT / "core/capture/examples/raw-events.sample.jsonl"),
                "--mode",
                "strict",
                "--json",
            ],
        )
    )
    results.append(
        run_check(
            name="raw-events-data-compat",
            command=[
                sys.executable,
                str(REPO_ROOT / "scripts/validation/validate_raw_event_logs.py"),
                "--input",
                str(REPO_ROOT / "data/raw-events"),
                "--mode",
                "compat",
                "--json",
            ],
        )
    )
    results.append(
        run_check(
            name="knowledge-sample-strict",
            command=[
                sys.executable,
                str(REPO_ROOT / "scripts/validation/validate_knowledge_items.py"),
                "--input",
                str(REPO_ROOT / "core/knowledge/examples/knowledge-item.sample.json"),
                "--mode",
                "strict",
                "--json",
            ],
        )
    )
    results.append(
        run_check(
            name="knowledge-data-compat",
            command=[
                sys.executable,
                str(REPO_ROOT / "scripts/validation/validate_knowledge_items.py"),
                "--input",
                str(REPO_ROOT / "data/knowledge"),
                "--mode",
                "compat",
                "--json",
            ],
        )
    )


def append_replay_verify_checks(results: list[CheckResult], replay_verify_executable: str | None) -> None:
    command = [
        sys.executable,
        str(REPO_ROOT / "scripts/validation/run_replay_verify_check.py"),
        "--knowledge",
        str(REPO_ROOT / "core/knowledge/examples/knowledge-item.sample.json"),
        "--snapshot",
        str(REPO_ROOT / "core/executor/examples/replay-environment.sample.json"),
        "--expected-exit-code",
        "0",
        "--json",
    ]
    if replay_verify_executable:
        command.extend(["--replay-verify-executable", replay_verify_executable])

    results.append(run_check(name="replay-verify-sample", command=command))


def append_benchmark_check(
    results: list[CheckResult],
    benchmark_root: Path,
    *,
    benchmark_case_limit: int | None,
    openclaw_executable: str | None,
) -> None:
    command = [
        sys.executable,
        str(REPO_ROOT / "scripts/benchmarks/run_personal_desktop_benchmark.py"),
        "--benchmark-root",
        str(benchmark_root),
        "--report",
        str(benchmark_root / "manifest.json"),
    ]
    if benchmark_case_limit is not None:
        command.extend(["--case-limit", str(benchmark_case_limit)])
    if openclaw_executable:
        command.extend(["--openclaw-executable", openclaw_executable])

    results.append(run_check(name="benchmark-personal-desktop", command=command))


def main() -> int:
    args = parse_args()
    run_id = datetime.now().strftime("run-%Y%m%d-%H%M%S")
    run_dir = args.output_root.resolve() / run_id
    run_dir.mkdir(parents=True, exist_ok=True)
    skills_root = run_dir / "skills-sample"
    report_path = args.report.resolve() if args.report else run_dir / "regression-report.json"

    results: list[CheckResult] = []
    append_data_validation_checks(results)
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
    append_replay_verify_checks(results, args.replay_verify_executable)

    if not args.skip_benchmark:
        append_benchmark_check(
            results,
            run_dir / "benchmark",
            benchmark_case_limit=args.benchmark_case_limit,
            openclaw_executable=args.openclaw_executable,
        )

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
