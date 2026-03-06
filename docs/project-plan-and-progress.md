# OpenStaff 项目方案与实现进展

## 1. 项目目标

OpenStaff 的定位是“老师-学生”式个人助理：
- 老师：真实用户。
- 学生：OpenStaff 软件。

学生通过观察老师在 macOS 上的操作行为进行学习，沉淀为结构化知识，再在不同模式下辅助或自主执行任务。

---

## 2. 三种核心模式

### 2.1 教学模式（Learning）
- 老师主导操作电脑。
- 学生被动观察并记录行为事件（点击、上下文、步骤顺序）。
- 自动完成分类、分析、总结，形成知识条目。

### 2.2 辅助模式（Assist）
- 老师继续主导操作。
- 学生基于历史知识预测下一步动作。
- 学生发起确认：“是否需要我执行下一步？”
- 老师同意后，学生执行动作并记录反馈。

### 2.3 学生模式（Autonomous）
- 学生根据学习到的知识自主执行任务。
- 执行后输出过程日志与结果摘要供老师审阅。

---

## 3. 最小可行能力（MVP）

优先实现顺序：
1. **操作采集**：记录屏幕点击与上下文信息。
2. **知识格式化存储**：将采集结果写入统一格式文件。
3. **知识解析脚本**：通过 ChatGPT 提示词把知识文件解析为结构化步骤。
4. **OpenClaw skill 转换**：将结构化步骤映射为 OpenClaw skills。
5. **执行闭环**：OpenClaw 消费 skills 并回传执行日志。

---

## 4. 技术架构草案

### 4.1 分层
- 应用层（GUI）：模式切换、确认交互、日志审阅。
- 核心层（Core）：采集、知识、编排、执行、存储。
- 脚本层（Scripts）：LLM 解析、skill 生成、批量工具。
- 集成层（Vendor）：对接 `vendors/openclaw`。

### 4.2 数据流
1. Capture 采集事件。
2. Knowledge 归档成知识条目。
3. Orchestrator 按模式调度。
4. Scripts/LLM 进行知识理解与结构化。
5. Scripts/Skills 产出 OpenClaw skills。
6. Executor 执行并记录日志。
7. Storage 持久化并供 GUI 展示。

---

## 5. 知识文件建议格式（草案）

建议采用 `JSONL` 便于流式追加与审计，单行一条事件或步骤，例如：

- `schemaVersion`：事件 schema 版本（如 `capture.raw.v0`）。
- `eventId`：事件唯一 ID。
- `sessionId`：学习会话 ID。
- `timestamp`：事件时间。
- `contextSnapshot.appName`：应用名。
- `contextSnapshot.windowTitle`：窗口标题。
- `action`：点击/输入/快捷键等动作。
- `target`：操作目标（v0 使用坐标）。
- `confidence`：标准化置信度（`NormalizedEvent`）。

详细字段定义见 `core/capture/event-model-v0.md` 与 `core/capture/schemas/*.schema.json`。

---

## 6. 与 ChatGPT / OpenClaw 协作方案

1. 将知识文件输入提示词模板。
2. 让 ChatGPT 解析为标准任务步骤（含前置条件、执行顺序、失败处理）。
3. 将解析结果转为 OpenClaw 所需 skills 格式。
4. 在辅助/学生模式触发 OpenClaw 执行。
5. 回收日志并反馈到知识库，形成“学习-执行-再学习”闭环。

---

## 7. 风险与约束

- **隐私风险**：屏幕与输入采集需明确权限、脱敏策略与本地存储优先。
- **误操作风险**：辅助/学生模式必须保留确认与紧急停止机制。
- **知识漂移**：软件更新导致 UI 变化时，旧知识可能失效，需要版本化。
- **模型不确定性**：LLM 解析结果需校验、回退与人工审阅机制。

---

## 8. 当前实现进展（本次）

### 已完成
- 完成项目目录结构初始化。
- 为核心目录与子目录补充职责说明文档（README）。
- 在 `docs/` 建立本方案文档，记录目标、架构、MVP 与风险。
- 完成阶段 0 技术栈 ADR：`docs/adr/ADR-0000-tech-stack.md`。
- 完成编码规范文档：`docs/coding-conventions.md`。
- 新增 `core/contracts/` 共享契约目录与 `data/` 本地数据目录基线。
- 在 `apps/macos` 落地 SwiftUI 最小空应用，并提供统一启动命令 `make dev`。
- 完成阶段 1.1 事件模型定义：`RawEvent` / `ContextSnapshot` / `NormalizedEvent`。
- 新增事件 schema 文档、JSON Schema、样例 JSONL 与 `ADR-0001-event-schema.md`。

### 未开始
- 采集引擎代码实现。
- 事件采集进程（权限检查、点击监听、上下文抓取）。
- JSONL 落盘与 session 分文件轮转。
- 知识 schema 定义与任务切片实现。
- 与 ChatGPT 的脚本联通。
- OpenClaw skills 转换与执行联调。
- 业务级 GUI 原型与前端实现。

### 下一步建议
1. 开始 TODO 1.2：实现权限检查与全局点击监听，产出 `RawEvent`。
2. 在采集器中补 `ContextSnapshot` 读取（前台 app + windowTitle + windowId）。
3. 开始 TODO 1.3：按 `sessionId` 写入 `data/raw-events/{date}/{sessionId}.jsonl`。
4. 新增 schema 校验脚本（`scripts/validation`）并在写盘前执行快速校验。

---

## 9. 架构合理性评审与执行清单

- 架构与目录合理性评审请见：`docs/architecture-review.md`。
- 详细编码 TODO 清单请见：`docs/implementation-todo-checklist.md`。
- 建议按 TODO 阶段顺序推进，每完成一个阶段回写本文件“当前实现进展”。
