# Knowledge Item v0（TODO 2.2）

## 1. 目标

定义可被后续 LLM 与执行链路稳定消费的知识条目结构 `KnowledgeItem`。

要求：
- 固定 `schemaVersion`。
- 覆盖目标（goal）、步骤（steps）、上下文（context）、约束（constraints）。
- 能由任意 `TaskChunk` 映射得到合法 `KnowledgeItem`。

## 2. 核心结构

`KnowledgeItem` 字段：
- `schemaVersion`: 固定 `knowledge.item.v0`
- `knowledgeItemId`: 知识条目标识（v0：`ki-{taskId}`）
- `taskId`
- `sessionId`
- `goal`
- `summary`（老师可读摘要）
- `steps[]`
- `context`
- `constraints[]`
- `source`
- `createdAt`
- `generatorVersion`

定义见：`core/contracts/KnowledgeItemContracts.swift`

## 3. 映射规则（TaskChunk -> KnowledgeItem, rule-v0）

输入：`TaskChunk`

输出：`KnowledgeItem`

映射规则：
1. `knowledgeItemId = "ki-{taskId}"`
2. `goal`：基于主上下文生成（例如“在 Safari 中复现任务 task-xxx”）
3. `steps`：按 `eventIds` 顺序生成步骤；每步保留 `sourceEventIds`
   - 点击步骤额外保留 `target.coordinate`
   - 点击步骤额外保留 `target.semanticTargets[]`
4. `summary`：使用规则摘要器将步骤压缩为可读链路（如 `点击 -> 点击`），附带上下文和切分原因。
5. `context`：来自 `TaskChunk.primaryContext`
6. `constraints`（v0 固定三条）
   - 前台应用需匹配
   - 执行前需人工确认
   - 坐标目标可能漂移
7. `source`：保留 `TaskChunk` 边界与统计信息

## 4. 文件落地

- TaskChunk：`data/task-chunks/{yyyy-mm-dd}/{taskId}.json`
- KnowledgeItem：`data/knowledge/{yyyy-mm-dd}/{taskId}.json`

## 5. Schema 与样例

- JSON Schema：`core/knowledge/schemas/knowledge-item.schema.json`
- 示例文件：`core/knowledge/examples/knowledge-item.sample.json`
- 摘要规则：`core/knowledge/summary-generator-v0.md`
- 语义定位规则：`core/capture/semantic-target-v0.md`
