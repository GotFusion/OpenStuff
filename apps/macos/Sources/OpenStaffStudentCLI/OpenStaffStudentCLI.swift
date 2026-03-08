import Foundation

@main
struct OpenStaffStudentCLI {
    static func main() {
        do {
            let options = try StudentCLIOptions.parse(arguments: CommandLine.arguments)

            if options.showHelp {
                printHelp()
                return
            }

            let loader = StudentKnowledgeLoader()
            let items = try loader.load(from: options.knowledgeInputURL)
            guard !items.isEmpty else {
                throw StudentCLIOptionError.invalidValue("--knowledge", options.knowledgeInputPath)
            }

            let primaryItem = items[0]
            let sessionId = options.sessionId ?? primaryItem.sessionId
            let taskId = options.taskId ?? primaryItem.taskId

            let modeLogger = StdoutOrchestratorStateLogger()
            let stateMachine = ModeStateMachine(initialMode: options.initialMode, logger: modeLogger)
            let planner = RuleBasedStudentTaskPlanner()
            let skillExecutor = StudentSkillExecutor()
            let logWriter = StudentLoopLogWriter(logsRootDirectory: options.logsRootDirectoryURL)
            let reportWriter = StudentReviewReportWriter(reportsRootDirectory: options.reportsRootDirectoryURL)

            let orchestrator = StudentModeLoopOrchestrator(
                modeStateMachine: stateMachine,
                planner: planner,
                skillExecutor: skillExecutor,
                logWriter: logWriter,
                reportWriter: reportWriter
            )

            let input = StudentLoopInput(
                traceId: options.traceId,
                sessionId: sessionId,
                taskId: taskId,
                timestamp: options.timestamp,
                teacherConfirmed: options.teacherConfirmed,
                emergencyStopActive: options.emergencyStopActive,
                goal: options.goal,
                preferredKnowledgeItemId: options.preferredKnowledgeItemId,
                pendingAssistSuggestion: options.pendingAssistSuggestion,
                knowledgeItems: items
            )

            let executionContext = StudentExecutionContext(
                traceId: options.traceId,
                sessionId: sessionId,
                taskId: taskId,
                dryRun: !options.realExecution,
                simulateFailureAtStepIndex: options.simulateFailureAtStepIndex,
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
            print("Student CLI failed: \(error.localizedDescription)")
            Foundation.exit(1)
        }
    }

    static func printHelp() {
        print("""
        OpenStaffStudentCLI

        Usage:
          make student ARGS="--goal 在 Safari 中复现点击流程 --knowledge core/knowledge/examples/knowledge-item.sample.json"

        Flags:
          --goal <text>                      Student mode task goal.
          --knowledge <path>                 Knowledge item JSON file or directory path.
          --session-id <id>                  Session ID override. Default: from knowledge item.
          --task-id <id>                     Task ID override. Default: from selected plan item.
          --from <teaching|assist|student>   Initial mode. Default: assist
          --preferred-knowledge-item-id <id> Prefer a specific KnowledgeItem for planning.
          --teacher-not-confirmed            Set teacherConfirmed=false for transition guard.
          --emergency-stop-active            Set emergency stop active (blocks execution).
          --pending-assist-suggestion        Simulate pending assist suggestion for transition guard.
          --real-execution                   Disable dry-run tag in skill executor output.
          --simulate-failure-step <n>        Simulate failure on step n (1-based).
          --logs-root <path>                 Student log root directory. Default: data/logs
          --reports-root <path>              Student report root directory. Default: data/reports
          --trace-id <id>                    Trace ID. Default: auto generated.
          --timestamp <iso8601>              Timestamp. Default: now.
          --json-result                      Print final result as JSON.
          --help                             Show this help message.
        """)
    }

    static func printSummary(result: StudentLoopRunResult) {
        print("Student loop finished. finalStatus=\(result.finalStatus.rawValue)")
        print("message=\(result.message)")
        print("logFile=\(result.logFilePath)")
        if let reportFilePath = result.reportFilePath {
            print("reportFile=\(reportFilePath)")
        }
        if let plan = result.plan {
            print("planId=\(plan.planId)")
            print("plannedSteps=\(plan.steps.count)")
            print("selectedKnowledgeItem=\(plan.selectedKnowledgeItemId)")
        }
        if let report = result.report {
            print("reviewSummary=\(report.summary)")
        }
    }
}

struct StudentCLIOptions {
    static let defaultLogsRoot = "data/logs"
    static let defaultReportsRoot = "data/reports"

    let goal: String
    let knowledgeInputPath: String
    let sessionId: String?
    let taskId: String?
    let initialMode: OpenStaffMode
    let preferredKnowledgeItemId: String?
    let teacherConfirmed: Bool
    let emergencyStopActive: Bool
    let pendingAssistSuggestion: Bool
    let realExecution: Bool
    let simulateFailureAtStepIndex: Int?
    let logsRootPath: String
    let reportsRootPath: String
    let traceId: String
    let timestamp: String
    let printJSONResult: Bool
    let showHelp: Bool

    var knowledgeInputURL: URL {
        resolve(path: knowledgeInputPath)
    }

    var logsRootDirectoryURL: URL {
        resolve(path: logsRootPath)
    }

    var reportsRootDirectoryURL: URL {
        resolve(path: reportsRootPath)
    }

    static func parse(arguments: [String]) throws -> StudentCLIOptions {
        var goal: String?
        var knowledgeInputPath: String?
        var sessionId: String?
        var taskId: String?
        var initialMode: OpenStaffMode = .assist
        var preferredKnowledgeItemId: String?
        var teacherConfirmed = true
        var emergencyStopActive = false
        var pendingAssistSuggestion = false
        var realExecution = false
        var simulateFailureAtStepIndex: Int?
        var logsRootPath = defaultLogsRoot
        var reportsRootPath = defaultReportsRoot
        var traceId = "trace-\(UUID().uuidString.lowercased())"
        var timestamp = currentTimestamp()
        var printJSONResult = false
        var showHelp = false

        var index = 1
        while index < arguments.count {
            let token = arguments[index]

            switch token {
            case "--goal":
                index += 1
                guard index < arguments.count else {
                    throw StudentCLIOptionError.missingValue("--goal")
                }
                goal = arguments[index]
            case "--knowledge":
                index += 1
                guard index < arguments.count else {
                    throw StudentCLIOptionError.missingValue("--knowledge")
                }
                knowledgeInputPath = arguments[index]
            case "--session-id":
                index += 1
                guard index < arguments.count else {
                    throw StudentCLIOptionError.missingValue("--session-id")
                }
                sessionId = arguments[index]
            case "--task-id":
                index += 1
                guard index < arguments.count else {
                    throw StudentCLIOptionError.missingValue("--task-id")
                }
                taskId = arguments[index]
            case "--from":
                index += 1
                guard index < arguments.count else {
                    throw StudentCLIOptionError.missingValue("--from")
                }
                guard let parsed = OpenStaffMode(rawValue: arguments[index]) else {
                    throw StudentCLIOptionError.invalidValue("--from", arguments[index])
                }
                initialMode = parsed
            case "--preferred-knowledge-item-id":
                index += 1
                guard index < arguments.count else {
                    throw StudentCLIOptionError.missingValue("--preferred-knowledge-item-id")
                }
                preferredKnowledgeItemId = arguments[index]
            case "--teacher-not-confirmed":
                teacherConfirmed = false
            case "--emergency-stop-active":
                emergencyStopActive = true
            case "--pending-assist-suggestion":
                pendingAssistSuggestion = true
            case "--real-execution":
                realExecution = true
            case "--simulate-failure-step":
                index += 1
                guard index < arguments.count else {
                    throw StudentCLIOptionError.missingValue("--simulate-failure-step")
                }
                guard let parsed = Int(arguments[index]), parsed > 0 else {
                    throw StudentCLIOptionError.invalidValue("--simulate-failure-step", arguments[index])
                }
                simulateFailureAtStepIndex = parsed - 1
            case "--logs-root":
                index += 1
                guard index < arguments.count else {
                    throw StudentCLIOptionError.missingValue("--logs-root")
                }
                logsRootPath = arguments[index]
            case "--reports-root":
                index += 1
                guard index < arguments.count else {
                    throw StudentCLIOptionError.missingValue("--reports-root")
                }
                reportsRootPath = arguments[index]
            case "--trace-id":
                index += 1
                guard index < arguments.count else {
                    throw StudentCLIOptionError.missingValue("--trace-id")
                }
                traceId = arguments[index]
            case "--timestamp":
                index += 1
                guard index < arguments.count else {
                    throw StudentCLIOptionError.missingValue("--timestamp")
                }
                timestamp = arguments[index]
            case "--json-result":
                printJSONResult = true
            case "--help", "-h":
                showHelp = true
            default:
                throw StudentCLIOptionError.unknownFlag(token)
            }

            index += 1
        }

        if showHelp {
            return StudentCLIOptions(
                goal: goal ?? "demo goal",
                knowledgeInputPath: knowledgeInputPath ?? "core/knowledge/examples/knowledge-item.sample.json",
                sessionId: sessionId,
                taskId: taskId,
                initialMode: initialMode,
                preferredKnowledgeItemId: preferredKnowledgeItemId,
                teacherConfirmed: teacherConfirmed,
                emergencyStopActive: emergencyStopActive,
                pendingAssistSuggestion: pendingAssistSuggestion,
                realExecution: realExecution,
                simulateFailureAtStepIndex: simulateFailureAtStepIndex,
                logsRootPath: logsRootPath,
                reportsRootPath: reportsRootPath,
                traceId: traceId,
                timestamp: timestamp,
                printJSONResult: printJSONResult,
                showHelp: true
            )
        }

        guard let goal else {
            throw StudentCLIOptionError.missingRequired("--goal")
        }
        guard !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StudentCLIOptionError.invalidValue("--goal", goal)
        }
        guard let knowledgeInputPath else {
            throw StudentCLIOptionError.missingRequired("--knowledge")
        }

        let idPattern = "^[a-z0-9-]+$"
        if let sessionId, sessionId.range(of: idPattern, options: .regularExpression) == nil {
            throw StudentCLIOptionError.invalidValue("--session-id", sessionId)
        }
        if let taskId, taskId.range(of: idPattern, options: .regularExpression) == nil {
            throw StudentCLIOptionError.invalidValue("--task-id", taskId)
        }
        if let preferredKnowledgeItemId,
           preferredKnowledgeItemId.range(of: idPattern, options: .regularExpression) == nil {
            throw StudentCLIOptionError.invalidValue("--preferred-knowledge-item-id", preferredKnowledgeItemId)
        }
        guard traceId.range(of: idPattern, options: .regularExpression) != nil else {
            throw StudentCLIOptionError.invalidValue("--trace-id", traceId)
        }
        guard isValidISO8601(timestamp) else {
            throw StudentCLIOptionError.invalidValue("--timestamp", timestamp)
        }

        return StudentCLIOptions(
            goal: goal,
            knowledgeInputPath: knowledgeInputPath,
            sessionId: sessionId,
            taskId: taskId,
            initialMode: initialMode,
            preferredKnowledgeItemId: preferredKnowledgeItemId,
            teacherConfirmed: teacherConfirmed,
            emergencyStopActive: emergencyStopActive,
            pendingAssistSuggestion: pendingAssistSuggestion,
            realExecution: realExecution,
            simulateFailureAtStepIndex: simulateFailureAtStepIndex,
            logsRootPath: logsRootPath,
            reportsRootPath: reportsRootPath,
            traceId: traceId,
            timestamp: timestamp,
            printJSONResult: printJSONResult,
            showHelp: false
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

struct StudentKnowledgeLoader {
    private let fileManager: FileManager
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func load(from inputURL: URL) throws -> [KnowledgeItem] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: inputURL.path, isDirectory: &isDirectory) else {
            throw StudentKnowledgeLoaderError.inputNotFound(path: inputURL.path)
        }

        if isDirectory.boolValue {
            let files: [URL]
            do {
                files = try fileManager.contentsOfDirectory(
                    at: inputURL,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )
            } catch {
                throw StudentKnowledgeLoaderError.listDirectoryFailed(path: inputURL.path, underlying: error)
            }

            let jsonFiles = files
                .filter { $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }

            var items: [KnowledgeItem] = []
            for fileURL in jsonFiles {
                let item = try decodeItem(from: fileURL)
                items.append(item)
            }
            return items
        }

        return [try decodeItem(from: inputURL)]
    }

    private func decodeItem(from fileURL: URL) throws -> KnowledgeItem {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw StudentKnowledgeLoaderError.readFileFailed(path: fileURL.path, underlying: error)
        }

        do {
            return try decoder.decode(KnowledgeItem.self, from: data)
        } catch {
            throw StudentKnowledgeLoaderError.decodeFailed(path: fileURL.path, underlying: error)
        }
    }
}

enum StudentCLIOptionError: LocalizedError {
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

enum StudentKnowledgeLoaderError: LocalizedError {
    case inputNotFound(path: String)
    case listDirectoryFailed(path: String, underlying: Error)
    case readFileFailed(path: String, underlying: Error)
    case decodeFailed(path: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .inputNotFound(let path):
            return "Knowledge input path not found: \(path)"
        case .listDirectoryFailed(let path, let underlying):
            return "Failed to list knowledge directory \(path): \(underlying.localizedDescription)"
        case .readFileFailed(let path, let underlying):
            return "Failed to read knowledge item \(path): \(underlying.localizedDescription)"
        case .decodeFailed(let path, let underlying):
            return "Failed to decode knowledge item \(path): \(underlying.localizedDescription)"
        }
    }
}
