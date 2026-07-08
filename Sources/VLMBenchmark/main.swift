import Foundation
import cerberusCore

@main
struct VLMBenchmarkCommand {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("-h") || arguments.contains("--help") {
            Options.printUsage()
            return
        }

        let options = try Options(arguments: arguments)
        let input = try await options.resolveImageInput()
        let configuration = try options.localVLMConfiguration()
        guard let provider = try LocalVLMProviderFactory.provider(for: configuration) else {
            throw ToolExecutionError.invalidArguments("Local VLM benchmark requires an enabled provider config or --provider.")
        }

        print("provider: \(provider.providerName)")
        print("model: \(provider.modelID)")
        print("preset: \(configuration.presetID)")
        print("input: \(input.mode.rawValue) \(input.url.path)")
        print("prompt: \(options.prompt)")

        let report = await VLMBenchmarkRunner.run(
            using: provider,
            presetID: configuration.presetID,
            prompt: options.prompt,
            imageURL: input.url,
            imageFixture: input.fixtureName,
            inputMode: input.mode,
            options: configuration.requestOptions
        )
        try BenchmarkReportWriter.write(report, to: options.outputURL)

        print(String(format: "latency: %.3fs", report.latencySeconds))
        print("success: \(report.success)")
        if report.success {
            print("response: \(report.response)")
        } else {
            print("error: \(report.error ?? "unknown")")
        }
        print("wrote report: \(options.outputURL.path)")
    }
}

private struct Options {
    let prompt: String
    let outputURL: URL
    let configURL: URL
    let provider: LocalVLMProviderKind?
    let presetID: String?
    let modelID: String?
    let endpointURLString: String?
    let executablePath: String?
    let providerArguments: [String]
    let maxTokens: Int?
    let timeoutSeconds: Double?
    let allowNonLocalEndpoint: Bool
    let imageURL: URL?
    let liveScreen: Bool
    let scope: String?
    let fixtureDirectoryURL: URL

    init(arguments: [String]) throws {
        var prompt = "Describe the visible UI, primary text, and any uncertainty."
        var outputURL: URL?
        var configURL = LocalVLMConfiguration.defaultFileURL()
        var provider: LocalVLMProviderKind?
        var presetID: String?
        var modelID: String?
        var endpointURLString: String?
        var executablePath: String?
        var providerArguments: [String] = []
        var maxTokens: Int?
        var timeoutSeconds: Double?
        var allowNonLocalEndpoint = false
        var imageURL: URL?
        var generatedFixture = false
        var liveScreen = false
        var scope: String?
        var fixtureDirectoryURL = Self.fileURL(".dist/validation/vlm-fixtures")
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "--prompt":
                guard let value = iterator.next(), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ToolExecutionError.invalidArguments("--prompt requires text.")
                }
                prompt = value
            case "--output":
                guard let value = iterator.next() else {
                    throw ToolExecutionError.invalidArguments("--output requires a path.")
                }
                outputURL = Self.fileURL(value)
            case "--config":
                guard let value = iterator.next() else {
                    throw ToolExecutionError.invalidArguments("--config requires a path.")
                }
                configURL = Self.fileURL(value)
            case "--provider":
                guard let value = iterator.next(), let parsed = LocalVLMProviderKind(rawValue: value) else {
                    throw ToolExecutionError.invalidArguments("--provider requires mlx_vlm, ollama, llama_cpp, or openai_compatible.")
                }
                provider = parsed
            case "--preset-id":
                guard let value = iterator.next(), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ToolExecutionError.invalidArguments("--preset-id requires text.")
                }
                presetID = value
            case "--model-id":
                guard let value = iterator.next(), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ToolExecutionError.invalidArguments("--model-id requires text.")
                }
                modelID = value
            case "--endpoint":
                guard let value = iterator.next(), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ToolExecutionError.invalidArguments("--endpoint requires a URL.")
                }
                endpointURLString = value
            case "--executable":
                guard let value = iterator.next(), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ToolExecutionError.invalidArguments("--executable requires a path.")
                }
                executablePath = value
            case "--arg":
                guard let value = iterator.next() else {
                    throw ToolExecutionError.invalidArguments("--arg requires a subprocess argument.")
                }
                providerArguments.append(value)
            case "--max-tokens":
                guard let value = iterator.next(), let parsed = Int(value), parsed > 0 else {
                    throw ToolExecutionError.invalidArguments("--max-tokens requires a positive integer.")
                }
                maxTokens = parsed
            case "--timeout":
                guard let value = iterator.next(), let parsed = Double(value), parsed > 0 else {
                    throw ToolExecutionError.invalidArguments("--timeout requires a positive number.")
                }
                timeoutSeconds = parsed
            case "--allow-non-local-endpoint":
                allowNonLocalEndpoint = true
            case "--image":
                guard let value = iterator.next() else {
                    throw ToolExecutionError.invalidArguments("--image requires a path.")
                }
                imageURL = Self.fileURL(value)
            case "--generated-fixture":
                generatedFixture = true
            case "--live-screen":
                liveScreen = true
            case "--scope":
                guard let value = iterator.next(), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ToolExecutionError.invalidArguments("--scope requires main_display or active_window.")
                }
                scope = value
            case "--fixture-dir":
                guard let value = iterator.next() else {
                    throw ToolExecutionError.invalidArguments("--fixture-dir requires a path.")
                }
                fixtureDirectoryURL = Self.fileURL(value)
            default:
                throw ToolExecutionError.invalidArguments("Unknown argument: \(argument)")
            }
        }

        if imageURL != nil, liveScreen || generatedFixture {
            throw ToolExecutionError.invalidArguments("Use only one image source: --image, --generated-fixture, or --live-screen.")
        }
        if liveScreen, generatedFixture {
            throw ToolExecutionError.invalidArguments("Use only one image source: --generated-fixture or --live-screen.")
        }

        self.prompt = prompt
        self.outputURL = outputURL ?? Self.defaultOutputURL()
        self.configURL = configURL
        self.provider = provider
        self.presetID = presetID
        self.modelID = modelID
        self.endpointURLString = endpointURLString
        self.executablePath = executablePath
        self.providerArguments = providerArguments
        self.maxTokens = maxTokens
        self.timeoutSeconds = timeoutSeconds
        self.allowNonLocalEndpoint = allowNonLocalEndpoint
        self.imageURL = imageURL
        self.liveScreen = liveScreen
        self.scope = scope
        self.fixtureDirectoryURL = fixtureDirectoryURL
    }

    func localVLMConfiguration() throws -> LocalVLMConfiguration {
        let base = try provider == nil ? LocalVLMConfiguration.load(from: configURL) : (try? LocalVLMConfiguration.load(from: configURL)) ?? .disabled
        let enabled = provider != nil || base.enabled
        guard enabled else {
            throw ToolExecutionError.invalidArguments("Local VLM config is disabled; pass --provider and --model-id or create local-vlm.json.")
        }
        return LocalVLMConfiguration(
            enabled: true,
            provider: provider ?? base.provider,
            presetID: presetID ?? base.presetID,
            modelID: modelID ?? base.modelID,
            endpointURLString: endpointURLString ?? base.endpointURLString,
            executablePath: executablePath ?? base.executablePath,
            arguments: providerArguments.isEmpty ? base.arguments : providerArguments,
            maxTokens: maxTokens ?? base.maxTokens,
            timeoutSeconds: timeoutSeconds ?? base.timeoutSeconds,
            allowNonLocalEndpoint: allowNonLocalEndpoint || base.allowNonLocalEndpoint
        )
    }

    func resolveImageInput() async throws -> ImageInput {
        if liveScreen {
            try FileManager.default.createDirectory(at: fixtureDirectoryURL, withIntermediateDirectories: true)
            let tool = ScreenSnapshotTool(outputDirectoryURL: fixtureDirectoryURL)
            let result = try await tool.run(arguments: ScreenSnapshotTool.Arguments(scope: scope))
            guard let path = result.metadata["imagePath"] else {
                throw ToolExecutionError.denied("Live screen capture did not return an image path.")
            }
            let url = URL(fileURLWithPath: path)
            return ImageInput(url: url, fixtureName: url.lastPathComponent, mode: .liveScreen)
        }
        if let imageURL {
            return ImageInput(url: imageURL, fixtureName: imageURL.lastPathComponent, mode: .fixture)
        }
        let url = try Self.writeGeneratedFixture(in: fixtureDirectoryURL)
        return ImageInput(url: url, fixtureName: url.lastPathComponent, mode: .generatedRedacted)
    }

    static func printUsage() {
        print("""
        usage: cerberus-vlm-benchmark [--config local-vlm.json] [--provider mlx_vlm|ollama|llama_cpp|openai_compatible] [--model-id id] [--prompt text] [--image file.png|--generated-fixture|--live-screen] [--output .dist/validation/vlm.json]

        Writes a JSON report with provider, model id, prompt, image fixture, latency, success/failure, and response.
        Defaults to a generated redacted PNG and .dist/validation/vlm-<timestamp>.json.
        Use --arg repeatedly for mlx_vlm subprocess arguments; placeholders match local-vlm.json: {model}, {image}, {prompt}, {maxTokens}, {timeoutSeconds}.
        """)
    }

    private static func writeGeneratedFixture(in directoryURL: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = directoryURL.appendingPathComponent("vlm-redacted-fixture.png")
        let data = try redactedPNGData()
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    private static func redactedPNGData() throws -> Data {
        let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
        guard let data = Data(base64Encoded: base64) else {
            throw ToolExecutionError.denied("Could not create generated VLM fixture.")
        }
        return data
    }

    private static func defaultOutputURL() -> URL {
        fileURL(".dist/validation/vlm-\(Int(Date().timeIntervalSince1970)).json")
    }

    private static func fileURL(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }
}

private struct ImageInput {
    let url: URL
    let fixtureName: String
    let mode: VLMBenchmarkInputMode
}
