import Foundation

public struct WakeWordSampleRecord: Codable, Equatable, Sendable {
    public let label: String
    public let relativePath: String
    public let durationSeconds: Double
    public let createdAt: Date
    public let note: String?

    public init(
        label: String,
        relativePath: String,
        durationSeconds: Double,
        createdAt: Date = Date(),
        note: String? = nil
    ) {
        self.label = label
        self.relativePath = relativePath
        self.durationSeconds = durationSeconds
        self.createdAt = createdAt
        self.note = note
    }
}

public enum WakeWordSampleDataset {
    public static let manifestFileName = "manifest.jsonl"
    public static let supportedAudioExtensions: Set<String> = ["aif", "aiff", "caf", "m4a", "mp3", "wav"]

    public static func defaultDirectoryURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return baseURL
            .appendingPathComponent(CerberusCore.appName, isDirectory: true)
            .appendingPathComponent("wake-word-samples", isDirectory: true)
    }

    public static func normalizedLabel(_ label: String) throws -> String {
        let normalized = label
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .map { character -> Character in
                if character.isLetter || character.isNumber || character == "_" || character == "-" {
                    return character
                }
                return "_"
            }
        let value = String(normalized)
            .split(separator: "_")
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        guard !value.isEmpty else {
            throw ToolExecutionError.invalidArguments("Wake sample label is required.")
        }
        return value
    }

    public static func sampleFileURL(
        baseDirectoryURL: URL,
        label: String,
        index: Int,
        date: Date,
        id: UUID = UUID()
    ) throws -> URL {
        let normalizedLabel = try normalizedLabel(label)
        let timestamp = Int(date.timeIntervalSince1970)
        return baseDirectoryURL
            .appendingPathComponent(normalizedLabel, isDirectory: true)
            .appendingPathComponent(String(format: "%@-%010d-%03d-%@.wav", normalizedLabel, timestamp, index, id.uuidString))
    }

    public static func relativePath(for fileURL: URL, baseDirectoryURL: URL) -> String {
        let basePath = baseDirectoryURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(basePath + "/") else {
            return fileURL.lastPathComponent
        }
        return String(filePath.dropFirst(basePath.count + 1))
    }

    public static func write(record: WakeWordSampleRecord, to baseDirectoryURL: URL) throws {
        try FileManager.default.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
        let fileURL = baseDirectoryURL.appendingPathComponent(manifestFileName)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let line = try String(decoding: encoder.encode(record), as: UTF8.self)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("\n".utf8))
            try handle.write(contentsOf: Data(line.utf8))
            try handle.close()
        } else {
            try Data(line.utf8).write(to: fileURL, options: .atomic)
        }
    }

    public static func classCounts(in baseDirectoryURL: URL) throws -> [String: Int] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: baseDirectoryURL.path, isDirectory: &isDirectory) else {
            return [:]
        }
        guard isDirectory.boolValue else {
            throw ToolExecutionError.invalidArguments("Wake sample input must be a directory: \(baseDirectoryURL.path)")
        }

        let labels = try FileManager.default.contentsOfDirectory(
            at: baseDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var counts: [String: Int] = [:]
        for labelURL in labels {
            let values = try labelURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else {
                continue
            }
            let label = labelURL.lastPathComponent
            let files = try FileManager.default.contentsOfDirectory(
                at: labelURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            counts[label] = try files.filter { fileURL in
                let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                return values.isRegularFile == true && supportedAudioExtensions.contains(fileURL.pathExtension.lowercased())
            }.count
        }
        return counts.filter { $0.value > 0 }
    }
}
