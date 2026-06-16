import Foundation
import CoreAudio
import CoreGraphics
import Testing
@testable import cerberusCore

@Test func appMetadataIsStable() {
    #expect(CerberusCore.appName == "cerberus")
    #expect(CerberusCore.bundleIdentifier == "dev.gongahkia.cerberus")
}

@Test func stateMachineFollowsHappyPath() {
    var machine = AssistantStateMachine()

    #expect(machine.handle(.wakeDetected(.manual))?.to == .listening)
    #expect(machine.handle(.silenceDetected)?.to == .reasoning)
    #expect(machine.handle(.responseReady("done"))?.to == .speaking)
    #expect(machine.handle(.speechFinished)?.to == .idle)
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
    #expect(text.contains("1970-01-01T00:00:00Z,0.123457,-0.250000,0.350000,0.450000,nod"))
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
