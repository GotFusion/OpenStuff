---
name: openstaff-task-session-20260307-a1-001
description: 在 Safari 中复现任务 task-session-20260307-a1-001 的操作流程
user-invocable: true
disable-model-invocation: false
metadata: {"openclaw":{"emoji":"🎓","skillKey":"openstaff-task-session-20260307-a1-001","requires":{"config":["openstaff.enabled"]}},"openstaff":{"knowledgeItemId":"ki-task-session-20260307-a1-001","taskId":"task-session-20260307-a1-001","sessionId":"session-20260307-a1","repairVersion":0}}
---

# 在 Safari 中复现任务 task-session-20260307-a1-001 的操作流程

## Context
- appName: `Safari`
- appBundleId: `com.apple.Safari`
- windowTitle: `OpenStaff - GitHub`

## Provenance
- sessionId: `session-20260307-a1`
- taskId: `task-session-20260307-a1-001`
- knowledgeItemId: `ki-task-session-20260307-a1-001`
- sourceTaskChunkSchemaVersion: `knowledge.task-chunk.v0`
- sourceEventCount: `2`
- knowledgeGeneratorVersion: `rule-v0`
- skillGeneratorVersion: `openstaff-skill-mapper-v1`
- repairVersion: `0`

## Teacher Summary
在 Safari（OpenStaff - GitHub）中，步骤摘要：点击 -> 点击。共 2 步，任务分段原因：空闲间隔切分。

## Steps
1. [click] 执行第 1 步点击操作（源事件 11111111-1111-4111-8111-111111111111）。
   - knowledgeStepId: `step-001`
   - target: `unknown`
   - preferredLocatorType: `roleAndTitle`
   - sourceEventIds: `11111111-1111-4111-8111-111111111111`
2. [click] 执行第 2 步点击操作（源事件 22222222-2222-4222-8222-222222222222）。
   - knowledgeStepId: `step-002`
   - target: `unknown`
   - preferredLocatorType: `roleAndTitle`
   - sourceEventIds: `22222222-2222-4222-8222-222222222222`

## Safety Notes
- 执行前前台应用必须是 com.apple.Safari。
- 执行该知识条目时，需要老师确认后再执行。
- 坐标点击目标可能随分辨率或界面变化漂移。

## Failure Policy
- onContextMismatch: `stopAndAskTeacher`
- onStepError: `stopAndAskTeacher`
- onUnknownAction: `stopAndAskTeacher`

## Runtime Requirements
- requiresTeacherConfirmation: `true`
- expectedStepCount: `2`
- requiredFrontmostAppBundleId: `com.apple.Safari`
- confidence: `0.86`
