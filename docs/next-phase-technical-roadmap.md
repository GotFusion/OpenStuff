# OpenStaff 下一阶段技术路线图（Phase 7+）

版本：v0.7.0-roadmap  
更新时间：2026-03-13

## 1. 路线定位

OpenStaff 下一阶段不应继续朝“通用桌面 Agent”泛化，而应明确定位为：

- OpenClaw 的 **teaching layer**（示教学习层）
- OpenClaw 的 **desktop skill foundry**（桌面技能工坊）
- OpenClaw 的 **personal review cockpit**（个人审阅与修复台）

即：

1. OpenClaw 负责渠道、通用工具执行、远程节点、自动化调度。
2. OpenStaff 负责观察老师、沉淀知识、生成更稳的桌面技能、在执行后做审阅与再学习。

---

## 2. 当前基线与关键缺口

结合现有文档与实现，当前已经完成：

- 教学 / 辅助 / 学生三模式最小闭环。
- `Capture -> Knowledge -> LLM -> Skill -> Review` 主链路。
- GUI、日志、反馈、安全基线与发布前检查。
- OpenClaw `SKILL.md` 生成与校验链路。

下一阶段最关键的缺口有 5 个：

1. **语义定位缺失**
   - 当前 `NormalizedEvent.target.kind` 仍以 `coordinate` 为主，尚无稳定的 UI 语义定位层。
2. **OpenClaw 真执行未打通**
   - 当前已能产出 OpenClaw skill，但尚未完成稳定的端到端执行联调。
3. **知识与技能未完全分层**
   - “观察记录”“抽象步骤”“可执行 skill”“执行后审阅”仍缺少强边界与可回溯映射。
4. **辅助模式仍以规则预测为主**
   - 还没有基于历史轨迹检索的个性化下一步预测。
5. **缺少个人基准集**
   - 还没有一套可持续回归的个人高频任务 benchmark 来衡量学习质量和执行稳定性。

---

## 3. 下一阶段总目标

Phase 7+ 的总目标不是扩更多花哨能力，而是完成以下 4 件事：

1. 把“点击坐标”升级为“可修复、可回放、可迁移的语义定位”。
2. 把 OpenClaw 从“生成目标”升级为“真实执行内核”。
3. 把辅助模式从“规则提示”升级为“基于历史经验检索的个性化提示”。
4. 建立个人任务基准、漂移修复与发布门禁，形成长期可迭代闭环。

---

## 4. 设计原则

### 4.1 执行优先级

- `Accessibility / AX` 优先
- `文本锚点 / OCR` 次之
- `截图锚点` 再次
- `坐标回退` 最后

### 4.2 数据分层

必须将知识链路明确拆为四层：

1. `ObservationRecord`
   - 老师真实操作轨迹与上下文证据。
2. `ProcedureSpec`
   - 从轨迹抽象出的老师意图、步骤、约束和前置条件。
3. `SkillArtifact`
   - 面向 OpenClaw 的可执行技能包。
4. `ExecutionReview`
   - 实际执行日志、结果、老师反馈与修复建议。

### 4.3 路线优先级

- 先解决“学到的东西能否稳定复现”
- 再做“是否更智能地预测下一步”
- 最后才做“更强的自主泛化”

---

## 5. 分阶段技术路线

### 阶段 7：语义定位层（Week 1 ~ Week 2）

#### 目标

为每一步操作增加“可理解、可回放、可修复”的语义定位信息，替代单纯坐标依赖。

#### TODO 7.1 定义 Semantic Target 数据模型

状态：已完成（2026-03-13）

- 新增 `SemanticTarget` 契约：
  - `locatorType`：`axPath` / `roleAndTitle` / `textAnchor` / `imageAnchor` / `coordinateFallback`
  - `appBundleId`
  - `windowTitlePattern`
  - `elementRole`
  - `elementTitle`
  - `elementIdentifier`
  - `boundingRect`
  - `confidence`
  - `source`（capture / inferred / repaired）
- 扩展 `NormalizedEvent` 与 `KnowledgeItem`，支持保留多种 locator 候选。

**输出物**
- `core/contracts/SemanticTargetContracts.swift`
- `core/capture/semantic-target-v0.md`
- `core/capture/schemas/semantic-target.schema.json`
- `docs/adr/ADR-0005-semantic-target-model.md`

**验收标准**
- [x] 任意点击事件都能同时保留 `coordinate` 与至少一个候选 `SemanticTarget`。
- [x] schema 校验通过，旧数据可兼容迁移。

#### TODO 7.2 丰富采集上下文

状态：已实现（2026-03-13，待真机验收）

- 在现有 AX 抓取能力上补充：
  - 前台 App `bundleId`
  - 当前窗口稳定签名
  - 当前焦点元素可读属性
  - 操作前后轻量截图锚点
- 不采集高敏感原文输入，继续遵守本地优先与脱敏策略。

**输出物**
- `apps/macos/Sources/OpenStaffCaptureCLI/*`
- `apps/macos/Sources/OpenStaffApp/ModeObservationCapture.swift`
- `core/capture/examples/*.jsonl`

**验收标准**
- [ ] 在 Finder / Safari / Terminal 三类应用中，能稳定抓取语义属性。
- [x] 权限受限时有清晰降级策略与错误码。

#### TODO 7.3 语义定位解析与回放验证器

- 实现 `SemanticTargetResolver`
  - 解析优先级：`axPath -> roleAndTitle -> textAnchor -> imageAnchor -> coordinateFallback`
- 实现 `ReplayVerifier`
  - 对历史步骤做 dry-run 解析，不执行危险动作，只验证“能否找到目标”
- 输出定位失败原因：
  - 窗口不匹配
  - 元素缺失
  - 文本锚点变化
  - 仅剩坐标回退

**输出物**
- `core/executor/SemanticTargetResolver.swift`
- `core/executor/ReplayVerifier.swift`
- `apps/macos/Sources/OpenStaffReplayVerifyCLI/*`

**验收标准**
- [ ] 对 10 条真实历史步骤做 dry-run，目标解析成功率达到可人工接受水平。
- [ ] 失败原因可结构化输出，不再只返回“点击失败”。

---

### 阶段 8：OpenClaw 伴侣集成（Week 3 ~ Week 4）

#### 目标

让 OpenStaff 不只“生成 skill”，而是能够对 OpenClaw 的真实执行过程做编排、审计和回收。

#### TODO 8.1 明确 OpenClaw 集成边界

- 固定边界：
  - OpenClaw：执行内核 / 渠道 / agent runtime
  - OpenStaff：学习层 / skill 构建层 / 执行前校验 / 执行后审阅
- 统一 skill 元数据：
  - 来源知识条目 ID
  - 来源 session / task / step 映射
  - 生成版本
  - 修复版本

**输出物**
- `docs/adr/ADR-0006-openclaw-companion-boundary.md`
- `scripts/skills/openclaw_skill_mapper.py`（补充 provenance 字段）
- `scripts/skills/schemas/openstaff-openclaw-skill.schema.json`

**验收标准**
- [ ] 任意 skill 都能回溯到对应知识条目与老师原始轨迹。
- [ ] OpenClaw skill 目录中保留可审计元信息。

#### TODO 8.2 实现 OpenClaw Runner 适配层

- 新增统一执行入口：
  - `OpenClawRunner`
  - `OpenClawExecutionRequest`
  - `OpenClawExecutionResult`
- 负责：
  - 调用 OpenClaw CLI / gateway
  - 捕获 stdout / stderr / 退出码
  - 写入结构化执行日志
  - 将执行结果回灌到 `ExecutionReview`

**输出物**
- `core/executor/OpenClawRunner.swift`
- `core/contracts/OpenClawExecutionContracts.swift`
- `apps/macos/Sources/OpenStaffOpenClawCLI/*`

**验收标准**
- [ ] 至少 3 条样例 skill 能真实触发 OpenClaw 执行。
- [ ] 执行失败时能保留结构化错误而非纯文本报错。

#### TODO 8.3 Skill 预检与安全门

- 在执行前增加预检：
  - skill schema 校验
  - locator 可解析性检查
  - 高风险动作检查
  - 目标 App 白名单检查
- 对高风险或低置信度步骤强制要求老师确认。

**输出物**
- `core/executor/SkillPreflightValidator.swift`
- `scripts/validation/validate_skill_bundle.py`
- `docs/adr/ADR-0007-skill-preflight-and-repair.md`

**验收标准**
- [ ] 高风险或低置信步骤不会直接进入自动执行。
- [ ] 预检失败原因可在 GUI 中直接展示。

---

### 阶段 9：辅助预测与漂移修复（Week 5）

#### 目标

把“辅助模式”和“执行后反馈”做成真正有个性化价值的能力。

#### TODO 9.1 基于历史知识检索的下一步预测

- 替换单纯规则预测，新增 `AssistKnowledgeRetriever`
- 以以下信号检索相似历史步骤：
  - app / window
  - 最近动作序列
  - 当前任务目标
  - 老师历史偏好
- 输出推荐理由：
  - “过去你在此窗口中通常下一步会点击 X”

**输出物**
- `core/orchestrator/AssistKnowledgeRetriever.swift`
- `core/orchestrator/RetrievalBasedAssistPredictor.swift`
- `core/contracts/AssistPredictionContracts.swift`

**验收标准**
- [ ] 对个人高频任务，辅助模式能给出有来源依据的下一步建议。
- [ ] 推荐结果可展示“来自哪条历史知识”。

#### TODO 9.2 Skill 漂移检测与修复建议

- 当执行失败或解析失败时，识别是否属于：
  - UI 文案变化
  - 元素位置变化
  - 窗口结构变化
  - App 版本变化
- 给出修复路径：
  - 重新定位
  - 重新示教当前步骤
  - 更新现有 skill locator

**输出物**
- `core/repair/SkillDriftDetector.swift`
- `core/repair/SkillRepairPlanner.swift`
- `docs/adr/ADR-0008-skill-drift-repair.md`

**验收标准**
- [ ] 对至少 3 种故障类型输出不同修复建议。
- [ ] 老师可在 GUI 中选择“更新 skill”或“重新示教”。

#### TODO 9.3 审阅台增强

- 在执行日志旁增加三栏对照：
  - 老师原始步骤
  - 当前 skill 步骤
  - 本次实际执行结果
- 支持反馈：
  - 通过
  - 驳回
  - 修复 locator
  - 重新示教

**输出物**
- `apps/macos/Sources/OpenStaffApp/*`
- `core/storage/ExecutionReviewStore.swift`

**验收标准**
- [ ] 老师可以直接在 GUI 内完成“看失败 -> 做判断 -> 发起修复”闭环。

---

### 阶段 10：个人基准与发布硬化（Week 6）

#### 目标

建立长期可回归、可量化的个人桌面任务评测体系。

#### TODO 10.1 建立 Personal Desktop Benchmark

- 选取 20 ~ 30 个个人高频任务，分 4 类：
  - 文件整理
  - 浏览器操作
  - 开发者工具
  - 日常办公
- 每条任务保留：
  - 原始轨迹
  - 抽象知识
  - skill 产物
  - 执行日志
  - 审阅结果

**输出物**
- `data/benchmarks/personal-desktop/*`
- `docs/personal-benchmark-spec.md`

**验收标准**
- [ ] 任意版本更新后可重复回归至少 20 条任务。

#### TODO 10.2 补齐验证脚本与门禁

- 新增统一校验命令：
  - 原始事件 schema 校验
  - 知识条目校验
  - skill bundle 校验
  - replay verify
  - benchmark run
- 接入发布预检。

**输出物**
- `scripts/validation/*`
- `scripts/release/run_regression.py`
- `Makefile` 新增一键入口

**验收标准**
- [ ] `make release-preflight` 可覆盖关键数据链路与 benchmark。

#### TODO 10.3 安全策略二次升级

- 引入按 App / 按任务 / 按 skill 的白名单机制。
- 对“低置信 + 高风险 + 低复现度”动作默认禁止自动执行。
- 增加敏感窗口识别：
  - 支付
  - 系统设置
  - 密码管理器
  - 隐私权限弹窗

**输出物**
- `config/safety-rules.yaml`
- `core/executor/SafetyPolicyEvaluator.swift`

**验收标准**
- [ ] 高风险窗口与高风险步骤在学生模式下默认不能自动通过。

---

## 6. 六周里程碑视图

### Week 1

- 完成 `SemanticTarget` 契约、schema 与 ADR。
- 设计数据迁移与旧事件兼容策略。

### Week 2

- 完成 AX / 文本 / 截图锚点采集。
- 完成 `ReplayVerifier` 原型与 dry-run CLI。

### Week 3

- 明确 OpenClaw companion boundary。
- 为 skill 产物补 provenance 与 preflight 校验。

### Week 4

- 打通 `OpenClawRunner`，完成至少 3 条 skill 真执行联调。
- 执行日志回灌到 GUI 审阅台。

### Week 5

- 上线 retrieval-based assist predictor。
- 补齐 skill 漂移检测与修复建议。

### Week 6

- 建立 personal benchmark。
- 将 replay verify、skill preflight、benchmark 接入发布门禁。

---

## 7. 阶段完成标志（Definition of Done）

当满足以下条件时，可认为 Phase 7+ 第一阶段完成：

1. 老师完成一次真实教学。
2. OpenStaff 生成带语义定位的知识条目与 OpenClaw skill。
3. OpenStaff 在执行前完成 preflight 与 replay verify。
4. OpenClaw 完成真实执行并返回结构化日志。
5. 老师能在 GUI 中看到“原始步骤 / 当前 skill / 实际结果”的三栏对照。
6. 若 UI 变化导致失败，系统能给出“修 locator”或“重新示教”的明确路径。
7. 全流程能被个人 benchmark 持续回归。

---

## 8. 暂缓项（本阶段不优先）

- 纯视觉驱动的通用桌面 Agent 泛化。
- 云端多设备同步。
- 多租户 / 团队协作 gateway。
- 自动自我训练或强化学习闭环。
- 广覆盖应用生态适配。

优先级应始终保持为：

`可稳定复现个人高频任务` > `更聪明的泛化` > `更炫的自动化能力`

---

## 9. 建议新增 ADR

- `ADR-0005-semantic-target-model.md`
- `ADR-0006-openclaw-companion-boundary.md`
- `ADR-0007-skill-preflight-and-repair.md`
- `ADR-0008-skill-drift-repair.md`

---

## 10. 一句话结论

OpenStaff 下一阶段最重要的，不是“再做一个更强的通用 Agent”，而是把自己做成：

**最懂老师桌面习惯、最会把示教转成稳定 OpenClaw skill、最擅长在执行后帮老师修复和沉淀知识的伴侣软件。**
