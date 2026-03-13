# core/capture/

负责采集老师在 macOS 上的操作行为。

## 当前状态（Phase 1.1 / 1.2 / 7.2 已完成）
- 已定义事件模型：`RawEvent`、`ContextSnapshot`、`NormalizedEvent`。
- 已定义语义定位模型：`SemanticTarget`。
- 已补充窗口稳定签名、焦点元素属性、截图锚点与结构化降级诊断。
- 已补充 JSON Schema：`schemas/*.schema.json`。
- 已提供样例数据：`examples/*.jsonl`。
- 已落地跨模块 Swift 契约：`core/contracts/CaptureEventContracts.swift`。
- 已落地最小采集引擎 CLI：`apps/macos/Sources/OpenStaffCaptureCLI/`。

## 关键文档
- 事件模型说明：`event-model-v0.md`
- 语义定位说明：`semantic-target-v0.md`
- 采集引擎说明：`capture-engine-v0.md`
- schema：`schemas/raw-event.schema.json`
- schema：`schemas/context-snapshot.schema.json`
- schema：`schemas/normalized-event.schema.json`
- schema：`schemas/semantic-target.schema.json`

## 未来实现
- JSONL 落盘与轮转（TODO 1.3）。
- 标准化事件持久化与知识层消费链路。
