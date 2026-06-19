import Foundation
import FoundationModels
import cerberusCore

@main
struct AdapterEvalCommand {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("-h") || arguments.contains("--help") {
            Options.printUsage()
            return
        }

        let options = try Options(arguments: arguments)
        let data = try Data(contentsOf: options.evalFileURL)
        var cases = try AdapterEvaluation.cases(fromJSONL: data)
        if let limit = options.limit {
            cases = Array(cases.prefix(limit))
        }
        guard !cases.isEmpty else {
            throw ToolExecutionError.invalidArguments("No adapter eval cases found.")
        }

        let model = try await options.model()
        let session = LanguageModelSession(
            model: model,
            instructions: "Answer the user request directly and concisely. Do not mention evaluation."
        )
        var results: [AdapterEvaluationResult] = []

        for testCase in cases {
            let response = try await session.respond(to: testCase.prompt)
            let result = AdapterEvaluation.result(for: testCase, actualResponse: response.content)
            results.append(result)
            print(result.matchesExpected ? "PASS" : "FAIL")
            print("prompt: \(testCase.prompt)")
            print("expected: \(testCase.expectedResponse)")
            print("actual: \(result.actualResponse)")
            print(String(format: "responseTokenF1: %.4f", result.responseTokenF1))
            if let expectedToolName = result.expectedToolName {
                print("expectedTool: \(expectedToolName)")
                print("actualTool: \(result.actualToolName ?? "none")")
            }
            print("")
        }

        let summary = AdapterEvaluation.score(results)
        print("total: \(summary.total)")
        print("matches: \(summary.matches)")
        print(String(format: "accuracy: %.4f", summary.accuracy))
        print(String(format: "responseTokenF1.avg: %.4f", summary.averageResponseTokenF1))
        print("toolSelection.total: \(summary.toolSelectionTotal)")
        print("toolSelection.matches: \(summary.toolSelectionMatches)")
        print(String(format: "toolSelection.accuracy: %.4f", summary.toolSelectionAccuracy))
    }
}

private struct Options {
    let evalFileURL: URL
    let adapterConfigURL: URL?
    let limit: Int?

    init(arguments: [String]) throws {
        var evalFileURL: URL?
        var adapterConfigURL: URL?
        var limit: Int?
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "--adapter-config":
                guard let value = iterator.next() else {
                    throw ToolExecutionError.invalidArguments("--adapter-config requires a path.")
                }
                adapterConfigURL = URL(fileURLWithPath: value)
            case "--limit":
                guard let value = iterator.next(), let parsed = Int(value), parsed > 0 else {
                    throw ToolExecutionError.invalidArguments("--limit requires a positive integer.")
                }
                limit = parsed
            default:
                guard !argument.hasPrefix("-"), evalFileURL == nil else {
                    throw ToolExecutionError.invalidArguments("Unknown argument: \(argument)")
                }
                evalFileURL = URL(fileURLWithPath: argument)
            }
        }

        self.evalFileURL = evalFileURL ?? AdapterTrainingDatasetExporter.defaultOutputDirectory()
            .appendingPathComponent("eval.jsonl")
        self.adapterConfigURL = adapterConfigURL
        self.limit = limit
    }

    func model() async throws -> SystemLanguageModel {
        guard let adapterConfigURL else {
            return .default
        }
        return try await FoundationModelAdapterLoader(fileURL: adapterConfigURL).configuredModelIfPresent() ?? .default
    }

    static func printUsage() {
        print("""
        usage: cerberus-adapter-eval [eval.jsonl] [--adapter-config adapter.json] [--limit count]

        Runs exact normalized response matching against Foundation Models using eval.jsonl.
        """)
    }
}
