import json
import os
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
PACKAGE_PATH = REPO_ROOT / "apps/macos"
XCODE_DEVELOPER_DIR = Path("/Applications/Xcode.app/Contents/Developer")


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


def run_swift_target(target: str, args: list[str]) -> subprocess.CompletedProcess[str]:
    cmd = [
        "swift",
        "run",
        "--package-path",
        str(PACKAGE_PATH),
        target,
        *args,
    ]
    return subprocess.run(
        cmd,
        cwd=REPO_ROOT,
        env=build_swift_env(),
        capture_output=True,
        text=True,
        check=False,
    )


def extract_last_json_object(text: str) -> dict:
    end = text.rfind("}")
    if end == -1:
        raise ValueError(f"No JSON object found in output: {text}")

    for start in range(end, -1, -1):
        if text[start] != "{":
            continue
        candidate = text[start : end + 1]
        try:
            parsed = json.loads(candidate)
        except json.JSONDecodeError:
            continue
        if isinstance(parsed, dict):
            return parsed

    raise ValueError(f"No JSON object found in output: {text}")
