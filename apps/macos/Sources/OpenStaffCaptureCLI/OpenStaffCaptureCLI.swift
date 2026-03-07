import AppKit
import Foundation

@main
struct OpenStaffCaptureCLI {
    static func main() {
        do {
            let options = try CaptureCLIOptions.parse(arguments: CommandLine.arguments)

            if options.showHelp {
                printHelp()
                return
            }

            _ = NSApplication.shared
            NSApp.setActivationPolicy(.prohibited)

            let permissionChecker = AccessibilityPermissionChecker()
            guard permissionChecker.isTrusted(prompt: options.promptForPermission) else {
                print("[CAP-PERMISSION-DENIED] Accessibility permission is required for global capture.")
                print("Open System Settings > Privacy & Security > Accessibility and allow your terminal app, then rerun this command.")
                Foundation.exit(2)
            }

            let eventSink = try RawEventFileSink(
                sessionId: options.sessionId,
                outputRootDirectory: options.outputDirectoryURL,
                maxFileSizeBytes: options.rotateMaxBytes,
                maxFileAgeSeconds: options.rotateMaxSeconds
            )

            let engine = MouseCaptureEngine(
                sessionId: options.sessionId,
                maxEvents: options.maxEvents,
                printJSON: options.printJSON,
                eventSink: eventSink
            )

            let signalTrap = SignalTrap {
                engine.stop()
                print("Capture stopped by signal. total=\(engine.capturedCount)")
                CFRunLoopStop(CFRunLoopGetMain())
            }

            engine.onStopRequested = {
                engine.stop()
                print("Capture stopped after reaching max events. total=\(engine.capturedCount)")
                CFRunLoopStop(CFRunLoopGetMain())
            }

            engine.onFatalError = { error in
                engine.stop()
                print("[STO-IO-FAILED] Capture stopped due to storage failure: \(error.localizedDescription)")
                CFRunLoopStop(CFRunLoopGetMain())
            }

            try engine.start()
            print("Capture started. sessionId=\(options.sessionId)")
            print("Persisting JSONL to \(options.outputDirectoryURL.path)")
            print("Press Ctrl+C to stop.")
            if let maxEvents = options.maxEvents {
                print("Auto-stop after \(maxEvents) events.")
            }

            withExtendedLifetime(signalTrap) {
                RunLoop.main.run()
            }
        } catch {
            print("Capture startup failed: \(error.localizedDescription)")
            Foundation.exit(1)
        }
    }

    static func printHelp() {
        print("""
        OpenStaffCaptureCLI

        Usage:
          make capture
          make capture ARGS=\"--session-id session-20260307-a1 --max-events 20\"

        Flags:
          --session-id <id>           Set a custom session ID (lowercase letters, numbers, hyphen).
          --max-events <n>            Stop automatically after n captured events.
          --json                      Print raw events as JSONL lines.
          --output-dir <path>         Storage root for raw events. Default: data/raw-events
          --rotate-max-bytes <n>      Rotate when file exceeds n bytes. Default: 1048576
          --rotate-max-seconds <n>    Rotate when file age exceeds n seconds (0 disables). Default: 1800
          --no-permission-prompt      Do not trigger macOS accessibility permission prompt.
          --help                      Show this help message.
        """)
    }
}

struct CaptureCLIOptions {
    static let defaultOutputDirectory = "data/raw-events"
    static let defaultRotateMaxBytes: UInt64 = 1_048_576
    static let defaultRotateMaxSeconds: TimeInterval = 1_800

    let sessionId: String
    let maxEvents: Int?
    let printJSON: Bool
    let outputDirectory: String
    let rotateMaxBytes: UInt64
    let rotateMaxSeconds: TimeInterval
    let promptForPermission: Bool
    let showHelp: Bool

    static func parse(arguments: [String]) throws -> CaptureCLIOptions {
        var sessionId: String?
        var maxEvents: Int?
        var printJSON = false
        var outputDirectory = defaultOutputDirectory
        var rotateMaxBytes = defaultRotateMaxBytes
        var rotateMaxSeconds = defaultRotateMaxSeconds
        var promptForPermission = true
        var showHelp = false

        var index = 1
        while index < arguments.count {
            let token = arguments[index]

            switch token {
            case "--session-id":
                index += 1
                guard index < arguments.count else {
                    throw CaptureCLIOptionError.missingValue("--session-id")
                }
                sessionId = arguments[index]
            case "--max-events":
                index += 1
                guard index < arguments.count else {
                    throw CaptureCLIOptionError.missingValue("--max-events")
                }

                guard let parsed = Int(arguments[index]), parsed > 0 else {
                    throw CaptureCLIOptionError.invalidValue("--max-events", arguments[index])
                }

                maxEvents = parsed
            case "--json":
                printJSON = true
            case "--output-dir":
                index += 1
                guard index < arguments.count else {
                    throw CaptureCLIOptionError.missingValue("--output-dir")
                }
                outputDirectory = arguments[index]
            case "--rotate-max-bytes":
                index += 1
                guard index < arguments.count else {
                    throw CaptureCLIOptionError.missingValue("--rotate-max-bytes")
                }

                guard let parsed = UInt64(arguments[index]), parsed > 0 else {
                    throw CaptureCLIOptionError.invalidValue("--rotate-max-bytes", arguments[index])
                }
                rotateMaxBytes = parsed
            case "--rotate-max-seconds":
                index += 1
                guard index < arguments.count else {
                    throw CaptureCLIOptionError.missingValue("--rotate-max-seconds")
                }

                guard let parsed = TimeInterval(arguments[index]), parsed >= 0 else {
                    throw CaptureCLIOptionError.invalidValue("--rotate-max-seconds", arguments[index])
                }
                rotateMaxSeconds = parsed
            case "--no-permission-prompt":
                promptForPermission = false
            case "--help", "-h":
                showHelp = true
            default:
                throw CaptureCLIOptionError.unknownFlag(token)
            }

            index += 1
        }

        let resolvedSessionId = sessionId ?? defaultSessionId()
        guard isValidSessionId(resolvedSessionId) else {
            throw CaptureCLIOptionError.invalidValue("--session-id", resolvedSessionId)
        }

        return CaptureCLIOptions(
            sessionId: resolvedSessionId,
            maxEvents: maxEvents,
            printJSON: printJSON,
            outputDirectory: outputDirectory,
            rotateMaxBytes: rotateMaxBytes,
            rotateMaxSeconds: rotateMaxSeconds,
            promptForPermission: promptForPermission,
            showHelp: showHelp
        )
    }

    private static func defaultSessionId() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        return "session-\(formatter.string(from: Date()))"
    }

    private static func isValidSessionId(_ value: String) -> Bool {
        guard !value.isEmpty else {
            return false
        }

        let pattern = "^[a-z0-9-]+$"
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    var outputDirectoryURL: URL {
        let fileManager = FileManager.default
        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        return URL(fileURLWithPath: outputDirectory, relativeTo: currentDirectory).standardizedFileURL
    }
}

enum CaptureCLIOptionError: LocalizedError {
    case missingValue(String)
    case invalidValue(String, String)
    case unknownFlag(String)

    var errorDescription: String? {
        switch self {
        case .missingValue(let flag):
            return "Missing value for \(flag)."
        case .invalidValue(let flag, let value):
            return "Invalid value for \(flag): \(value)."
        case .unknownFlag(let flag):
            return "Unknown flag: \(flag). Use --help to see supported flags."
        }
    }
}

final class SignalTrap {
    private let source: DispatchSourceSignal

    init(handler: @escaping () -> Void) {
        Foundation.signal(SIGINT, SIG_IGN)
        source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        source.setEventHandler(handler: handler)
        source.resume()
    }
}
