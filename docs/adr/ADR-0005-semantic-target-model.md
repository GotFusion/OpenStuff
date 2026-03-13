# ADR-0005：Semantic Target 数据模型

- 状态：Accepted
- 日期：2026-03-13
- 阶段：Phase 7.1

## 背景

当前 OpenStaff 的点击知识仍主要依赖纯坐标。坐标可以保证最小可回放，但在窗口大小变化、界面重排、分辨率调整时容易漂移，导致：

- 辅助模式无法稳定预判下一步真实目标。
- 学生模式无法对历史知识做 dry-run 校验。
- OpenClaw skill 生成只能依赖脆弱的 `coordinate:x,y` 字符串。

因此需要一个统一的语义定位载体，让采集层、知识层和后续回放验证器使用同一套目标描述。

## 决策

### 1) 引入 `SemanticTarget`

定义独立共享契约 `SemanticTarget`，字段固定为：

- `locatorType`
- `appBundleId`
- `windowTitlePattern`
- `elementRole`
- `elementTitle`
- `elementIdentifier`
- `boundingRect`
- `confidence`
- `source`

其中 `locatorType` 的优先级约定为：

`axPath -> roleAndTitle -> textAnchor -> imageAnchor -> coordinateFallback`

### 2) 坐标与语义目标并存

- `NormalizedEvent.target.coordinate` 必须继续保留原始点击坐标。
- `NormalizedEvent.target.semanticTargets[]` 用于保存多个语义定位候选。
- `KnowledgeStep.target.coordinate` 与 `KnowledgeStep.target.semanticTargets[]` 复用同一策略。

这样可以保证：

- 坐标始终可作为最后回退。
- 更稳定的 locator 可以后续增量加入，而不必替换已有数据结构。

### 3) v0 默认写入 `coordinateFallback`

由于阶段 7.2 之前还没有完整 AX path、文本锚点和图像锚点，因此 v0 先约定：

- 每个点击步骤都自动生成一个 `coordinateFallback` 候选。
- `appBundleId` 与 `windowTitlePattern` 来自当前上下文。
- `boundingRect` 使用点击点对应的 `1x1` 屏幕矩形。
- `source = capture`
- `confidence = 0.24`

这满足了“任意点击事件同时保留坐标与至少一个语义候选”的最低要求。

### 4) 兼容策略

- 不升级 `capture.normalized.v0` 与 `knowledge.item.v0` 的 schemaVersion。
- 缺省 `semanticTargets` 的旧数据按空数组处理。
- 缺省 `KnowledgeStep.target` 的旧数据按 `nil` 处理。

本次属于向后兼容扩展，不要求批量重写历史文件。

## 影响

- 阶段 7.2 可以在现有数组上直接追加 AX/text/image locator。
- 阶段 7.3 的 `SemanticTargetResolver` 可以基于统一优先级做解析与 dry-run。
- skill 构建链路后续可以优先消费语义目标，而不是从自然语言 instruction 反向猜测目标。
