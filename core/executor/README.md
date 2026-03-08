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

## 后续实现
- 执行回滚与中断机制。
- 更细粒度高风险动作保护（白名单、二次确认、沙箱演练）。
