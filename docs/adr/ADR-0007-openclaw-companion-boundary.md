# ADR-0007：OpenClaw Companion 集成边界

- 状态：Accepted
- 日期：2026-03-13
- 阶段：Phase 8.1

## 背景

OpenStaff 的核心价值是观察老师、沉淀知识、在执行前后做校验与审阅。OpenClaw 的核心价值是提供执行 runtime、工具渠道和 agent action dispatch。

如果二者边界不明确，会出现三个问题：

1. OpenStaff 直接绑定 OpenClaw 内部实现，后续 runtime 升级会牵连学习链路。
2. OpenClaw 直接读取 `raw-events/knowledge`，会把学习层与执行层耦合成单体，审计路径也会变脏。
3. skill 一旦被修复、重放或二次生成，来源知识条目与老师原始轨迹难以回溯。

因此，Phase 8.1 必须先固定 companion boundary，再推进真实执行联调。

## 决策

### 1) 职责切分

OpenStaff 负责：

- 教学模式采集与本地存储。
- `RawEvent -> TaskChunk -> KnowledgeItem` 的学习链路。
- ChatGPT 提示词编排与 skill 构建。
- 执行前 preflight、replay verify 与老师确认。
- 执行后日志回收、审阅、修复与知识回灌。

OpenClaw 负责：

- skill runtime 执行。
- 工具/渠道访问（本地 CLI、桌面控制、远程节点等）。
- 执行阶段的 stdout / stderr / exit code / runtime log 产出。

明确禁止：

- OpenClaw 直接读取 `data/raw-events`、`data/task-chunks`、`data/knowledge` 作为运行时输入。
- OpenStaff 依赖 OpenClaw 内部 memory、planner、数据库 schema 或私有目录结构。

### 2) 边界协议采用 skill bundle

OpenStaff 输出 skill bundle 目录，作为跨边界唯一稳定输入：

- `SKILL.md`
  - 面向 OpenClaw runtime 与人工审阅。
  - 保留目标、步骤、失败策略、最小 provenance 摘要。
- `openstaff-skill.json`
  - 面向 OpenStaff 审计、回放、修复。
  - 是 OpenStaff 自有契约，不要求 OpenClaw 解析全部字段，但要求目录在执行后仍可保留。

OpenClaw 对 OpenStaff 的回传输出采用结构化执行结果，Phase 8.2 再固化为 `OpenClawExecutionRequest/Result` 契约；在此之前，OpenStaff 不假设任何 OpenClaw 私有内部对象。

### 3) skill provenance 固定为 v1 审计契约

`openstaff-skill.json` 必须包含以下 provenance：

- `knowledge`
  - `knowledgeItemId`
  - `knowledgeSchemaVersion`
  - `taskId`
  - `sessionId`
  - `knowledgeCreatedAt`
  - `knowledgeGeneratorVersion`
- `sourceTrace`
  - `taskChunkSchemaVersion`
  - `startTimestamp`
  - `endTimestamp`
  - `eventCount`
  - `boundaryReason`
- `skillBuild`
  - `skillName`
  - `skillSchemaVersion`
  - `skillGeneratorVersion`
  - `generatedAt`
  - `repairVersion`
  - `llmOutputAccepted`
- `stepMappings[]`
  - `skillStepId`
  - `knowledgeStepId`
  - `instruction`
  - `sourceEventIds`
  - `preferredLocatorType`
  - `coordinate`
  - `semanticTargets`

这使任意一条 skill 都能沿着：

`skill -> knowledgeItem -> task/session -> sourceEventIds -> raw event`

回溯到老师原始示教轨迹。

### 4) repairVersion 归 OpenStaff 管理

- 初次生成 skill 时，`repairVersion = 0`。
- 任何由 OpenStaff 触发的修复动作（例如 preflight 自动修补、老师审阅后确认修订、skill drift repair）都必须递增该版本。
- OpenClaw 只消费当前 skill，不负责维护 repair lineage。

## 影响

### 正面

- 学习层与执行层解耦，OpenClaw 可以替换或升级而不影响知识建模。
- 每个 skill 都具备稳定 provenance，后续 preflight、repair、review 可以共享同一审计底座。
- OpenStaff 可以保留“老师原始行为 -> 当前 skill -> 实际执行结果”的完整闭环。

### 负面

- skill bundle 变得更重，生成与校验逻辑会比 v0 更复杂。
- OpenClaw 不能直接跳过 OpenStaff 读取原始知识库，意味着边界外的快速试验需要额外适配。

## 后续

- Phase 8.2：定义 `OpenClawRunner`、`OpenClawExecutionRequest`、`OpenClawExecutionResult`。
- Phase 8.3：在此 boundary 上补齐 skill preflight、repair policy 与高风险动作守门。
