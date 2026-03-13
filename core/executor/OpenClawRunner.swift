import Foundation

public struct OpenClawSubprocessOutput: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol OpenClawSubprocessRunning {
    func run(request: OpenClawExecutionRequest) throws -> OpenClawSubprocessOutput
}

public enum OpenClawSubprocessRunnerError: LocalizedError {
    case executableMissing(String)
    case launchFailed(String, underlying: Error)
    case timedOut(String, seconds: Int)

    public var errorDescription: String? {
        switch self {
        case .executableMissing(let path):
            return "OpenClaw executable not found: \(path)"
        case .launchFailed(let path, let underlying):
            return "Failed to launch OpenClaw executable \(path): \(underlying.localizedDescription)"
        case .timedOut(let path, let seconds):
            return "OpenClaw executable \(path) timed out after \(seconds) seconds."
        }
    }
}

public struct FoundationOpenClawSubprocessRunner: OpenClawSubprocessRunning {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func run(request: OpenClawExecutionRequest) throws -> OpenClawSubprocessOutput {
        let executablePath = request.runtimeExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !executablePath.isEmpty else {
            throw OpenClawSubprocessRunnerError.executableMissing(request.runtimeExecutablePath)
        }
        guard fileManager.isExecutableFile(atPath: executablePath) else {
            throw OpenClawSubprocessRunnerError.executableMissing(executablePath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath, isDirectory: false)
        process.arguments = request.runtimeArguments

        if let workingDirectoryPath = request.workingDirectoryPath,
           !workingDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectoryPath, isDirectory: true)
        }

        var environment = ProcessInfo.processInfo.environment
        for (key, value) in request.runtimeEnvironment {
            environment[key] = value
        }
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw OpenClawSubprocessRunnerError.launchFailed(executablePath, underlying: error)
        }

        if let timeoutSeconds = request.timeoutSeconds, timeoutSeconds > 0 {
            let deadline = Date().addingTimeInterval(Double(timeoutSeconds))
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
                throw OpenClawSubprocessRunnerError.timedOut(executablePath, seconds: timeoutSeconds)
            }
        } else {
            process.waitUntilExit()
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        return OpenClawSubprocessOutput(
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr
        )
    }
}

public struct OpenClawRunner {
    private let subprocessRunner: any OpenClawSubprocessRunning
    private let preflightValidator: SkillPreflightValidator
    private let fileManager: FileManager
    private let nowProvider: () -> Date
    private let formatter: ISO8601DateFormatter
    private let encoder: JSONEncoder

    public init(
        subprocessRunner: any OpenClawSubprocessRunning = FoundationOpenClawSubprocessRunner(),
        preflightValidator: SkillPreflightValidator = SkillPreflightValidator(),
        fileManager: FileManager = .default,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.subprocessRunner = subprocessRunner
        self.preflightValidator = preflightValidator
        self.fileManager = fileManager
        self.nowProvider = nowProvider

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.formatter = formatter

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
    }

    public func execute(request: OpenClawExecutionRequest) -> OpenClawExecutionResult {
        let startedAt = timestamp(nowProvider())
        let validationError = validate(request: request)
        if let validationError {
            return finalizeTerminal(
                request: request,
                startedAt: startedAt,
                finishedAt: timestamp(nowProvider()),
                status: .failed,
                summary: validationError,
                errorCode: OpenClawExecutionErrorCode.runnerInvalidRequest.rawValue,
                stdout: "",
                stderr: validationError,
                exitCode: nil
            )
        }

        let preflight = preflightValidator.validateSkillDirectory(
            at: URL(fileURLWithPath: request.skillDirectoryPath, isDirectory: true)
        )
        if preflight.status == .failed {
            return finalizeTerminal(
                request: request,
                startedAt: startedAt,
                finishedAt: timestamp(nowProvider()),
                status: terminalStatus(for: preflight),
                summary: preflight.summary,
                errorCode: OpenClawExecutionErrorCode.skillPreflightFailed.rawValue,
                stdout: "",
                stderr: preflight.userFacingIssueMessages.joined(separator: "\n"),
                exitCode: nil,
                preflight: preflight
            )
        }
        if preflight.requiresTeacherConfirmation && !request.teacherConfirmed {
            return finalizeTerminal(
                request: request,
                startedAt: startedAt,
                finishedAt: timestamp(nowProvider()),
                status: .blocked,
                summary: preflight.summary,
                errorCode: OpenClawExecutionErrorCode.skillConfirmationRequired.rawValue,
                stdout: "",
                stderr: preflight.userFacingIssueMessages.joined(separator: "\n"),
                exitCode: nil,
                preflight: preflight
            )
        }

        let startEntry = OpenClawExecutionLogEntry(
            timestamp: startedAt,
            traceId: request.traceId,
            sessionId: request.sessionId,
            taskId: request.taskId,
            component: request.component,
            status: "STATUS_OCW_EXECUTION_STARTED",
            message: "OpenClaw execution started for skill \(request.skillName).",
            skillName: request.skillName,
            skillDirectoryPath: request.skillDirectoryPath
        )

        let startLogWrite = appendLog(entry: startEntry, logsRootDirectoryPath: request.logsRootDirectoryPath)
        if let logWriteError = startLogWrite.errorDescription {
            return finalizeTerminal(
                request: request,
                startedAt: startedAt,
                finishedAt: timestamp(nowProvider()),
                status: .failed,
                summary: "Failed to write OpenClaw start log.",
                errorCode: OpenClawExecutionErrorCode.logWriteFailed.rawValue,
                stdout: "",
                stderr: logWriteError,
                exitCode: nil,
                preflight: preflight
            )
        }

        let subprocessOutput: OpenClawSubprocessOutput
        do {
            subprocessOutput = try subprocessRunner.run(request: request)
        } catch let error as OpenClawSubprocessRunnerError {
            let errorCode: String
            switch error {
            case .executableMissing:
                errorCode = OpenClawExecutionErrorCode.runtimeExecutableMissing.rawValue
            case .launchFailed:
                errorCode = OpenClawExecutionErrorCode.processLaunchFailed.rawValue
            case .timedOut:
                errorCode = OpenClawExecutionErrorCode.processTimedOut.rawValue
            }
            return finalizeTerminal(
                request: request,
                startedAt: startedAt,
                finishedAt: timestamp(nowProvider()),
                status: .failed,
                summary: error.localizedDescription,
                errorCode: errorCode,
                stdout: "",
                stderr: error.localizedDescription,
                exitCode: nil,
                preflight: preflight
            )
        } catch {
            return finalizeTerminal(
                request: request,
                startedAt: startedAt,
                finishedAt: timestamp(nowProvider()),
                status: .failed,
                summary: error.localizedDescription,
                errorCode: OpenClawExecutionErrorCode.processLaunchFailed.rawValue,
                stdout: "",
                stderr: error.localizedDescription,
                exitCode: nil,
                preflight: preflight
            )
        }

        guard let gatewayPayload = decodeGatewayPayload(from: subprocessOutput.stdout) else {
            let summary = "OpenClaw runtime returned non-JSON or invalid structured output."
            return finalizeTerminal(
                request: request,
                startedAt: startedAt,
                finishedAt: timestamp(nowProvider()),
                status: .failed,
                summary: summary,
                errorCode: OpenClawExecutionErrorCode.invalidRuntimeOutput.rawValue,
                stdout: subprocessOutput.stdout,
                stderr: subprocessOutput.stderr,
                exitCode: subprocessOutput.exitCode,
                preflight: preflight
            )
        }

        let result = buildResult(
            request: request,
            subprocessOutput: subprocessOutput,
            gatewayPayload: gatewayPayload,
            startedAt: startedAt,
            preflight: preflight
        )

        let logWriteResult = appendGatewayLogs(
            payload: gatewayPayload,
            request: request,
            exitCode: subprocessOutput.exitCode
        )
        if let logWriteError = logWriteResult.errorDescription {
            return finalizeTerminal(
                request: request,
                startedAt: startedAt,
                finishedAt: timestamp(nowProvider()),
                status: .failed,
                summary: "OpenClaw runtime finished but writing execution logs failed.",
                errorCode: OpenClawExecutionErrorCode.logWriteFailed.rawValue,
                stdout: subprocessOutput.stdout,
                stderr: [subprocessOutput.stderr, logWriteError]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n"),
                exitCode: subprocessOutput.exitCode,
                preflight: preflight
            )
        }

        let review = OpenClawExecutionReview(
            reviewId: "openclaw-review-\(request.traceId)",
            traceId: request.traceId,
            sessionId: request.sessionId,
            taskId: request.taskId,
            skillName: request.skillName,
            skillDirectoryPath: request.skillDirectoryPath,
            component: request.component,
            status: gatewayPayload.status,
            errorCode: gatewayPayload.errorCode,
            startedAt: gatewayPayload.startedAt,
            finishedAt: gatewayPayload.finishedAt,
            totalSteps: gatewayPayload.totalSteps,
            succeededSteps: gatewayPayload.succeededSteps,
            failedSteps: gatewayPayload.failedSteps,
            blockedSteps: gatewayPayload.blockedSteps,
            summary: gatewayPayload.summary,
            logFilePath: logWriteResult.path ?? "",
            exitCode: subprocessOutput.exitCode,
            preflight: preflight
        )

        return OpenClawExecutionResult(
            traceId: result.traceId,
            sessionId: result.sessionId,
            taskId: result.taskId,
            skillName: result.skillName,
            skillDirectoryPath: result.skillDirectoryPath,
            runtimeExecutablePath: result.runtimeExecutablePath,
            runtimeArguments: result.runtimeArguments,
            status: result.status,
            errorCode: result.errorCode,
            exitCode: result.exitCode,
            startedAt: result.startedAt,
            finishedAt: result.finishedAt,
            stdout: result.stdout,
            stderr: result.stderr,
            summary: result.summary,
            totalSteps: result.totalSteps,
            succeededSteps: result.succeededSteps,
            failedSteps: result.failedSteps,
            blockedSteps: result.blockedSteps,
            stepResults: result.stepResults,
            review: review,
            preflight: preflight
        )
    }

    private func buildResult(
        request: OpenClawExecutionRequest,
        subprocessOutput: OpenClawSubprocessOutput,
        gatewayPayload: OpenClawGatewayExecutionPayload,
        startedAt: String,
        preflight: SkillPreflightReport
    ) -> OpenClawExecutionResult {
        OpenClawExecutionResult(
            traceId: request.traceId,
            sessionId: request.sessionId,
            taskId: request.taskId,
            skillName: request.skillName,
            skillDirectoryPath: request.skillDirectoryPath,
            runtimeExecutablePath: request.runtimeExecutablePath,
            runtimeArguments: request.runtimeArguments,
            status: gatewayPayload.status,
            errorCode: gatewayPayload.errorCode,
            exitCode: subprocessOutput.exitCode,
            startedAt: startedAt,
            finishedAt: gatewayPayload.finishedAt,
            stdout: subprocessOutput.stdout,
            stderr: subprocessOutput.stderr,
            summary: gatewayPayload.summary,
            totalSteps: gatewayPayload.totalSteps,
            succeededSteps: gatewayPayload.succeededSteps,
            failedSteps: gatewayPayload.failedSteps,
            blockedSteps: gatewayPayload.blockedSteps,
            stepResults: gatewayPayload.stepResults,
            preflight: preflight
        )
    }

    private func finalizeTerminal(
        request: OpenClawExecutionRequest,
        startedAt: String,
        finishedAt: String,
        status: OpenClawExecutionStatus,
        summary: String,
        errorCode: String,
        stdout: String,
        stderr: String,
        exitCode: Int32?,
        preflight: SkillPreflightReport? = nil
    ) -> OpenClawExecutionResult {
        let logStatus: String
        switch status {
        case .succeeded:
            logStatus = "STATUS_OCW_EXECUTION_COMPLETED"
        case .failed:
            logStatus = "STATUS_OCW_EXECUTION_FAILED"
        case .blocked:
            logStatus = "STATUS_OCW_EXECUTION_BLOCKED"
        }

        let failureEntry = OpenClawExecutionLogEntry(
            timestamp: finishedAt,
            traceId: request.traceId,
            sessionId: request.sessionId,
            taskId: request.taskId,
            component: request.component,
            status: logStatus,
            errorCode: errorCode,
            message: summary,
            skillName: request.skillName,
            skillDirectoryPath: request.skillDirectoryPath,
            exitCode: exitCode
        )
        let logResult = appendLog(entry: failureEntry, logsRootDirectoryPath: request.logsRootDirectoryPath)

        let review = OpenClawExecutionReview(
            reviewId: "openclaw-review-\(request.traceId)",
            traceId: request.traceId,
            sessionId: request.sessionId,
            taskId: request.taskId,
            skillName: request.skillName,
            skillDirectoryPath: request.skillDirectoryPath,
            component: request.component,
            status: status,
            errorCode: errorCode,
            startedAt: startedAt,
            finishedAt: finishedAt,
            totalSteps: 0,
            succeededSteps: 0,
            failedSteps: 0,
            blockedSteps: 0,
            summary: summary,
            logFilePath: logResult.path ?? "",
            exitCode: exitCode,
            preflight: preflight
        )

        let mergedStderr = [stderr, logResult.errorDescription]
            .compactMap { value in
                guard let value else { return nil }
                return value.isEmpty ? nil : value
            }
            .joined(separator: "\n")

        return OpenClawExecutionResult(
            traceId: request.traceId,
            sessionId: request.sessionId,
            taskId: request.taskId,
            skillName: request.skillName,
            skillDirectoryPath: request.skillDirectoryPath,
            runtimeExecutablePath: request.runtimeExecutablePath,
            runtimeArguments: request.runtimeArguments,
            status: status,
            errorCode: errorCode,
            exitCode: exitCode,
            startedAt: startedAt,
            finishedAt: finishedAt,
            stdout: stdout,
            stderr: mergedStderr,
            summary: summary,
            totalSteps: 0,
            succeededSteps: 0,
            failedSteps: 0,
            blockedSteps: 0,
            stepResults: [],
            review: review,
            preflight: preflight
        )
    }

    private func appendGatewayLogs(
        payload: OpenClawGatewayExecutionPayload,
        request: OpenClawExecutionRequest,
        exitCode: Int32
    ) -> LogWriteResult {
        var lastResult = LogWriteResult(path: nil, errorDescription: nil)

        for step in payload.stepResults {
            let statusCode: String
            switch step.status {
            case .succeeded:
                statusCode = "STATUS_OCW_STEP_SUCCEEDED"
            case .failed:
                statusCode = "STATUS_OCW_STEP_FAILED"
            case .blocked:
                statusCode = "STATUS_OCW_STEP_BLOCKED"
            }

            lastResult = appendLog(
                entry: OpenClawExecutionLogEntry(
                    timestamp: step.finishedAt,
                    traceId: request.traceId,
                    sessionId: request.sessionId,
                    taskId: request.taskId,
                    component: "\(request.component).step",
                    status: statusCode,
                    errorCode: step.errorCode,
                    message: step.output,
                    skillName: request.skillName,
                    skillDirectoryPath: request.skillDirectoryPath,
                    stepId: step.stepId,
                    actionType: step.actionType,
                    exitCode: exitCode
                ),
                logsRootDirectoryPath: request.logsRootDirectoryPath
            )
            if lastResult.errorDescription != nil {
                return lastResult
            }
        }

        let completionStatus: String
        switch payload.status {
        case .succeeded:
            completionStatus = "STATUS_OCW_EXECUTION_COMPLETED"
        case .failed:
            completionStatus = "STATUS_OCW_EXECUTION_FAILED"
        case .blocked:
            completionStatus = "STATUS_OCW_EXECUTION_BLOCKED"
        }

        return appendLog(
            entry: OpenClawExecutionLogEntry(
                timestamp: payload.finishedAt,
                traceId: request.traceId,
                sessionId: request.sessionId,
                taskId: request.taskId,
                component: request.component,
                status: completionStatus,
                errorCode: payload.errorCode,
                message: payload.summary,
                skillName: request.skillName,
                skillDirectoryPath: request.skillDirectoryPath,
                exitCode: exitCode
            ),
            logsRootDirectoryPath: request.logsRootDirectoryPath
        )
    }

    private func appendLog(
        entry: OpenClawExecutionLogEntry,
        logsRootDirectoryPath: String
    ) -> LogWriteResult {
        let dateKey = String(entry.timestamp.prefix(10))
        let dateDirectory = URL(fileURLWithPath: logsRootDirectoryPath, isDirectory: true)
            .appendingPathComponent(dateKey, isDirectory: true)

        do {
            try fileManager.createDirectory(at: dateDirectory, withIntermediateDirectories: true)
        } catch {
            return LogWriteResult(
                path: nil,
                errorDescription: "Failed to create OpenClaw log directory \(dateDirectory.path): \(error.localizedDescription)"
            )
        }

        let fileURL = dateDirectory.appendingPathComponent("\(entry.sessionId)-openclaw.log", isDirectory: false)
        let lineData: Data
        do {
            lineData = try encoder.encode(entry) + Data([0x0A])
        } catch {
            return LogWriteResult(
                path: nil,
                errorDescription: "Failed to encode OpenClaw log entry: \(error.localizedDescription)"
            )
        }

        if !fileManager.fileExists(atPath: fileURL.path) {
            let created = fileManager.createFile(atPath: fileURL.path, contents: nil)
            if !created {
                return LogWriteResult(
                    path: nil,
                    errorDescription: "Failed to create OpenClaw log file \(fileURL.path)."
                )
            }
        }

        guard let handle = try? FileHandle(forWritingTo: fileURL) else {
            return LogWriteResult(
                path: nil,
                errorDescription: "Failed to open OpenClaw log file \(fileURL.path)."
            )
        }
        defer {
            try? handle.close()
        }

        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: lineData)
        } catch {
            return LogWriteResult(
                path: nil,
                errorDescription: "Failed to append OpenClaw log file \(fileURL.path): \(error.localizedDescription)"
            )
        }

        return LogWriteResult(path: fileURL.path, errorDescription: nil)
    }

    private func decodeGatewayPayload(from stdout: String) -> OpenClawGatewayExecutionPayload? {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(OpenClawGatewayExecutionPayload.self, from: data)
    }

    private func validate(request: OpenClawExecutionRequest) -> String? {
        if request.traceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "OpenClaw execution request missing traceId."
        }
        if request.sessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "OpenClaw execution request missing sessionId."
        }
        if request.skillName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "OpenClaw execution request missing skillName."
        }
        if request.skillDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "OpenClaw execution request missing skillDirectoryPath."
        }
        if request.runtimeExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "OpenClaw execution request missing runtimeExecutablePath."
        }
        if request.runtimeArguments.isEmpty {
            return "OpenClaw execution request missing runtimeArguments."
        }
        return nil
    }

    private func timestamp(_ date: Date) -> String {
        formatter.string(from: date)
    }

    private func terminalStatus(for preflight: SkillPreflightReport) -> OpenClawExecutionStatus {
        let failedCodes: Set<SkillPreflightIssueCode> = [
            .skillBundleUnreadable,
            .skillBundleDecodeFailed,
            .unsupportedSchemaVersion,
            .emptyExecutionPlan,
            .expectedStepCountMismatch
        ]
        if preflight.issues.contains(where: { failedCodes.contains($0.code) }) {
            return .failed
        }
        return .blocked
    }
}

private struct LogWriteResult {
    let path: String?
    let errorDescription: String?
}
