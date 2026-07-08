import Foundation

public struct LocalVLMRequestOptions: Equatable, Sendable {
    public let maxTokens: Int
    public let timeoutSeconds: Double

    public init(maxTokens: Int = 256, timeoutSeconds: Double = 45) {
        self.maxTokens = max(1, maxTokens)
        self.timeoutSeconds = max(1, timeoutSeconds)
    }
}

public struct LocalVLMResponse: Equatable, Sendable {
    public let text: String
    public let metadata: [String: String]

    public init(text: String, metadata: [String: String] = [:]) {
        self.text = text
        self.metadata = metadata
    }
}

public enum LocalVLMProviderError: Error, Equatable, LocalizedError, Sendable {
    case invalidImagePath(String)
    case timedOut(Double)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidImagePath(let path):
            "Local VLM image path is not a readable file: \(path)"
        case .timedOut(let seconds):
            "Local VLM provider timed out after \(seconds) seconds."
        case .cancelled:
            "Local VLM provider request was cancelled."
        }
    }
}

public protocol LocalVLMProviding: Sendable {
    var providerName: String { get }
    var modelID: String { get }

    func answer(
        imageURL: URL,
        prompt: String,
        options: LocalVLMRequestOptions
    ) async throws -> LocalVLMResponse
}

public enum LocalVLMProviderExecutor {
    public static func answer(
        using provider: any LocalVLMProviding,
        imageURL: URL,
        prompt: String,
        options: LocalVLMRequestOptions
    ) async throws -> LocalVLMResponse {
        try validateImageURL(imageURL)
        return try await withThrowingTaskGroup(of: LocalVLMResponse.self) { group in
            group.addTask {
                try await provider.answer(imageURL: imageURL, prompt: prompt, options: options)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds(options.timeoutSeconds))
                throw LocalVLMProviderError.timedOut(options.timeoutSeconds)
            }
            defer {
                group.cancelAll()
            }
            do {
                guard let response = try await group.next() else {
                    throw LocalVLMProviderError.cancelled
                }
                return response
            } catch is CancellationError {
                throw LocalVLMProviderError.cancelled
            }
        }
    }

    private static func validateImageURL(_ imageURL: URL) throws {
        var isDirectory = ObjCBool(false)
        let exists = imageURL.isFileURL
            && FileManager.default.fileExists(atPath: imageURL.path, isDirectory: &isDirectory)
        guard exists, !isDirectory.boolValue else {
            throw LocalVLMProviderError.invalidImagePath(imageURL.path)
        }
    }

    private static func timeoutNanoseconds(_ seconds: Double) -> UInt64 {
        UInt64(max(0.001, seconds) * 1_000_000_000)
    }
}

public enum LocalVLMEndpointPolicy {
    public static func validate(_ url: URL, allowNonLocalEndpoint: Bool) throws {
        guard allowNonLocalEndpoint || isLocal(url) else {
            throw ToolExecutionError.denied("Local VLM endpoint must be localhost unless allowNonLocalEndpoint is true.")
        }
    }

    public static func isLocal(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), !host.isEmpty else {
            return true
        }
        return host == "localhost"
            || host == "127.0.0.1"
            || host == "::1"
            || host == "0.0.0.0"
            || host.hasSuffix(".localhost")
    }
}

public enum LocalVLMProviderFactory {
    public static func provider(for configuration: LocalVLMConfiguration) throws -> (any LocalVLMProviding)? {
        guard configuration.enabled else {
            return nil
        }
        let modelID = try required(configuration.modelID, fieldName: "modelID")
        let options = LocalVLMRequestOptions(
            maxTokens: configuration.maxTokens,
            timeoutSeconds: configuration.timeoutSeconds
        )

        switch configuration.provider {
        case .mlxVLM:
            let executablePath = try required(configuration.executablePath, fieldName: "executablePath")
            return LocalVLMSubprocessProvider(
                providerName: configuration.provider.displayName,
                modelID: modelID,
                executableURL: URL(fileURLWithPath: (executablePath as NSString).expandingTildeInPath),
                arguments: configuration.arguments,
                defaultOptions: options
            )
        case .ollama:
            let endpointURL = try endpointURL(
                configuration.endpointURLString,
                fallback: "http://127.0.0.1:11434",
                allowNonLocalEndpoint: configuration.allowNonLocalEndpoint
            )
            return OllamaVLMProvider(modelID: modelID, endpointURL: endpointURL)
        case .llamaCPP:
            let endpointURL = try endpointURL(
                configuration.endpointURLString,
                fallback: "http://127.0.0.1:8080",
                allowNonLocalEndpoint: configuration.allowNonLocalEndpoint
            )
            return OpenAICompatibleVLMProvider(
                providerName: configuration.provider.displayName,
                modelID: modelID,
                endpointURL: endpointURL
            )
        case .openAICompatible:
            let endpointURL = try endpointURL(
                configuration.endpointURLString,
                fallback: "http://127.0.0.1:8080",
                allowNonLocalEndpoint: configuration.allowNonLocalEndpoint
            )
            return OpenAICompatibleVLMProvider(
                providerName: configuration.provider.displayName,
                modelID: modelID,
                endpointURL: endpointURL
            )
        }
    }

    private static func endpointURL(
        _ rawValue: String?,
        fallback: String,
        allowNonLocalEndpoint: Bool
    ) throws -> URL {
        let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value?.isEmpty == false ? value! : fallback) else {
            throw ToolExecutionError.invalidArguments("Local VLM endpointURLString is not a valid URL.")
        }
        try LocalVLMEndpointPolicy.validate(url, allowNonLocalEndpoint: allowNonLocalEndpoint)
        return url
    }

    private static func required(_ rawValue: String?, fieldName: String) throws -> String {
        let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty else {
            throw ToolExecutionError.invalidArguments("Local VLM \(fieldName) is required when enabled.")
        }
        return value
    }
}

public struct LocalVLMSubprocessProvider: LocalVLMProviding {
    public let providerName: String
    public let modelID: String
    public let executableURL: URL
    public let arguments: [String]
    public let defaultOptions: LocalVLMRequestOptions

    public init(
        providerName: String,
        modelID: String,
        executableURL: URL,
        arguments: [String],
        defaultOptions: LocalVLMRequestOptions = LocalVLMRequestOptions()
    ) {
        self.providerName = providerName
        self.modelID = modelID
        self.executableURL = executableURL
        self.arguments = arguments
        self.defaultOptions = defaultOptions
    }

    public func answer(
        imageURL: URL,
        prompt: String,
        options: LocalVLMRequestOptions
    ) async throws -> LocalVLMResponse {
        try await Task.detached(priority: .userInitiated) {
            try self.runSubprocess(imageURL: imageURL, prompt: prompt, options: options)
        }.value
    }

    private func runSubprocess(
        imageURL: URL,
        prompt: String,
        options: LocalVLMRequestOptions
    ) throws -> LocalVLMResponse {
        let resolvedArguments = substitutedArguments(
            imageURL: imageURL,
            prompt: prompt,
            options: options
        )
        guard !resolvedArguments.isEmpty else {
            throw ToolExecutionError.invalidArguments("Local VLM subprocess arguments must include {image} and {prompt} placeholders.")
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = resolvedArguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let box = LocalVLMProcessBox(process)
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            box.waitUntilExit()
            group.leave()
        }

        let timeout = max(1, options.timeoutSeconds)
        if group.wait(timeout: .now() + timeout) == .timedOut {
            box.terminate()
            throw ToolExecutionError.denied("Local VLM subprocess timed out.")
        }

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard box.terminationStatus == 0 else {
            throw ToolExecutionError.denied(errorOutput.isEmpty ? "Local VLM subprocess failed." : errorOutput)
        }
        guard !output.isEmpty else {
            throw ToolExecutionError.denied("Local VLM subprocess returned no output.")
        }

        return LocalVLMResponse(
            text: output,
            metadata: [
                "provider": providerName,
                "modelID": modelID
            ]
        )
    }

    private func substitutedArguments(
        imageURL: URL,
        prompt: String,
        options: LocalVLMRequestOptions
    ) -> [String] {
        let values = [
            "{image}": imageURL.path,
            "{prompt}": prompt,
            "{model}": modelID,
            "{maxTokens}": "\(options.maxTokens)",
            "{timeoutSeconds}": String(format: "%.0f", options.timeoutSeconds)
        ]
        return arguments.map { argument in
            values.reduce(argument) { partial, entry in
                partial.replacingOccurrences(of: entry.key, with: entry.value)
            }
        }
    }
}

private final class LocalVLMProcessBox: @unchecked Sendable {
    private let process: Process

    init(_ process: Process) {
        self.process = process
    }

    var terminationStatus: Int32 {
        process.terminationStatus
    }

    func waitUntilExit() {
        process.waitUntilExit()
    }

    func terminate() {
        process.terminate()
    }
}
