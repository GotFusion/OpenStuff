# core/repair/

执行后 / 回放时的 skill 漂移检测与修复建议层。

## 当前实现（Phase 9.2）
- `SkillDriftDetector.swift`
  - 对 `SkillBundlePayload` + 当前 `ReplayEnvironmentSnapshot` 做 dry-run 漂移检测。
  - 识别 `uiTextChanged / elementPositionChanged / windowStructureChanged / appVersionChanged` 等类型。
- `SkillRepairPlanner.swift`
  - 把漂移报告转换为 `updateSkillLocator / relocalize / reteachCurrentStep` 修复动作。
  - 输出建议的 `repairVersion`。

## 当前接入点
- `OpenStaffReplayVerifyCLI --skill-dir`
- `OpenStaffApp` 技能详情页中的“检测漂移”与修复动作按钮
