# OpenStaff 辅助模式闭环 v0（Phase 4.2）

> 注：Phase 9.1 已在 `assist-knowledge-retrieval-v1.md` 上补充“基于历史知识检索的下一步预测”。本文保留最小闭环设计背景。

## 1. 目标

实现辅助模式最小可演示闭环：
- 预测下一步（规则优先）。
- 弹窗确认（当前用 CLI mock）。
- 确认后执行。
- 回写结构化日志。

实现位置：
- `core/contracts/AssistModeContracts.swift`
- `core/orchestrator/AssistModeLoop.swift`
- `core/executor/AssistActionExecutor.swift`
- `core/storage/AssistLoopLogWriter.swift`
- `apps/macos/Sources/OpenStaffAssistCLI/*`

## 2. 闭环流程

1. `ModeStateMachine` 确保进入 `assist` 模式。  
2. `RuleBasedAssistNextActionPredictor` 生成 `AssistSuggestion`。  
3. `AssistPopupConfirmationPrompter` 生成确认决策（yes/no）。  
4. `AssistActionExecutor` 执行动作（默认 dry-run，可模拟失败）。  
5. `AssistLoopLogWriter` 将每一步写入 `data/logs/{date}/{sessionId}-assist.log`。  

## 3. 下一步预测策略（先规则后模型）

### 规则策略 `rule.v0`
- 规则 1：优先匹配前台 `appBundleId` 的 `KnowledgeItem`。
- 规则 2：在匹配项中按 `completedStepCount` 选下一步 `KnowledgeStep`。
- 规则 3：若无匹配，回退到第一条可用 `KnowledgeItem` 的下一步。

### 模型策略（预留）
- `modelV1Placeholder` 已在契约中预留，后续可接模型推理。

## 4. 确认与执行

- 确认器：`AssistPopupConfirmationPrompter`
  - `--auto-confirm yes|no`：用 CLI 参数模拟老师确认结果。
  - 未提供时：终端交互输入（mock popup）。
- 执行器：`AssistActionExecutor`
  - 默认 `dry-run`。
  - 可用 `--simulate-execution-failure` 验证失败回路。
  - 内置高风险关键词拦截（返回 `EXE-ACTION-BLOCKED`）。

## 5. 日志回写

日志格式：JSONL，单行一条 `AssistLoopLogEntry`。  
核心字段：
- `timestamp`
- `traceId`
- `sessionId`
- `taskId`
- `component`
- `status`
- `errorCode`（失败时）

常见状态码：
- `STATUS_ORC_ASSIST_PREDICTED`
- `STATUS_ORC_WAITING_CONFIRMATION`
- `STATUS_ORC_ASSIST_CONFIRMATION_ACCEPTED`
- `STATUS_ORC_ASSIST_CONFIRMATION_REJECTED`
- `STATUS_EXE_ASSIST_EXECUTION_STARTED`
- `STATUS_EXE_ASSIST_EXECUTION_COMPLETED`
- `STATUS_EXE_ASSIST_EXECUTION_FAILED`

## 6. CLI 验收

成功闭环（老师确认后执行）：

```bash
make assist ARGS="--knowledge-item core/knowledge/examples/knowledge-item.sample.json --auto-confirm yes"
```

拒绝闭环（老师拒绝，不执行）：

```bash
make assist ARGS="--knowledge-item core/knowledge/examples/knowledge-item.sample.json --auto-confirm no"
```

执行失败闭环（用于测试失败日志）：

```bash
make assist ARGS="--knowledge-item core/knowledge/examples/knowledge-item.sample.json --auto-confirm yes --simulate-execution-failure"
```
