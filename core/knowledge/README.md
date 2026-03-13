# core/knowledge/

负责将采集到的操作事件转换为“可学习知识”。

## 当前实现（Phase 2.1 / 2.2）
- 已定义任务切片结构：`TaskChunk`（见 `core/contracts/KnowledgeTaskContracts.swift`）。
- 已定义切片规则文档：`core/knowledge/task-slicer-v0.md`。
- 已定义知识条目结构：`KnowledgeItem`（见 `core/contracts/KnowledgeItemContracts.swift`）。
- 已为点击步骤补充语义目标载体：`KnowledgeStep.target`（坐标 + `SemanticTarget[]`）。
- 已定义知识条目文档：`core/knowledge/knowledge-item-v0.md`。
- 已定义规则摘要文档：`core/knowledge/summary-generator-v0.md`。
- 已提供 CLI：
  - `OpenStaffTaskSlicerCLI`（读取 session raw-events，输出 task chunk 文件）。
  - `OpenStaffKnowledgeBuilderCLI`（读取 task chunk，输出 knowledge item 文件）。

## 后续实现
- 输出可供 LLM 解析的结构化提示上下文。
- 转换为 OpenClaw skills 所需中间格式。
