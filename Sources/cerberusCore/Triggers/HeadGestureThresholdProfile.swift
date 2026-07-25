import Foundation

public struct HeadGestureThresholdProfile: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let nodThreshold: Double
    public let shakeThreshold: Double
    public let cooldownSeconds: Double

    public init(
        schemaVersion: Int = 1,
        nodThreshold: Double,
        shakeThreshold: Double,
        cooldownSeconds: Double
    ) throws {
        guard schemaVersion == 1 else {
            throw HeadGestureThresholdProfileError.unsupportedSchemaVersion(schemaVersion)
        }
        guard (0.15...0.8).contains(nodThreshold) else {
            throw HeadGestureThresholdProfileError.invalidValue("nodThreshold")
        }
        guard (0.15...0.8).contains(shakeThreshold) else {
            throw HeadGestureThresholdProfileError.invalidValue("shakeThreshold")
        }
        guard (0.3...3.0).contains(cooldownSeconds) else {
            throw HeadGestureThresholdProfileError.invalidValue("cooldownSeconds")
        }

        self.schemaVersion = schemaVersion
        self.nodThreshold = nodThreshold
        self.shakeThreshold = shakeThreshold
        self.cooldownSeconds = cooldownSeconds
    }

    public static func read(from url: URL) throws -> HeadGestureThresholdProfile {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(HeadGestureThresholdProfile.self, from: data)
    }

    public func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case nodThreshold
        case shakeThreshold
        case cooldownSeconds
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
            nodThreshold: try container.decode(Double.self, forKey: .nodThreshold),
            shakeThreshold: try container.decode(Double.self, forKey: .shakeThreshold),
            cooldownSeconds: try container.decode(Double.self, forKey: .cooldownSeconds)
        )
    }
}

public enum HeadGestureThresholdProfileError: Error, LocalizedError, Equatable {
    case unsupportedSchemaVersion(Int)
    case invalidValue(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchemaVersion(version):
            "Unsupported head gesture profile schema version \(version)."
        case let .invalidValue(field):
            "Invalid head gesture profile value for \(field)."
        }
    }
}
