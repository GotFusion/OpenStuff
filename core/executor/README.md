# core/executor/

负责自动化操作执行（模拟输入与脚本触发）。

## 当前实现（Phase 4.2 ~ 4.3）
- `AssistActionExecutor.swift`：辅助模式动作执行器（默认 dry-run），支持：
  - 老师确认后执行建议动作。
  - 高风险关键词 + 正则规则拦截（返回 `EXE-ACTION-BLOCKED`）。
  - 紧急停止状态拦截（`emergencyStopActive`）。
  - 失败模拟（用于闭环验证）。
- `StudentSkillExecutor.swift`：学生模式技能执行器（OpenClaw 调用模拟），支持：
  - 按计划步骤顺序执行技能。
  - 高风险关键词 + 正则规则拦截。
  - 紧急停止状态拦截（`emergencyStopActive`）。
  - 指定步骤失败模拟（用于闭环验证）。
- `OpenClawRunner.swift`：阶段 8.2 的 OpenClaw 适配层，支持：
  - 通过子进程调用 OpenClaw CLI / gateway。
  - 捕获 stdout / stderr / exit code。
  - 写入 `data/logs/{date}/{sessionId}-openclaw.log` 结构化执行日志。
  - 产出 `OpenClawExecutionResult` 与 `OpenClawExecutionReview`。
- `SkillPreflightValidator.swift`：阶段 8.3 的统一预检器，支持：
  - `openstaff-skill.json` / `SKILL.md` 结构与 schema 一致性检查。
  - click locator 可解析性检查（语义 locator / 坐标回退）。
  - 高风险动作、低置信步骤、目标 App 白名单判断。
  - 产出 `SkillPreflightReport`，供 GUI / CLI / release-preflight 共享。
- `SemanticTargetResolver.swift`：阶段 7.3 语义定位解析器，支持
  `axPath -> roleAndTitle -> textAnchor -> imageAnchor -> coordinateFallback`
  的优先级解析与结构化失败原因。
- `ReplayVerifier.swift`：阶段 7.3 dry-run 回放验证器，对 `KnowledgeItem`
  做“不执行危险动作、只验证能否找到目标”的离线/实时校验。
- `replay-verifier-v0.md`：回放验证模型、状态码与 CLI 约定。

## 后续实现
- 执行回滚与中断机制。
- 更细粒度高风险动作保护（白名单、二次确认、沙箱演练）。
- repair flow 已由 `core/repair/*` 提供检测与建议；后续补齐“自动生成新 skill 并递增 repairVersion”。
