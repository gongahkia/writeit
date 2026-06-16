import Foundation
import cerberusCore

@main
struct ModelBenchmarkCommand {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("-h") || arguments.contains("--help") {
            Options.printUsage()
            return
        }

        let options = try Options(arguments: arguments)
        let assistant = Assistant(
            toolSummaries: DefaultToolCatalog.summaries,
            readOnlyNativeTools: options.enableNativeReadOnlyTools
                ? DefaultToolCatalog.readOnlyFoundationModelTools()
                : []
        )
        if options.prewarm {
            await assistant.prewarm()
        }

        print("request: \(options.request)")
        print("iterations: \(options.iterations)")
        print("native read-only tools: \(options.enableNativeReadOnlyTools)")

        let allowedTools = DefaultToolCatalog.summaries.map(\.name).sorted()
        let context = AssistantContext(allowedToolNames: allowedTools)
        var planDurations: [Double] = []
        var summarizeDurations: [Double] = []
        var nativeToolDurations: [Double] = []

        for index in 1...options.iterations {
            let planStart = Date()
            let plan = try await assistant.plan(for: options.request, context: context)
            let planDuration = Date().timeIntervalSince(planStart)
            planDurations.append(planDuration)

            if options.verbose {
                print("iteration \(index) plan: \(String(format: "%.3fs", planDuration)) intent=\(plan.intent) tool=\(plan.toolName)")
            }

            let result = ToolResult(
                toolName: plan.toolName.isEmpty ? "benchmark.synthetic" : plan.toolName,
                succeeded: true,
                spokenSummary: "Synthetic benchmark tool result.",
                untrustedPayload: options.syntheticToolPayload,
                metadata: ["benchmark": "true"]
            )
            let summarizeStart = Date()
            _ = try await assistant.summarize(toolResult: result, for: options.request)
            let summarizeDuration = Date().timeIntervalSince(summarizeStart)
            summarizeDurations.append(summarizeDuration)

            if options.enableNativeReadOnlyTools {
                let nativeStart = Date()
                _ = try await assistant.answerWithReadOnlyTools(for: options.request, context: context)
                let nativeDuration = Date().timeIntervalSince(nativeStart)
                nativeToolDurations.append(nativeDuration)
                if options.verbose {
                    print("iteration \(index) native tools: \(String(format: "%.3fs", nativeDuration))")
                }
            }

            if options.verbose {
                print("iteration \(index) summarize: \(String(format: "%.3fs", summarizeDuration))")
            }
        }

        print(LatencyBenchmarkSummary(samples: planDurations).line(label: "plan"))
        print(LatencyBenchmarkSummary(samples: summarizeDurations).line(label: "summarize synthetic tool output"))
        if options.enableNativeReadOnlyTools {
            print(LatencyBenchmarkSummary(samples: nativeToolDurations).line(label: "native read-only tool answer"))
        }
    }
}

private struct Options {
    let request: String
    let iterations: Int
    let syntheticToolPayload: String
    let enableNativeReadOnlyTools: Bool
    let prewarm: Bool
    let verbose: Bool

    init(arguments: [String]) throws {
        var request = "what text is on my screen?"
        var iterations = 3
        var syntheticToolPayload = "Synthetic local tool output for latency measurement. No external data."
        var enableNativeReadOnlyTools = false
        var prewarm = true
        var verbose = false
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "--request":
                guard let value = iterator.next(), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ToolExecutionError.invalidArguments("--request requires text.")
                }
                request = value
            case "--iterations":
                guard let value = iterator.next(), let parsed = Int(value), parsed > 0 else {
                    throw ToolExecutionError.invalidArguments("--iterations requires a positive integer.")
                }
                iterations = parsed
            case "--payload":
                guard let value = iterator.next() else {
                    throw ToolExecutionError.invalidArguments("--payload requires text.")
                }
                syntheticToolPayload = value
            case "--native-read-only-tools":
                enableNativeReadOnlyTools = true
            case "--no-prewarm":
                prewarm = false
            case "--verbose":
                verbose = true
            default:
                throw ToolExecutionError.invalidArguments("Unknown argument: \(argument)")
            }
        }

        self.request = request
        self.iterations = iterations
        self.syntheticToolPayload = syntheticToolPayload
        self.enableNativeReadOnlyTools = enableNativeReadOnlyTools
        self.prewarm = prewarm
        self.verbose = verbose
    }

    static func printUsage() {
        print("""
        usage: cerberus-model-benchmark [--request text] [--iterations 3] [--payload text] [--native-read-only-tools] [--no-prewarm] [--verbose]

        Measures Foundation Models planning latency and synthetic tool-output summarization latency.
        By default it does not run live native tools. Add --native-read-only-tools to benchmark the app's read-only Tool session.
        """)
    }
}
