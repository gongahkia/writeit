import Foundation
import cerberusCore

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.contains("-h") || arguments.contains("--help") {
    print("usage: cerberus-head-gesture-eval [head-gesture-validation.csv]")
    exit(0)
}

let fileURL: URL
if let path = arguments.first {
    fileURL = URL(fileURLWithPath: path)
} else {
    fileURL = HeadGestureValidationLog.defaultFileURL()
}

do {
    let text = try String(contentsOf: fileURL, encoding: .utf8)
    let samples = try HeadGestureValidationAnalyzer.parseCSV(text)
    let report = HeadGestureValidationAnalyzer.report(samples: samples)
    print(HeadGestureValidationAnalyzer.render(report))
} catch {
    fputs("head gesture eval failed: \(error.localizedDescription)\n", stderr)
    exit(65)
}
