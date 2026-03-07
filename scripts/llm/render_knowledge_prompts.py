#!/usr/bin/env python3
"""
Render stable system/user prompts for KnowledgeItem -> LLM structured parse.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_SYSTEM_TEMPLATE = SCRIPT_DIR / "prompts" / "system-knowledge-parser-v0.md"
DEFAULT_TASK_TEMPLATE = SCRIPT_DIR / "prompts" / "task-knowledge-parser-v0.md"
DEFAULT_OUTPUT_SCHEMA = SCRIPT_DIR / "schemas" / "knowledge-parse-output.schema.json"


def load_json(path: Path) -> object:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def load_text(path: Path) -> str:
    with path.open("r", encoding="utf-8") as f:
        return f.read()


def render_task_prompt(
    task_template: str,
    knowledge_item: object,
    output_schema: object,
) -> str:
    knowledge_json = json.dumps(knowledge_item, ensure_ascii=False, indent=2, sort_keys=True)
    schema_json = json.dumps(output_schema, ensure_ascii=False, indent=2, sort_keys=True)
    return (
        task_template.replace("{{KNOWLEDGE_ITEM_JSON}}", knowledge_json).replace(
            "{{OUTPUT_SCHEMA_JSON}}", schema_json
        )
    )


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        f.write(content.rstrip() + "\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render prompt files for LLM knowledge parsing."
    )
    parser.add_argument(
        "--knowledge-item",
        required=True,
        type=Path,
        help="Path to KnowledgeItem JSON input.",
    )
    parser.add_argument(
        "--system-template",
        default=DEFAULT_SYSTEM_TEMPLATE,
        type=Path,
        help=f"System prompt template path (default: {DEFAULT_SYSTEM_TEMPLATE}).",
    )
    parser.add_argument(
        "--task-template",
        default=DEFAULT_TASK_TEMPLATE,
        type=Path,
        help=f"Task prompt template path (default: {DEFAULT_TASK_TEMPLATE}).",
    )
    parser.add_argument(
        "--output-schema",
        default=DEFAULT_OUTPUT_SCHEMA,
        type=Path,
        help=f"Output schema path (default: {DEFAULT_OUTPUT_SCHEMA}).",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        help="Optional output directory. If provided, writes system/user prompt files.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    knowledge_item = load_json(args.knowledge_item)
    output_schema = load_json(args.output_schema)
    system_prompt = load_text(args.system_template).strip() + "\n"
    task_template = load_text(args.task_template)
    user_prompt = render_task_prompt(task_template, knowledge_item, output_schema)

    if args.out_dir:
        system_output = args.out_dir / "system.prompt.md"
        user_output = args.out_dir / "user.prompt.md"
        write_text(system_output, system_prompt)
        write_text(user_output, user_prompt)
        print(f"Rendered system prompt: {system_output}")
        print(f"Rendered user prompt:   {user_output}")
        return 0

    print("=== SYSTEM PROMPT ===")
    print(system_prompt.rstrip())
    print()
    print("=== USER PROMPT ===")
    print(user_prompt.rstrip())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
