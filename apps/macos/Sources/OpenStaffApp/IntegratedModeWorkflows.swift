import Foundation

struct IntegratedTeachingWorkflowResult {
    let sessionId: String
    let dateKey: String
    let rawEventCount: Int
    let taskChunkCount: Int
    let knowledgeItemCount: Int
    let knowledgeItemFilePaths: [URL]
}

struct TeachingSkillBuildResult {
    let skillDirectory: URL
    let skillName: String
    let llmOutputAccepted: Bool
    let diagnostics: [String]
    let llmOutputPath: URL
}

final class IntegratedModeWorkflowRunner {
    private let fileManager: FileManager
    // Teaching pipeline prefers one task per start/stop session, and delegates noise filtering to LLM.
    private let teachingSlicingPolicy = TaskSlicingPolicy(
        idleGapSeconds: TimeInterval.greatestFiniteMagnitude,
        splitOnContextSwitch: false
    )

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func buildKnowledgeFromCapturedSession(sessionId: String) throws -> IntegratedTeachingWorkflowResult {
        let dateKey = try resolveDateKeyForCapturedSession(sessionId: sessionId)

        let rawLoader = SessionRawEventLoader(fileManager: fileManager)
        let loaded = try rawLoader.load(
            sessionId: sessionId,
            dateKey: dateKey,
            rawRootDirectory: OpenStaffWorkspacePaths.rawEventsDirectory
        )

        guard !loaded.events.isEmpty else {
            throw IntegratedWorkflowError.emptyCapturedEvents(sessionId: sessionId, dateKey: dateKey)
        }

        let slicer = SessionTaskSlicer(policy: teachingSlicingPolicy)
        let chunks = try slicer.slice(events: loaded.events, sessionId: sessionId)

        let chunkWriter = TaskChunkWriter(fileManager: fileManager)
        _ = try chunkWriter.write(
            chunks: chunks,
            dateKey: dateKey,
            taskChunkRootDirectory: OpenStaffWorkspacePaths.taskChunksDirectory
        )

        let knowledgeBuilder = KnowledgeItemBuilder()
        let rawEventIndex = Dictionary(uniqueKeysWithValues: loaded.events.map { ($0.eventId, $0) })
        let knowledgeItems = chunks.map { knowledgeBuilder.build(from: $0, rawEventIndex: rawEventIndex) }
        let knowledgeWriter = KnowledgeItemWriter(fileManager: fileManager)
        let knowledgeItemFilePaths = try knowledgeWriter.write(
            items: knowledgeItems,
            dateKey: dateKey,
            knowledgeRootDirectory: OpenStaffWorkspacePaths.knowledgeDirectory
        )

        return IntegratedTeachingWorkflowResult(
            sessionId: sessionId,
            dateKey: dateKey,
            rawEventCount: loaded.events.count,
            taskChunkCount: chunks.count,
            knowledgeItemCount: knowledgeItems.count,
            knowledgeItemFilePaths: knowledgeItemFilePaths
        )
    }

    func renderManualPromptPreview(knowledgeItemPath: URL) throws -> String {
        let item = try loadKnowledgeItem(at: knowledgeItemPath)
        let rendered = try runPythonScript(
            relativeScriptPath: "scripts/llm/render_knowledge_prompts.py",
            arguments: [
                "--knowledge-item",
                knowledgeItemPath.path
            ]
        )

        let promptBody = rendered.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !promptBody.isEmpty else {
            throw IntegratedWorkflowError.scriptExecutionFailed(
                script: "render_knowledge_prompts.py",
                exitCode: rendered.terminationStatus,
                stderr: "提示词输出为空。"
            )
        }

        return """
        【OpenStaff 手动 ChatGPT 转换包】
        - sessionId: \(item.sessionId)
        - taskId: \(item.taskId)
        - knowledgeItemId: \(item.knowledgeItemId)
        - knowledgeFile: \(knowledgeItemPath.path)

        使用方式：
        1. 复制下方完整内容到 ChatGPT（system + user prompt）。
        2. 要求 ChatGPT 仅返回 JSON 对象，不要额外解释文字。
        3. 仅将 ChatGPT 的最终 JSON 结果粘贴回 OpenStaff 的“LLM 结果输入框”，点击“执行手动结果”。
        4. 注意：不要把本“转换包”文本粘贴到结果输入框。

        \(promptBody)
        """
    }

    func buildSkillUsingOpenAIAdapter(
        knowledgeItemPath: URL,
        model: String
    ) throws -> TeachingSkillBuildResult {
        _ = try loadKnowledgeItem(at: knowledgeItemPath)
        let dateKey = OpenStaffDateFormatter.dayString(from: Date())
        let baseName = sanitizedOutputBaseName(for: knowledgeItemPath)

        let llmOutputDirectory = OpenStaffWorkspacePaths.llmOutputDirectory
            .appendingPathComponent(dateKey, isDirectory: true)
        try fileManager.createDirectory(at: llmOutputDirectory, withIntermediateDirectories: true)
        let llmOutputPath = llmOutputDirectory.appendingPathComponent("\(baseName)-llm-output.json", isDirectory: false)
        let llmErrorReportPath = llmOutputDirectory.appendingPathComponent("\(baseName)-llm-error-report.json", isDirectory: false)

        _ = try runPythonScript(
            relativeScriptPath: "scripts/llm/chatgpt_adapter.py",
            arguments: [
                "--provider",
                "openai",
                "--model",
                model,
                "--knowledge-item",
                knowledgeItemPath.path,
                "--output",
                llmOutputPath.path,
                "--error-report",
                llmErrorReportPath.path
            ]
        )

        return try buildSkillFromLLMOutputFile(
            knowledgeItemPath: knowledgeItemPath,
            llmOutputPath: llmOutputPath
        )
    }

    func buildSkillFromManualLLMOutput(
        knowledgeItemPath: URL,
        llmOutputText: String
    ) throws -> TeachingSkillBuildResult {
        _ = try loadKnowledgeItem(at: knowledgeItemPath)
        let normalizedOutput = llmOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedOutput.isEmpty else {
            throw IntegratedWorkflowError.manualLLMOutputEmpty
        }
        if normalizedOutput.contains("=== SYSTEM PROMPT ===")
            || normalizedOutput.contains("=== USER PROMPT ===")
            || normalizedOutput.contains("【OpenStaff 手动 ChatGPT 转换包】") {
            throw IntegratedWorkflowError.manualLLMOutputLooksLikePromptPackage
        }

        let dateKey = OpenStaffDateFormatter.dayString(from: Date())
        let baseName = sanitizedOutputBaseName(for: knowledgeItemPath)
        let manualOutputDirectory = OpenStaffWorkspacePaths.llmManualDirectory
            .appendingPathComponent(dateKey, isDirectory: true)
        try fileManager.createDirectory(at: manualOutputDirectory, withIntermediateDirectories: true)
        let manualOutputPath = manualOutputDirectory.appendingPathComponent("\(baseName)-manual-llm-output.txt", isDirectory: false)
        try normalizedOutput.write(to: manualOutputPath, atomically: true, encoding: .utf8)

        return try buildSkillFromLLMOutputFile(
            knowledgeItemPath: knowledgeItemPath,
            llmOutputPath: manualOutputPath
        )
    }

    func runAssistLoop(sessionId: String, emergencyStopActive: Bool) throws -> AssistLoopRunResult {
        let knowledgeItems = try loadKnowledgeItems(preferredSessionId: sessionId)
        guard let primaryItem = knowledgeItems.first else {
            throw IntegratedWorkflowError.knowledgeNotFound
        }

        let stateMachine = ModeStateMachine(initialMode: .teaching, logger: InMemoryOrchestratorStateLogger())
        let orchestrator = AssistModeLoopOrchestrator(
            modeStateMachine: stateMachine,
            predictor: RetrievalBasedAssistPredictor(),
            confirmationPrompter: AssistPopupConfirmationPrompter(forcedDecision: true),
            actionExecutor: AssistActionExecutor(),
            logWriter: AssistLoopLogWriter(logsRootDirectory: OpenStaffWorkspacePaths.logsDirectory)
        )

        let traceId = "trace-gui-assist-\(UUID().uuidString.lowercased())"
        let timestamp = currentTimestamp()
        let input = AssistLoopInput(
            traceId: traceId,
            sessionId: sessionId,
            taskId: primaryItem.taskId,
            timestamp: timestamp,
            teacherConfirmed: true,
            emergencyStopActive: emergencyStopActive,
            completedStepCount: 0,
            currentAppName: primaryItem.context.appName,
            currentAppBundleId: primaryItem.context.appBundleId,
            currentWindowTitle: primaryItem.context.windowTitle,
            currentTaskGoal: primaryItem.goal,
            knowledgeItems: knowledgeItems
        )
        let executionContext = AssistExecutionContext(
            traceId: traceId,
            sessionId: sessionId,
            taskId: primaryItem.taskId,
            dryRun: true,
            emergencyStopActive: emergencyStopActive
        )

        return try orchestrator.run(input: input, executionContext: executionContext)
    }

    func runStudentLoop(
        sessionId: String,
        preferredGoal: String?,
        emergencyStopActive: Bool
    ) throws -> StudentLoopRunResult {
        let knowledgeItems = try loadKnowledgeItems(preferredSessionId: sessionId)
        guard let primaryItem = knowledgeItems.first else {
            throw IntegratedWorkflowError.knowledgeNotFound
        }

        let stateMachine = ModeStateMachine(initialMode: .assist, logger: InMemoryOrchestratorStateLogger())
        let orchestrator = StudentModeLoopOrchestrator(
            modeStateMachine: stateMachine,
            planner: RuleBasedStudentTaskPlanner(),
            skillExecutor: StudentSkillExecutor(),
            logWriter: StudentLoopLogWriter(logsRootDirectory: OpenStaffWorkspacePaths.logsDirectory),
            reportWriter: StudentReviewReportWriter(reportsRootDirectory: OpenStaffWorkspacePaths.reportsDirectory)
        )

        let goal = resolveGoal(preferredGoal: preferredGoal, fallbackItem: primaryItem)
        let traceId = "trace-gui-student-\(UUID().uuidString.lowercased())"
        let timestamp = currentTimestamp()

        let input = StudentLoopInput(
            traceId: traceId,
            sessionId: sessionId,
            taskId: primaryItem.taskId,
            timestamp: timestamp,
            teacherConfirmed: true,
            emergencyStopActive: emergencyStopActive,
            goal: goal,
            preferredKnowledgeItemId: primaryItem.knowledgeItemId,
            pendingAssistSuggestion: false,
            knowledgeItems: knowledgeItems
        )
        let executionContext = StudentExecutionContext(
            traceId: traceId,
            sessionId: sessionId,
            taskId: primaryItem.taskId,
            dryRun: true,
            emergencyStopActive: emergencyStopActive
        )

        return try orchestrator.run(input: input, executionContext: executionContext)
    }

    private func resolveGoal(preferredGoal: String?, fallbackItem: KnowledgeItem) -> String {
        if let preferredGoal {
            let normalized = preferredGoal.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty {
                return normalized
            }
        }
        return fallbackItem.goal
    }

    private func resolveDateKeyForCapturedSession(sessionId: String) throws -> String {
        let rawRoot = OpenStaffWorkspacePaths.rawEventsDirectory
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rawRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw IntegratedWorkflowError.rawEventDirectoryMissing(rawRoot.path)
        }

        let dateDirectories = try fileManager.contentsOfDirectory(
            at: rawRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            .sorted { lhs, rhs in
                lhs.lastPathComponent > rhs.lastPathComponent
            }

        for dateDirectory in dateDirectories {
            if try containsSessionFile(in: dateDirectory, sessionId: sessionId) {
                return dateDirectory.lastPathComponent
            }
        }

        throw IntegratedWorkflowError.rawEventsForSessionNotFound(sessionId: sessionId)
    }

    private func containsSessionFile(in dateDirectory: URL, sessionId: String) throws -> Bool {
        let files = try fileManager.contentsOfDirectory(
            at: dateDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        let baseName = "\(sessionId).jsonl"
        let rotatedPrefix = "\(sessionId)-r"

        return files.contains { fileURL in
            guard fileURL.pathExtension == "jsonl" else {
                return false
            }
            let filename = fileURL.lastPathComponent
            if filename == baseName {
                return true
            }
            return filename.hasPrefix(rotatedPrefix) && filename.hasSuffix(".jsonl")
        }
    }

    private func loadKnowledgeItems(preferredSessionId: String?) throws -> [KnowledgeItem] {
        let root = OpenStaffWorkspacePaths.knowledgeDirectory
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw IntegratedWorkflowError.knowledgeDirectoryMissing(root.path)
        }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw IntegratedWorkflowError.knowledgeNotFound
        }

        let decoder = JSONDecoder()
        var allItems: [KnowledgeItem] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "json" else {
                continue
            }
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else {
                continue
            }

            let data: Data
            do {
                data = try Data(contentsOf: fileURL)
            } catch {
                continue
            }

            if let item = try? decoder.decode(KnowledgeItem.self, from: data) {
                allItems.append(item)
            }
        }

        guard !allItems.isEmpty else {
            throw IntegratedWorkflowError.knowledgeNotFound
        }

        if let preferredSessionId {
            let matched = allItems.filter { $0.sessionId == preferredSessionId }
            if !matched.isEmpty {
                return matched.sorted { lhs, rhs in
                    lhs.createdAt > rhs.createdAt
                }
            }
        }

        return allItems.sorted { lhs, rhs in
            lhs.createdAt > rhs.createdAt
        }
    }

    private func currentTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private func buildSkillFromLLMOutputFile(
        knowledgeItemPath: URL,
        llmOutputPath: URL
    ) throws -> TeachingSkillBuildResult {
        let dateKey = OpenStaffDateFormatter.dayString(from: Date())
        let baseName = sanitizedOutputBaseName(for: knowledgeItemPath)
        let reportDirectory = OpenStaffWorkspacePaths.llmReportDirectory
            .appendingPathComponent(dateKey, isDirectory: true)
        try fileManager.createDirectory(at: reportDirectory, withIntermediateDirectories: true)
        let mapperReportPath = reportDirectory.appendingPathComponent("\(baseName)-skill-map-report.json", isDirectory: false)

        _ = try runPythonScript(
            relativeScriptPath: "scripts/skills/openclaw_skill_mapper.py",
            arguments: [
                "--knowledge-item",
                knowledgeItemPath.path,
                "--llm-output",
                llmOutputPath.path,
                "--skills-root",
                OpenStaffWorkspacePaths.skillsPendingDirectory.path,
                "--overwrite",
                "--report",
                mapperReportPath.path
            ]
        )

        let reportData: Data
        do {
            reportData = try Data(contentsOf: mapperReportPath)
        } catch {
            throw IntegratedWorkflowError.skillMapperReportMissing(mapperReportPath.path)
        }

        let report: SkillMapperReport
        do {
            report = try JSONDecoder().decode(SkillMapperReport.self, from: reportData)
        } catch {
            throw IntegratedWorkflowError.skillMapperReportInvalid(mapperReportPath.path)
        }

        return TeachingSkillBuildResult(
            skillDirectory: URL(fileURLWithPath: report.skillDir, isDirectory: true),
            skillName: report.skillName,
            llmOutputAccepted: report.llmOutputAccepted,
            diagnostics: report.diagnostics,
            llmOutputPath: llmOutputPath
        )
    }

    private func runPythonScript(
        relativeScriptPath: String,
        arguments: [String]
    ) throws -> PythonScriptExecutionResult {
        let scriptURL = OpenStaffWorkspacePaths.repositoryRoot.appendingPathComponent(relativeScriptPath, isDirectory: false)
        guard fileManager.fileExists(atPath: scriptURL.path) else {
            throw IntegratedWorkflowError.scriptMissing(scriptURL.path)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", scriptURL.path] + arguments
        process.currentDirectoryURL = OpenStaffWorkspacePaths.repositoryRoot

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw IntegratedWorkflowError.pythonRuntimeUnavailable
        }

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        let status = process.terminationStatus
        guard status == 0 else {
            let failureMessage = [stderr.trimmingCharacters(in: .whitespacesAndNewlines), stdout.trimmingCharacters(in: .whitespacesAndNewlines)]
                .filter { !$0.isEmpty }
                .joined(separator: " | ")
            throw IntegratedWorkflowError.scriptExecutionFailed(
                script: relativeScriptPath,
                exitCode: status,
                stderr: failureMessage.isEmpty ? "未知错误" : failureMessage
            )
        }

        return PythonScriptExecutionResult(
            terminationStatus: status,
            stdout: stdout,
            stderr: stderr
        )
    }

    private func loadKnowledgeItem(at path: URL) throws -> KnowledgeItem {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw IntegratedWorkflowError.knowledgeItemPathMissing(path.path)
        }

        do {
            let data = try Data(contentsOf: path)
            return try JSONDecoder().decode(KnowledgeItem.self, from: data)
        } catch {
            throw IntegratedWorkflowError.knowledgeItemReadFailed(path.path)
        }
    }

    private func sanitizedOutputBaseName(for knowledgeItemPath: URL) -> String {
        let rawName = knowledgeItemPath.deletingPathExtension().lastPathComponent
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let sanitized = rawName.unicodeScalars
            .map { scalar -> String in
                allowed.contains(scalar) ? String(scalar) : "-"
            }
            .joined()
        return sanitized.isEmpty ? "openstaff-task" : sanitized
    }
}

enum IntegratedWorkflowError: LocalizedError {
    case rawEventDirectoryMissing(String)
    case rawEventsForSessionNotFound(sessionId: String)
    case emptyCapturedEvents(sessionId: String, dateKey: String)
    case knowledgeDirectoryMissing(String)
    case knowledgeNotFound
    case knowledgeItemPathMissing(String)
    case knowledgeItemReadFailed(String)
    case manualLLMOutputEmpty
    case manualLLMOutputLooksLikePromptPackage
    case pythonRuntimeUnavailable
    case scriptMissing(String)
    case scriptExecutionFailed(script: String, exitCode: Int32, stderr: String)
    case skillMapperReportMissing(String)
    case skillMapperReportInvalid(String)

    var errorDescription: String? {
        switch self {
        case .rawEventDirectoryMissing(let path):
            return "教学模式原始事件目录不存在：\(path)"
        case .rawEventsForSessionNotFound(let sessionId):
            return "未找到会话 \(sessionId) 的采集事件文件。"
        case .emptyCapturedEvents(let sessionId, let dateKey):
            return "会话 \(sessionId) 在 \(dateKey) 下没有可切片事件。"
        case .knowledgeDirectoryMissing(let path):
            return "知识目录不存在：\(path)"
        case .knowledgeNotFound:
            return "未找到可用于辅助/学生模式的知识条目。"
        case .knowledgeItemPathMissing(let path):
            return "知识条目文件不存在：\(path)"
        case .knowledgeItemReadFailed(let path):
            return "读取知识条目失败：\(path)"
        case .manualLLMOutputEmpty:
            return "手动粘贴的 LLM 结果为空，无法执行。"
        case .manualLLMOutputLooksLikePromptPackage:
            return "检测到你粘贴的是 OpenStaff 提示词包而非 ChatGPT 最终 JSON。请仅粘贴 ChatGPT 返回结果。"
        case .pythonRuntimeUnavailable:
            return "Python 运行时不可用（需可执行 python3）。"
        case .scriptMissing(let path):
            return "脚本不存在：\(path)"
        case .scriptExecutionFailed(let script, let exitCode, let stderr):
            return "脚本执行失败：\(script)（exit=\(exitCode)）\(stderr)"
        case .skillMapperReportMissing(let path):
            return "未找到 skill 映射报告：\(path)"
        case .skillMapperReportInvalid(let path):
            return "解析 skill 映射报告失败：\(path)"
        }
    }
}

private struct PythonScriptExecutionResult {
    let terminationStatus: Int32
    let stdout: String
    let stderr: String
}

private struct SkillMapperReport: Decodable {
    let status: String
    let skillDir: String
    let skillName: String
    let llmOutputAccepted: Bool
    let diagnostics: [String]
}
