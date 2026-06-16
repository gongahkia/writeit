import CreateML
import Foundation
import cerberusCore

@main
struct WakeModelTrainCommand {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("-h") || arguments.contains("--help") {
            Options.printUsage()
            return
        }

        let options = try Options(arguments: arguments)
        let classCounts = try WakeWordSampleDataset.classCounts(in: options.inputDirectory)
        try validateDataset(classCounts: classCounts, targetLabel: options.targetLabel, inputDirectory: options.inputDirectory)

        let summary = classCounts
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
        print("input: \(options.inputDirectory.path)")
        print("output: \(options.outputURL.path)")
        print("classes: \(summary)")
        print("target: \(options.targetLabel)")
        print("training...")

        let dataSource = MLSoundClassifier.DataSource.labeledDirectories(at: options.inputDirectory)
        let parameters = MLSoundClassifier.ModelParameters(
            validation: options.validation.createMLValue,
            maxIterations: options.maxIterations,
            overlapFactor: options.overlapFactor
        )
        let classifier = try MLSoundClassifier(trainingData: dataSource, parameters: parameters)
        let metadata = MLModelMetadata(
            author: options.author,
            shortDescription: "cerberus wake word sound classifier.",
            license: options.modelLicense,
            version: options.version,
            additional: [
                "targetLabel": options.targetLabel,
                "classCounts": summary,
                "confidenceThreshold": String(options.confidenceThreshold),
                "overlapFactor": String(options.overlapFactor)
            ]
        )

        try FileManager.default.createDirectory(
            at: options.outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: options.outputURL.path) {
            try FileManager.default.removeItem(at: options.outputURL)
        }
        try classifier.write(to: options.outputURL, metadata: metadata)

        printMetrics("training", classifier.trainingMetrics)
        printMetrics("validation", classifier.validationMetrics)
        print("wrote model: \(options.outputURL.path)")

        if options.writeConfig {
            let configURL = WakeWordSoundClassifierConfigurationLoader.defaultFileURL()
            let configuration = WakeWordSoundClassifierConfiguration(
                modelPath: options.outputURL.path,
                targetLabels: [options.targetLabel],
                confidenceThreshold: options.confidenceThreshold,
                overlapFactor: options.overlapFactor
            )
            try configuration.validate()
            try FileManager.default.createDirectory(
                at: configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(configuration).write(to: configURL, options: .atomic)
            print("wrote config: \(configURL.path)")
        }
    }

    private static func validateDataset(
        classCounts: [String: Int],
        targetLabel: String,
        inputDirectory: URL
    ) throws {
        guard classCounts.count >= 2 else {
            throw ToolExecutionError.invalidArguments(
                "Wake training needs at least two labeled class directories with audio files in \(inputDirectory.path)."
            )
        }
        guard classCounts[targetLabel] != nil else {
            throw ToolExecutionError.invalidArguments(
                "Target label \(targetLabel) is missing from wake sample classes: \(classCounts.keys.sorted().joined(separator: ", "))."
            )
        }
    }

    private static func printMetrics(_ label: String, _ metrics: MLClassifierMetrics) {
        guard metrics.isValid else {
            print("\(label) classification error: unavailable")
            return
        }
        print(String(format: "\(label) classification error: %.4f", metrics.classificationError))
    }
}

private enum ValidationMode: String {
    case automatic
    case none

    var createMLValue: MLSoundClassifier.ModelParameters.ValidationData {
        switch self {
        case .automatic:
            .split(strategy: .automatic)
        case .none:
            .none
        }
    }
}

private struct Options {
    let inputDirectory: URL
    let outputURL: URL
    let maxIterations: Int
    let overlapFactor: Double
    let validation: ValidationMode
    let targetLabel: String
    let confidenceThreshold: Double
    let writeConfig: Bool
    let author: String
    let version: String
    let modelLicense: String?

    init(arguments: [String]) throws {
        var inputDirectory = WakeWordSampleDataset.defaultDirectoryURL()
        var outputURL = Self.defaultOutputURL()
        var maxIterations = 25
        var overlapFactor = 0.5
        var validation = ValidationMode.automatic
        var targetLabel = "hey_cerberus"
        var confidenceThreshold = 0.85
        var writeConfig = false
        var author = NSFullUserName()
        var version = "1"
        var modelLicense: String?
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "--input":
                guard let value = iterator.next() else {
                    throw ToolExecutionError.invalidArguments("--input requires a directory.")
                }
                inputDirectory = Self.fileURL(value)
            case "--output":
                guard let value = iterator.next() else {
                    throw ToolExecutionError.invalidArguments("--output requires a file path.")
                }
                outputURL = Self.fileURL(value)
            case "--iterations":
                guard let value = iterator.next(), let parsed = Int(value), parsed > 0 else {
                    throw ToolExecutionError.invalidArguments("--iterations requires a positive integer.")
                }
                maxIterations = parsed
            case "--overlap":
                guard let value = iterator.next(), let parsed = Double(value), parsed >= 0, parsed < 1 else {
                    throw ToolExecutionError.invalidArguments("--overlap requires a number in [0, 1).")
                }
                overlapFactor = parsed
            case "--validation":
                guard let value = iterator.next(), let parsed = ValidationMode(rawValue: value) else {
                    throw ToolExecutionError.invalidArguments("--validation requires automatic or none.")
                }
                validation = parsed
            case "--target-label":
                guard let value = iterator.next() else {
                    throw ToolExecutionError.invalidArguments("--target-label requires a label.")
                }
                targetLabel = value
            case "--confidence-threshold":
                guard let value = iterator.next(), let parsed = Double(value), parsed > 0, parsed <= 1 else {
                    throw ToolExecutionError.invalidArguments("--confidence-threshold requires a number in (0, 1].")
                }
                confidenceThreshold = parsed
            case "--write-config":
                writeConfig = true
            case "--author":
                guard let value = iterator.next() else {
                    throw ToolExecutionError.invalidArguments("--author requires text.")
                }
                author = value
            case "--version":
                guard let value = iterator.next(), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ToolExecutionError.invalidArguments("--version requires text.")
                }
                version = value
            case "--license":
                guard let value = iterator.next() else {
                    throw ToolExecutionError.invalidArguments("--license requires text.")
                }
                modelLicense = value
            default:
                throw ToolExecutionError.invalidArguments("Unknown argument: \(argument)")
            }
        }

        guard outputURL.pathExtension == "mlmodel" else {
            throw ToolExecutionError.invalidArguments("--output must end in .mlmodel.")
        }

        self.inputDirectory = inputDirectory
        self.outputURL = outputURL
        self.maxIterations = maxIterations
        self.overlapFactor = overlapFactor
        self.validation = validation
        self.targetLabel = try WakeWordSampleDataset.normalizedLabel(targetLabel)
        self.confidenceThreshold = confidenceThreshold
        self.writeConfig = writeConfig
        self.author = author
        self.version = version
        self.modelLicense = modelLicense
    }

    static func printUsage() {
        print("""
        usage: cerberus-wake-train [--input dir] [--output CerberusWakeWord.mlmodel] [--target-label hey_cerberus] [--iterations 25] [--overlap 0.5] [--validation automatic|none] [--confidence-threshold 0.85] [--write-config]

        Trains a CreateML MLSoundClassifier from labeled class directories and writes a Core ML .mlmodel.
        Default input: \(WakeWordSampleDataset.defaultDirectoryURL().path)
        Default output: \(defaultOutputURL().path)
        """)
    }

    private static func defaultOutputURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return baseURL
            .appendingPathComponent(CerberusCore.appName, isDirectory: true)
            .appendingPathComponent("wake-word-models", isDirectory: true)
            .appendingPathComponent("CerberusWakeWord.mlmodel")
    }

    private static func fileURL(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }
}
