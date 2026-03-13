# core/orchestrator/

统一调度三种模式，管理状态与流程。

## 当前实现（Phase 4.1 ~ 4.3）
- `ModeStateMachine.swift`：三模式状态机（`teaching` / `assist` / `student`）。
- 合法切换与守卫条件校验：不满足时拒绝切换并输出结构化日志。
- 每种模式能力白名单：限制可调用能力集合。
- 日志接口：`OrchestratorStateLogger`，默认 `StdoutOrchestratorStateLogger` 输出 JSON 行日志。
- `AssistModeLoop.swift`：辅助模式闭环（历史知识检索预测 -> 弹窗确认 -> 执行 -> 回写日志）。
- `AssistKnowledgeRetriever.swift`：辅助模式历史知识检索器。
- `RetrievalBasedAssistPredictor.swift`：基于检索结果生成个性化下一步建议。
- `StudentModeLoop.swift`：学生模式闭环（目标输入 -> 自动规划 -> 技能执行 -> 审阅报告）。

## 文档
- 设计说明：`mode-state-machine-v0.md`
- 设计说明：`assist-mode-loop-v0.md`
- 设计说明：`assist-knowledge-retrieval-v1.md`
- 设计说明：`student-mode-loop-v0.md`
