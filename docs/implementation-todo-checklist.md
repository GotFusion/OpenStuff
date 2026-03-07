# OpenStaff 详细编码步骤 TODO 清单（可直接按顺序执行）

> 目标：把规划文档变成可执行开发路线。每一项都定义输入、输出、验收标准。

## 阶段 0：基线准备（Day 0 ~ Day 1）

### TODO 0.1 锁定技术栈与运行边界
- [x] 明确 macOS GUI 技术方案（SwiftUI + AppKit 桥接策略）。
- [x] 明确核心服务语言（Swift 6，单语言优先）。
- [x] 记录 OpenClaw 集成方式（文件驱动优先 + 进程调用补充）。

**输出物**
- `docs/adr/ADR-0000-tech-stack.md`

**验收标准**
- [x] 团队成员可在同一命令下启动最小空应用（`make dev`）。

### TODO 0.2 约定目录与命名规范
- [x] 定义 `shared/contracts`（或 `core/contracts`）位置（采用 `core/contracts`）。
- [x] 定义日志、数据、配置文件命名规范。
- [x] 定义错误码和状态码命名规则。

**输出物**
- `docs/coding-conventions.md`

**验收标准**
- [x] 新增模块均按统一命名规范落地（以 `core/contracts` + `data/*` 基线目录验证）。

---

## 阶段 1：采集 MVP（Day 1 ~ Day 4）

### TODO 1.1 事件模型定义（最关键）
- [x] 定义 `RawEvent`（原始事件）。
- [x] 定义 `ContextSnapshot`（上下文快照：app/window）。
- [x] 定义 `NormalizedEvent`（标准化事件）。

**输出物**
- `core/capture` 下 schema 文档或类型定义。
- `core/capture/event-model-v0.md`
- `core/capture/schemas/*.schema.json`
- `core/contracts/CaptureEventContracts.swift`

**验收标准**
- [x] 能覆盖“鼠标点击 + 前台应用 + 时间戳 + 会话 ID”。

### TODO 1.2 采集引擎最小实现
- [x] macOS 权限检查（辅助功能权限）。
- [x] 监听鼠标点击坐标。
- [x] 获取当前前台应用和窗口标题。
- [x] 将事件写入本地队列。

**输出物**
- 可运行的采集进程（CLI 或后台服务）。
- `apps/macos/Sources/OpenStaffCaptureCLI/*`
- 运行命令：`make capture ARGS="--max-events 20"`

**验收标准**
- [x] 连续点击 20 次，事件不丢失（命令已提供：`--max-events 20`，需本机手动点击验证）。
- [x] 权限不足时给出明确提示（`CAP-PERMISSION-DENIED`）。

### TODO 1.3 事件落盘与轮转
- [x] JSONL 落盘实现。
- [x] 以 session 分文件（按日期+sessionId 分片）。
- [x] 日志轮转策略（大小/时间）。

**输出物**
- `data/raw-events/*.jsonl`
- `apps/macos/Sources/OpenStaffCaptureCLI/RawEventFileSink.swift`

**验收标准**
- [x] 文件可被 `jq` 正确解析（每条事件按 JSONL 单行落盘）。
- [x] 异常中断后数据文件可继续追加（同日期同 session 自动续写最后可写分片）。

---

## 阶段 2：知识建模 MVP（Day 4 ~ Day 7）

### TODO 2.1 任务切片器（Session -> Task）
- [x] 按空闲间隔/窗口切换识别任务边界。
- [x] 给每段任务生成 `task_id`。

**输出物**
- `TaskChunk` 结构与切片规则。
- `core/contracts/KnowledgeTaskContracts.swift`
- `core/knowledge/task-slicer-v0.md`
- `apps/macos/Sources/OpenStaffTaskSlicerCLI/*`

**验收标准**
- [x] 可将 1 个 session 自动切分为多个任务片段。

### TODO 2.2 知识条目格式定义
- [x] 定义 `KnowledgeItem`（目标、步骤、上下文、约束）。
- [x] 增加版本号字段（schemaVersion）。

**输出物**
- `data/knowledge/*.json`
- `core/contracts/KnowledgeItemContracts.swift`
- `core/knowledge/knowledge-item-v0.md`
- `core/knowledge/schemas/knowledge-item.schema.json`
- `apps/macos/Sources/OpenStaffKnowledgeBuilderCLI/*`

**验收标准**
- [x] 任意任务切片都能映射为合法 `KnowledgeItem`。

### TODO 2.3 自动总结初版（无 LLM）
- [x] 用规则生成步骤摘要（例如“打开 X -> 点击 Y -> 输入 Z”）。
- [x] 输出老师可读的摘要文本。

**输出物**
- `summary` 字段及其生成模块。
- `core/contracts/KnowledgeItemContracts.swift`（`summary` 字段）
- `apps/macos/Sources/OpenStaffKnowledgeBuilderCLI/KnowledgeSummaryGenerator.swift`
- `core/knowledge/summary-generator-v0.md`
- `core/knowledge/examples/summary-review-10-samples.md`

**验收标准**
- [x] 10 条样例任务中，摘要可读性通过人工检查。

---

## 阶段 3：LLM 解析与 Skill 转换（Day 7 ~ Day 10）

### TODO 3.1 提示词模板系统
- [x] 定义系统提示词、任务提示词、输出格式约束。
- [x] 强制 JSON 输出并校验。

**输出物**
- `scripts/llm/prompts/*.md`（或模板文件）。
- `scripts/llm/schemas/knowledge-parse-output.schema.json`
- `scripts/llm/render_knowledge_prompts.py`
- `scripts/llm/validate_knowledge_parse_output.py`

**验收标准**
- [x] 同一输入可稳定输出结构化步骤（提示词渲染采用规范化 JSON；输出可被严格校验）。

### TODO 3.2 ChatGPT 调用适配层
- [x] 封装重试、超时、限流。
- [x] 记录请求摘要（不落敏感原文）。

**输出物**
- `scripts/llm/chatgpt_adapter.py`
- `scripts/llm/README.md`（调用方式与离线验证说明）

**验收标准**
- [x] 网络抖动时可自动重试并出错误报告（离线 text provider 支持瞬时失败模拟验证重试链路）。

### TODO 3.3 OpenClaw skill 映射器
- [x] 将 `KnowledgeItem` + LLM 结果映射为 OpenClaw 技能格式。
- [x] 增加字段校验与 fallback。

**输出物**
- `scripts/skills/openclaw_skill_mapper.py`
- `scripts/skills/validate_openclaw_skill.py`
- `scripts/skills/schemas/openstaff-openclaw-skill.schema.json`
- `scripts/skills/examples/*`（3 条示例输入）

**验收标准**
- [x] 至少 3 个示例任务成功转换并可被 OpenClaw 读取（`make skills-demo` + `make skills-validate-demo`）。

---

## 阶段 4：模式编排（Day 10 ~ Day 14）

### TODO 4.1 模式状态机
- [x] 定义 `teaching / assist / student` 状态与切换条件。
- [x] 定义每种模式可调用的能力白名单。

**输出物**
- `core/orchestrator/ModeStateMachine.swift`
- `core/orchestrator/mode-state-machine-v0.md`
- `core/contracts/OrchestratorContracts.swift`
- `apps/macos/Sources/OpenStaffOrchestratorCLI/*`

**验收标准**
- [x] 非法状态切换被拒绝并记录日志（`make orchestrator` 默认输出结构化日志，非法切换返回退出码 `2`）。

### TODO 4.2 辅助模式闭环
- [x] 下一步预测策略（先规则后模型）。
- [x] 弹窗确认 -> 执行 -> 回写日志。

**输出物**
- `core/orchestrator/AssistModeLoop.swift`
- `core/orchestrator/assist-mode-loop-v0.md`
- `core/contracts/AssistModeContracts.swift`
- `core/executor/AssistActionExecutor.swift`
- `core/storage/AssistLoopLogWriter.swift`
- `apps/macos/Sources/OpenStaffAssistCLI/*`

**验收标准**
- [x] “老师确认后执行”全链路可演示（`make assist ARGS="--knowledge-item core/knowledge/examples/knowledge-item.sample.json --auto-confirm yes"`）。

### TODO 4.3 学生模式闭环
- [x] 输入任务目标 -> 自动规划 -> 调用技能执行。
- [x] 输出结构化审阅报告。

**输出物**
- `core/orchestrator/StudentModeLoop.swift`
- `core/orchestrator/student-mode-loop-v0.md`
- `core/contracts/StudentModeContracts.swift`
- `core/executor/StudentSkillExecutor.swift`
- `core/storage/StudentLoopLogWriter.swift`
- `core/storage/StudentReviewReportWriter.swift`
- `apps/macos/Sources/OpenStaffStudentCLI/*`

**验收标准**
- [x] 演示 1 条完整自主执行任务（`make student ARGS="--goal '在 Safari 中复现点击流程' --knowledge core/knowledge/examples/knowledge-item.sample.json"`）。

---

## 阶段 5：macOS GUI（Day 14 ~ Day 20）

### TODO 5.1 主界面与模式切换
- [x] 三模式切换组件。
- [x] 当前状态、权限状态、最近任务显示。

### TODO 5.2 学习记录与知识浏览
- [ ] 会话列表。
- [ ] 任务详情与知识条目查看。

### TODO 5.3 审阅与反馈
- [ ] 执行日志查看。
- [ ] 老师反馈入口（通过/驳回/修正）。

**验收标准（阶段 5）**
- [ ] 不打开终端即可完成一次教学->辅助->学生模式演示。

---

## 阶段 6：安全、测试与发布准备（Day 20 ~ Day 24）

### TODO 6.1 安全控制
- [ ] 高风险动作拦截规则。
- [ ] 紧急停止按钮（UI + 全局快捷键）。

### TODO 6.2 测试体系落地
- [ ] 单元测试：schema、切片器、映射器。
- [ ] 集成测试：采集->知识->转换->执行。
- [ ] E2E：三模式最小演示用例。

### TODO 6.3 发布前检查
- [ ] 配置模板与文档完善。
- [ ] 演示数据与回归脚本。

**验收标准（阶段 6）**
- [ ] 一键执行测试脚本可输出通过/失败摘要。

---

## 横向任务（贯穿全程）

### A. 文档治理
- [ ] 每完成一个阶段更新 `docs/project-plan-and-progress.md`。
- [ ] 每个关键决策补 ADR。

### B. 可观测性
- [ ] 统一日志格式（traceId/sessionId/taskId）。
- [ ] 基础指标：采集速率、解析成功率、执行成功率。

### C. 数据治理
- [ ] 明确保留周期和清理机制。
- [ ] 支持按 session/task 导出。

---

## 首周执行建议（最具体）

### Day 1
- [ ] 完成技术栈 ADR。
- [ ] 输出事件 schema v0。

### Day 2
- [ ] 跑通鼠标点击采集。
- [ ] 采集进程写 JSONL。

### Day 3
- [ ] 增加 app/window 上下文。
- [ ] 完成 session 文件切分。

### Day 4
- [x] 做任务切片规则 v0。
- [x] 产出首个 `KnowledgeItem` 示例。

### Day 5
- [x] 完成提示词模板 v0。
- [x] 跑通 1 条知识 -> LLM 结构化输出（离线 text provider）。

### Day 6
- [x] 完成 OpenClaw skill 映射 v0。
- [x] 验证 1 条 skill 被 OpenClaw 读取。

### Day 7
- [ ] 打通“教学模式最小闭环”演示。
- [ ] 更新进展文档与下一周计划。

---

## Definition of Done（本清单完成标准）

- [ ] 三模式均有可演示最小链路。
- [ ] 从点击采集到 skill 执行形成闭环。
- [ ] 执行日志可审阅、可追踪、可回放。
- [ ] 所有关键行为有文档、有测试、有回退策略。
