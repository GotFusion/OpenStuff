# Capture Event Model v0

本文定义阶段 1.1 的三类事件模型：`RawEvent`、`ContextSnapshot`、`NormalizedEvent`。

## 1. 设计目标

- 覆盖最小采集能力：鼠标点击、前台应用、时间戳、会话 ID。
- 原始事件与标准化事件分层，便于后续规则升级和 LLM 消费。
- 保留 schemaVersion，支持未来版本演进。

## 2. 模型关系

```text
RawEvent
  └── contextSnapshot: ContextSnapshot

NormalizedEvent
  ├── sourceEventId -> RawEvent.eventId
  ├── contextSnapshot: ContextSnapshot
  └── target.semanticTargets[]: SemanticTarget
```

## 3. RawEvent（原始事件）

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| schemaVersion | string | 是 | 固定为 `capture.raw.v0` |
| eventId | string | 是 | 原始事件唯一 ID（UUID） |
| sessionId | string | 是 | 会话 ID（同一教学过程共享） |
| timestamp | string | 是 | ISO-8601 时间戳 |
| source | enum | 是 | 当前固定 `mouse` |
| action | enum | 是 | `leftClick` / `rightClick` / `doubleClick` |
| pointer | object | 是 | 点击坐标（屏幕坐标系） |
| contextSnapshot | ContextSnapshot | 是 | 前台上下文 |
| modifiers | string[] | 否 | 点击时按下的修饰键 |

## 4. ContextSnapshot（上下文快照）

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| appName | string | 是 | 应用名称（例：`Safari`） |
| appBundleId | string | 是 | 应用 Bundle ID |
| windowTitle | string \| null | 否 | 前台窗口标题 |
| windowId | string \| null | 否 | 系统窗口 ID（可空） |
| isFrontmost | bool | 是 | 是否前台窗口 |

## 5. NormalizedEvent（标准化事件）

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| schemaVersion | string | 是 | 固定为 `capture.normalized.v0` |
| normalizedEventId | string | 是 | 标准化事件唯一 ID |
| sourceEventId | string | 是 | 对应 `RawEvent.eventId` |
| sessionId | string | 是 | 会话 ID |
| timestamp | string | 是 | 标准化时间戳 |
| eventType | enum | 是 | 当前固定 `click` |
| target | object | 是 | 保留坐标并可附带多候选 `SemanticTarget` |
| contextSnapshot | ContextSnapshot | 是 | 标准化后上下文 |
| confidence | number | 是 | 归一化置信度（0 ~ 1） |
| normalizerVersion | string | 是 | 归一化规则版本（如 `rule-v0`） |

## 6. v0 约束

- `RawEvent.action=leftClick` 是 MVP 必须覆盖路径。
- `sessionId` 在同一会话内不变。
- `timestamp` 必须带时区偏移。
- `contextSnapshot.appName` 和 `contextSnapshot.appBundleId` 必须同时存在。
- 新写入的点击 `NormalizedEvent` 应同时保留：
  - `target.coordinate`
  - 至少一个 `target.semanticTargets[]`
- 旧 `capture.normalized.v0` 数据允许缺省 `semanticTargets`，读取时按空数组兼容。

## 7. 文件位置

- Swift 类型定义：`core/contracts/CaptureEventContracts.swift`
- 语义定位说明：`core/capture/semantic-target-v0.md`
- JSON Schema：`core/capture/schemas/*.schema.json`
- 示例数据：`core/capture/examples/*.jsonl`
