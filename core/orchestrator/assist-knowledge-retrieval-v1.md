# OpenStaff 辅助模式历史知识检索 v1（Phase 9.1）

## 1. 目标

把辅助模式的“下一步预测”从单条规则提升为“基于历史知识检索的个性化建议”。

实现位置：
- `core/contracts/AssistPredictionContracts.swift`
- `core/orchestrator/AssistKnowledgeRetriever.swift`
- `core/orchestrator/RetrievalBasedAssistPredictor.swift`

## 2. 查询输入

检索器显式消费以下信号：
- 当前 app / bundleId
- 当前窗口标题
- 当前任务目标
- 最近已完成步骤序列
- 当前已完成步数

这些输入统一收口到 `AssistPredictionInput`，由 `AssistModeLoop` 在进入预测前组装。

## 3. 检索策略

每条 `KnowledgeItem` 只取“当前步数之后的下一步”作为候选，再按多信号打分：

- `app`
  - 前台 `bundleId` 精确匹配最高分。
  - 仅 `appName` 匹配给次高分。
- `window`
  - 先做窗口标题精确/包含匹配。
  - 再做轻量文本相似度匹配。
- `recentSequence`
  - 把老师最近步骤与候选知识的历史前缀做后缀对齐。
- `goal`
  - 用当前任务目标与 `KnowledgeItem.goal` 做轻量文本相似度比较。
- `historicalPreference`
  - 若多条历史知识在同一位置收敛到同一步，则提升该候选分数。

输出按 `score desc -> createdAt desc -> knowledgeItemId asc` 排序，保证稳定可复现。

## 4. 预测输出

`RetrievalBasedAssistPredictor` 会把检索结果压缩为：
- `AssistSuggestion`
- `action.reason`
- `evidence[]`

其中 `evidence` 会保留：
- 来自哪条 `knowledgeItem`
- 对应 `taskId / sessionId / stepId`
- 命中的信号
- 单条证据分数

辅助模式确认弹窗与 CLI summary 会直接展示：
- 推荐理由
- 历史来源知识 ID

## 5. 当前边界

- 仍是规则化检索，不依赖外部模型。
- 最近动作序列暂由调用方传入，后续可接入实时观察缓存。
- 历史偏好基于“相同步骤签名”的频次，不区分显式老师反馈权重。
