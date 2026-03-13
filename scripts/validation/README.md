# scripts/validation/

数据链路与执行前门禁校验脚本。

## 脚本

- `validate_raw_event_logs.py`
  - 校验 `capture.raw.v0` JSONL。
  - `strict` 模式面向样例/新格式。
  - `compat` 模式面向历史存量数据，允许旧键盘事件缺少 `keyboard.isSensitiveInput`，但会输出告警。
- `validate_knowledge_items.py`
  - 校验 `knowledge.item.v0` JSON。
  - 对缺失 `target` 的历史知识条目输出告警，避免直接卡死发布门禁。
- `validate_skill_bundle.py`
  - 执行前 skill preflight，检查 locator、风险、白名单与自动执行条件。
- `run_replay_verify_check.py`
  - 包装 `OpenStaffReplayVerifyCLI`，将 replay verify 结果标准化为可供 release preflight 消费的报告。

## 推荐命令

```bash
make validate-raw-events
make validate-knowledge
make validate-replay-sample ARGS="--replay-verify-executable apps/macos/.build/debug/OpenStaffReplayVerifyCLI"
```

发布门禁统一入口：

```bash
make release-preflight ARGS="--openclaw-executable apps/macos/.build/debug/OpenStaffOpenClawCLI --replay-verify-executable apps/macos/.build/debug/OpenStaffReplayVerifyCLI"
```
