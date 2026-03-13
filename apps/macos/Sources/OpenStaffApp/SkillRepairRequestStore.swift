import Foundation

struct SkillRepairRequestWriteEntry: Codable {
    let schemaVersion: String
    let requestId: String
    let timestamp: String
    let skillId: String
    let skillName: String
    let skillDirectoryPath: String
    let actionType: String
    let actionTitle: String
    let actionReason: String
    let affectedStepIds: [String]
    let dominantDriftKind: String
    let recommendedRepairVersion: Int?

    init(
        requestId: String,
        timestamp: String,
        skillId: String,
        skillName: String,
        skillDirectoryPath: String,
        actionType: String,
        actionTitle: String,
        actionReason: String,
        affectedStepIds: [String],
        dominantDriftKind: String,
        recommendedRepairVersion: Int?
    ) {
        self.schemaVersion = "openstaff.skill-repair-request.v0"
        self.requestId = requestId
        self.timestamp = timestamp
        self.skillId = skillId
        self.skillName = skillName
        self.skillDirectoryPath = skillDirectoryPath
        self.actionType = actionType
        self.actionTitle = actionTitle
        self.actionReason = actionReason
        self.affectedStepIds = affectedStepIds
        self.dominantDriftKind = dominantDriftKind
        self.recommendedRepairVersion = recommendedRepairVersion
    }
}

enum SkillRepairRequestWriter {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static func append(_ entry: SkillRepairRequestWriteEntry) throws {
        let directory = OpenStaffWorkspacePaths.skillsRepairDirectory
            .appendingPathComponent(OpenStaffDateFormatter.dayString(from: Date()), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appendingPathComponent("skill-repair.jsonl", isDirectory: false)
        var payload = try encoder.encode(entry)
        payload.append(0x0A)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: payload)
            try handle.close()
        } else {
            try payload.write(to: fileURL, options: .atomic)
        }
    }
}

extension SkillRepairActionType {
    var buttonTitle: String {
        switch self {
        case .relocalize:
            return "更新 skill"
        case .reteachCurrentStep:
            return "重新示教"
        case .updateSkillLocator:
            return "更新 locator"
        }
    }
}
