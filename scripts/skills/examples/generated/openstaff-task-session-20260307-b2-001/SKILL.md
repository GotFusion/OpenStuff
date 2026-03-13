---
name: openstaff-task-session-20260307-b2-001
description: 在 Finder 中创建并重命名项目文件夹
user-invocable: true
disable-model-invocation: false
metadata: {"openclaw":{"emoji":"🎓","skillKey":"openstaff-task-session-20260307-b2-001","requires":{"config":["openstaff.enabled"]}},"openstaff":{"knowledgeItemId":"ki-task-session-20260307-b2-001","taskId":"task-session-20260307-b2-001","sessionId":"session-20260307-b2","repairVersion":0}}
---

# 在 Finder 中创建并重命名项目文件夹

## Context
- appName: `Finder`
- appBundleId: `com.apple.finder`
- windowTitle: `Documents`

## Provenance
- sessionId: `session-20260307-b2`
- taskId: `task-session-20260307-b2-001`
- knowledgeItemId: `ki-task-session-20260307-b2-001`
- sourceTaskChunkSchemaVersion: `knowledge.task-chunk.v0`
- sourceEventCount: `3`
- knowledgeGeneratorVersion: `rule-v0`
- skillGeneratorVersion: `openstaff-skill-mapper-v1`
- repairVersion: `0`

## Teacher Summary
在 Finder（Documents）中，步骤摘要：点击 -> 快捷键 -> 输入。共 3 步，任务分段原因：上下文切换切分。

## Steps
1. [click] 点击 Finder 侧边栏中的 Documents。
   - knowledgeStepId: `step-001`
   - target: `unknown`
   - preferredLocatorType: `unknown`
   - sourceEventIds: `33333333-3333-4333-8333-333333333333`
2. [shortcut] 使用快捷键 Command+Shift+N 创建新文件夹。
   - knowledgeStepId: `step-002`
   - target: `unknown`
   - preferredLocatorType: `unknown`
   - sourceEventIds: `44444444-4444-4444-8444-444444444444`
3. [input] 输入文件夹名称 OpenStaff-Workspace 并回车。
   - knowledgeStepId: `step-003`
   - target: `unknown`
   - preferredLocatorType: `unknown`
   - sourceEventIds: `55555555-5555-4555-8555-555555555555`

## Safety Notes
- 执行前前台应用必须是 com.apple.finder。
- 执行该知识条目时，需要老师确认后再执行。
- 列表位置可能随窗口尺寸变化而漂移。

## Failure Policy
- onContextMismatch: `stopAndAskTeacher`
- onStepError: `stopAndAskTeacher`
- onUnknownAction: `stopAndAskTeacher`

## Runtime Requirements
- requiresTeacherConfirmation: `true`
- expectedStepCount: `3`
- requiredFrontmostAppBundleId: `com.apple.finder`
- confidence: `0.91`
