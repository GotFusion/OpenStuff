import Foundation

@main
struct OpenStaffAssistCLI {
    static func main() {
        do {
            let options = try AssistCLIOptions.parse(arguments: CommandLine.arguments)

            if options.showHelp {
                printHelp()
                return
            }

            let loader = AssistKnowledgeLoader()
            let items = try loader.load(from: options.knowledgeItemURL)
            guard let primaryItem = items.first else {
                throw AssistCLIOptionError.invalidValue("--knowledge-item", options.knowledgeItemURL.path)
            }

            let sessionId = options.sessionId ?? primaryItem.sessionId
            let currentAppName = options.currentAppName ?? primaryItem.context.appName
            let currentAppBundleId = options.currentAppBundleId ?? primaryItem.context.appBundleId

            let modeLogger = StdoutOrchestratorStateLogger()
            let stateMachine = ModeStateMachine(initialMode: options.initialMode, logger: modeLogger)
            let predictor = RuleBasedAssistNextActionPredictor()
            let prompter = AssistPopupConfirmationPrompter(forcedDecision: options.autoConfirm)
            let executor = AssistActionExecutor()
            let logWriter = AssistLoopLogWriter(logsRootDirectory: options.logsRootDirectoryURL)

            let orchestrator = AssistModeLoopOrchestrator(
                modeStateMachine: stateMachine,
                predictor: predictor,
                confirmationPrompter: prompter,
                actionExecutor: executor,
                logWriter: logWriter
            )

            let input = AssistLoopInput(
                traceId: options.traceId,
                sessionId: sessionId,
                taskId: options.taskId ?? primaryItem.taskId,
                timestamp: options.timestamp,
                teacherConfirmed: options.teacherConfirmed,
                emergencyStopActive: options.emergencyStopActive,
                completedStepCount: options.completedStepCount,
                currentAppName: currentAppName,
                currentAppBundleId: currentAppBundleId,
                knowledgeItems: items
            )

            let executionContext = AssistExecutionContext(
                traceId: options.traceId,
                sessionId: sessionId,
                taskId: options.taskId ?? primaryItem.taskId,
                dryRun: !options.realExecution,
                simulateFailure: options.simulateExecutionFailure,
                emergencyStopActive: options.emergencyStopActive
            )

            let result = try orchestrator.run(input: input, executionContext: executionContext)
            printSummary(result: result)

            if options.printJSONResult {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(result)
                if let text = String(data: data, encoding: .utf8) {
                    print(text)
                }
            }

            if result.finalStatus != .completed {
                Foundation.exit(2)
            }
        } catch {
            print("Assist CLI failed: \(error.localizedDescription)")
            Foundation.exit(1)
        }
    }

    static func printHelp() {
        print("""
        OpenStaffAssistCLI

        Usage:
          make assist ARGS="--knowledge-item core/knowledge/examples/knowledge-item.sample.json --auto-confirm yes"

        Flags:
          --knowledge-item <path>            KnowledgeItem JSON path.
          --session-id <id>                  Session ID override. Default: from knowledge item.
          --task-id <id>                     Task ID override. Default: from knowledge item.
          --from <teaching|assist|student>   Initial mode. Default: teaching
          --app-name <name>                  Current app name override.
          --app-bundle-id <bundleId>         Current app bundle ID override.
          --completed-steps <n>              Already completed step count. Default: 0
          --auto-confirm <yes|no>            Mock popup response from CLI flag.
          --teacher-not-confirmed            Set teacherConfirmed=false for mode transition guard.
          --emergency-stop-active            Set emergency stop active (blocks execution).
          --real-execution                   Disable dry-run tag in executor output.
          --simulate-execution-failure       Force execution failure for validation.
          --logs-root <path>                 Assist log root directory. Default: data/logs
          --trace-id <id>                    Trace ID. Default: auto generated.
          --timestamp <iso8601>              Timestamp. Default: now.
          --json-result                       Print final result as JSON.
          --help                             Show this help message.
        """)
    }

    static func printSummary(result: AssistLoopRunResult) {
        print("Assist loop finished. finalStatus=\(result.finalStatus.rawValue)")
        print("message=\(result.message)")
        print("logFile=\(result.logFilePath)")

        if let suggestion = result.suggestion {
            print("suggestion=\(suggestion.action.instruction)")
            print("confidence=\(suggestion.confidence)")
        }
        if let confirmation = result.confirmation {
            print("teacherConfirmed=\(confirmation.confirmed)")
        }
        if let execution = result.execution {
            print("executionStatus=\(execution.status.rawValue)")
            print("executionOutput=\(execution.output)")
        }
    }
}

struct AssistCLIOptions {
    static let defaultLogsRoot = "data/logs"

    let knowledgeItemPath: String
    let sessionId: String?
    let taskId: String?
    let initialMode: OpenStaffMode
    let currentAppName: String?
    let currentAppBundleId: String?
    let completedStepCount: Int
    let autoConfirm: Bool?
    let teacherConfirmed: Bool
    let emergencyStopActive: Bool
    let realExecution: Bool
    let simulateExecutionFailure: Bool
    let logsRootPath: String
    let traceId: String
    let timestamp: String
    let printJSONResult: Bool
    let showHelp: Bool

    var knowledgeItemURL: URL {
        resolve(path: knowledgeItemPath)
    }

    var logsRootDirectoryURL: URL {
        resolve(path: logsRootPath)
    }

    static func parse(arguments: [String]) throws -> AssistCLIOptions {
        var knowledgeItemPath: String?
        var sessionId: String?
        var taskId: String?
        var initialMode: OpenStaffMode = .teaching
        var currentAppName: String?
        var currentAppBundleId: String?
        var completedStepCount = 0
        var autoConfirm: Bool?
        var teacherConfirmed = true
        var emergencyStopActive = false
        var realExecution = false
        var simulateExecutionFailure = false
        var logsRootPath = defaultLogsRoot
        var traceId = "trace-\(UUID().uuidString.lowercased())"
        var timestamp = currentTimestamp()
        var printJSONResult = false
        var showHelp = false

        var index = 1
        while index < arguments.count {
            let token = arguments[index]

            switch token {
            case "--knowledge-item":
                index += 1
                guard index < arguments.count else {
                    throw AssistCLIOptionError.missingValue("--knowledge-item")
                }
                knowledgeItemPath = arguments[index]
            case "--session-id":
                index += 1
                guard index < arguments.count else {
                    throw AssistCLIOptionError.missingValue("--session-id")
                }
                sessionId = arguments[index]
            case "--task-id":
                index += 1
                guard index < arguments.count else {
                    throw AssistCLIOptionError.missingValue("--task-id")
                }
                taskId = arguments[index]
            case "--from":
                index += 1
                guard index < arguments.count else {
                    throw AssistCLIOptionError.missingValue("--from")
                }
                guard let parsed = OpenStaffMode(rawValue: arguments[index]) else {
                    throw AssistCLIOptionError.invalidValue("--from", arguments[index])
                }
                initialMode = parsed
            case "--app-name":
                index += 1
                guard index < arguments.count else {
                    throw AssistCLIOptionError.missingValue("--app-name")
                }
                currentAppName = arguments[index]
            case "--app-bundle-id":
                index += 1
                guard index < arguments.count else {
                    throw AssistCLIOptionError.missingValue("--app-bundle-id")
                }
                currentAppBundleId = arguments[index]
            case "--completed-steps":
                index += 1
                guard index < arguments.count else {
                    throw AssistCLIOptionError.missingValue("--completed-steps")
                }
                guard let parsed = Int(arguments[index]), parsed >= 0 else {
                    throw AssistCLIOptionError.invalidValue("--completed-steps", arguments[index])
                }
                completedStepCount = parsed
            case "--auto-confirm":
                index += 1
                guard index < arguments.count else {
                    throw AssistCLIOptionError.missingValue("--auto-confirm")
                }
                switch arguments[index].lowercased() {
                case "yes", "y", "true":
                    autoConfirm = true
                case "no", "n", "false":
                    autoConfirm = false
                default:
                    throw AssistCLIOptionError.invalidValue("--auto-confirm", arguments[index])
                }
            case "--teacher-not-confirmed":
                teacherConfirmed = false
            case "--emergency-stop-active":
                emergencyStopActive = true
            case "--real-execution":
                realExecution = true
            case "--simulate-execution-failure":
                simulateExecutionFailure = true
            case "--logs-root":
                index += 1
                guard index < arguments.count else {
                    throw AssistCLIOptionError.missingValue("--logs-root")
                }
                logsRootPath = arguments[index]
            case "--trace-id":
                index += 1
                guard index < arguments.count else {
                    throw AssistCLIOptionError.missingValue("--trace-id")
                }
                traceId = arguments[index]
            case "--timestamp":
                index += 1
                guard index < arguments.count else {
                    throw AssistCLIOptionError.missingValue("--timestamp")
                }
                timestamp = arguments[index]
            case "--json-result":
                printJSONResult = true
            case "--help", "-h":
                showHelp = true
            default:
                throw AssistCLIOptionError.unknownFlag(token)
            }

            index += 1
        }

        if !showHelp {
            guard let knowledgeItemPath else {
                throw AssistCLIOptionError.missingRequired("--knowledge-item")
            }

            let sessionPattern = "^[a-z0-9-]+$"
            if let sessionId, sessionId.range(of: sessionPattern, options: .regularExpression) == nil {
                throw AssistCLIOptionError.invalidValue("--session-id", sessionId)
            }

            let taskPattern = "^[a-z0-9-]+$"
            if let taskId, taskId.range(of: taskPattern, options: .regularExpression) == nil {
                throw AssistCLIOptionError.invalidValue("--task-id", taskId)
            }

            let tracePattern = "^[a-z0-9-]+$"
            guard traceId.range(of: tracePattern, options: .regularExpression) != nil else {
                throw AssistCLIOptionError.invalidValue("--trace-id", traceId)
            }

            guard isValidISO8601(timestamp) else {
                throw AssistCLIOptionError.invalidValue("--timestamp", timestamp)
            }

            return AssistCLIOptions(
                knowledgeItemPath: knowledgeItemPath,
                sessionId: sessionId,
                taskId: taskId,
                initialMode: initialMode,
                currentAppName: currentAppName,
                currentAppBundleId: currentAppBundleId,
                completedStepCount: completedStepCount,
                autoConfirm: autoConfirm,
                teacherConfirmed: teacherConfirmed,
                emergencyStopActive: emergencyStopActive,
                realExecution: realExecution,
                simulateExecutionFailure: simulateExecutionFailure,
                logsRootPath: logsRootPath,
                traceId: traceId,
                timestamp: timestamp,
                printJSONResult: printJSONResult,
                showHelp: showHelp
            )
        }

        return AssistCLIOptions(
            knowledgeItemPath: knowledgeItemPath ?? "core/knowledge/examples/knowledge-item.sample.json",
            sessionId: sessionId,
            taskId: taskId,
            initialMode: initialMode,
            currentAppName: currentAppName,
            currentAppBundleId: currentAppBundleId,
            completedStepCount: completedStepCount,
            autoConfirm: autoConfirm,
            teacherConfirmed: teacherConfirmed,
            emergencyStopActive: emergencyStopActive,
            realExecution: realExecution,
            simulateExecutionFailure: simulateExecutionFailure,
            logsRootPath: logsRootPath,
            traceId: traceId,
            timestamp: timestamp,
            printJSONResult: printJSONResult,
            showHelp: showHelp
        )
    }

    private func resolve(path: String) -> URL {
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return URL(fileURLWithPath: path, relativeTo: currentDirectory).standardizedFileURL
    }

    private static func currentTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private static func isValidISO8601(_ value: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if formatter.date(from: value) != nil {
            return true
        }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) != nil
    }
}

struct AssistKnowledgeLoader {
    private let decoder = JSONDecoder()

    func load(from fileURL: URL) throws -> [KnowledgeItem] {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw AssistKnowledgeLoaderError.readFileFailed(path: fileURL.path, underlying: error)
        }

        do {
            let item = try decoder.decode(KnowledgeItem.self, from: data)
            return [item]
        } catch {
            throw AssistKnowledgeLoaderError.decodeFailed(path: fileURL.path, underlying: error)
        }
    }
}

enum AssistCLIOptionError: LocalizedError {
    case missingValue(String)
    case missingRequired(String)
    case invalidValue(String, String)
    case unknownFlag(String)

    var errorDescription: String? {
        switch self {
        case .missingValue(let flag):
            return "Missing value for \(flag)."
        case .missingRequired(let flag):
            return "Missing required flag: \(flag). Use --help to see usage."
        case .invalidValue(let flag, let value):
            return "Invalid value for \(flag): \(value)."
        case .unknownFlag(let flag):
            return "Unknown flag: \(flag). Use --help to see supported flags."
        }
    }
}

enum AssistKnowledgeLoaderError: LocalizedError {
    case readFileFailed(path: String, underlying: Error)
    case decodeFailed(path: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .readFileFailed(let path, let underlying):
            return "Failed to read knowledge item \(path): \(underlying.localizedDescription)"
        case .decodeFailed(let path, let underlying):
            return "Failed to decode knowledge item \(path): \(underlying.localizedDescription)"
        }
    }
}
