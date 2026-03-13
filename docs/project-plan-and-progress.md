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
3. 将解析结果转为 OpenClaw skill bundle（`SKILL.md` + `openstaff-skill.json provenance`）。
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
- 完成阶段 1.2 采集引擎最小实现：`OpenStaffCaptureCLI`（权限检查、全局点击监听、上下文抓取、本地队列）。
- 完成阶段 1.3 事件落盘与轮转：`RawEventFileSink`（JSONL 追加写盘、按日期+session 分片、按大小/时间轮转、异常中断恢复追加）。
- 新增存储策略 ADR：`docs/adr/ADR-0002-storage-strategy.md`。
- 完成阶段 2.1 任务切片器：`OpenStaffTaskSlicerCLI`（按空闲间隔 + 上下文切换切片，输出 `TaskChunk` 并生成稳定 `task_id`）。
- 完成阶段 2.2 知识条目格式定义：`KnowledgeItem` schema + `OpenStaffKnowledgeBuilderCLI`（`TaskChunk -> KnowledgeItem` 映射落盘）。
- 完成阶段 2.3 自动总结初版（无 LLM）：`KnowledgeSummaryGenerator`（规则摘要写入 `KnowledgeItem.summary`）。
- 完成阶段 3.1 提示词模板系统：新增系统/任务提示词模板、LLM 输出 schema、提示词渲染脚本与 JSON 严格校验脚本（`scripts/llm/*`）。
- 完成阶段 3.2 ChatGPT 调用适配层：新增 `chatgpt_adapter.py`（重试、超时、限流、请求摘要日志、错误报告），并提供离线 `text` provider 以支持无 API 场景验证。
- 完成阶段 3.3 OpenClaw skill 映射器：新增 `openclaw_skill_mapper.py` 与 `validate_openclaw_skill.py`，实现 `KnowledgeItem + LLM` 到 OpenClaw `SKILL.md` 的映射，并支持字段校验与 fallback；阶段 8.1 已将其升级为带 provenance 的 `openstaff.openclaw-skill.v1` 审计产物。
- 完成阶段 4.1 模式状态机：新增 `ModeStateMachine`、`OrchestratorContracts`、`OpenStaffOrchestratorCLI`，实现三模式合法切换校验、切换守卫与能力白名单，非法切换会拒绝并输出结构化日志。
- 完成阶段 4.2 辅助模式闭环：新增 `AssistModeLoop` + `AssistActionExecutor` + `AssistLoopLogWriter` + `OpenStaffAssistCLI`，实现“规则预测 -> 弹窗确认 -> 执行 -> 回写日志”最小闭环。
- 完成阶段 4.3 学生模式闭环：新增 `StudentModeLoop` + `StudentSkillExecutor` + `StudentLoopLogWriter` + `StudentReviewReportWriter` + `OpenStaffStudentCLI`，实现“目标输入 -> 自动规划 -> 技能执行 -> 结构化审阅报告”最小闭环。
- 完成阶段 5.1 主界面与模式切换：升级 `OpenStaffApp` 为 Dashboard，提供三模式切换组件（复用状态机守卫）、当前状态卡片、权限状态（辅助功能与数据目录可写性）及最近任务列表（从 `data/logs` + `data/knowledge` 汇总）。
- 完成阶段 5.2 学习记录与知识浏览：新增学习记录浏览区，支持会话列表、会话任务列表、任务详情与知识条目查看（含目标/摘要/约束/步骤）。
- 完成阶段 5.3 审阅与反馈：新增执行日志审阅区，支持日志详情查看与老师反馈入口（通过/驳回/修正），反馈落盘到 `data/feedback/{yyyy-mm-dd}/*.jsonl`。
- 完成阶段 6.1 安全控制：执行层新增高风险关键词+正则拦截规则，支持紧急停止状态拦截；GUI 新增紧急停止按钮与全局快捷键（`Cmd+Shift+.`）。
- 完成阶段 6.2 测试体系落地（补强）：在原有 schema/映射链路测试基础上，新增 `test_validate_openclaw_skill.py`、`test_task_slicer_cli.py`、`test_three_mode_cli_roundtrip.py`，把覆盖扩展到 `SKILL.md` 校验器、`OpenStaffTaskSlicerCLI` 切片策略，以及 `Orchestrator/Assist/Student` 三模式真实 CLI 闭环；统一入口仍为 `scripts/tests/run_all.py` 与 `make test*`。
- 完成阶段 6.3 发布前检查：补齐配置模板（`config/release.example.yaml`）与配置文档；新增 `scripts/release/run_regression.py`（发布回归与 JSON 报告）；新增 `make release-regression` / `make release-preflight` 一键入口。
- 完成阶段 7.1 Semantic Target 数据模型：新增 `SemanticTarget` 共享契约、capture/knowledge schema 与 ADR，并让 `KnowledgeItemBuilder` 为点击步骤自动写入 `coordinateFallback` 候选，同时保持旧 `capture.normalized.v0` / `knowledge.item.v0` 数据兼容解码。
- 完成阶段 7.2 采集上下文增强：CLI 与教学模式采集统一写出共享 `RawEvent`，补充窗口稳定签名、焦点元素可读属性、轻量截图锚点指纹和结构化降级错误码；高敏感键盘输入在安全文本场景下会自动脱敏。
- 完成阶段 7.3 语义定位解析与回放验证器：新增 `SemanticTargetResolver`、`ReplayVerifier` 与 `OpenStaffReplayVerifyCLI`，支持 `axPath -> roleAndTitle -> textAnchor -> imageAnchor -> coordinateFallback` 的 dry-run 解析、离线 snapshot/实时前台窗口双输入，以及窗口不匹配、元素缺失、文本锚点变化、仅剩坐标回退等结构化结果输出。
- 完成阶段 8.1 OpenClaw companion boundary：新增 `docs/adr/ADR-0007-openclaw-companion-boundary.md`，明确 OpenStaff/OpenClaw 职责切分；`scripts/skills/openclaw_skill_mapper.py`、skill schema 与 validator 升级为 `openstaff.openclaw-skill.v1`，统一写出 `knowledge/sourceTrace/skillBuild/stepMappings` provenance，并在 `SKILL.md` 中保留关键审计摘要。
- 完成阶段 9.1 基于历史知识检索的下一步预测：新增 `AssistPredictionContracts`、`AssistKnowledgeRetriever`、`RetrievalBasedAssistPredictor`，辅助模式改为按 `app / window / goal / recent steps / 历史偏好` 检索相似知识并输出来源证据；`OpenStaffAssistCLI` 现支持知识目录输入与推荐来源展示。
- 完成阶段 8.2 OpenClaw Runner 适配层：新增 `core/contracts/OpenClawExecutionContracts.swift`、`core/executor/OpenClawRunner.swift` 与 `apps/macos/Sources/OpenStaffOpenClawCLI/*`，实现 OpenClaw CLI / gateway 子进程调用、stdout/stderr/exit code 捕获、`data/logs/{date}/{sessionId}-openclaw.log` 结构化日志回写，以及 `OpenClawExecutionReview` 结果产出；3 条 sample skill 已通过真实子进程链路联调。
- 完成阶段 8.3 Skill 预检与安全门：新增 `core/executor/SkillPreflightValidator.swift`、`scripts/validation/validate_skill_bundle.py` 与 `docs/adr/ADR-0008-skill-preflight-and-repair.md`，统一执行前 schema/locator/高风险/目标 App 白名单检查；GUI 技能列表可直接展示预检摘要与失败原因，学生模式自动执行仅允许 `preflight=passed` 的技能直跑，`needs_teacher_confirmation` 技能必须经老师审核通过后才能手动执行；`OpenStaffOpenClawCLI` 也已接入 `teacherConfirmed` 安全门。
- 新增用户使用说明书 `docs/user-manual.md`，覆盖教学->辅助->学生三模式日常运行与发布回归流程。
- 完成菜单栏+前台部件 v4 的 Phase A（基础样式收敛）：字体/间距/节点透明色/截断规则统一 token 化，超长文案统一按场景截断。
- 完成菜单栏+前台部件 v4 的 Phase B（精简模式改造）：球体样式替换为透明方框，精简信息收敛到当前任务/下一步/轻提示，整块区域可点击切换详细模式。
- 完成菜单栏+前台部件 v4 的 Phase C（详细模式收敛）：时间轴去重背景嵌入、一级/二级透明节点调色、间距参数规范化，并加入紧急停止细红线状态提示。
- 完成菜单栏+前台部件 v4 的 Phase D（菜单栏原生化）：菜单改为系统原生样式，危险操作仅文字强调，模式切换在部件隐藏时可自动显示并联动生效。
- 完成菜单栏+前台部件 v4 的 Phase E（回归验收）：新增 `OpenStaffAppTests` 回归套件并完成空态/长文本/多任务/交互动作链路验证，且现有 unit/integration/e2e 与 `OpenStaffApp` 构建均通过。

### 下一步建议
1. API 可用后补充 `provider=openai` 联机验证（模型行为、限流参数、错误码映射）并补充 skill 端到端执行联调。
2. 在 `scripts/validation` 上继续扩展：对 `data/raw-events/**/*.jsonl`、`data/task-chunks/**/*.json`、`data/knowledge/**/*.json`、`data/skills/**/*.json` 做 schema 快速校验。
3. 补齐 preflight 失败后的 repair workflow，把 `repairVersion` 真正接进自动修复与老师复核闭环。

---

## 9. 架构合理性评审与执行清单

- 架构与目录合理性评审请见：`docs/architecture-review.md`。
- 详细编码 TODO 清单请见：`docs/implementation-todo-checklist.md`。
- 下一阶段技术路线图请见：`docs/next-phase-technical-roadmap.md`。
- 建议按 TODO 阶段顺序推进，每完成一个阶段回写本文件“当前实现进展”。
