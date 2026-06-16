import Foundation
import FoundationModels

public struct FoundationModelAdapterConfiguration: Codable, Equatable, Sendable {
    public let name: String?
    public let filePath: String?

    public init(name: String? = nil, filePath: String? = nil) {
        self.name = name
        self.filePath = filePath
    }

    public func validate() throws {
        let hasName = !(name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasFilePath = !(filePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        guard hasName != hasFilePath else {
            throw ToolExecutionError.invalidArguments("Configure exactly one FoundationModels adapter source: name or filePath.")
        }
    }
}

public struct FoundationModelAdapterLoader: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = FoundationModelAdapterLoader.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public func configuredModelIfPresent() async throws -> SystemLanguageModel? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        let configuration = try JSONDecoder().decode(FoundationModelAdapterConfiguration.self, from: data)
        try configuration.validate()

        let adapter: SystemLanguageModel.Adapter
        if let name = configuration.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            adapter = try SystemLanguageModel.Adapter(name: name)
        } else if let filePath = configuration.filePath?.trimmingCharacters(in: .whitespacesAndNewlines), !filePath.isEmpty {
            adapter = try SystemLanguageModel.Adapter(fileURL: URL(fileURLWithPath: filePath))
        } else {
            throw ToolExecutionError.invalidArguments("FoundationModels adapter source is empty.")
        }

        try await adapter.compile()
        return SystemLanguageModel(adapter: adapter)
    }

    public static func defaultFileURL() -> URL {
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cerberus", isDirectory: true)
        return supportDirectory.appendingPathComponent("foundation-model-adapter.json")
    }
}
