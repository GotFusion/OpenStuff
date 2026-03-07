# apps/macos/

macOS GUI + CLI package built with SwiftUI and Swift 6.

## Run

From repository root:

```bash
make dev
make capture
make slice
make knowledge
```

## Build

```bash
make build
```

## Layout

- `Package.swift`: Swift package entry for macOS app shell.
- `Sources/OpenStaffApp/OpenStaffApp.swift`: Phase 5.1 dashboard UI（模式切换、状态展示、权限状态、最近任务）。
- `Sources/OpenStaffCaptureCLI/`: Phase 1.3 capture CLI (permission check, click capture, context snapshot, JSONL persistence + rotation).
- `Sources/OpenStaffTaskSlicerCLI/`: Phase 2.1 task slicer CLI (session events -> TaskChunk files).
- `Sources/OpenStaffKnowledgeBuilderCLI/`: Phase 2.2 knowledge builder CLI (TaskChunk -> KnowledgeItem).

## Capture CLI

```bash
# Start capture with auto-stop at 20 events
make capture ARGS="--max-events 20"

# Print RawEvent JSONL lines
make capture ARGS="--json --max-events 20"

# Configure output root and rotation policy
make capture ARGS="--output-dir data/raw-events --rotate-max-bytes 1048576 --rotate-max-seconds 1800"
```

If accessibility permission is missing, CLI prints a clear error and points to:
`System Settings > Privacy & Security > Accessibility`.

Captured raw events are stored under:
- `data/raw-events/{yyyy-mm-dd}/{sessionId}.jsonl`
- `data/raw-events/{yyyy-mm-dd}/{sessionId}-r0001.jsonl` ... (rotation)

## Task Slicer CLI

```bash
# Slice one session into task chunks
make slice ARGS="--session-id session-20260307-a1 --date 2026-03-07"

# Adjust idle threshold and print generated TaskChunk JSON lines
make slice ARGS="--session-id session-20260307-a1 --idle-gap-seconds 30 --json"
```

Task chunks are written to:
- `data/task-chunks/{yyyy-mm-dd}/{taskId}.json`

## Knowledge Builder CLI

```bash
# Build KnowledgeItem files from task chunks
make knowledge ARGS="--session-id session-20260307-a1 --date 2026-03-07"

# Print generated KnowledgeItem JSON lines (including summary)
make knowledge ARGS="--session-id session-20260307-a1 --json"
```

Knowledge items are written to:
- `data/knowledge/{yyyy-mm-dd}/{taskId}.json`

## GUI Status (Phase 5.1)

- Three-mode switcher: `teaching / assist / student`（复用状态机守卫）。
- Current status card: 当前模式、状态码、能力白名单、未满足守卫信息。
- Permission status card: 辅助功能权限 + 数据目录可写性。
- Recent task panel: 汇总 `data/logs/**/*.log` 与 `data/knowledge/**/*.json`。
