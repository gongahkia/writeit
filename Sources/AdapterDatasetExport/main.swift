import Foundation
import cerberusCore

@main
struct AdapterDatasetExportCommand {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("-h") || arguments.contains("--help") {
            Options.printUsage()
            return
        }
        let options = try Options(arguments: arguments)
        let records = try await EncryptedTranscriptStore().records()
        let exporter = AdapterTrainingDatasetExporter()
        let samples = exporter.samples(
            from: records,
            limit: options.limit,
            redactsPrivateData: options.redactsPrivateData
        )
        let statistics = exporter.statistics(from: records, limit: options.limit)
        let split = try exporter.split(samples: samples, evalFraction: options.evalFraction)
        try exporter.write(split, to: options.outputDirectory)
        try exporter.writeStatistics(statistics, to: options.outputDirectory)

        print(options.outputDirectory.path)
        print("train: \(split.train.count)")
        print("eval: \(split.eval.count)")
        print("redaction: \(options.redactsPrivateData ? "enabled" : "disabled")")
        for line in statistics.summaryLines {
            print(line)
        }
    }
}

private struct Options {
    let outputDirectory: URL
    let evalFraction: Double
    let limit: Int?
    let redactsPrivateData: Bool

    init(arguments: [String]) throws {
        var outputDirectory: URL?
        var evalFraction = 0.2
        var limit: Int?
        var redactsPrivateData = true
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "--eval-fraction":
                guard let value = iterator.next(), let parsed = Double(value) else {
                    throw ToolExecutionError.invalidArguments("--eval-fraction requires a number.")
                }
                evalFraction = parsed
            case "--limit":
                guard let value = iterator.next(), let parsed = Int(value), parsed > 0 else {
                    throw ToolExecutionError.invalidArguments("--limit requires a positive integer.")
                }
                limit = parsed
            case "--no-redact":
                redactsPrivateData = false
            default:
                guard !argument.hasPrefix("-"), outputDirectory == nil else {
                    throw ToolExecutionError.invalidArguments("Unknown argument: \(argument)")
                }
                outputDirectory = URL(fileURLWithPath: argument)
            }
        }

        self.outputDirectory = outputDirectory ?? AdapterTrainingDatasetExporter.defaultOutputDirectory()
        self.evalFraction = evalFraction
        self.limit = limit
        self.redactsPrivateData = redactsPrivateData
    }

    static func printUsage() {
        print("""
        usage: cerberus-adapter-dataset [output-directory] [--eval-fraction 0.2] [--limit count] [--no-redact]

        Exports encrypted cerberus transcripts to Foundation Models adapter-training JSONL:
          train.jsonl
          eval.jsonl
          stats.json

        Redaction is enabled by default for email addresses, bearer tokens, long hex tokens, and /Users home paths.
        """)
    }
}
