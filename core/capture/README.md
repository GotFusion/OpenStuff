# core/capture/

负责采集老师在 macOS 上的操作行为。

## 当前状态（Phase 1.1 已完成）
- 已定义事件模型：`RawEvent`、`ContextSnapshot`、`NormalizedEvent`。
- 已补充 JSON Schema：`schemas/*.schema.json`。
- 已提供样例数据：`examples/*.jsonl`。
- 已落地跨模块 Swift 契约：`core/contracts/CaptureEventContracts.swift`。

## 关键文档
- 事件模型说明：`event-model-v0.md`
- schema：`schemas/raw-event.schema.json`
- schema：`schemas/context-snapshot.schema.json`
- schema：`schemas/normalized-event.schema.json`

## 未来实现
- 全局鼠标点击事件采集。
- 活动窗口与应用上下文采集。
- 截图或 UI 元素定位信息（按隐私策略可开关）。
- 标准化事件格式输出，供知识层消费。
