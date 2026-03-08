# ADR-0004 Execution Safety Baseline

- Status: Accepted
- Date: 2026-03-08
- Owners: OpenStaff Core Team

## Context

OpenStaff 在辅助模式与学生模式下会触发自动化执行。若没有统一安全控制，存在以下风险：
- 高风险指令误执行（删除、系统级命令、支付相关动作）。
- 用户希望立即停止执行时缺少统一中断入口。
- 不同执行器对“可执行动作”的判断标准不一致。

## Decision

建立 Phase 6.1 的统一执行安全基线：

1. 高风险动作拦截规则（执行层强制）
- 在 `AssistActionExecutor` 与 `StudentSkillExecutor` 中统一启用：
  - 关键词拦截（中文业务词 + 常见高危命令片段）。
  - 正则拦截（`rm -rf`、`sudo`、`shutdown/reboot`、`dd if=` 等模式）。
- 命中规则时统一返回阻断状态与 `EXE-ACTION-BLOCKED`。

2. 紧急停止机制（多入口）
- 执行上下文增加 `emergencyStopActive`，为 `true` 时直接阻断执行。
- GUI 提供紧急停止按钮（可见状态）与解除按钮。
- GUI 注册全局快捷键 `Cmd+Shift+.` 触发紧急停止。

3. 行为约束
- 紧急停止是“执行层最终守门”，优先级高于普通执行逻辑。
- 紧急停止激活期间，模式切换守卫应视为 `emergencyStopActive=true`。

## Consequences

### Positive
- 高风险动作具备统一最小防线，降低误操作概率。
- 用户有明确、快速的紧急中断能力。
- 执行器安全行为一致，便于测试与审计。

### Negative
- 关键词/正则策略会产生误拦截，需要后续白名单与二次确认策略优化。
- 全局快捷键监听在权限受限场景下可能不可用，需要降级提示。

## Follow-up

- Phase 6.2 增加安全规则单元测试（关键词、正则、紧急停止）。
- Phase 6.3 补充可配置规则文件与白名单机制（按任务/应用维度）。
