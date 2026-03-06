# ADR-0001：采集事件模型（RawEvent / ContextSnapshot / NormalizedEvent）

- 状态：Accepted
- 日期：2026-03-07
- 阶段：Phase 1.1

## 背景

阶段 1.1 要求建立采集链路最关键的数据模型，后续 1.2 采集引擎与 1.3 落盘都依赖此模型。

必须满足最小覆盖：
- 鼠标点击
- 前台应用
- 时间戳
- 会话 ID

## 决策

### 1) 采用三层模型

- `RawEvent`：采集层输出，保留原始语义。
- `ContextSnapshot`：可复用上下文对象（应用/窗口/前台状态）。
- `NormalizedEvent`：标准化后供知识层与后续脚本消费。

### 2) 时间与标识规则

- 时间字段统一 `timestamp`，格式 ISO-8601（带时区偏移）。
- `eventId` / `normalizedEventId` 使用 UUID。
- `sessionId` 使用小写字母+数字+短横线。

### 3) 版本策略

- `RawEvent.schemaVersion` 固定 `capture.raw.v0`。
- `NormalizedEvent.schemaVersion` 固定 `capture.normalized.v0`。
- 破坏性变更时升级到 `v1`，并保留迁移脚本。

### 4) 目标描述策略（v0）

- `NormalizedEvent.target.kind` 固定 `coordinate`。
- 暂不做 UI 语义目标（如按钮语义名），待后续视觉/辅助功能信息稳定后再扩展。

## 产物落地

- 事件模型说明：`core/capture/event-model-v0.md`
- JSON Schema：
  - `core/capture/schemas/raw-event.schema.json`
  - `core/capture/schemas/context-snapshot.schema.json`
  - `core/capture/schemas/normalized-event.schema.json`
- Swift 契约：`core/contracts/CaptureEventContracts.swift`
- 示例数据：`core/capture/examples/*.jsonl`

## 影响

- 阶段 1.2 可直接按该模型实现采集器输出。
- 阶段 1.3 可按 schema 校验 JSONL 文件完整性。
- 知识层和脚本层可在 `NormalizedEvent` 基础上向上建模。
