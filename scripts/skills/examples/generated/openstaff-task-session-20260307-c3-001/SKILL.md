---
name: openstaff-task-session-20260307-c3-001
description: 在 Terminal 中创建日志目录并查看当前路径
user-invocable: true
disable-model-invocation: false
metadata: {"openclaw":{"emoji":"🎓","skillKey":"openstaff-task-session-20260307-c3-001","requires":{"config":["openstaff.enabled"]}},"openstaff":{"knowledgeItemId":"ki-task-session-20260307-c3-001","taskId":"task-session-20260307-c3-001","sessionId":"session-20260307-c3","repairVersion":0}}
---

# 在 Terminal 中创建日志目录并查看当前路径

## Context
- appName: `Terminal`
- appBundleId: `com.apple.Terminal`
- windowTitle: `zsh`

## Provenance
- sessionId: `session-20260307-c3`
- taskId: `task-session-20260307-c3-001`
- knowledgeItemId: `ki-task-session-20260307-c3-001`
- sourceTaskChunkSchemaVersion: `knowledge.task-chunk.v0`
- sourceEventCount: `2`
- knowledgeGeneratorVersion: `rule-v0`
- skillGeneratorVersion: `openstaff-skill-mapper-v1`
- repairVersion: `0`

## Teacher Summary
在 Terminal（zsh）中，步骤摘要：输入 -> 输入。共 2 步，任务分段原因：会话结束切分。

## Steps
1. [input] 输入命令 mkdir -p ~/Desktop/OpenStaffLogs。
   - knowledgeStepId: `step-001`
   - target: `unknown`
   - preferredLocatorType: `unknown`
   - sourceEventIds: `66666666-6666-4666-8666-666666666666`
2. [input] 输入命令 pwd 并回车。
   - knowledgeStepId: `step-002`
   - target: `unknown`
   - preferredLocatorType: `unknown`
   - sourceEventIds: `77777777-7777-4777-8777-777777777777`

## Safety Notes
- 执行前前台应用必须是 com.apple.Terminal。
- 执行命令前需要老师确认，避免误操作。
- 终端窗口位置变化不影响命令执行，但焦点需要正确。

## Failure Policy
- onContextMismatch: `stopAndAskTeacher`
- onStepError: `stopAndAskTeacher`
- onUnknownAction: `stopAndAskTeacher`

## Runtime Requirements
- requiresTeacherConfirmation: `true`
- expectedStepCount: `2`
- requiredFrontmostAppBundleId: `com.apple.Terminal`
- confidence: `0.72`
