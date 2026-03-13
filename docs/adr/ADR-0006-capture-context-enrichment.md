# ADR-0006：采集上下文增强与降级策略

- 状态：Accepted
- 日期：2026-03-13
- 阶段：Phase 7.2

## 背景

仅有 `appName/windowTitle/windowId` 的采集上下文不足以支撑后续语义定位修复：

- 同一应用中的多个窗口难以区分。
- 点击目标只有坐标，没有当前焦点元素的可读属性。
- 视觉回放无法做轻量比对。
- 权限受限时，缺少结构化降级原因。

同时，OpenStaff 仍需遵守本地优先和隐私最小化原则，避免采集高敏感原文输入或完整屏幕截图。

## 决策

### 1) 扩展 `ContextSnapshot`

新增四类可选上下文：

- `windowSignature`
- `focusedElement`
- `screenshotAnchors`
- `captureDiagnostics`

这些字段均为向后兼容扩展，旧 `capture.raw.v0` / `capture.normalized.v0` 数据可以缺省。

### 2) 轻量截图锚点只存指纹，不存原图

截图锚点采用小区域派生特征，而不是原始像素文件：

- 保存捕获区域矩形
- 保存采样尺寸
- 保存像素哈希
- 保存平均亮度

不落盘原始截图，以降低隐私风险和存储成本。

### 3) 键盘输入仅对高敏感场景脱敏

对 `AXSecureTextField` 等高敏感输入场景：

- `KeyboardEventPayload.characters = nil`
- `KeyboardEventPayload.charactersIgnoringModifiers = nil`
- `isSensitiveInput = true`
- `redactionReason = "secureTextField"`

普通非敏感输入仍保留原有最小键盘语义，以免完全破坏知识构建链路。

### 4) 降级必须结构化记录错误码

当 AX 或截图锚点不可用时，不直接丢弃事件，而是写入 `captureDiagnostics[]`。

首批错误码：

- `CTX-FRONTMOST-APP-UNAVAILABLE`
- `CTX-AX-CAPTURE-DISABLED`
- `CTX-AX-WINDOW-UNAVAILABLE`
- `CTX-AX-WINDOW-SIGNATURE-UNAVAILABLE`
- `CTX-AX-FOCUSED-ELEMENT-UNAVAILABLE`
- `CTX-SCREENSHOT-PERMISSION-DENIED`
- `CTX-SCREENSHOT-CAPTURE-FAILED`

## 影响

- 阶段 7.3 的 `SemanticTargetResolver` 可以优先利用窗口签名和焦点元素属性。
- 教学模式与 CLI 采集链路统一写出同一 `RawEvent` 结构。
- 未来若引入完整截图或图像锚点，只需要在现有 `screenshotAnchors` 和 `captureDiagnostics` 体系上演进。
