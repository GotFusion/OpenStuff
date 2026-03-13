import Foundation

struct LoadedTaskChunks {
    let sourceFiles: [URL]
    let chunks: [TaskChunk]
}

struct TaskChunkLoader {
    private let fileManager: FileManager
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func load(
        sessionId: String,
        dateKey: String,
        taskChunkRootDirectory: URL
    ) throws -> LoadedTaskChunks {
        let dateDirectory = taskChunkRootDirectory.appendingPathComponent(dateKey, isDirectory: true)

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: dateDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw TaskChunkLoaderError.missingDateDirectory(dateDirectory.path)
        }

        let files = try discoverTaskChunkFiles(sessionId: sessionId, in: dateDirectory)
        guard !files.isEmpty else {
            throw TaskChunkLoaderError.noTaskChunkFiles(sessionId: sessionId, dateDirectory: dateDirectory.path)
        }

        var chunks: [TaskChunk] = []
        for fileURL in files {
            do {
                let data = try Data(contentsOf: fileURL)
                let chunk = try decoder.decode(TaskChunk.self, from: data)
                guard chunk.sessionId == sessionId else {
                    throw TaskChunkLoaderError.sessionMismatch(
                        expected: sessionId,
                        actual: chunk.sessionId,
                        filePath: fileURL.path
                    )
                }
                chunks.append(chunk)
            } catch let error as TaskChunkLoaderError {
                throw error
            } catch {
                throw TaskChunkLoaderError.decodeChunkFailed(filePath: fileURL.path, underlying: error)
            }
        }

        return LoadedTaskChunks(sourceFiles: files, chunks: chunks)
    }

    private func discoverTaskChunkFiles(sessionId: String, in directory: URL) throws -> [URL] {
        let files: [URL]
        do {
            files = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw TaskChunkLoaderError.listDirectoryFailed(directory.path, error)
        }

        let prefix = "task-\(sessionId)-"
        let candidates = files.compactMap { fileURL -> URL? in
            guard fileURL.pathExtension == "json" else {
                return nil
            }
            guard fileURL.lastPathComponent.hasPrefix(prefix) else {
                return nil
            }

            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else {
                return nil
            }

            return fileURL
        }

        return candidates.sorted { lhs, rhs in
            lhs.lastPathComponent < rhs.lastPathComponent
        }
    }
}

struct KnowledgeItemBuilder {
    private let nowProvider: () -> Date
    private let timestampFormatter: ISO8601DateFormatter
    private let summaryGenerator: KnowledgeSummaryGenerator

    init(
        nowProvider: @escaping () -> Date = Date.init,
        summaryGenerator: KnowledgeSummaryGenerator = KnowledgeSummaryGenerator()
    ) {
        self.nowProvider = nowProvider
        self.summaryGenerator = summaryGenerator

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.timestampFormatter = formatter
    }

    func build(from chunk: TaskChunk, rawEventIndex: [String: RawEvent] = [:]) -> KnowledgeItem {
        let knowledgeItemId = "ki-\(chunk.taskId)"
        let goal = "在 \(chunk.primaryContext.appName) 中复现任务 \(chunk.taskId) 的操作流程"

        let steps = buildSteps(from: chunk, rawEventIndex: rawEventIndex)
        let summary = summaryGenerator.generate(from: chunk, steps: steps)
        let context = KnowledgeContext(
            appName: chunk.primaryContext.appName,
            appBundleId: chunk.primaryContext.appBundleId,
            windowTitle: chunk.primaryContext.windowTitle,
            windowId: chunk.primaryContext.windowId
        )

        let constraints: [KnowledgeConstraint] = [
            KnowledgeConstraint(
                type: .frontmostAppMustMatch,
                description: "执行前前台应用必须是 \(chunk.primaryContext.appBundleId)。"
            ),
            KnowledgeConstraint(
                type: .manualConfirmationRequired,
                description: "执行该知识条目时，需要老师确认后再执行。"
            ),
            KnowledgeConstraint(
                type: .coordinateTargetMayDrift,
                description: "坐标点击目标可能随分辨率或界面变化漂移。"
            )
        ]

        let source = KnowledgeSource(
            taskChunkSchemaVersion: chunk.schemaVersion,
            startTimestamp: chunk.startTimestamp,
            endTimestamp: chunk.endTimestamp,
            eventCount: chunk.eventCount,
            boundaryReason: chunk.boundaryReason
        )

        return KnowledgeItem(
            knowledgeItemId: knowledgeItemId,
            taskId: chunk.taskId,
            sessionId: chunk.sessionId,
            goal: goal,
            summary: summary,
            steps: steps,
            context: context,
            constraints: constraints,
            source: source,
            createdAt: timestampFormatter.string(from: nowProvider())
        )
    }

    private func buildSteps(from chunk: TaskChunk, rawEventIndex: [String: RawEvent]) -> [KnowledgeStep] {
        if chunk.eventIds.isEmpty {
            return [
                KnowledgeStep(
                    stepId: "step-001",
                    instruction: "该任务片段未包含可回放事件，请老师补充操作示例。",
                    sourceEventIds: []
                )
            ]
        }

        var steps: [KnowledgeStep] = []
        steps.reserveCapacity(chunk.eventIds.count)

        var cursor = 0
        while cursor < chunk.eventIds.count {
            let eventId = chunk.eventIds[cursor]
            let stepId = String(format: "step-%03d", steps.count + 1)

            guard let event = rawEventIndex[eventId] else {
                steps.append(
                    KnowledgeStep(
                        stepId: stepId,
                        instruction: "执行第 \(steps.count + 1) 步操作（源事件 \(eventId)）。",
                        sourceEventIds: [eventId]
                    )
                )
                cursor += 1
                continue
            }

            if event.action == .keyDown,
               let keyboardStep = buildKeyboardStep(
                    stepId: stepId,
                    stepNumber: steps.count + 1,
                    chunkEventIds: chunk.eventIds,
                    startIndex: cursor,
                    rawEventIndex: rawEventIndex
               ) {
                steps.append(keyboardStep.step)
                cursor = keyboardStep.nextIndex
                continue
            }

            steps.append(buildPointerStep(stepId: stepId, stepNumber: steps.count + 1, event: event))
            cursor += 1
        }

        return steps
    }

    private func buildPointerStep(stepId: String, stepNumber: Int, event: RawEvent) -> KnowledgeStep {
        let actionText: String
        switch event.action {
        case .leftClick:
            actionText = "点击"
        case .rightClick:
            actionText = "右键点击"
        case .doubleClick:
            actionText = "双击点击"
        case .keyDown:
            actionText = "键盘操作"
        }

        let semanticTargets = semanticTargets(for: event)

        return KnowledgeStep(
            stepId: stepId,
            instruction: "执行第 \(stepNumber) 步\(actionText)操作（x=\(event.pointer.x), y=\(event.pointer.y)，源事件 \(event.eventId)）。",
            sourceEventIds: [event.eventId],
            target: KnowledgeStepTarget(
                coordinate: event.pointer,
                semanticTargets: semanticTargets,
                preferredLocatorType: semanticTargets.first?.locatorType
            )
        )
    }

    private func semanticTargets(for event: RawEvent) -> [SemanticTarget] {
        var targets: [SemanticTarget] = []

        if let focusedElement = event.contextSnapshot.focusedElement,
           focusedElement.role != nil
            || focusedElement.title != nil
            || focusedElement.identifier != nil
            || focusedElement.descriptionText != nil
            || focusedElement.helpText != nil {
            let elementTitle = focusedElement.title
                ?? focusedElement.descriptionText
                ?? focusedElement.helpText

            targets.append(
                SemanticTarget(
                    locatorType: .roleAndTitle,
                    appBundleId: event.contextSnapshot.appBundleId,
                    windowTitlePattern: SemanticTarget.exactWindowTitlePattern(for: event.contextSnapshot.windowTitle),
                    elementRole: focusedElement.role ?? focusedElement.subrole,
                    elementTitle: elementTitle,
                    elementIdentifier: focusedElement.identifier,
                    boundingRect: focusedElement.boundingRect,
                    confidence: 0.68,
                    source: .capture
                )
            )
        }

        targets.append(
            SemanticTarget.coordinateFallback(
                appBundleId: event.contextSnapshot.appBundleId,
                windowTitle: event.contextSnapshot.windowTitle,
                coordinate: event.pointer
            )
        )

        return targets
    }

    private func buildKeyboardStep(
        stepId: String,
        stepNumber: Int,
        chunkEventIds: [String],
        startIndex: Int,
        rawEventIndex: [String: RawEvent]
    ) -> (step: KnowledgeStep, nextIndex: Int)? {
        guard startIndex < chunkEventIds.count,
              let firstEvent = rawEventIndex[chunkEventIds[startIndex]],
              firstEvent.action == .keyDown else {
            return nil
        }

        if isShortcutEvent(firstEvent),
           let shortcut = shortcutSpec(from: firstEvent) {
            let instruction = "执行第 \(stepNumber) 步快捷键 \(shortcut)（源事件 \(firstEvent.eventId)）。"
            return (
                KnowledgeStep(stepId: stepId, instruction: instruction, sourceEventIds: [firstEvent.eventId]),
                startIndex + 1
            )
        }

        var cursor = startIndex
        var sourceEventIds: [String] = []
        var textBuffer = ""
        var appendReturn = false

        while cursor < chunkEventIds.count {
            guard let current = rawEventIndex[chunkEventIds[cursor]],
                  current.action == .keyDown,
                  !isShortcutEvent(current),
                  let token = keyboardToken(from: current) else {
                break
            }

            sourceEventIds.append(current.eventId)
            switch token {
            case .printable(let value):
                textBuffer.append(value)
            case .space:
                textBuffer.append(" ")
            case .delete:
                if !textBuffer.isEmpty {
                    textBuffer.removeLast()
                }
            case .returnKey:
                appendReturn = true
                cursor += 1
                break
            case .tab:
                if textBuffer.isEmpty {
                    let instruction = "执行第 \(stepNumber) 步快捷键 tab（源事件 \(current.eventId)）。"
                    return (
                        KnowledgeStep(stepId: stepId, instruction: instruction, sourceEventIds: [current.eventId]),
                        cursor + 1
                    )
                }
                break
            case .escape:
                if textBuffer.isEmpty {
                    let instruction = "执行第 \(stepNumber) 步快捷键 escape（源事件 \(current.eventId)）。"
                    return (
                        KnowledgeStep(stepId: stepId, instruction: instruction, sourceEventIds: [current.eventId]),
                        cursor + 1
                    )
                }
                break
            }

            if appendReturn {
                break
            }
            cursor += 1
        }

        if !textBuffer.isEmpty {
            let escaped = textBuffer.replacingOccurrences(of: "“", with: "\"")
                .replacingOccurrences(of: "”", with: "\"")
            let enterSuffix = appendReturn ? "并按回车" : ""
            let instruction = "执行第 \(stepNumber) 步输入\"\(escaped)\"\(enterSuffix)（源事件 \(sourceEventIds.joined(separator: ", "))）。"
            return (
                KnowledgeStep(stepId: stepId, instruction: instruction, sourceEventIds: sourceEventIds),
                max(cursor, startIndex + 1)
            )
        }

        if appendReturn {
            let instruction = "执行第 \(stepNumber) 步快捷键 return（源事件 \(sourceEventIds.joined(separator: ", "))）。"
            return (
                KnowledgeStep(stepId: stepId, instruction: instruction, sourceEventIds: sourceEventIds),
                max(cursor, startIndex + 1)
            )
        }

        if let shortcut = shortcutSpec(from: firstEvent) {
            let instruction = "执行第 \(stepNumber) 步快捷键 \(shortcut)（源事件 \(firstEvent.eventId)）。"
            return (
                KnowledgeStep(stepId: stepId, instruction: instruction, sourceEventIds: [firstEvent.eventId]),
                startIndex + 1
            )
        }

        return nil
    }

    private func isShortcutEvent(_ event: RawEvent) -> Bool {
        let modifiers = Set(event.modifiers)
        return modifiers.contains(.command)
            || modifiers.contains(.option)
            || modifiers.contains(.control)
    }

    private func shortcutSpec(from event: RawEvent) -> String? {
        guard event.action == .keyDown else {
            return nil
        }

        let key = shortcutKey(from: event)
        guard let key, !key.isEmpty else {
            return nil
        }

        var tokens: [String] = []
        let modifiers = Set(event.modifiers)
        if modifiers.contains(.command) {
            tokens.append("command")
        }
        if modifiers.contains(.shift) {
            tokens.append("shift")
        }
        if modifiers.contains(.option) {
            tokens.append("option")
        }
        if modifiers.contains(.control) {
            tokens.append("control")
        }
        tokens.append(key)
        return tokens.joined(separator: "+")
    }

    private func shortcutKey(from event: RawEvent) -> String? {
        if let charactersIgnoringModifiers = event.keyboard?.charactersIgnoringModifiers,
           !charactersIgnoringModifiers.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let normalized = normalizeShortcutKey(charactersIgnoringModifiers)
            if !normalized.isEmpty {
                return normalized
            }
        }

        guard let keyCode = event.keyboard?.keyCode else {
            return nil
        }
        switch keyCode {
        case 36, 76: return "return"
        case 48: return "tab"
        case 53: return "escape"
        case 51: return "delete"
        case 49: return "space"
        default: return nil
        }
    }

    private func normalizeShortcutKey(_ raw: String) -> String {
        if raw == "\r" || raw == "\n" {
            return "return"
        }
        if raw == "\t" {
            return "tab"
        }
        if raw == "\u{1B}" {
            return "escape"
        }
        if raw == "\u{7F}" {
            return "delete"
        }
        if raw == " " {
            return "space"
        }
        if raw.count == 1 {
            return raw.lowercased()
        }
        return raw.lowercased()
    }

    private enum KeyboardToken {
        case printable(String)
        case space
        case returnKey
        case tab
        case escape
        case delete
    }

    private func keyboardToken(from event: RawEvent) -> KeyboardToken? {
        guard event.action == .keyDown else {
            return nil
        }

        if let characters = event.keyboard?.characters,
           let parsed = parseKeyboardTokenFromCharacters(characters) {
            return parsed
        }

        if let charactersIgnoringModifiers = event.keyboard?.charactersIgnoringModifiers,
           let parsed = parseKeyboardTokenFromCharacters(charactersIgnoringModifiers) {
            return parsed
        }

        guard let keyCode = event.keyboard?.keyCode else {
            return nil
        }
        switch keyCode {
        case 36, 76: return .returnKey
        case 48: return .tab
        case 53: return .escape
        case 51: return .delete
        case 49: return .space
        default: return nil
        }
    }

    private func parseKeyboardTokenFromCharacters(_ raw: String) -> KeyboardToken? {
        if raw == "\r" || raw == "\n" {
            return .returnKey
        }
        if raw == "\t" {
            return .tab
        }
        if raw == "\u{1B}" {
            return .escape
        }
        if raw == "\u{7F}" {
            return .delete
        }
        if raw == " " {
            return .space
        }

        guard raw.count == 1 else {
            return nil
        }
        return .printable(raw)
    }
}

struct KnowledgeItemWriter {
    private let fileManager: FileManager
    private let encoder: JSONEncoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
    }

    @discardableResult
    func write(
        items: [KnowledgeItem],
        dateKey: String,
        knowledgeRootDirectory: URL
    ) throws -> [URL] {
        let outputDirectory = knowledgeRootDirectory.appendingPathComponent(dateKey, isDirectory: true)

        do {
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            throw KnowledgeItemWriterError.createOutputDirectoryFailed(outputDirectory.path, error)
        }

        var outputFiles: [URL] = []
        for item in items {
            let outputURL = outputDirectory.appendingPathComponent("\(item.taskId).json", isDirectory: false)
            do {
                let data = try encoder.encode(item)
                try data.write(to: outputURL, options: [.atomic])
                outputFiles.append(outputURL)
            } catch {
                throw KnowledgeItemWriterError.writeItemFailed(outputURL.path, error)
            }
        }

        return outputFiles
    }
}

enum TaskChunkLoaderError: LocalizedError {
    case missingDateDirectory(String)
    case noTaskChunkFiles(sessionId: String, dateDirectory: String)
    case listDirectoryFailed(String, Error)
    case decodeChunkFailed(filePath: String, underlying: Error)
    case sessionMismatch(expected: String, actual: String, filePath: String)

    var errorDescription: String? {
        switch self {
        case .missingDateDirectory(let path):
            return "Task chunk date directory not found: \(path)"
        case .noTaskChunkFiles(let sessionId, let dateDirectory):
            return "No task chunk files found for session \(sessionId) in \(dateDirectory)."
        case .listDirectoryFailed(let path, let error):
            return "Failed to list task chunk directory \(path): \(error.localizedDescription)"
        case .decodeChunkFailed(let filePath, let underlying):
            return "Failed to decode task chunk \(filePath): \(underlying.localizedDescription)"
        case .sessionMismatch(let expected, let actual, let filePath):
            return "Session mismatch in task chunk \(filePath). expected=\(expected), actual=\(actual)."
        }
    }
}

enum KnowledgeItemWriterError: LocalizedError {
    case createOutputDirectoryFailed(String, Error)
    case writeItemFailed(String, Error)

    var errorDescription: String? {
        switch self {
        case .createOutputDirectoryFailed(let path, let error):
            return "Failed to create knowledge output directory \(path): \(error.localizedDescription)"
        case .writeItemFailed(let path, let error):
            return "Failed to write knowledge item file \(path): \(error.localizedDescription)"
        }
    }
}
