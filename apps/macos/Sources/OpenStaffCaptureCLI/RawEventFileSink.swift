import Foundation

final class RawEventFileSink {
    private struct Segment {
        let index: Int
        let fileURL: URL
        let sizeBytes: UInt64
        let openedAt: Date
    }

    private let sessionId: String
    private let outputRootDirectory: URL
    private let maxFileSizeBytes: UInt64
    private let maxFileAgeSeconds: TimeInterval
    private let fileManager: FileManager
    private let nowProvider: () -> Date
    private let lock = NSLock()

    private let encoder = JSONEncoder()
    private let dayFormatter: DateFormatter
    private let timestampParserWithFractional: ISO8601DateFormatter
    private let timestampParser: ISO8601DateFormatter

    private var activeDateKey: String?
    private var activeSegmentIndex: Int?
    private var activeFileURL: URL?
    private var activeFileSizeBytes: UInt64 = 0
    private var activeOpenedAt: Date?
    private var activeHandle: FileHandle?

    init(
        sessionId: String,
        outputRootDirectory: URL,
        maxFileSizeBytes: UInt64,
        maxFileAgeSeconds: TimeInterval,
        fileManager: FileManager = .default,
        nowProvider: @escaping () -> Date = Date.init
    ) throws {
        guard !sessionId.isEmpty else {
            throw RawEventFileSinkError.invalidSessionId
        }
        guard maxFileSizeBytes > 0 else {
            throw RawEventFileSinkError.invalidRotationPolicy
        }

        self.sessionId = sessionId
        self.outputRootDirectory = outputRootDirectory
        self.maxFileSizeBytes = maxFileSizeBytes
        self.maxFileAgeSeconds = maxFileAgeSeconds
        self.fileManager = fileManager
        self.nowProvider = nowProvider

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = .current
        self.dayFormatter = dayFormatter

        let timestampParserWithFractional = ISO8601DateFormatter()
        timestampParserWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.timestampParserWithFractional = timestampParserWithFractional

        let timestampParser = ISO8601DateFormatter()
        timestampParser.formatOptions = [.withInternetDateTime]
        self.timestampParser = timestampParser

        try fileManager.createDirectory(at: outputRootDirectory, withIntermediateDirectories: true, attributes: nil)
    }

    deinit {
        try? close()
    }

    @discardableResult
    func append(_ event: RawEvent) throws -> URL {
        try lock.withLock {
            let lineData = try encodeJSONLine(event)
            let timestampDate = parseTimestamp(event.timestamp) ?? nowProvider()
            let dateKey = dayFormatter.string(from: timestampDate)

            try prepareWritableFile(for: dateKey, incomingBytes: UInt64(lineData.count))
            guard let activeHandle, let activeFileURL else {
                throw RawEventFileSinkError.internalInvariantBroken("active file handle is not ready")
            }

            try activeHandle.write(contentsOf: lineData)
            activeFileSizeBytes += UInt64(lineData.count)
            return activeFileURL
        }
    }

    func close() throws {
        try lock.withLock {
            try closeActiveHandle()
        }
    }

    private func encodeJSONLine(_ event: RawEvent) throws -> Data {
        do {
            var data = try encoder.encode(event)
            data.append(0x0A)
            return data
        } catch {
            throw RawEventFileSinkError.encodeFailed(error)
        }
    }

    private func parseTimestamp(_ raw: String) -> Date? {
        if let parsed = timestampParserWithFractional.date(from: raw) {
            return parsed
        }

        return timestampParser.date(from: raw)
    }

    private func prepareWritableFile(for dateKey: String, incomingBytes: UInt64) throws {
        if activeDateKey != dateKey {
            try closeActiveHandle()
            try openInitialSegment(for: dateKey)
        } else if activeHandle == nil {
            try openInitialSegment(for: dateKey)
        }

        if shouldRotate(incomingBytes: incomingBytes) {
            try rotateToNextSegment(for: dateKey)
        }
    }

    private func openInitialSegment(for dateKey: String) throws {
        let directory = outputRootDirectory.appendingPathComponent(dateKey, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)

        let selected = try selectWritableSegment(in: directory)
        try openSegment(selected, dateKey: dateKey)
    }

    private func rotateToNextSegment(for dateKey: String) throws {
        guard let activeSegmentIndex else {
            throw RawEventFileSinkError.internalInvariantBroken("active segment index is missing during rotation")
        }

        let nextIndex = activeSegmentIndex + 1
        let directory = outputRootDirectory.appendingPathComponent(dateKey, isDirectory: true)
        let nextFileURL = segmentFileURL(index: nextIndex, in: directory)
        let segment = Segment(index: nextIndex, fileURL: nextFileURL, sizeBytes: 0, openedAt: nowProvider())

        try openSegment(segment, dateKey: dateKey)
    }

    private func openSegment(_ segment: Segment, dateKey: String) throws {
        try closeActiveHandle()

        if !fileManager.fileExists(atPath: segment.fileURL.path) {
            let created = fileManager.createFile(atPath: segment.fileURL.path, contents: nil)
            if !created {
                throw RawEventFileSinkError.createFileFailed(segment.fileURL.path)
            }
        }

        do {
            let handle = try FileHandle(forUpdating: segment.fileURL)
            let endOffset = try handle.seekToEnd()

            activeDateKey = dateKey
            activeSegmentIndex = segment.index
            activeFileURL = segment.fileURL
            activeFileSizeBytes = endOffset
            activeOpenedAt = segment.openedAt
            activeHandle = handle
        } catch {
            throw RawEventFileSinkError.openFileFailed(segment.fileURL.path, error)
        }
    }

    private func closeActiveHandle() throws {
        if let activeHandle {
            do {
                try activeHandle.close()
            } catch {
                throw RawEventFileSinkError.closeFileFailed(error)
            }
        }

        activeHandle = nil
        activeDateKey = nil
        activeSegmentIndex = nil
        activeFileURL = nil
        activeFileSizeBytes = 0
        activeOpenedAt = nil
    }

    private func shouldRotate(incomingBytes: UInt64) -> Bool {
        if activeFileSizeBytes > 0, activeFileSizeBytes + incomingBytes > maxFileSizeBytes {
            return true
        }

        guard maxFileAgeSeconds > 0, let activeOpenedAt else {
            return false
        }

        return nowProvider().timeIntervalSince(activeOpenedAt) >= maxFileAgeSeconds
    }

    private func selectWritableSegment(in directory: URL) throws -> Segment {
        let dateNow = nowProvider()
        let existingSegments = try discoverSegments(in: directory)

        guard let latest = existingSegments.max(by: { $0.index < $1.index }) else {
            return Segment(
                index: 0,
                fileURL: segmentFileURL(index: 0, in: directory),
                sizeBytes: 0,
                openedAt: dateNow
            )
        }

        let latestIsWithinSizeLimit = latest.sizeBytes < maxFileSizeBytes
        let latestIsWithinAgeLimit: Bool
        if maxFileAgeSeconds <= 0 {
            latestIsWithinAgeLimit = true
        } else {
            latestIsWithinAgeLimit = dateNow.timeIntervalSince(latest.openedAt) < maxFileAgeSeconds
        }

        if latestIsWithinSizeLimit, latestIsWithinAgeLimit {
            return latest
        }

        return Segment(
            index: latest.index + 1,
            fileURL: segmentFileURL(index: latest.index + 1, in: directory),
            sizeBytes: 0,
            openedAt: dateNow
        )
    }

    private func discoverSegments(in directory: URL) throws -> [Segment] {
        let files: [URL]
        do {
            files = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw RawEventFileSinkError.listDirectoryFailed(directory.path, error)
        }

        var segments: [Segment] = []
        for fileURL in files {
            guard let index = parseSegmentIndex(from: fileURL.lastPathComponent) else {
                continue
            }

            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey])
            guard values.isRegularFile == true else {
                continue
            }

            segments.append(
                Segment(
                    index: index,
                    fileURL: fileURL,
                    sizeBytes: UInt64(max(values.fileSize ?? 0, 0)),
                    openedAt: values.creationDate ?? values.contentModificationDate ?? nowProvider()
                )
            )
        }

        return segments
    }

    private func parseSegmentIndex(from filename: String) -> Int? {
        let baseName = "\(sessionId).jsonl"
        if filename == baseName {
            return 0
        }

        let prefix = "\(sessionId)-r"
        let suffix = ".jsonl"
        guard filename.hasPrefix(prefix), filename.hasSuffix(suffix) else {
            return nil
        }

        let indexStart = filename.index(filename.startIndex, offsetBy: prefix.count)
        let indexEnd = filename.index(filename.endIndex, offsetBy: -suffix.count)
        let value = filename[indexStart..<indexEnd]
        return Int(value)
    }

    private func segmentFileURL(index: Int, in directory: URL) -> URL {
        if index == 0 {
            return directory.appendingPathComponent("\(sessionId).jsonl", isDirectory: false)
        }

        let name = "\(sessionId)-r\(String(format: "%04d", index)).jsonl"
        return directory.appendingPathComponent(name, isDirectory: false)
    }
}

enum RawEventFileSinkError: LocalizedError {
    case invalidSessionId
    case invalidRotationPolicy
    case encodeFailed(Error)
    case listDirectoryFailed(String, Error)
    case createFileFailed(String)
    case openFileFailed(String, Error)
    case closeFileFailed(Error)
    case internalInvariantBroken(String)

    var errorDescription: String? {
        switch self {
        case .invalidSessionId:
            return "Session ID cannot be empty."
        case .invalidRotationPolicy:
            return "Rotation policy is invalid. maxFileSizeBytes must be greater than 0."
        case .encodeFailed(let error):
            return "Failed to encode RawEvent JSON line: \(error.localizedDescription)"
        case .listDirectoryFailed(let path, let error):
            return "Failed to list storage directory at \(path): \(error.localizedDescription)"
        case .createFileFailed(let path):
            return "Failed to create storage file at \(path)."
        case .openFileFailed(let path, let error):
            return "Failed to open storage file at \(path): \(error.localizedDescription)"
        case .closeFileFailed(let error):
            return "Failed to close storage file handle: \(error.localizedDescription)"
        case .internalInvariantBroken(let message):
            return "Internal storage state error: \(message)"
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) throws -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
