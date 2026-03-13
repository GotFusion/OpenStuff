# ADR-0008：Skill Preflight 与安全门

- 状态：Accepted
- 日期：2026-03-13
- 阶段：Phase 8.3

## 背景

Phase 8.2 已经打通 OpenStaff -> OpenClaw 的执行链路，但 skill 在真正执行前仍然缺少统一守门：

1. `openstaff-skill.json` 结构损坏时，GUI 只能看到“运行失败”，看不到具体预检原因。
2. click 步骤如果只剩 `target=unknown` 或 locator 已缺失，仍可能进入运行阶段才暴露问题。
3. 高风险动作、低置信步骤、`requiresTeacherConfirmation=true` 的 skill，没有统一的“禁止自动直跑”语义。
4. 不同入口（GUI 手动运行、学生模式自动运行、OpenClaw CLI、发布预检）使用的判断规则不一致。

## 决策

### 1. 引入统一 `SkillPreflightValidator`

新增 `core/executor/SkillPreflightValidator.swift`，在执行前产出结构化 `SkillPreflightReport`：

- `status`
  - `passed`
  - `needs_teacher_confirmation`
  - `failed`
- `issues[]`
  - severity / code / message / stepId
- `steps[]`
  - 逐步记录 locator 状态、置信度、风险标记、是否要求老师确认

预检覆盖四类检查：

1. skill schema / bundle 完整性
2. locator 可解析性
3. 高风险动作识别
4. 目标 App 白名单检查

### 2. 目标 App 白名单采用“skill 内生白名单”

当前阶段不引入额外配置中心，而是从 skill 自身导出 allowlist：

- `mappedOutput.context.appBundleId`
- `executionPlan.completionCriteria.requiredFrontmostAppBundleId`
- 可选额外 allowlist 参数（CLI / script）

任何步骤若命中 allowlist 之外的 bundleId，直接 `failed`。

这样可以先保证 skill 不会悄悄跨 App 漂移；后续若要接项目级白名单，只需在此 allowlist 上叠加。

### 3. locator 预检规则

- `click` 步骤必须满足以下之一：
  - 至少一个可解析的语义 locator（`axPath` / `roleAndTitle` / `textAnchor` / `imageAnchor`）
  - 或仅剩 `coordinateFallback` / 坐标回退，此时标记为 `degraded`
- `degraded` 不直接失败，但会强制要求老师确认
- 完全缺失 locator / provenance step mapping 时，直接 `failed`

### 4. 高风险 / 低置信步骤禁止自动直跑

以下情况统一进入 `needs_teacher_confirmation`：

- `executionPlan.requiresTeacherConfirmation = true`
- step 置信度低于阈值
- 命中高风险关键字 / 正则
- Terminal `input` 等高风险执行
- click 只能依赖坐标回退

具体执行策略：

- GUI 手动运行：
  - `failed` 直接禁止
  - `needs_teacher_confirmation` 需要老师先在技能面板执行“审核 -> 通过”
- 学生模式自动运行：
  - 只允许 `passed`
  - `needs_teacher_confirmation` 不进入自动执行候选集
- OpenClaw CLI / Runner：
  - 默认若命中确认门则返回 `OCW-SKILL-CONFIRMATION-REQUIRED`
  - 只有显式 `teacherConfirmed=true` 时才允许继续执行

### 5. 预检结果必须可见

- GUI 技能列表新增“预检”列与预检摘要
- 选中 skill 后可直接看到 `summary + issues`
- OpenClaw JSON 结果回传 `preflight`
- `scripts/validation/validate_skill_bundle.py` 输出同结构状态，供发布预检与 CI 使用

## 影响

### 正面

- 高风险 / 低置信 skill 不会直接进入自动执行。
- 预检失败原因可在 GUI、CLI、CI 中统一展示。
- 发布预检可以覆盖 skill bundle 的“可运行前状态”，而不是只验证 schema。

### 负面

- 旧样例或历史 skill 如果缺少 locator，会被显式拦下，需要修复或补充 provenance。
- 当前白名单仍是 skill 内生 allowlist，尚未做到团队级 / 用户级动态配置。

## 后续

- Phase 9.2 接入 repair flow：允许根据 preflight / drift 报告自动生成修复建议并递增 `repairVersion`。
- 把 allowlist 与低置信阈值外置到配置文件。
- 将 replay verify 与 preflight 结果合并成统一“执行前健康度报告”。
