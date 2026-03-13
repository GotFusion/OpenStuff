# ADR-0009 Skill Drift Detection And Repair

## Status

Accepted - 2026-03-13

## Context

阶段 8.3 已完成 skill preflight，但 preflight 只能在执行前回答“当前 skill 能否安全运行”。

仍缺一层执行后 / 回放时的诊断能力：
- 无法把失败进一步解释为“文案变了”“位置变了”“窗口结构变了”。
- 老师在 GUI 中看见失败后，缺少统一的修复入口。
- `repairVersion` 已在 provenance 中定义，但还没有实际 repair 计划去驱动它。

## Decision

新增独立 repair 层：
- `core/repair/SkillDriftDetector.swift`
- `core/repair/SkillRepairPlanner.swift`

### 1. 漂移检测输入

检测对象以 `SkillBundlePayload` 为主，而不是直接面向运行日志：
- 直接复用 skill 的 `provenance.stepMappings`
- 使用当前 `ReplayEnvironmentSnapshot`
- 复用 `SemanticTargetResolver`

这样可以在不执行危险动作的前提下，对 skill locator 做 dry-run 级漂移判断。

### 2. 漂移类型

检测层输出以下主类型：
- `uiTextChanged`
- `elementPositionChanged`
- `windowStructureChanged`
- `appVersionChanged`
- `captureUnavailable`
- `contextMismatch`

其中 `appVersionChanged` 是报告级聚合结论：
- 当同一 App 内多个步骤同时发生 locator 失效时，升级为“疑似版本级变化”。

### 3. 修复建议

规划层输出显式 repair action：
- `updateSkillLocator`
- `relocalize`
- `reteachCurrentStep`

每条 action 都带：
- 影响步骤 ID
- 原因说明
- 是否应递增 `repairVersion`

### 4. GUI 与 CLI 接入

- `OpenStaffReplayVerifyCLI` 支持 `--skill-dir`，可直接输出 `driftReport + repairPlan`
- `OpenStaffApp` 在技能详情中新增：
  - “检测漂移”
  - 基于 plan 的“更新 locator / 更新 skill / 重新示教”入口
- GUI 中老师的 repair 选择会记录到 `data/skills/repairs/{date}/skill-repair.jsonl`

## Consequences

### Positive

- skill 失败不再只有“没点到”这一类粗粒度描述。
- repair 建议可在 CLI、GUI、后续自动修复流程中复用。
- `repairVersion` 终于有了明确的触发来源。

### Negative

- 当前属于启发式诊断，不等同于真正理解 App 内部版本信息。
- “appVersionChanged” 依赖多步聚合推断，仍可能和大规模布局变化混淆。

## Follow-up

- Phase 9.3 将把 drift report、老师原始步骤、当前 skill 步骤和实际执行结果并排展示。
- 后续可在 repair action 执行时真正自动递增 `repairVersion` 并生成新的 skill 版本。
