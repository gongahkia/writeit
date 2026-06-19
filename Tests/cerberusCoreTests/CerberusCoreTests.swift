import Foundation
import CoreAudio
import CoreGraphics
import Testing
@testable import cerberusCore

@Test func appMetadataIsStable() {
    #expect(CerberusCore.appName == "cerberus")
    #expect(CerberusCore.bundleIdentifier == "dev.gongahkia.cerberus")
}

@Test func appOwnedDefaultPathsStayInSupportOrCachesDirectories() {
    let supportPath = CerberusDirectories.applicationSupportDirectory().standardizedFileURL.path
    let cachesPath = CerberusDirectories.cachesDirectory().standardizedFileURL.path
    let supportFiles = [
        AuditLog.defaultFileURL(),
        EncryptedTranscriptStore.defaultFileURL(),
        EncryptedMemoryStore.defaultFileURL(),
        HeadGestureValidationLog.defaultFileURL(),
        MCPServerRegistry.defaultFileURL(),
        FoundationModelAdapterLoader.defaultFileURL(),
        WakeWordSoundClassifierConfigurationLoader.defaultFileURL()
    ]
    let supportDirectories = [
        AdapterTrainingDatasetExporter.defaultOutputDirectory(),
        WakeWordSampleDataset.defaultDirectoryURL()
    ]
    let cacheDirectories = [
        ScreenSnapshotTool.defaultOutputDirectoryURL()
    ]

    #expect(supportPath.hasSuffix("/Library/Application Support/cerberus"))
    #expect(cachesPath.hasSuffix("/Library/Caches/cerberus"))
    #expect(ScreenSnapshotTool.defaultOutputDirectoryURL().standardizedFileURL.path.hasSuffix("/Library/Caches/cerberus/screen-snapshots"))
    #expect((supportFiles + supportDirectories).allSatisfy { $0.standardizedFileURL.path.hasPrefix(supportPath + "/") })
    #expect(cacheDirectories.allSatisfy { $0.standardizedFileURL.path.hasPrefix(cachesPath + "/") })
}

@Test func settingsPersistenceKeysStayStableAndUnique() {
    #expect(CerberusSettingsKeys.persistedKeys == [
        "wakePhrase",
        "prefersSoundWakeWordClassifier",
        "routesSpeechDirectlyToAirPods",
        "onboardingSkipped",
        "requiresConfirmationForAllTools",
        "usesConfiguredAdapter",
        "hotKeyConfigurationID",
        "shellProposalMode"
    ])
    #expect(Set(CerberusSettingsKeys.persistedKeys).count == CerberusSettingsKeys.persistedKeys.count)
}

@Test func hotKeyConfigurationPresetsStayStable() {
    #expect(HotKeyConfiguration.controlOptionSpace.displayName == "Control Option Space")
    #expect(HotKeyConfiguration.preset(id: "control-shift-space").displayName == "Control Shift Space")
    #expect(HotKeyConfiguration.preset(id: "missing") == .controlOptionSpace)
    #expect(Set(HotKeyConfiguration.presets.map(\.id)).count == HotKeyConfiguration.presets.count)
}

@Test func wakeWordMonitorStatusLinesStayStable() {
    #expect(WakeWordMonitorStatusLine.speechTranscription == "Wake phrase uses speech transcription")
    #expect(WakeWordMonitorStatusLine.soundModelConfigured == "Sound wake model configured")
    #expect(WakeWordMonitorStatusLine.soundModelConfigMissing == "Sound wake model config missing")
    #expect(WakeWordMonitorStatusLine.soundModelConfigMissingUsingSpeechPhrase == "Sound wake model config not found; using speech phrase")
    #expect(WakeWordMonitorStatusLine.soundModelArmed == "Sound wake model armed")
    #expect(WakeWordMonitorStatusLine.soundMatched == "Sound wake matched")
    #expect(WakeWordMonitorStatusLine.soundMatched(identifier: "hey_cerberus", confidence: 0.873) == "Sound wake matched hey_cerberus 87%")
}

@Test func appInfoPlistDeclaresRequiredUsageDescriptions() throws {
    let plist = try loadPlist("Sources/cerberusApp/Resources/Info.plist")
    let usageDescriptionKeys = [
        "NSAppleEventsUsageDescription",
        "NSCalendarsUsageDescription",
        "NSCalendarsFullAccessUsageDescription",
        "NSMicrophoneUsageDescription",
        "NSRemindersUsageDescription",
        "NSRemindersFullAccessUsageDescription",
        "NSScreenCaptureUsageDescription",
        "NSSpeechRecognitionUsageDescription"
    ]

    for key in usageDescriptionKeys {
        let value = try #require(plist[key] as? String)
        #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

@Test func releaseEntitlementsCoverShippedToolPermissions() throws {
    let appEntitlements = try loadPlist("Config/cerberus.entitlements")
    let requiredAppEntitlements = [
        "com.apple.security.automation.apple-events",
        "com.apple.security.device.audio-input",
        "com.apple.security.network.client",
        "com.apple.security.personal-information.calendars",
        "com.apple.security.personal-information.reminders"
    ]

    for key in requiredAppEntitlements {
        #expect(appEntitlements[key] as? Bool == true)
    }

    let shellEntitlements = try loadPlist("Config/ShellExecService.entitlements")
    #expect(shellEntitlements["com.apple.security.app-sandbox"] as? Bool == true)
    #expect(shellEntitlements["com.apple.security.inherit"] as? Bool == false)
    #expect(shellEntitlements["com.apple.security.temporary-exception.files.absolute-path.read-only"] as? [String] == [
        "/bin/",
        "/usr/bin/",
        "/opt/homebrew/bin/"
    ])
}

@Test func shellXPCExecutorMatchesEmbeddedServiceIdentifier() throws {
    let xpcInfo = try loadPlist("Config/ShellExecService-Info.plist")

    #expect(xpcInfo["CFBundleIdentifier"] as? String == ShellXPCCommandExecutor().serviceName)
}

@Test func demoRecorderCheckModeAcceptsRenderedDemoPath() throws {
    let result = try runScript(
        "Scripts/record_demo.sh",
        arguments: ["--check"],
        environment: ["DEMO_CAPTURE_MODE": "rendered"]
    )

    #expect(result.exitCode == 0)
    #expect(result.output.contains("rendered demo ok"))
}

@Test func releaseScriptsExposeNonDestructivePreflightModes() throws {
    let checks = [
        ("Scripts/build_app.sh", ["--check"], "bundle layout ok:"),
        ("Scripts/release_check.sh", ["--help"], "usage: Scripts/release_check.sh"),
        ("Scripts/release_smoke.sh", ["--help"], "usage: Scripts/release_smoke.sh"),
        ("Scripts/package_release.sh", ["--help"], "usage: Scripts/package_release.sh"),
        ("Scripts/record_demo.sh", ["--check"], "rendered demo ok")
    ]

    for check in checks {
        let result = try runScript(
            check.0,
            arguments: check.1,
            environment: ["DEMO_CAPTURE_MODE": "rendered"]
        )
        #expect(result.exitCode == 0)
        #expect(result.output.contains(check.2))
    }
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

@Test func earconMapperDistinguishesSameDestinationTransitions() {
    let speechDone = AssistantTransition(from: .speaking, event: .speechFinished, to: .idle)
    let speechCancel = AssistantTransition(from: .speaking, event: .cancelRequested, to: .idle)
    let confirmAccepted = AssistantTransition(from: .awaitingConfirm, event: .confirmationAccepted, to: .executing)
    let executionStarted = AssistantTransition(from: .reasoning, event: .executionStarted("calendar.read"), to: .executing)
    let confirmDenied = AssistantTransition(from: .awaitingConfirm, event: .confirmationDenied, to: .idle)
    let responseReady = AssistantTransition(from: .reasoning, event: .responseReady("done"), to: .speaking)
    let executionFinished = AssistantTransition(from: .executing, event: .executionFinished("done"), to: .speaking)

    #expect(EarconMapper.earcon(for: speechDone) != EarconMapper.earcon(for: speechCancel))
    #expect(EarconMapper.earcon(for: confirmAccepted) != EarconMapper.earcon(for: executionStarted))
    #expect(EarconMapper.earcon(for: confirmDenied) != EarconMapper.earcon(for: speechCancel))
    #expect(EarconMapper.earcon(for: responseReady) == .speaking)
    #expect(EarconMapper.earcon(for: executionFinished) == .toolResult)
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

@Test func disabledAmbientToolsAreOmittedFromPlannerPrompt() {
    let summaries = [
        ToolSummary(name: "calendar.read", capability: "Read calendar.", mutatesState: false),
        ToolSummary(name: "web.search", capability: "Search web.", mutatesState: false)
    ]
    var allowlist = ToolSessionAllowlist()
    allowlist.setEnabled("web.search", enabled: false)

    let prompt = SystemPrompt.render(toolSummaries: allowlist.filter(summaries))

    #expect(prompt.contains("calendar.read"))
    #expect(!prompt.contains("web.search"))
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

@Test func longRunningTaskNotificationPolicyUsesDurationThreshold() {
    let policy = LongRunningTaskNotificationPolicy(minimumDuration: 30)
    let startedAt = Date(timeIntervalSince1970: 100)

    let shortRecord = LongRunningTaskRecord(
        id: "short",
        displayName: "shell.run",
        startedAt: startedAt,
        finishedAt: startedAt.addingTimeInterval(29),
        succeeded: true
    )
    let longRecord = LongRunningTaskRecord(
        id: "long",
        displayName: "shell.run",
        startedAt: startedAt,
        finishedAt: startedAt.addingTimeInterval(31),
        succeeded: true
    )

    #expect(policy.completionNotification(for: shortRecord) == nil)
    #expect(policy.completionNotification(for: longRecord) == LongRunningTaskNotification(
        identifier: "cerberus.long-running.long",
        title: "shell.run finished",
        body: "Completed after 31 seconds."
    ))
}

@Test func longRunningTaskNotificationPolicyReportsFailure() {
    let policy = LongRunningTaskNotificationPolicy(minimumDuration: 1)
    let startedAt = Date(timeIntervalSince1970: 100)
    let record = LongRunningTaskRecord(
        id: "failed",
        displayName: "mail.search",
        startedAt: startedAt,
        finishedAt: startedAt.addingTimeInterval(2),
        succeeded: false
    )

    #expect(policy.completionNotification(for: record)?.title == "mail.search failed")
}

@Test func localTelemetryStoreWritesJSONLRecords() async throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("telemetry.jsonl")
    let store = LocalTelemetryStore(fileURL: fileURL)
    let record = LocalTelemetryRecord(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        timestamp: Date(timeIntervalSince1970: 1_000),
        category: .toolExecution,
        name: "shell.run",
        durationSeconds: 1.25,
        succeeded: true,
        qualitySignal: "success",
        modelProfile: "default"
    )

    try await store.append(record)

    #expect(try await store.records() == [record])
    let text = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(text.contains(#""category":"tool_execution""#))
    #expect(!text.contains("request"))
    #expect(!text.contains("arguments"))
}

@Test func toolOutputSummarizationFallbackUsesSpokenSummaryWhenSummarizerFails() async {
    let result = ToolResult(
        toolName: "files.search",
        succeeded: true,
        spokenSummary: "Found 2 matching files.",
        untrustedPayload: "large payload"
    )

    let response = await ToolOutputSummarizationFallback.spokenResponse(for: result, request: "find files") { _, _ in
        throw ToolExecutionError.denied("model unavailable")
    }

    #expect(response == "Found 2 matching files.")
}

@Test func adapterFailureCircuitBreakerDisablesOnlyAfterAdapterFailures() {
    var breaker = AdapterFailureCircuitBreaker(threshold: 2)

    let defaultFailureTripped = breaker.recordFailure(modelProfile: "default")
    #expect(!defaultFailureTripped)
    #expect(breaker.consecutiveFailures == 0)
    let firstAdapterFailureTripped = breaker.recordFailure(modelProfile: "adapter:demo")
    #expect(!firstAdapterFailureTripped)
    #expect(breaker.consecutiveFailures == 1)
    breaker.recordSuccess()
    #expect(breaker.consecutiveFailures == 0)
    let adapterFailureAfterSuccessTripped = breaker.recordFailure(modelProfile: "adapter:demo")
    let secondAdapterFailureTripped = breaker.recordFailure(modelProfile: "adapter:demo")
    #expect(!adapterFailureAfterSuccessTripped)
    #expect(secondAdapterFailureTripped)
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

@Test func wakeWordSampleQualityReportFlagsWeakDataset() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let wakeDirectory = directory.appendingPathComponent("hey_cerberus", isDirectory: true)
    let backgroundDirectory = directory.appendingPathComponent("background", isDirectory: true)
    try FileManager.default.createDirectory(at: wakeDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: backgroundDirectory, withIntermediateDirectories: true)
    try Data().write(to: wakeDirectory.appendingPathComponent("wake.wav"))
    try Data().write(to: backgroundDirectory.appendingPathComponent("background.wav"))
    try WakeWordSampleDataset.write(
        record: WakeWordSampleRecord(
            label: "hey_cerberus",
            relativePath: "hey_cerberus/wake.wav",
            durationSeconds: 0.2,
            createdAt: Date(timeIntervalSince1970: 0)
        ),
        to: directory
    )

    let report = try WakeWordSampleQualityReporter.report(in: directory, targetLabel: "hey_cerberus")
    let rendered = WakeWordSampleQualityReporter.render(report)

    #expect(report.classCounts == ["background": 1, "hey_cerberus": 1])
    #expect(report.missingManifestRecordCount == 1)
    #expect(report.shortSampleCount == 1)
    #expect(rendered.contains("sample quality:"))
    #expect(rendered.contains("background has only 1 sample(s)"))
}

@Test func audioOutputDeviceDetectsAirPodsByName() {
    #expect(AudioOutputDevice(id: 1, name: "AirPods Pro").isLikelyAirPods)
    #expect(!AudioOutputDevice(id: 2, name: "MacBook Pro Speakers").isLikelyAirPods)
    #expect(AudioOutputDevice(id: 1, name: "AirPods Pro").displayName == "AirPods Pro (AirPods)")
}

@Test func audioOutputRouteSelectsPreferredAirPodsFromFakeDevices() {
    let devices = [
        AudioOutputDevice(id: 1, name: "Studio Display Speakers"),
        AudioOutputDevice(id: 2, name: "AirPods Max"),
        AudioOutputDevice(id: 3, name: "AirPods Pro")
    ]

    #expect(AudioOutputRouteInspector.preferredAirPodsOutputDevice(in: devices) == devices[1])
    #expect(AudioOutputRouteInspector.preferredAirPodsOutputDevice(in: [devices[0]]) == nil)
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

    #expect(payload.contains("image: 400x200"))
    #expect(payload.contains("scope: main_display"))
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
    #expect(payload.contains("scope: main_display"))
    #expect(payload.contains("image: 1440x900"))
    #expect(payload.contains("screen.ocr"))
}

@Test func screenCaptureScopeParsesActiveWindow() throws {
    #expect(try ScreenCaptureScope.parse(nil) == .mainDisplay)
    #expect(try ScreenCaptureScope.parse("active_window") == .activeWindow)
    #expect(throws: ToolExecutionError.self) {
        try ScreenCaptureScope.parse("everything")
    }
}

@Test func screenSnapshotWriteCreatesOutputDirectory() throws {
    let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let directory = rootDirectory.appendingPathComponent("Library/Caches/cerberus/screen-snapshots", isDirectory: true)
    let fileURL = directory.appendingPathComponent("screen-test.png")
    defer { try? FileManager.default.removeItem(at: rootDirectory) }

    try ScreenCaptureSupport.writePNG(makeTestImage(), to: fileURL)

    #expect(FileManager.default.fileExists(atPath: directory.path))
    #expect(FileManager.default.fileExists(atPath: fileURL.path))
    #expect(fileURL.path.hasSuffix("/Library/Caches/cerberus/screen-snapshots/screen-test.png"))
}

@Test func screenSnapshotCacheCleanupPrunesOldSnapshotsAndKeepsUnrelatedFiles() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let now = Date(timeIntervalSince1970: 2_000)
    let oldSnapshot = directory.appendingPathComponent("screen-1-old.png")
    let newSnapshot = directory.appendingPathComponent("screen-2-new.png")
    let preservedSnapshot = directory.appendingPathComponent("screen-3-preserved.png")
    let unrelated = directory.appendingPathComponent("notes.txt")
    for fileURL in [oldSnapshot, newSnapshot, preservedSnapshot, unrelated] {
        try Data(fileURL.lastPathComponent.utf8).write(to: fileURL)
    }
    try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-200)], ofItemAtPath: oldSnapshot.path)
    try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-10)], ofItemAtPath: newSnapshot.path)
    try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-500)], ofItemAtPath: preservedSnapshot.path)

    let policy = ScreenSnapshotCachePolicy(maximumFileCount: 2, maximumAge: 60) { now }
    try ScreenSnapshotCache.cleanDirectory(directory, preserving: preservedSnapshot, policy: policy)

    #expect(!FileManager.default.fileExists(atPath: oldSnapshot.path))
    #expect(FileManager.default.fileExists(atPath: newSnapshot.path))
    #expect(FileManager.default.fileExists(atPath: preservedSnapshot.path))
    #expect(FileManager.default.fileExists(atPath: unrelated.path))
}

@Test func screenSnapshotCacheCleanupLimitsSnapshotCount() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let now = Date(timeIntervalSince1970: 2_000)
    let newest = directory.appendingPathComponent("screen-3-newest.png")
    let middle = directory.appendingPathComponent("screen-2-middle.png")
    let oldest = directory.appendingPathComponent("screen-1-oldest.png")
    for fileURL in [newest, middle, oldest] {
        try Data(fileURL.lastPathComponent.utf8).write(to: fileURL)
    }
    try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-1)], ofItemAtPath: newest.path)
    try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-2)], ofItemAtPath: middle.path)
    try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-3)], ofItemAtPath: oldest.path)

    let policy = ScreenSnapshotCachePolicy(maximumFileCount: 2, maximumAge: 60) { now }
    try ScreenSnapshotCache.cleanDirectory(directory, preserving: newest, policy: policy)

    #expect(FileManager.default.fileExists(atPath: newest.path))
    #expect(FileManager.default.fileExists(atPath: middle.path))
    #expect(!FileManager.default.fileExists(atPath: oldest.path))
}

@Test func screenSnapshotCacheReportsLatestAndDeletesSnapshotsOnly() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let now = Date(timeIntervalSince1970: 2_000)
    let newest = directory.appendingPathComponent("screen-2-newest.png")
    let oldest = directory.appendingPathComponent("screen-1-oldest.png")
    let unrelated = directory.appendingPathComponent("screen-note.txt")
    for fileURL in [newest, oldest, unrelated] {
        try Data(fileURL.lastPathComponent.utf8).write(to: fileURL)
    }
    try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: newest.path)
    try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-10)], ofItemAtPath: oldest.path)

    #expect(ScreenSnapshotCache.snapshotCount(in: directory) == 2)
    #expect(ScreenSnapshotCache.latestSnapshotURL(in: directory)?.standardizedFileURL.path == newest.standardizedFileURL.path)
    #expect(try ScreenSnapshotCache.deleteSnapshots(in: directory) == 2)
    #expect(!FileManager.default.fileExists(atPath: newest.path))
    #expect(!FileManager.default.fileExists(atPath: oldest.path))
    #expect(FileManager.default.fileExists(atPath: unrelated.path))
}

private func makeTestImage() throws -> CGImage {
    let bytes = Data([255, 255, 255, 255])
    guard let provider = CGDataProvider(data: bytes as CFData),
          let image = CGImage(
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    ) else {
        throw ToolExecutionError.denied("Could not create test image.")
    }
    return image
}

private func loadPlist(_ relativePath: String) throws -> [String: Any] {
    let fileURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(relativePath)
    let data = try Data(contentsOf: fileURL)
    return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
}

private func runScript(
    _ relativePath: String,
    arguments: [String] = [],
    environment: [String: String] = [:]
) throws -> (exitCode: Int32, output: String) {
    let process = Process()
    process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [relativePath] + arguments
    process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()

    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return (process.terminationStatus, output)
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

@Test func foundationModelAvailabilityStatusFormatsUnavailableReasons() {
    let disabled = FoundationModelAvailabilityStatusProvider {
        .unavailable(.appleIntelligenceNotEnabled)
    }
    let pendingDownload = FoundationModelAvailabilityStatusProvider {
        .unavailable(.modelNotReady)
    }
    let ineligible = FoundationModelAvailabilityStatusProvider {
        .unavailable(.deviceNotEligible)
    }

    #expect(!disabled.isAvailable())
    #expect(disabled.statusLine() == "Foundation Models unavailable: Apple Intelligence not enabled")
    #expect(disabled.fallbackText() == "Apple Intelligence is not enabled. Turn it on in System Settings to use model planning.")
    #expect(pendingDownload.fallbackText() == "The local model is not ready yet. Finish the Apple Intelligence model download, then try again.")
    #expect(ineligible.fallbackText() == "Foundation Models are unavailable on this Mac.")
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
            response: "Opened Calendar.",
            toolName: "app.control"
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
            response: "Standup at 9.",
            toolName: "calendar.read"
        )
    ]
    let exporter = AdapterTrainingDatasetExporter()
    let samples = exporter.samples(from: records)
    let statistics = exporter.statistics(from: records)
    let split = try exporter.split(samples: samples, evalFraction: 0.5)

    try exporter.write(split, to: directory)
    try exporter.writeStatistics(statistics, to: directory)

    let trainText = try String(contentsOf: directory.appendingPathComponent("train.jsonl"), encoding: .utf8)
    let evalText = try String(contentsOf: directory.appendingPathComponent("eval.jsonl"), encoding: .utf8)
    let statsData = try Data(contentsOf: directory.appendingPathComponent("stats.json"))
    let decodedStats = try JSONDecoder().decode(AdapterTrainingDatasetStatistics.self, from: statsData)
    #expect(split.train.count == 1)
    #expect(split.eval.count == 1)
    #expect(trainText.contains(#""role":"user""#))
    #expect(trainText.contains(#""content":"open calendar""#))
    #expect(evalText.contains(#""content":"Standup at 9.""#))
    #expect(decodedStats.totalSamples == 2)
    #expect(decodedStats.taskCategories == ["app": 1, "calendar": 1])
    #expect(decodedStats.tools == ["app.control": 1, "calendar.read": 1])
    #expect(decodedStats.responseWords.maximum == 3)
}

@Test func adapterTrainingDatasetExporterRedactsPrivateValues() throws {
    let records = [
        TranscriptRecord(
            request: "email me@example.com and read /Users/alice/Secret.txt",
            response: "Bearer abcdefghijklmnopqrstuvwxyz123456 token 0123456789abcdef0123456789abcdef"
        )
    ]
    let samples = AdapterTrainingDatasetExporter().samples(
        from: records,
        redactsPrivateData: true
    )
    let messages = try #require(samples.first?.messages)
    let text = messages.map(\.content).joined(separator: "\n")

    #expect(text.contains("[email]"))
    #expect(text.contains("/Users/[user]/Secret.txt"))
    #expect(text.contains("Bearer [token]"))
    #expect(text.contains("[hex-token]"))
    #expect(!text.contains("me@example.com"))
    #expect(!text.contains("/Users/alice"))
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
    #expect(summary.averageResponseTokenF1 > 0.25)
}

@Test func adapterEvaluationScoresToolSelectionAndTokenOverlap() {
    let toolCase = AdapterEvaluationCase(
        prompt: "open calendar",
        expectedResponse: #"{"intent":"callTool","toolName":"app.control","spokenResponse":"Opening Calendar."}"#
    )
    let directCase = AdapterEvaluationCase(
        prompt: "summarize",
        expectedResponse: "Opened Calendar and showed today's meetings."
    )
    let results = [
        AdapterEvaluation.result(
            for: toolCase,
            actualResponse: #"{"intent":"callTool","toolName":"calendar.read","spokenResponse":"Opening Calendar."}"#
        ),
        AdapterEvaluation.result(
            for: directCase,
            actualResponse: "Calendar opened and meetings are visible."
        )
    ]
    let summary = AdapterEvaluation.score(results)

    #expect(results[0].expectedToolName == "app.control")
    #expect(results[0].actualToolName == "calendar.read")
    #expect(results[0].toolNameMatches == false)
    #expect(results[1].toolNameMatches == nil)
    #expect(results[1].responseTokenF1 > 0)
    #expect(summary.toolSelectionTotal == 1)
    #expect(summary.toolSelectionMatches == 0)
    #expect(summary.toolSelectionAccuracy == 0)
}
