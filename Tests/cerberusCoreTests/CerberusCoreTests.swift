import Foundation
import CoreAudio
import CoreGraphics
import Testing
@testable import cerberusCore

@Test func appMetadataIsStable() {
    #expect(CerberusCore.appName == "cerberus")
    #expect(CerberusCore.bundleIdentifier == "dev.gongahkia.cerberus")
}

@Test func appInfoPlistDeclaresEventKitFullAccessUsage() throws {
    let fileURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/cerberusApp/Resources/Info.plist")
    let data = try Data(contentsOf: fileURL)
    let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

    #expect(plist["NSCalendarsFullAccessUsageDescription"] as? String != nil)
    #expect(plist["NSRemindersFullAccessUsageDescription"] as? String != nil)
}

@Test func stateMachineFollowsHappyPath() {
    var machine = AssistantStateMachine()

    #expect(machine.handle(.wakeDetected(.manual))?.to == .listening)
    #expect(machine.handle(.silenceDetected)?.to == .reasoning)
    #expect(machine.handle(.responseReady("done"))?.to == .speaking)
    #expect(machine.handle(.speechFinished)?.to == .idle)
}

@Test func stateMachineAllowsSpeechInterruptionBeforeNewWake() {
    var machine = AssistantStateMachine(initialState: .speaking)

    #expect(machine.handle(.cancelRequested)?.to == .idle)
    #expect(machine.handle(.wakeDetected(.stemTriplePress))?.to == .listening)
}

@Test func stateMachineRejectsInvalidTransitions() {
    var machine = AssistantStateMachine()

    #expect(machine.handle(.silenceDetected) == nil)
    #expect(machine.state == .idle)
}

@Test func systemPromptDocumentsUntrustedToolOutput() {
    let prompt = SystemPrompt.render(toolSummaries: [
        ToolSummary(name: "calendar.read", capability: "Read upcoming events.", mutatesState: false)
    ])

    #expect(prompt.contains("untrusted data"))
    #expect(prompt.contains("calendar.read"))
    #expect(prompt.contains("read-only"))
}

@Test func toolSessionAllowlistFiltersDisabledTools() {
    let summaries = [
        ToolSummary(name: "calendar.read", capability: "Read calendar.", mutatesState: false),
        ToolSummary(name: "web.search", capability: "Search web.", mutatesState: false)
    ]
    var allowlist = ToolSessionAllowlist()

    #expect(allowlist.filter(summaries).map(\.name) == ["calendar.read", "web.search"])

    allowlist.setEnabled("web.search", enabled: false)

    #expect(allowlist.isEnabled("web.search") == false)
    #expect(allowlist.filter(summaries).map(\.name) == ["calendar.read"])

    allowlist.reset()

    #expect(allowlist.filter(summaries).map(\.name) == ["calendar.read", "web.search"])
}

@Test func assistantContextIncludesActiveApplicationName() {
    let context = AssistantContext(
        activeApplicationName: "Xcode",
        allowedToolNames: ["files.search"],
        fileSearchScopePaths: ["/Users/example/Documents"]
    )

    #expect(context.promptFragment.contains("Active app: Xcode"))
    #expect(context.promptFragment.contains("Allowed tools: files.search"))
    #expect(context.promptFragment.contains("File search folders: /Users/example/Documents"))
}

@Test func assistantContextWarnsWhenFileSearchHasNoApprovedFolders() {
    let context = AssistantContext(allowedToolNames: ["files.search"])

    #expect(context.promptFragment.contains("File search folders: none approved"))
}

@Test func headGestureClassifierUsesCalibratedNeutralPose() {
    var classifier = HeadGestureClassifier(pitchThreshold: 0.3, yawThreshold: 0.4, cooldown: 1.0)
    let start = Date(timeIntervalSince1970: 1_000)

    classifier.calibrate(pitch: 0.1, yaw: -0.1)

    #expect(classifier.classify(pitch: 0.2, yaw: -0.2, at: start) == nil)
    #expect(classifier.classify(pitch: 0.5, yaw: -0.1, at: start.addingTimeInterval(1.1)) == .nod)
}

@Test func headGestureClassifierAppliesCooldown() {
    var classifier = HeadGestureClassifier(pitchThreshold: 0.3, yawThreshold: 0.4, cooldown: 2.0)
    let start = Date(timeIntervalSince1970: 2_000)

    classifier.calibrate(pitch: 0, yaw: 0)

    #expect(classifier.classify(pitch: 0.4, yaw: 0, at: start) == .nod)
    #expect(classifier.classify(pitch: 0.8, yaw: 0, at: start.addingTimeInterval(1.0)) == nil)
}

@Test func headGestureClassifierUpdatesThresholds() {
    var classifier = HeadGestureClassifier(pitchThreshold: 0.3, yawThreshold: 0.4, cooldown: 0)
    let start = Date(timeIntervalSince1970: 3_000)

    classifier.calibrate(pitch: 0, yaw: 0)
    classifier.updateThresholds(pitch: 0.6, yaw: 0.7)

    #expect(classifier.classify(pitch: 0.4, yaw: 0, at: start) == nil)
    #expect(classifier.classify(pitch: 0.7, yaw: 0, at: start.addingTimeInterval(1.0)) == .nod)
}

@Test func headGestureValidationLogWritesCSV() async throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("head-gesture-validation.csv")
    let log = HeadGestureValidationLog(fileURL: fileURL)
    let snapshot = HeadGestureMotionSnapshot(
        timestamp: Date(timeIntervalSince1970: 0),
        pitch: 0.1234567,
        yaw: -0.25,
        pitchThreshold: 0.35,
        yawThreshold: 0.45,
        gesture: .nod
    )

    try await log.append(snapshot)

    let text = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(text.contains(HeadGestureMotionSnapshot.csvHeader))
    #expect(text.contains("1970-01-01T00:00:00Z,0.123457,-0.250000,,,,,0.350000,0.450000,nod"))
}

@Test func headGestureValidationAnalyzerReportsThresholdSuggestions() throws {
    let csv = """
    timestamp,pitch,yaw,neutralPitch,neutralYaw,deltaPitch,deltaYaw,pitchThreshold,yawThreshold,gesture
    1970-01-01T00:00:00Z,0.00,0.00,0.00,0.00,0.00,0.00,0.35,0.45,
    1970-01-01T00:00:01Z,0.10,0.04,0.00,0.00,0.10,0.04,0.35,0.45,
    1970-01-01T00:00:02Z,0.42,0.05,0.00,0.00,0.42,0.05,0.35,0.45,nod
    1970-01-01T00:00:03Z,0.05,0.52,0.00,0.00,0.05,0.52,0.35,0.45,shake
    """

    let samples = try HeadGestureValidationAnalyzer.parseCSV(csv)
    let report = HeadGestureValidationAnalyzer.report(samples: samples)

    #expect(report.sampleCount == 4)
    #expect(report.quietSampleCount == 2)
    #expect(report.nodCount == 1)
    #expect(report.shakeCount == 1)
    #expect(report.maxQuietPitchDelta == 0.10)
    #expect(report.maxQuietYawDelta == 0.04)
    #expect(report.suggestedPitchThreshold == 0.15)
    #expect(report.suggestedYawThreshold == 0.15)
    #expect(HeadGestureValidationAnalyzer.render(report).contains("nod detections: 1"))
}

@Test func wakeWordDetectorMatchesNormalizedPhrase() {
    let detector = WakeWordDetector()

    #expect(detector.detectsWakeWord(in: "Hey, Cerberus."))
    #expect(!detector.detectsWakeWord(in: "hello service"))
}

@Test func wakeWordDetectorSupportsCustomPhrases() {
    let detector = WakeWordDetector(phrases: ["computer activate"])
    let emptyDetector = WakeWordDetector(phrases: [""])

    #expect(detector.detectsWakeWord(in: "Computer, activate."))
    #expect(!detector.detectsWakeWord(in: "hey cerberus"))
    #expect(!emptyDetector.detectsWakeWord(in: "anything"))
}

@Test func speechBenchmarkScorerNormalizesWords() {
    #expect(SpeechBenchmarkScorer.normalizedWords("Hey, Cerberus!") == ["hey", "cerberus"])
    #expect(SpeechBenchmarkScorer.normalizedWords("open  README.md") == ["open", "readme", "md"])
}

@Test func speechBenchmarkScorerComputesWordErrorRate() {
    #expect(SpeechBenchmarkScorer.wordErrorRate(expected: "hey cerberus", actual: "hey cerberus") == 0)
    #expect(SpeechBenchmarkScorer.wordErrorRate(expected: "hey cerberus", actual: "hey service") == 0.5)
    #expect(SpeechBenchmarkScorer.wordErrorRate(expected: "", actual: "") == 0)
    #expect(SpeechBenchmarkScorer.wordErrorRate(expected: "", actual: "extra") == 1)
}

@Test func latencyBenchmarkSummaryComputesPercentiles() {
    let summary = LatencyBenchmarkSummary(samples: [0.4, 0.1, 0.2, 0.3])

    #expect(summary.count == 4)
    #expect(summary.minimum == 0.1)
    #expect(summary.median == 0.25)
    #expect(summary.p95 == 0.385)
    #expect(summary.maximum == 0.4)
    #expect(summary.average == 0.25)
    #expect(summary.line(label: "plan").contains("plan: count=4"))
}

@Test func benchmarkReportWriterWritesPrettyJSON() throws {
    struct Report: Codable {
        let name: String
        let value: Int
    }

    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("report.json")
    defer {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
    }

    try BenchmarkReportWriter.write(Report(name: "demo", value: 2), to: fileURL)

    let text = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(text.contains(#""name" : "demo""#))
    #expect(text.contains(#""value" : 2"#))
}

@Test func wakeWordSoundClassifierConfigurationValidatesModelAndLabels() throws {
    let valid = WakeWordSoundClassifierConfiguration(
        modelPath: "/tmp/wake.mlmodelc",
        targetLabels: ["Hey Cerberus"],
        confidenceThreshold: 0.9
    )

    try valid.validate()
    #expect(valid.normalizedTargetLabels == ["hey cerberus"])

    #expect(throws: WakeWordSoundClassifierError.self) {
        try WakeWordSoundClassifierConfiguration(modelPath: "", targetLabels: ["wake"]).validate()
    }
    #expect(throws: WakeWordSoundClassifierError.self) {
        try WakeWordSoundClassifierConfiguration(modelPath: "/tmp/wake.mlmodelc", targetLabels: []).validate()
    }
    #expect(throws: WakeWordSoundClassifierError.self) {
        try WakeWordSoundClassifierConfiguration(
            modelPath: "/tmp/wake.mlmodelc",
            targetLabels: ["wake"],
            confidenceThreshold: 1.2
        ).validate()
    }
}

@Test func wakeWordSampleDatasetNormalizesLabelsAndPaths() throws {
    let baseURL = URL(fileURLWithPath: "/tmp/wake-samples")
    let id = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000123"))
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let fileURL = try WakeWordSampleDataset.sampleFileURL(
        baseDirectoryURL: baseURL,
        label: "Hey, Cerberus!",
        index: 3,
        date: date,
        id: id
    )

    #expect(try WakeWordSampleDataset.normalizedLabel("Hey, Cerberus!") == "hey_cerberus")
    #expect(fileURL.path.contains("/hey_cerberus/hey_cerberus-1700000000-003-00000000-0000-0000-0000-000000000123.wav"))
    #expect(WakeWordSampleDataset.relativePath(for: fileURL, baseDirectoryURL: baseURL).hasPrefix("hey_cerberus/"))
    #expect(throws: ToolExecutionError.self) {
        try WakeWordSampleDataset.normalizedLabel(" , ")
    }
}

@Test func wakeWordSampleDatasetWritesManifestJSONL() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    let record = WakeWordSampleRecord(
        label: "hey_cerberus",
        relativePath: "hey_cerberus/sample.wav",
        durationSeconds: 1.5,
        createdAt: Date(timeIntervalSince1970: 0),
        note: "quiet"
    )

    try WakeWordSampleDataset.write(record: record, to: directory)
    try WakeWordSampleDataset.write(record: record, to: directory)

    let manifestURL = directory.appendingPathComponent(WakeWordSampleDataset.manifestFileName)
    let lines = try String(contentsOf: manifestURL, encoding: .utf8).split(separator: "\n")
    #expect(lines.count == 2)
    #expect(lines[0].contains(#""label":"hey_cerberus""#))
    #expect(lines[0].contains("hey_cerberus"))
    #expect(lines[0].contains("sample.wav"))
}

@Test func wakeWordSampleDatasetCountsSupportedAudioFilesByClass() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }
    let wakeDirectory = directory.appendingPathComponent("hey_cerberus", isDirectory: true)
    let backgroundDirectory = directory.appendingPathComponent("background", isDirectory: true)
    let emptyDirectory = directory.appendingPathComponent("empty", isDirectory: true)
    try FileManager.default.createDirectory(at: wakeDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: backgroundDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: emptyDirectory, withIntermediateDirectories: true)
    try Data().write(to: wakeDirectory.appendingPathComponent("one.wav"))
    try Data().write(to: wakeDirectory.appendingPathComponent("ignore.txt"))
    try Data().write(to: backgroundDirectory.appendingPathComponent("one.m4a"))
    try Data().write(to: backgroundDirectory.appendingPathComponent("two.WAV"))

    #expect(try WakeWordSampleDataset.classCounts(in: directory) == [
        "background": 2,
        "hey_cerberus": 1
    ])
}

@Test func wakeWordSampleDatasetClassCountsAllowsMissingDirectory() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)

    #expect(try WakeWordSampleDataset.classCounts(in: directory) == [:])
}

@Test func audioOutputDeviceDetectsAirPodsByName() {
    #expect(AudioOutputDevice(id: 1, name: "AirPods Pro").isLikelyAirPods)
    #expect(!AudioOutputDevice(id: 2, name: "MacBook Pro Speakers").isLikelyAirPods)
    #expect(AudioOutputDevice(id: 1, name: "AirPods Pro").displayName == "AirPods Pro (AirPods)")
}

@Test func audioOutputRouteMonitorUsesDefaultOutputSelector() {
    let address = AudioOutputRouteInspector.defaultOutputDeviceAddress()

    #expect(address.mSelector == kAudioHardwarePropertyDefaultOutputDevice)
    #expect(address.mScope == kAudioObjectPropertyScopeGlobal)
}

@Test func audioOutputRouteInspectorUsesDeviceAndOutputStreamSelectors() {
    let devicesAddress = AudioOutputRouteInspector.allDevicesAddress()
    let streamsAddress = AudioOutputRouteInspector.outputStreamsAddress()

    #expect(devicesAddress.mSelector == kAudioHardwarePropertyDevices)
    #expect(devicesAddress.mScope == kAudioObjectPropertyScopeGlobal)
    #expect(streamsAddress.mSelector == kAudioDevicePropertyStreams)
    #expect(streamsAddress.mScope == kAudioDevicePropertyScopeOutput)
}

@Test func screenOCRPayloadIncludesNormalizedAndPixelBoxes() {
    let payload = ScreenOCRTool.payload(
        for: [
            ScreenTextObservation(
                text: "OK",
                confidence: 0.93,
                boundingBox: CGRect(x: 0.25, y: 0.50, width: 0.50, height: 0.25)
            )
        ],
        imageSize: CGSize(width: 400, height: 200)
    )

    #expect(payload.contains("Image: 400x200"))
    #expect(payload.contains("normalizedBox: x=0.25 y=0.50 w=0.50 h=0.25"))
    #expect(payload.contains("pixelBox: x=100.00 y=50.00 w=200.00 h=50.00"))
}

@Test func screenSnapshotPayloadIncludesFileAndDimensions() {
    let fileURL = URL(fileURLWithPath: "/tmp/cerberus-screen.png")
    let payload = ScreenSnapshotTool.payload(
        fileURL: fileURL,
        imageSize: CGSize(width: 1440, height: 900)
    )

    #expect(payload.contains("Screen snapshot saved."))
    #expect(payload.contains("file: /tmp/cerberus-screen.png"))
    #expect(payload.contains("image: 1440x900"))
    #expect(payload.contains("screen.ocr"))
}

@Test func foundationModelAdapterConfigurationRequiresOneSource() throws {
    try FoundationModelAdapterConfiguration(name: "demo").validate()
    try FoundationModelAdapterConfiguration(filePath: "/tmp/demo.adapter").validate()

    #expect(throws: ToolExecutionError.self) {
        try FoundationModelAdapterConfiguration().validate()
    }
    #expect(throws: ToolExecutionError.self) {
        try FoundationModelAdapterConfiguration(name: "demo", filePath: "/tmp/demo.adapter").validate()
    }
}

@Test func adapterTrainingDatasetExporterWritesPromptResponseJSONL() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    let firstID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    let secondID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
    let thirdID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
    let records = [
        TranscriptRecord(
            id: firstID,
            timestamp: Date(timeIntervalSince1970: 1),
            request: " open calendar ",
            response: "Opened Calendar."
        ),
        TranscriptRecord(
            id: secondID,
            timestamp: Date(timeIntervalSince1970: 2),
            request: " ",
            response: "ignored"
        ),
        TranscriptRecord(
            id: thirdID,
            timestamp: Date(timeIntervalSince1970: 3),
            request: "what is next",
            response: "Standup at 9."
        )
    ]
    let exporter = AdapterTrainingDatasetExporter()
    let samples = exporter.samples(from: records)
    let split = try exporter.split(samples: samples, evalFraction: 0.5)

    try exporter.write(split, to: directory)

    let trainText = try String(contentsOf: directory.appendingPathComponent("train.jsonl"), encoding: .utf8)
    let evalText = try String(contentsOf: directory.appendingPathComponent("eval.jsonl"), encoding: .utf8)
    #expect(split.train.count == 1)
    #expect(split.eval.count == 1)
    #expect(trainText.contains(#""role":"user""#))
    #expect(trainText.contains(#""content":"open calendar""#))
    #expect(evalText.contains(#""content":"Standup at 9.""#))
}

@Test func adapterEvaluationParsesJSONLAndScoresNormalizedMatches() throws {
    let data = Data("""
    [{"role":"user","content":"open calendar"},{"role":"assistant","content":"Opened Calendar."}]
    [{"role":"user","content":"next event"},{"role":"assistant","content":"Standup at 9."}]
    """.utf8)

    let cases = try AdapterEvaluation.cases(fromJSONL: data)
    let first = try #require(cases.first)
    let second = try #require(cases.dropFirst().first)
    let results = [
        AdapterEvaluation.result(for: first, actualResponse: " Opened   Calendar. "),
        AdapterEvaluation.result(for: second, actualResponse: "No event.")
    ]
    let summary = AdapterEvaluation.score(results)

    #expect(cases.count == 2)
    #expect(first.prompt == "open calendar")
    #expect(results[0].matchesExpected)
    #expect(!results[1].matchesExpected)
    #expect(summary.total == 2)
    #expect(summary.matches == 1)
    #expect(summary.accuracy == 0.5)
}
