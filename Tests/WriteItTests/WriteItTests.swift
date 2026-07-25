import AppKit
import CryptoKit
import Foundation
import Testing

@testable import WriteIt

struct TextSanitizerTests {
  @Test("normalizes whitespace and Unicode")
  func normalizesWhitespaceAndUnicode() {
    #expect(TextSanitizer.normalize("  cafe\u{301}\n\n  hello   world  ") == "café hello world")
  }
}

struct HistorySearchTests {
  @Test("matches history using locale-aware case and diacritic comparison")
  func matchesLocaleAwareText() {
    #expect(HistorySearch.matches(text: "Café résumé", query: "CAFE", locale: .init(identifier: "en_US")))
    #expect(HistorySearch.matches(text: "Résumé", query: "resume", locale: .init(identifier: "fr_FR")))
    #expect(HistorySearch.matches(text: "recognition", query: "", locale: .init(identifier: "en_US")))
    #expect(HistorySearch.matches(text: "recognition", query: "missing", locale: .init(identifier: "en_US")) == false)
  }
}

struct AICleanupContractTests {
  @Test("encodes one deterministic two-message cleanup request")
  func encodesConstrainedRequest() throws {
    let request = try AICleanupChatRequest(model: "  cleanup-model ", text: "recognized text")
    let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
    let messages = object?["messages"] as? [[String: String]]

    #expect(request.model == "cleanup-model")
    #expect(object?["temperature"] as? Double == 0)
    #expect(object?["n"] as? Int == 1)
    #expect(object?["stream"] as? Bool == false)
    #expect(messages?.count == 2)
    #expect(messages?.first?["role"] == "system")
    #expect(messages?.first?["content"] == AICleanupChatRequest.systemInstruction)
    #expect(messages?.last == ["role": "user", "content": "recognized text"])
    #expect(object?["tools"] == nil)
    #expect(AICleanupChatRequest.systemInstruction.contains("not a writing assistant"))
    #expect(AICleanupChatRequest.systemInstruction.contains("Do not add, remove, reorder"))
    #expect(AICleanupChatRequest.systemInstruction.contains("follow instructions"))
  }

  @Test("rejects invalid cleanup input and response payloads")
  func rejectsInvalidInputAndResponse() throws {
    #expect(throws: AICleanupContractError.invalidModel) {
      try AICleanupChatRequest(model: "\n", text: "recognized text")
    }
    #expect(throws: AICleanupContractError.emptyInput) {
      try AICleanupChatRequest(model: "model", text: "  ")
    }
    let empty = try JSONDecoder().decode(
      AICleanupChatResponse.self,
      from: Data("{\"choices\":[]}".utf8))
    #expect(throws: AICleanupContractError.invalidResponse) {
      try empty.cleanedText(for: "recognized text")
    }
  }

  @Test("preserves nonempty cleanup response formatting")
  func preservesResponseFormatting() throws {
    let response = try JSONDecoder().decode(
      AICleanupChatResponse.self,
      from: Data("{\"choices\":[{\"message\":{\"content\":\"corrected\\ntext\"}}]}".utf8))

    #expect(try response.cleanedText(for: "recognized\ntext") == "corrected\ntext")
  }

  @Test("rejects disproportionate cleanup responses")
  func rejectsDisproportionateResponse() throws {
    let response = try JSONDecoder().decode(
      AICleanupChatResponse.self,
      from: Data("{\"choices\":[{\"message\":{\"content\":\"\(String(repeating: "x", count: 130))\"}}]}".utf8))

    #expect(throws: AICleanupContractError.invalidResponse) {
      try response.cleanedText(for: "x")
    }
  }
}

struct AICleanupCapabilityDiscoveryTests {
  @Test("derives a models probe without forwarding chat query data")
  func derivesModelsURL() {
    let url = AICleanupCapabilityDiscovery.modelsURL(
      for: "https://api.example.test/v1/chat/completions?ignored=true")

    #expect(url?.absoluteString == "https://api.example.test/v1/models")
    #expect(AICleanupCapabilityDiscovery.modelsURL(for: "https://api.example.test/v1/models") == nil)
  }

  @Test("reports discovered models and configured model availability")
  func discoversModels() async {
    let requester = TestAICleanupRequester(
      response: AICleanupHTTPResponse(
        data: Data("{\"data\":[{\"id\":\"other\"},{\"id\":\"cleanup\"}]}".utf8),
        statusCode: 200
      ))
    let status = await AICleanupCapabilityDiscovery(requester: requester).discover(
      endpoint: "https://api.example.test/v1/chat/completions",
      apiKey: "key",
      model: "cleanup"
    )

    #expect(status == .ready(models: ["cleanup", "other"], selectedModelAvailable: true))
    let request = await requester.requests.first
    #expect(request?.httpMethod == "GET")
    #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer key")
    #expect(request?.url?.path == "/v1/models")
    #expect(request?.httpBody == nil)
  }

  @Test("classifies rejected credentials and invalid configuration")
  func classifiesFailures() async {
    let rejected = TestAICleanupRequester(
      response: AICleanupHTTPResponse(data: Data(), statusCode: 401))
    let discovery = AICleanupCapabilityDiscovery(requester: rejected)

    #expect(await discovery.discover(
      endpoint: "https://api.example.test/v1/chat/completions", apiKey: "key", model: "cleanup")
      == .invalidCredentials)
    #expect(await discovery.discover(
      endpoint: "not a url", apiKey: "key", model: "cleanup") == .notConfigured)
  }
}

struct AICleanupTransportPolicyTests {
  @Test("retries only transient cleanup responses")
  func retriesTransientResponses() {
    #expect(AICleanupTransportPolicy.timeoutInterval == 30)
    #expect(AICleanupTransportPolicy.maximumAttempts == 2)
    #expect(AICleanupTransportPolicy.shouldRetry(statusCode: 408))
    #expect(AICleanupTransportPolicy.shouldRetry(statusCode: 429))
    #expect(AICleanupTransportPolicy.shouldRetry(statusCode: 503))
    #expect(AICleanupTransportPolicy.shouldRetry(statusCode: 400) == false)
    #expect(AICleanupTransportPolicy.shouldRetry(statusCode: 401) == false)
  }

  @Test("retries only transient cleanup transport errors")
  func retriesTransientErrors() {
    #expect(AICleanupTransportPolicy.shouldRetry(error: URLError(.timedOut)))
    #expect(AICleanupTransportPolicy.shouldRetry(error: URLError(.networkConnectionLost)))
    #expect(AICleanupTransportPolicy.shouldRetry(error: URLError(.badServerResponse)) == false)
  }
}

struct CustomOCRProviderCredentialStoreTests {
  @Test("stores bearer tokens under provider-specific Keychain accounts") @MainActor
  func storesDistinctBearerTokens() throws {
    let credentials = TestCustomOCRProviderCredentialStore()
    let store = CustomOCRProviderCredentialStore(credentials: credentials)
    let first = try customProvider(id: "custom.first", authentication: .bearerToken)
    let second = try customProvider(id: "custom.second", authentication: .bearerToken)

    try store.saveBearerToken(" first-token ", for: first)
    try store.saveBearerToken("second-token", for: second)

    #expect(try store.bearerToken(for: first) == "first-token")
    #expect(try store.bearerToken(for: second) == "second-token")
    #expect(store.account(for: first) != store.account(for: second))
  }

  @Test("replacing or removing a provider deletes obsolete bearer tokens") @MainActor
  func invalidatesObsoleteTokens() throws {
    let credentials = TestCustomOCRProviderCredentialStore()
    let store = CustomOCRProviderCredentialStore(credentials: credentials)
    let bearer = try customProvider(id: "custom.provider", authentication: .bearerToken)
    let noAuthentication = try customProvider(id: "custom.provider", authentication: .none)

    try store.saveBearerToken("token", for: bearer)
    try store.replace(noAuthentication, previous: bearer)
    #expect(try store.bearerToken(for: bearer) == nil)
    try store.saveBearerToken("token", for: bearer)
    try store.remove(bearer)
    #expect(try store.bearerToken(for: bearer) == nil)
  }

  @Test("rejects tokens for unauthenticated providers") @MainActor
  func rejectsUnauthenticatedProviderTokens() throws {
    let store = CustomOCRProviderCredentialStore(credentials: TestCustomOCRProviderCredentialStore())
    let configuration = try customProvider(id: "custom.none", authentication: .none)

    #expect(throws: CustomOCRProviderCredentialError.authenticationNotRequired) {
      try store.saveBearerToken("token", for: configuration)
    }
  }

  private func customProvider(
    id: String,
    authentication: CustomOCRProviderAuthentication
  ) throws -> CustomOCRProviderConfiguration {
    try CustomOCRProviderConfiguration(
      id: id,
      displayName: "Custom Provider",
      endpoint: URL(string: "https://provider.example.test/ocr")!,
      authentication: authentication,
      supportedLanguages: [.english]
    ).validated()
  }
}

struct LiteralReplacementRuleTests {
  @Test("applies literal replacements sequentially in stored order")
  func appliesRulesInOrder() throws {
    let rules = LiteralReplacementRules(rules: [
      try LiteralReplacementRule(find: "teh", replacement: "the"),
      try LiteralReplacementRule(find: "the cloud", replacement: "WriteIt"),
    ])
    #expect(rules.applying(to: "teh cloud") == "WriteIt")
  }

  @Test("permits literal deletion and rejects an empty find value")
  func validatesRules() throws {
    let deletion = try LiteralReplacementRule(find: "-draft", replacement: "")
    #expect(deletion.applying(to: "writeit-draft") == "writeit")
    #expect(throws: LiteralReplacementRuleError.emptyFindText) {
      try LiteralReplacementRule(find: "", replacement: "replacement")
    }
  }
}

struct RegexReplacementRuleTests {
  @Test("applies regular-expression replacements sequentially")
  func appliesRulesInOrder() throws {
    let rules = try RegexReplacementRules(rules: [
      try RegexReplacementRule(pattern: "teh", replacement: "the"),
      try RegexReplacementRule(pattern: "the (cloud)", replacement: "WriteIt $1"),
    ])
    #expect(try RegexReplacementWorker.apply(rules, to: "teh cloud") == "WriteIt cloud")
  }

  @Test("rejects invalid, empty, and oversized regular-expression rules")
  func validatesRules() throws {
    #expect(throws: RegexReplacementRuleError.emptyPattern) {
      try RegexReplacementRule(pattern: "", replacement: "replacement")
    }
    #expect(throws: RegexReplacementRuleError.invalidPattern) {
      try RegexReplacementRule(pattern: "(", replacement: "replacement")
    }
    #expect(throws: RegexReplacementRuleError.patternTooLong) {
      try RegexReplacementRule(
        pattern: String(repeating: "a", count: RegexReplacementRule.maximumPatternLength + 1),
        replacement: "replacement")
    }
  }

  @Test("service propagates a worker timeout") @MainActor
  func propagatesTimeout() async throws {
    let runner = TestRegexReplacementWorkerRunner(failure: .timedOut)
    let service = RegexReplacementService(runner: runner)
    let rules = try RegexReplacementRules(rules: [
      try RegexReplacementRule(pattern: "x", replacement: "y"),
    ])
    await #expect(throws: RegexReplacementExecutionError.timedOut) {
      try await service.apply(rules, to: "x")
    }
  }

  @Test("process worker terminates at the execution deadline") @MainActor
  func processWorkerTerminatesAtDeadline() async {
    let runner = ProcessRegexReplacementWorkerRunner(
      executableURL: URL(fileURLWithPath: "/bin/sh"),
      arguments: ["-c", "exec sleep 10"]
    )
    await #expect(throws: RegexReplacementExecutionError.timedOut) {
      try await runner.run(input: Data(), timeout: .milliseconds(50))
    }
  }
}

struct ReplacementPreviewModelTests {
  @Test("preview applies literal rules before regular-expression rules") @MainActor
  func appliesRulesInCaptureOrder() async throws {
    let regexReplacer = TestRegexReplacer()
    let preview = ReplacementPreviewModel(regexReplacer: regexReplacer)
    preview.updateRules(
      literal: LiteralReplacementRules(rules: [
        try LiteralReplacementRule(find: "teh", replacement: "the"),
      ]),
      regex: try RegexReplacementRules(rules: [
        try RegexReplacementRule(pattern: "the (cloud)", replacement: "WriteIt $1"),
      ])
    )
    preview.sampleText = "teh cloud"
    for _ in 0..<8 { await Task.yield() }

    #expect(preview.previewText == "WriteIt cloud")
    #expect(preview.errorMessage == nil)
  }

  @Test("preview reports bounded regex failures") @MainActor
  func reportsRegexFailure() async throws {
    let regexReplacer = TestRegexReplacer()
    regexReplacer.failure = .timedOut
    let preview = ReplacementPreviewModel(regexReplacer: regexReplacer)
    preview.updateRules(
      literal: LiteralReplacementRules(),
      regex: try RegexReplacementRules(rules: [
        try RegexReplacementRule(pattern: "text", replacement: "result"),
      ])
    )
    preview.sampleText = "sample text"
    for _ in 0..<8 { await Task.yield() }

    #expect(preview.previewText == "sample text")
    #expect(preview.errorMessage == "Regular-expression processing exceeded the time limit.")
  }
}

struct ReplacementRuleArchiveTests {
  @Test("round trips ordered literal and regex replacement rules")
  func roundTripsRules() throws {
    let archive = ReplacementRuleArchive(
      literalRules: LiteralReplacementRules(rules: [
        try LiteralReplacementRule(find: "teh", replacement: "the"),
      ]),
      regexRules: try RegexReplacementRules(rules: [
        try RegexReplacementRule(pattern: "the (cloud)", replacement: "WriteIt $1"),
      ])
    )
    let decoded = try ReplacementRuleArchiveCodec.decode(
      ReplacementRuleArchiveCodec.encode(archive))

    #expect(decoded == archive)
    #expect(decoded.literalRules.applying(to: "teh cloud") == "the cloud")
    #expect(try RegexReplacementWorker.apply(decoded.regexRules, to: "the cloud") == "WriteIt cloud")
  }

  @Test("rejects unsupported and invalid replacement-rule archives")
  func rejectsInvalidArchives() throws {
    let unsupported = Data("""
    {"schemaVersion":2,"literalRules":{"rules":[]},"regexRules":{"rules":[]}}
    """.utf8)
    let invalid = Data("""
    {"schemaVersion":1,"literalRules":{"rules":[{"id":"2A45F2F0-6D01-4E1B-9D85-7D5D2D4AA1C6","find":"","replacement":"x"}]},"regexRules":{"rules":[]}}
    """.utf8)

    #expect(throws: ReplacementRuleArchiveError.unsupportedVersion) {
      try ReplacementRuleArchiveCodec.decode(unsupported)
    }
    #expect(throws: ReplacementRuleArchiveError.invalidArchive) {
      try ReplacementRuleArchiveCodec.decode(invalid)
    }
  }

  @Test("import validates before replacing persisted rules")
  func importIsAtomic() throws {
    let defaults = makeDefaults()
    let preferences = Preferences(defaults: defaults)
    preferences.literalReplacementRules = LiteralReplacementRules(rules: [
      try LiteralReplacementRule(find: "old", replacement: "kept"),
    ])
    let invalid = Data("""
    {"schemaVersion":1,"literalRules":{"rules":[]},"regexRules":{"rules":[{"id":"2A45F2F0-6D01-4E1B-9D85-7D5D2D4AA1C6","pattern":"(","replacement":"x"}]}}
    """.utf8)

    #expect(throws: ReplacementRuleArchiveError.invalidArchive) {
      try preferences.importReplacementRules(from: invalid)
    }
    #expect(preferences.literalReplacementRules.applying(to: "old") == "kept")
    #expect(preferences.regexReplacementRules.rules.isEmpty)
  }

  @Test("file archive store writes and reads the exact exported data")
  func readsAndWritesArchiveData() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("writeit-rules-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let data = Data("replacement rules".utf8)

    try ReplacementRuleArchiveFileStore.write(data, to: url)
    #expect(try ReplacementRuleArchiveFileStore.read(from: url) == data)
  }
}

struct ConfigurationArchiveTests {
  @Test("exports complete configuration without captured or credential data") @MainActor
  func exportsConfigurationOnly() throws {
    let defaults = makeDefaults()
    let preferences = Preferences(defaults: defaults)
    preferences.captureMode = .penUpDelay
    preferences.recognitionLanguage = .french
    preferences.customWords = CustomWordList(words: ["WriteIt", "Café"])
    preferences.historyMode = .full
    preferences.aiEnabled = true
    preferences.aiBaseURL = "https://cleanup.example.test/v1/chat/completions"
    preferences.aiModel = "cleanup-model"
    try preferences.addLiteralReplacementRule(find: "teh", replacement: "the")
    try preferences.addRegexReplacementRule(pattern: "(WriteIt)", replacement: "$1 app")
    let profile = try AppProfile(
      bundleIdentifier: "com.example.editor",
      overrides: .init(
        recognitionLanguage: .spanish,
        aiCleanupConsent: AICleanupConsent(),
        customWords: CustomWordList(words: ["EditorWord"]),
        cloudOCRConsent: CloudOCRConsent()
      )
    )
    let profiles = AppProfileStore(defaults: defaults)
    try profiles.replaceProfiles([profile])
    let credentials = TestCloudOCRCredentialStore()
    let cloudProviders = CloudOCRProviderStore(defaults: defaults, credentials: credentials)
    try cloudProviders.configureAzure(
      endpoint: "https://writeit.cognitiveservices.azure.com", apiKey: "cloud-secret")

    let archive = ConfigurationArchive(
      preferences: preferences,
      profiles: profiles.profiles,
      cloudOCRProviders: cloudProviders.configurations
    )
    let data = try ConfigurationArchiveCodec.encode(archive)
    let decoded = try JSONDecoder().decode(ConfigurationArchive.self, from: data)
    let text = String(decoding: data, as: UTF8.self)

    #expect(decoded == archive)
    #expect(decoded.preferences.customWords.words == ["WriteIt", "Café"])
    #expect(decoded.profiles.first?.overrides.aiCleanupConsent?.allowsAICleanup == true)
    #expect(decoded.cloudOCRProviders == [
      ConfigurationCloudOCRProvider(configuration: cloudProviders.configurations[0]),
    ])
    #expect(text.contains("cloud-secret") == false)
    #expect(text.contains("ai-api-key") == false)
    #expect(text.contains("history.sealed") == false)
    #expect(text.contains("diagnostic") == false)
    #expect(text.contains("isValidated") == false)
  }

  @Test("rejects unsupported configuration schema versions")
  func rejectsUnsupportedVersion() {
    let data = Data("{\"schema_version\":2}".utf8)

    #expect(throws: ConfigurationArchiveError.unsupportedVersion) {
      try JSONDecoder().decode(ConfigurationArchive.self, from: data)
    }
  }

  @Test("imports a validated configuration without importing provider credentials") @MainActor
  func importsValidatedConfiguration() throws {
    let sourceDefaults = makeDefaults()
    let sourcePreferences = Preferences(defaults: sourceDefaults)
    sourcePreferences.captureMode = .penUpDelay
    sourcePreferences.customWords = CustomWordList(words: ["SourceWord"])
    let sourceProfiles = AppProfileStore(defaults: sourceDefaults)
    try sourceProfiles.replaceProfiles([
      AppProfile(bundleIdentifier: "com.example.source", overrides: .init(aiCleanupConsent: .init())),
    ])
    let sourceCredentials = TestCloudOCRCredentialStore()
    let sourceProviders = CloudOCRProviderStore(defaults: sourceDefaults, credentials: sourceCredentials)
    try sourceProviders.configureAzure(
      endpoint: "https://source.cognitiveservices.azure.com", apiKey: "source-secret")
    let archive = ConfigurationArchive(
      preferences: sourcePreferences,
      profiles: sourceProfiles.profiles,
      cloudOCRProviders: sourceProviders.configurations
    )

    let destinationDefaults = makeDefaults()
    let destinationPreferences = Preferences(defaults: destinationDefaults)
    destinationPreferences.captureMode = .holdToCapture
    let destinationProfiles = AppProfileStore(defaults: destinationDefaults)
    let destinationCredentials = TestCloudOCRCredentialStore()
    let destinationProviders = CloudOCRProviderStore(
      defaults: destinationDefaults, credentials: destinationCredentials)
    let state = ConfigurationStateStore(
      preferences: destinationPreferences,
      profiles: destinationProfiles,
      cloudProviders: destinationProviders
    )

    try state.apply(archive)

    #expect(destinationPreferences.captureMode == .penUpDelay)
    #expect(destinationPreferences.customWords.words == ["SourceWord"])
    #expect(destinationProfiles.profiles == sourceProfiles.profiles)
    #expect(destinationProviders.configurations.first?.endpoint?.host == "source.cognitiveservices.azure.com")
    #expect(destinationProviders.configurations.first?.isValidated == false)
    #expect(try destinationCredentials.data(for: CloudOCRProvider.azureVision.credentialAccount) == nil)
  }

  @Test("rolls back a partially applied configuration") @MainActor
  func rollsBackFailedImport() throws {
    let original = configurationArchive(captureMode: .toggle)
    let imported = configurationArchive(captureMode: .holdToCapture)
    let state = TestConfigurationState(current: original, failingArchive: imported)
    let controller = ConfigurationImportController(state: state)

    controller.preview(try ConfigurationArchiveCodec.encode(imported))
    controller.applyPreview()

    #expect(state.current == original)
    #expect(state.applied == [imported, original])
    #expect(state.validationStatuses == [.azureVision: .invalidCredentials])
    #expect(controller.preview == imported)
    #expect(controller.error?.message == "Configuration file is invalid.")
  }

  @Test("rejects invalid configuration values before previewing") @MainActor
  func rejectsInvalidValuesBeforePreview() throws {
    let archive = configurationArchive(captureMode: .toggle)
    let data = try ConfigurationArchiveCodec.encode(archive)
    var object = try #require(
      JSONSerialization.jsonObject(with: data) as? [String: Any])
    var preferences = try #require(object["preferences"] as? [String: Any])
    preferences["historyRetentionDays"] = 0
    object["preferences"] = preferences
    let invalid = try JSONSerialization.data(withJSONObject: object)
    let state = TestConfigurationState(current: archive, failingArchive: archive)
    let controller = ConfigurationImportController(state: state)

    controller.preview(invalid)

    #expect(controller.preview == nil)
    #expect(state.applied.isEmpty)
    #expect(controller.error?.message == "Configuration values are invalid.")
  }

  @MainActor
  private func configurationArchive(captureMode: CaptureMode) -> ConfigurationArchive {
    let preferences = Preferences(defaults: makeDefaults())
    preferences.captureMode = captureMode
    return ConfigurationArchive(preferences: preferences, profiles: [], cloudOCRProviders: [])
  }
}

struct DiagnosticEventStoreTests {
  @Test("retains only recent bounded local diagnostic events") @MainActor
  func retainsRecentBoundedEvents() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("writeit-diagnostics-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
    let broadPolicy = DiagnosticEventRetentionPolicy(maximumAge: 10_000, maximumEvents: 10)
    let store = DiagnosticEventStore(directory: directory, retentionPolicy: broadPolicy, now: { now })
    store.record(.runtimeStarted, at: now.addingTimeInterval(-3_700))
    store.record(.runtimeStopped, at: now.addingTimeInterval(-30))
    store.record(.runtimeStarted, at: now.addingTimeInterval(-10))
    let initialEvents = store.events
    #expect(initialEvents.count == 3)

    let strictPolicy = DiagnosticEventRetentionPolicy(maximumAge: 3_600, maximumEvents: 1)
    let restored = DiagnosticEventStore(directory: directory, retentionPolicy: strictPolicy, now: { now })
    let data = try Data(contentsOf: directory.appendingPathComponent("events.json"))
    let archive = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let encodedEvents = try #require(archive["events"] as? [[String: Any]])

    #expect(restored.events == [initialEvents[2]])
    #expect(Set(archive.keys) == Set(["schema_version", "events"]))
    #expect(encodedEvents.allSatisfy {
      Set($0.keys) == Set(["id", "schema_version", "occurred_at", "kind"])
    })
    try restored.erase()
    #expect(FileManager.default.fileExists(atPath: directory.path) == false)
    restored.record(.runtimeStopped, at: now)
    #expect(restored.events.map(\.kind) == [.runtimeStopped])
  }

  @Test("fails closed for malformed or unmodeled diagnostic archives") @MainActor
  func rejectsMalformedArchive() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("writeit-diagnostics-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let writer = DiagnosticEventStore(directory: directory)
    writer.record(.runtimeStarted)
    let fileURL = directory.appendingPathComponent("events.json")
    var archive = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any])
    var events = try #require(archive["events"] as? [[String: Any]])
    events[0]["recognized_text"] = "must-not-persist"
    archive["events"] = events
    try JSONSerialization.data(withJSONObject: archive).write(to: fileURL)

    let store = DiagnosticEventStore(directory: directory)
    store.record(.runtimeStopped)
    let preserved = String(decoding: try Data(contentsOf: fileURL), as: UTF8.self)

    #expect(store.events.isEmpty)
    #expect(store.error?.message == "Saved diagnostic events could not be read.")
    #expect(preserved.contains("must-not-persist"))
  }
}

struct CaptureDisplaySelectorTests {
  @Test("maps AX top-left coordinates to the containing display")
  func mapsAccessibilityPositionToDisplay() {
    let displays = [
      CaptureDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900)),
      CaptureDisplay(id: 2, frame: CGRect(x: 1440, y: 0, width: 1280, height: 1024)),
      CaptureDisplay(id: 3, frame: CGRect(x: 0, y: 900, width: 1440, height: 900)),
    ]
    #expect(
      CaptureDisplaySelector.sourceDisplayID(
        accessibilityPosition: CGPoint(x: 1600, y: 100),
        displays: displays
      ) == 2
    )
    #expect(
      CaptureDisplaySelector.sourceDisplayID(
        accessibilityPosition: CGPoint(x: 200, y: -100),
        displays: displays
      ) == 3
    )
  }

  @Test("uses the primary display when the source display is unavailable")
  func usesDeterministicPrimaryFallback() {
    let displays = [
      CaptureDisplay(id: 19, frame: CGRect(x: 0, y: 0, width: 1440, height: 900)),
      CaptureDisplay(id: 7, frame: CGRect(x: 1440, y: 0, width: 1280, height: 1024)),
    ]
    #expect(CaptureDisplaySelector.displayID(sourceDisplayID: 7, displays: displays) == 7)
    #expect(CaptureDisplaySelector.displayID(sourceDisplayID: 99, displays: displays) == 19)
    #expect(CaptureDisplaySelector.displayID(sourceDisplayID: nil, displays: displays) == 19)
    #expect(CaptureDisplaySelector.displayID(sourceDisplayID: 19, displays: []) == nil)
  }
}

struct CaptureOverlaySpacePolicyTests {
  @Test("uses the active Space and full-screen auxiliary behavior without global leakage")
  func scopesOverlayToActiveSpace() {
    let behavior = CaptureOverlaySpacePolicy.collectionBehavior
    #expect(behavior.contains(.moveToActiveSpace))
    #expect(behavior.contains(.fullScreenAuxiliary))
    #expect(behavior.contains(.ignoresCycle))
    #expect(behavior.contains(.canJoinAllSpaces) == false)
  }
}

struct RecognitionContractTests {
  @Test("recognition requests preserve an immutable language selection")
  func requestsPreserveLanguage() {
    let request = RecognitionRequest(imageData: Data([1, 2, 3]), language: .french)
    #expect(request.imageData == Data([1, 2, 3]))
    #expect(request.language == .french)
    #expect(request.language.displayName == "French")
    #expect(request.allowsCloudOCR == false)
    #expect(request.customWords == CustomWordList(words: []))
  }

  @Test("recognition errors provide a user-facing explanation")
  func errorsProvideExplanation() {
    #expect(RecognitionError.noText.errorDescription == "No handwriting was recognized.")
  }

  @Test("backend capabilities identify supported local recognition")
  func capabilitiesIdentifySupport() {
    let capabilities = RecognitionBackendCapabilities(
      identifier: "fixture",
      displayName: "Fixture",
      supportedLanguages: [.english, .french],
      isLocal: true,
      supportsStreaming: false,
      availability: .available
    )
    #expect(capabilities.supports(.french))
    #expect(capabilities.supports(.german) == false)
    #expect(capabilities.availability == .available)
  }

  @Test("unsupported languages resolve to the local fallback when possible")
  func resolvesLanguageFallback() {
    let capabilities = RecognitionBackendCapabilities(
      identifier: "fixture",
      displayName: "Fixture",
      supportedLanguages: [.english],
      isLocal: true,
      supportsStreaming: false,
      availability: .available
    )
    let resolution = capabilities.resolve(.italian)
    #expect(resolution?.resolved == .english)
    #expect(resolution?.usedFallback == true)
  }

  @Test("Latin language metadata covers the supported v1 choices")
  func latinLanguageMetadata() {
    #expect(
      RecognitionLanguage.allCases.map(\.displayName) == [
        "English", "French", "German", "Spanish", "Italian", "Portuguese",
      ])
  }

  @Test("Apple Vision exposes runtime capability state")
  func visionExposesCapabilityState() {
    let service = RecognitionService()
    #expect(service.capabilities.identifier == "apple-vision")
    #expect(service.capabilities.isLocal)
  }

  @Test("cloud OCR refuses unconsented captures before sending ink")
  func cloudOCRRequiresConsent() async {
    let googleRequester = TestGoogleVisionRequester(
      response: GoogleVisionHTTPResponse(data: Data(), statusCode: 200))
    let google = GoogleVisionRecognitionService(apiKey: "test-api-key", requester: googleRequester)
    do {
      _ = try await google.recognize(RecognitionRequest(imageData: Data([1]), language: .english))
      Issue.record("Google Cloud Vision must require profile consent")
    } catch let error as RecognitionError {
      #expect(error.errorDescription == "Cloud OCR requires consent for this app profile.")
    } catch {
      Issue.record("unexpected error type: \(String(reflecting: type(of: error)))")
    }
    #expect(await googleRequester.requests.isEmpty)

    let azureRequester = TestAzureVisionRequester(
      response: AzureVisionHTTPResponse(data: Data(), statusCode: 200))
    let azure = AzureVisionRecognitionService(
      endpoint: URL(string: "https://writeit.cognitiveservices.azure.com")!,
      apiKey: "test-subscription-key",
      requester: azureRequester
    )
    do {
      _ = try await azure.recognize(RecognitionRequest(imageData: Data([1]), language: .english))
      Issue.record("Azure AI Vision must require profile consent")
    } catch let error as RecognitionError {
      #expect(error.errorDescription == "Cloud OCR requires consent for this app profile.")
    } catch {
      Issue.record("unexpected error type: \(String(reflecting: type(of: error)))")
    }
    #expect(await azureRequester.requests.isEmpty)
  }

  @Test("Google Vision sends a document handwriting request and normalizes its result")
  func googleVisionRecognizesDocumentText() async throws {
    let requester = TestGoogleVisionRequester(
      response: GoogleVisionHTTPResponse(
        data: try JSONSerialization.data(withJSONObject: [
          "responses": [[
            "fullTextAnnotation": [
              "text": "  hello\nworld  ",
              "pages": [["blocks": [["paragraphs": [["words": [
                ["confidence": 0.8], ["confidence": 0.6],
              ]]]]]]],
            ],
          ]],
        ]),
        statusCode: 200
      ))
    let service = GoogleVisionRecognitionService(apiKey: "test-api-key", requester: requester)

    let imageData = CloudCredentialValidationProbe.imageData
    let encodedImage = try CloudImageRequestEncoder.encode(imageData)
    let result = try await service.recognize(
      RecognitionRequest(imageData: imageData, language: .french, allowsCloudOCR: true))

    #expect(result.text == "hello world")
    #expect(abs(result.confidence - 0.7) < 0.001)
    #expect(result.backendID == "google-cloud-vision")
    #expect(result.languageResolution == .identity(.french))
    let sent = try #require(await requester.requests.first)
    #expect(sent.timeoutInterval == CloudRequestPolicy.timeoutInterval)
    #expect(URLComponents(url: try #require(sent.url), resolvingAgainstBaseURL: false)?
      .queryItems?.first(where: { $0.name == "key" })?.value == "test-api-key")
    let body = try #require(sent.httpBody)
    let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    let requests = try #require(json["requests"] as? [[String: Any]])
    let request = try #require(requests.first)
    let image = try #require(request["image"] as? [String: Any])
    #expect(image["content"] as? String == encodedImage.data.base64EncodedString())
    let features = try #require(request["features"] as? [[String: Any]])
    #expect(features.first?["type"] as? String == "DOCUMENT_TEXT_DETECTION")
    let context = try #require(request["imageContext"] as? [String: Any])
    #expect(context["languageHints"] as? [String] == ["fr-FR"])
    #expect(context["customWords"] == nil)
  }

  @Test("Google Vision refuses an empty API key without sending ink")
  func googleVisionRequiresAPIKey() async {
    let requester = TestGoogleVisionRequester(
      response: GoogleVisionHTTPResponse(data: Data(), statusCode: 200))
    let service = GoogleVisionRecognitionService(apiKey: "  ", requester: requester)

    do {
      _ = try await service.recognize(
        RecognitionRequest(imageData: Data([1]), language: .english, allowsCloudOCR: true))
      Issue.record("an empty API key must be rejected")
    } catch let error as RecognitionError {
      #expect(error.errorDescription == "Google Cloud Vision is not configured.")
    } catch {
      Issue.record("unexpected error type: \(String(reflecting: type(of: error)))")
    }
    #expect(await requester.requests.isEmpty)
  }

  @Test("Azure Vision sends image bytes to the Read endpoint and maps confidence")
  func azureVisionRecognizesHandwriting() async throws {
    let requester = TestAzureVisionRequester(
      response: AzureVisionHTTPResponse(
        data: try JSONSerialization.data(withJSONObject: [
          "readResult": [
            "content": "  hello\nazure  ",
            "blocks": [["lines": [["text": "hello azure", "words": [
              ["confidence": 0.9], ["confidence": 0.7],
            ]]]]],
          ],
        ]),
        statusCode: 200
      ))
    let service = AzureVisionRecognitionService(
      endpoint: URL(string: "https://writeit.cognitiveservices.azure.com")!,
      apiKey: "test-subscription-key",
      requester: requester
    )

    let imageData = CloudCredentialValidationProbe.imageData
    let encodedImage = try CloudImageRequestEncoder.encode(imageData)
    let result = try await service.recognize(
      RecognitionRequest(imageData: imageData, language: .italian, allowsCloudOCR: true))

    #expect(result.text == "hello azure")
    #expect(abs(result.confidence - 0.8) < 0.001)
    #expect(result.backendID == "azure-ai-vision-read")
    let sent = try #require(await requester.requests.first)
    #expect(sent.timeoutInterval == CloudRequestPolicy.timeoutInterval)
    #expect(sent.httpBody == encodedImage.data)
    #expect(sent.value(forHTTPHeaderField: "Content-Type") == "image/jpeg")
    #expect(sent.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Key") == "test-subscription-key")
    let queryItems = URLComponents(url: try #require(sent.url), resolvingAgainstBaseURL: false)?
      .queryItems ?? []
    #expect(Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value) }) == [
      "api-version": "2024-02-01", "features": "read", "language": "it",
    ])
  }

  @Test("Azure Vision refuses an invalid endpoint without sending ink")
  func azureVisionRequiresAzureHTTPSResource() async {
    let requester = TestAzureVisionRequester(
      response: AzureVisionHTTPResponse(data: Data(), statusCode: 200))
    let service = AzureVisionRecognitionService(
      endpoint: URL(string: "https://example.invalid")!,
      apiKey: "test-subscription-key",
      requester: requester
    )

    do {
      _ = try await service.recognize(
        RecognitionRequest(imageData: Data([1]), language: .english, allowsCloudOCR: true))
      Issue.record("a non-Azure endpoint must be rejected")
    } catch let error as RecognitionError {
      #expect(error.errorDescription == "Azure AI Vision is not configured.")
    } catch {
      Issue.record("unexpected error type: \(String(reflecting: type(of: error)))")
    }
    #expect(await requester.requests.isEmpty)
  }

  @Test("Google credential validation maps authentication failures without sending capture ink")
  func validatesGoogleCredentials() async throws {
    let requester = TestGoogleVisionRequester(
      response: GoogleVisionHTTPResponse(data: Data(), statusCode: 403))
    let service = GoogleVisionRecognitionService(apiKey: "test-api-key", requester: requester)

    #expect(await service.validateCredentials() == .invalidCredentials)
    let sent = await requester.requests
    #expect(sent.count == 1)
    let body = try #require(sent.first?.httpBody)
    let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    let requests = try #require(json["requests"] as? [[String: Any]])
    let image = try #require(requests.first?["image"] as? [String: Any])
    let encodedProbe = try CloudImageRequestEncoder.encode(CloudCredentialValidationProbe.imageData)
    #expect(image["content"] as? String == encodedProbe.data.base64EncodedString())
  }

  @Test("Azure credential validation accepts a successful probe and rejects invalid configuration")
  func validatesAzureCredentials() async throws {
    let validRequester = TestAzureVisionRequester(
      response: AzureVisionHTTPResponse(data: Data(), statusCode: 200))
    let validService = AzureVisionRecognitionService(
      endpoint: URL(string: "https://writeit.cognitiveservices.azure.com")!,
      apiKey: "test-subscription-key",
      requester: validRequester
    )
    let invalidService = AzureVisionRecognitionService(
      endpoint: URL(string: "https://example.invalid")!,
      apiKey: "test-subscription-key",
      requester: TestAzureVisionRequester(
        response: AzureVisionHTTPResponse(data: Data(), statusCode: 200))
    )

    #expect(await validService.validateCredentials() == .valid)
    #expect(await invalidService.validateCredentials() == .notConfigured)
    let sent = await validRequester.requests
    #expect(sent.count == 1)
    let encodedProbe = try CloudImageRequestEncoder.encode(CloudCredentialValidationProbe.imageData)
    #expect(sent.first?.httpBody == encodedProbe.data)
  }

  @Test("cloud request encoding produces bounded JPEG and rejects malformed or over-budget input")
  func encodesCloudRequestImages() throws {
    let encoded = try CloudImageRequestEncoder.encode(CloudCredentialValidationProbe.imageData)
    #expect(encoded.contentType == "image/jpeg")
    #expect(encoded.data.count <= CloudImageRequestEncoder.maximumEncodedBytes)
    #expect(throws: CloudImageRequestEncodingError.invalidImage) {
      try CloudImageRequestEncoder.encode(Data([0, 1, 2]))
    }
    #expect(throws: CloudImageRequestEncodingError.tooLarge) {
      try CloudImageRequestEncoder.encode(CloudCredentialValidationProbe.imageData, maximumBytes: 1)
    }
  }

  @Test("custom OCR provider validates a versioned secure request and response contract")
  func validatesCustomOCRProviderContract() throws {
    let provider = try CustomOCRProviderConfiguration(
      id: "custom.example",
      displayName: "Example OCR",
      endpoint: URL(string: "https://ocr.example.com/v1/recognize")!,
      authentication: .bearerToken,
      supportedLanguages: [.english, .french]
    ).validated()
    let request = try CustomOCRProviderRequest(
      imageData: Data([1, 2, 3]),
      imageContentType: "image/jpeg",
      language: .french
    )
    let encoded = try JSONEncoder().encode(request)
    let payload = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect(payload["schema_version"] as? Int == 1)
    #expect(payload["image_base64"] as? String == Data([1, 2, 3]).base64EncodedString())
    #expect(payload["image_content_type"] as? String == "image/jpeg")
    #expect(payload["language"] as? String == "fr-FR")

    let result = try CustomOCRProviderResponse(text: "  bonjour\nmonde ", confidence: 0.84)
      .recognitionResult(provider: provider, language: .french)
    #expect(result.text == "bonjour monde")
    #expect(result.confidence == 0.84)
    #expect(result.backendID == "custom.example")
  }

  @Test("custom OCR provider rejects insecure or malformed contracts")
  func rejectsInvalidCustomOCRProviderContracts() {
    let insecureProvider = CustomOCRProviderConfiguration(
      id: "custom.example",
      displayName: "Example OCR",
      endpoint: URL(string: "http://ocr.example.com")!,
      authentication: .none,
      supportedLanguages: [.english]
    )
    #expect(throws: CustomOCRProviderContractError.invalidEndpoint) {
      try insecureProvider.validated()
    }
    #expect(throws: CustomOCRProviderContractError.invalidContentType) {
      try CustomOCRProviderRequest(
        imageData: Data([1]), imageContentType: "image/tiff", language: .english)
    }
    let localProvider = CustomOCRProviderConfiguration(
      id: "custom.local",
      displayName: "Local OCR",
      endpoint: URL(string: "http://127.0.0.1:8080/recognize")!,
      authentication: .none,
      supportedLanguages: [.english]
    )
    let validatedLocalProvider = try? localProvider.validated()
    #expect(validatedLocalProvider == localProvider)
  }

  @Test("custom OCR test request validates the provider contract without capture ink")
  func testsCustomOCRProviderRequest() async throws {
    let requester = TestCustomOCRProviderRequester(
      response: CustomOCRProviderHTTPResponse(
        data: try JSONEncoder().encode(
          CustomOCRProviderResponse(text: "probe accepted", confidence: 0.91)),
        statusCode: 200
      ))
    let configuration = CustomOCRProviderConfiguration(
      id: "custom.example",
      displayName: "Example OCR",
      endpoint: URL(string: "https://ocr.example.com/v1/recognize")!,
      authentication: .bearerToken,
      supportedLanguages: [.english]
    )
    let service = CustomOCRProviderTestService(
      configuration: configuration,
      bearerToken: "test-token",
      requester: requester
    )

    #expect(await service.testRequest() == .valid)
    let sent = try #require(await requester.requests.first)
    #expect(sent.httpMethod == "POST")
    #expect(sent.timeoutInterval == CloudRequestPolicy.timeoutInterval)
    #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
    let body = try #require(sent.httpBody)
    let request = try JSONDecoder().decode(CustomOCRProviderRequest.self, from: body)
    #expect(request.language == .english)
    let encodedProbe = try CloudImageRequestEncoder.encode(CloudCredentialValidationProbe.imageData)
    #expect(request.imageBase64 == encodedProbe.data.base64EncodedString())
  }

  @Test("custom OCR test request reports missing and rejected credentials")
  func rejectsInvalidCustomOCRProviderTestCredentials() async {
    let configuration = CustomOCRProviderConfiguration(
      id: "custom.example",
      displayName: "Example OCR",
      endpoint: URL(string: "https://ocr.example.com/v1/recognize")!,
      authentication: .bearerToken,
      supportedLanguages: [.english]
    )
    let missingRequester = TestCustomOCRProviderRequester(
      response: CustomOCRProviderHTTPResponse(data: Data(), statusCode: 200))
    let missingService = CustomOCRProviderTestService(
      configuration: configuration,
      requester: missingRequester
    )
    let rejectedService = CustomOCRProviderTestService(
      configuration: configuration,
      bearerToken: "test-token",
      requester: TestCustomOCRProviderRequester(
        response: CustomOCRProviderHTTPResponse(data: Data(), statusCode: 401))
    )

    #expect(await missingService.testRequest() == .notConfigured)
    #expect(await missingRequester.requests.isEmpty)
    #expect(await rejectedService.testRequest() == .invalidCredentials)
  }

  @Test("custom OCR test request rejects malformed success responses")
  func rejectsMalformedCustomOCRProviderTestResponse() async {
    let configuration = CustomOCRProviderConfiguration(
      id: "custom.example",
      displayName: "Example OCR",
      endpoint: URL(string: "https://ocr.example.com/v1/recognize")!,
      authentication: .none,
      supportedLanguages: [.english]
    )
    let service = CustomOCRProviderTestService(
      configuration: configuration,
      requester: TestCustomOCRProviderRequester(
        response: CustomOCRProviderHTTPResponse(data: Data("{}".utf8), statusCode: 200))
    )

    #expect(await service.testRequest() == .invalidResponse)
  }

  @Test("recognition failures map to a shared user-facing error")
  func failuresMapToPresentation() {
    let error = AppErrorPresentation.recognition(RecognitionError.noText)
    #expect(error.kind == .recognition)
    #expect(error.title == "Couldn’t read handwriting")
    #expect(error.message == "No handwriting was recognized.")
  }

  @Test("storage and Keychain failures retain typed user-facing presentations")
  func storageAndKeychainErrorsMapToPresentations() {
    let storage = AppErrorPresentation.persistence(HistoryStoreError.writeFailed)
    let keychain = AppErrorPresentation.security(KeychainError.status(errSecAuthFailed))
    #expect(storage.kind == .persistence)
    #expect(storage.message == "WriteIt could not save local history.")
    #expect(keychain.kind == .security)
    #expect(keychain.message == "Secure storage could not complete the request.")
  }

  @Test("delivery outcomes retain typed fallback and clipboard semantics")
  func deliveryOutcomesRetainTypedSemantics() {
    let outcome = DeliveryOutcome.clipboardFallback(.targetNotEditable)
    #expect(outcome.message == "Copied: Captured field no longer accepts text")
    #expect(
      DeliveryOutcome.pasted(.leaveRecognizedText, .notRequested)
        != .pasted(.restorePrevious, .notRequested))
  }

  @Test("delivery recovery retains a typed user-facing presentation")
  func deliveryRecoveryPresentation() throws {
    let fallback = try #require(
      AppErrorPresentation.delivery(.clipboardFallback(.targetNotEditable)))
    let failure = try #require(AppErrorPresentation.delivery(.failed(.clipboardWriteFailed)))
    #expect(fallback.kind == .delivery)
    #expect(fallback.title == "Copied to clipboard")
    #expect(fallback.message.contains("available in the clipboard"))
    #expect(failure.title == "Couldn’t deliver text")
  }

  @Test("delivery rejects stale or noneditable captured targets")
  func validatesCapturedDeliveryTarget() {
    #expect(
      CapturedTargetValidator.failure(isApplicationRunning: false, isEditable: true)
        == .targetAppNotRunning)
    #expect(
      CapturedTargetValidator.failure(isApplicationRunning: true, isEditable: false)
        == .targetNotEditable)
    #expect(CapturedTargetValidator.failure(isApplicationRunning: true, isEditable: true) == nil)
  }

  @Test("paste verification uses selected text or exposed value without retaining text")
  func classifiesPasteVerification() {
    #expect(
      PasteDeliveryVerifier.result(expectedText: "ink", selectedText: "ink", value: nil) == .verified)
    #expect(
      PasteDeliveryVerifier.result(expectedText: "ink", selectedText: nil, value: "prefix ink")
        == .verified)
    #expect(
      PasteDeliveryVerifier.result(expectedText: "ink", selectedText: nil, value: nil) == .unavailable)
    #expect(
      PasteDeliveryVerifier.result(expectedText: "ink", selectedText: "", value: "other") == .failed)
  }
}

struct CloudOCRProviderStoreTests {
  @Test("admits a configured provider only after its credential test succeeds") @MainActor
  func admitsValidatedProvider() async throws {
    let defaults = makeDefaults()
    let credentials = TestCloudOCRCredentialStore()
    let store = CloudOCRProviderStore(
      defaults: defaults,
      credentials: credentials,
      tester: TestCloudOCRProviderTester(status: .valid)
    )

    try store.configureGoogle(apiKey: "google-key")
    #expect(store.isSelectable(.googleVision) == false)
    #expect(try credentials.data(for: CloudOCRProvider.googleVision.credentialAccount)
      == Data("google-key".utf8))

    #expect(await store.test(.googleVision) == .valid)
    #expect(store.isSelectable(.googleVision))
    #expect(store.configuration(for: .googleVision)?.isValidated == true)

    let restored = CloudOCRProviderStore(
      defaults: defaults,
      credentials: credentials,
      tester: TestCloudOCRProviderTester(status: .unavailable)
    )
    #expect(restored.isSelectable(.googleVision))
    try restored.remove(.googleVision)
    #expect(restored.configuration(for: .googleVision) == nil)
    #expect(try credentials.data(for: CloudOCRProvider.googleVision.credentialAccount) == nil)
  }

  @Test("changing cloud configuration revokes prior validation") @MainActor
  func changingConfigurationRevokesValidation() async throws {
    let credentials = TestCloudOCRCredentialStore()
    let store = CloudOCRProviderStore(
      defaults: makeDefaults(),
      credentials: credentials,
      tester: TestCloudOCRProviderTester(status: .valid)
    )
    try store.configureAzure(
      endpoint: "https://writeit.cognitiveservices.azure.com",
      apiKey: "first-key"
    )
    _ = await store.test(.azureVision)
    #expect(store.isSelectable(.azureVision))

    try store.configureAzure(
      endpoint: "https://writeit.cognitiveservices.azure.com",
      apiKey: "second-key"
    )
    #expect(store.isSelectable(.azureVision) == false)
    #expect(store.validationStatus(for: .azureVision) == .notConfigured)
    #expect(throws: CloudOCRProviderStoreError.invalidAzureEndpoint) {
      try store.configureAzure(endpoint: "https://example.invalid", apiKey: "key")
    }
  }
}

struct RecognitionBackendRegistryTests {
  @Test("exposes only locally available and validated cloud recognizers") @MainActor
  func exposesValidatedBackends() async throws {
    let store = CloudOCRProviderStore(
      defaults: makeDefaults(),
      credentials: TestCloudOCRCredentialStore(),
      tester: TestCloudOCRProviderTester(status: .valid)
    )
    let registry = RecognitionBackendRegistry(localRecognizer: TestRecognition(), cloudProviders: store)
    #expect(registry.availableBackends.map(\.identifier) == ["test"])

    try store.configureGoogle(apiKey: "google-key")
    _ = await store.test(.googleVision)
    #expect(registry.availableBackends.map(\.identifier) == ["google-cloud-vision", "test"])
    let recognizer = try registry.recognizer(for: "google-cloud-vision")
    #expect(recognizer.capabilities.isLocal == false)
    #expect(throws: RecognitionError.self) {
      try registry.recognizer(for: "unknown-provider")
    }
  }
}

struct ManifestModelInstallerTests {
  @Test("model store exposes manifest-scoped installation state") @MainActor
  func tracksManifestInstallationState() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let source = directory.appendingPathComponent("fixture.asset")
    try Data([1]).write(to: source)
    let digest = try ModelAssetDigestVerifier.sha256(for: source)
    let manifest = ModelManifest(
      id: "fixture",
      version: "1.0.0",
      downloadURL: URL(string: "https://example.invalid/fixture.asset")!,
      sha256: digest,
      license: "MIT",
      supportedLanguages: [.english],
      requiresAppleSilicon: true
    )
    let store = ModelStore(modelsDirectory: directory.appendingPathComponent("Models"))

    store.install(manifest: manifest, stagedAssetURL: source)

    guard case .installed = store.installationState(for: manifest) else {
      Issue.record("Expected installed manifest state")
      return
    }
    store.activate(manifest: manifest)
    #expect(store.activeModelID == "fixture@1.0.0")
    store.remove(manifest: manifest)
    #expect(store.installationState(for: manifest) == .notInstalled)
    #expect(store.activeModelID == ModelStore.appleVisionModelID)
  }

  @Test("installs and resolves a model only through its manifest identity")
  func installsManifestModel() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let source = directory.appendingPathComponent("fixture.asset")
    try Data([1]).write(to: source)
    let digest = try ModelAssetDigestVerifier.sha256(for: source)
    let manifest = ModelManifest(
      id: "fixture",
      version: "1.0.0",
      downloadURL: URL(string: "https://example.invalid/fixture.asset")!,
      sha256: digest,
      license: "MIT",
      supportedLanguages: [.english],
      requiresAppleSilicon: true
    )

    let installed = try ManifestModelInstaller.install(
      manifest: manifest,
      stagedAssetURL: source,
      in: directory.appendingPathComponent("Models", isDirectory: true)
    )

    #expect(FileManager.default.fileExists(atPath: installed.path))
    #expect(ManifestModelInstaller.installedAssetURL(
      for: manifest,
      in: directory.appendingPathComponent("Models", isDirectory: true)
    ) == installed)
    #expect(ManifestModelInstaller.installedAssetURL(
      for: ModelManifest(
        id: "fixture", version: "2.0.0", downloadURL: manifest.downloadURL,
        sha256: manifest.sha256, license: manifest.license,
        supportedLanguages: manifest.supportedLanguages,
        requiresAppleSilicon: manifest.requiresAppleSilicon
      ),
      in: directory.appendingPathComponent("Models", isDirectory: true)
    ) == nil)
  }

  @Test("rejects unsafe manifests and preserves an existing model version")
  func rejectsUnsafeOrDuplicateManifestModel() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let source = directory.appendingPathComponent("fixture.asset")
    try Data([1]).write(to: source)
    let digest = try ModelAssetDigestVerifier.sha256(for: source)
    let validManifest = ModelManifest(
      id: "fixture",
      version: "1.0.0",
      downloadURL: URL(string: "https://example.invalid/fixture.asset")!,
      sha256: digest,
      license: "MIT",
      supportedLanguages: [.english],
      requiresAppleSilicon: true
    )
    let unsafeManifest = ModelManifest(
      id: "../outside",
      version: "1.0.0",
      downloadURL: validManifest.downloadURL,
      sha256: validManifest.sha256,
      license: validManifest.license,
      supportedLanguages: validManifest.supportedLanguages,
      requiresAppleSilicon: validManifest.requiresAppleSilicon
    )
    let modelsDirectory = directory.appendingPathComponent("Models", isDirectory: true)
    _ = try ManifestModelInstaller.install(
      manifest: validManifest, stagedAssetURL: source, in: modelsDirectory)

    #expect(throws: ManifestModelInstallerError.alreadyInstalled) {
      try ManifestModelInstaller.install(manifest: validManifest, stagedAssetURL: source, in: modelsDirectory)
    }
    #expect(throws: ManifestModelInstallerError.invalidManifest) {
      try ManifestModelInstaller.install(manifest: unsafeManifest, stagedAssetURL: source, in: modelsDirectory)
    }
    #expect(ManifestModelInstaller.installedAssetURL(for: validManifest, in: modelsDirectory) != nil)
  }

  @Test("cancelling installation removes staged state without publishing a model")
  func rollsBackCancelledInstall() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let source = directory.appendingPathComponent("fixture.asset")
    try Data([1]).write(to: source)
    let manifest = ModelManifest(
      id: "fixture",
      version: "1.0.0",
      downloadURL: URL(string: "https://example.invalid/fixture.asset")!,
      sha256: try ModelAssetDigestVerifier.sha256(for: source),
      license: "MIT",
      supportedLanguages: [.english],
      requiresAppleSilicon: true
    )
    let modelsDirectory = directory.appendingPathComponent("Models", isDirectory: true)
    var checks = 0

    #expect(throws: ManifestModelInstallerError.cancelled) {
      try ManifestModelInstaller.install(
        manifest: manifest,
        stagedAssetURL: source,
        in: modelsDirectory,
        isCancelled: {
          checks += 1
          return checks == 2
        }
      )
    }
    #expect(ManifestModelInstaller.installedAssetURL(for: manifest, in: modelsDirectory) == nil)
    #expect((try? FileManager.default.contentsOfDirectory(atPath: modelsDirectory.path))?.isEmpty != false)
  }
}

struct ModelAssetDigestVerifierTests {
  @Test("streams SHA-256 verification for downloaded model assets")
  func verifiesModelAssetDigest() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let asset = directory.appendingPathComponent("fixture.asset")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("abc".utf8).write(to: asset)

    #expect(try ModelAssetDigestVerifier.sha256(for: asset)
      == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    try ModelAssetDigestVerifier.verify(
      assetURL: asset,
      expectedSHA256: "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD"
    )
  }

  @Test("rejects mismatched and non-file model assets before installation")
  func rejectsInvalidModelAsset() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let asset = directory.appendingPathComponent("fixture.asset")
    try Data("abc".utf8).write(to: asset)

    #expect(throws: ModelAssetDigestError.digestMismatch) {
      try ModelAssetDigestVerifier.verify(assetURL: asset, expectedSHA256: String(repeating: "0", count: 64))
    }
    #expect(throws: ModelAssetDigestError.assetIsNotAFile) {
      try ModelAssetDigestVerifier.sha256(for: directory)
    }
  }

  @Test("installer rejects an asset whose manifest digest does not match")
  func installerRejectsMismatchedAsset() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let asset = directory.appendingPathComponent("fixture.asset")
    try Data("abc".utf8).write(to: asset)
    let manifest = ModelManifest(
      id: "fixture",
      version: "1.0.0",
      downloadURL: URL(string: "https://example.invalid/fixture.asset")!,
      sha256: String(repeating: "0", count: 64),
      license: "MIT",
      supportedLanguages: [.english],
      requiresAppleSilicon: true
    )
    let modelsDirectory = directory.appendingPathComponent("Models", isDirectory: true)

    #expect(throws: ModelAssetDigestError.digestMismatch) {
      try ManifestModelInstaller.install(
        manifest: manifest, stagedAssetURL: asset, in: modelsDirectory)
    }
    #expect(ManifestModelInstaller.installedAssetURL(for: manifest, in: modelsDirectory) == nil)
  }
}

struct ModelCompatibilityCheckerTests {
  @Test("requires Apple Silicon, macOS support, and two asset copies plus headroom")
  func validatesModelCompatibility() {
    let manifest = ModelManifest(
      id: "fixture",
      version: "1.0.0",
      downloadURL: URL(string: "https://example.invalid/fixture.asset")!,
      sha256: String(repeating: "a", count: 64),
      license: "MIT",
      supportedLanguages: [.english],
      requiresAppleSilicon: true,
      assetSizeBytes: 100,
      minimumMacOSVersion: ModelMacOSVersion(major: 16, minor: 1, patch: 0)
    )
    let required = ModelCompatibilityChecker.requiredStorageBytes(for: manifest)

    #expect(required == ModelCompatibilityChecker.installHeadroomBytes + 200)
    #expect(ModelCompatibilityChecker.failure(for: manifest, environment: .init(
      isAppleSilicon: false, macOSVersion: .macOS15, availableStorageBytes: required
    )) == .requiresAppleSilicon)
    #expect(ModelCompatibilityChecker.failure(for: manifest, environment: .init(
      isAppleSilicon: true, macOSVersion: .macOS15, availableStorageBytes: required
    )) == .requiresMacOS(manifest.minimumMacOSVersion))
    #expect(ModelCompatibilityChecker.failure(for: manifest, environment: .init(
      isAppleSilicon: true,
      macOSVersion: manifest.minimumMacOSVersion,
      availableStorageBytes: required - 1
    )) == .insufficientStorage(required: required, available: required - 1))
    #expect(ModelCompatibilityChecker.failure(for: manifest, environment: .init(
      isAppleSilicon: true, macOSVersion: manifest.minimumMacOSVersion, availableStorageBytes: required
    )) == nil)
  }
}

struct ModelDownloadCheckpointStoreTests {
  @Test("persists resumable model progress without asset content")
  func persistsDownloadCheckpoint() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manifest = ModelManifest(
      id: "fixture",
      version: "1.0.0",
      downloadURL: URL(string: "https://example.invalid/fixture.asset")!,
      sha256: String(repeating: "a", count: 64),
      license: "MIT",
      supportedLanguages: [.english],
      requiresAppleSilicon: true
    )
    let store = ModelDownloadCheckpointStore(fileURL: directory.appendingPathComponent("downloads.json"))
    let checkpoint = ModelDownloadCheckpoint(
      schemaVersion: ModelDownloadCheckpoint.currentSchemaVersion,
      manifest: manifest,
      progress: 0.4,
      resumeData: Data([1, 2, 3])
    )

    try store.save([checkpoint])

    #expect(try store.load() == [checkpoint])
  }

  @Test("model store restores, updates, and clears resumable download state") @MainActor
  func restoresDownloadState() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manifest = ModelManifest(
      id: "fixture",
      version: "1.0.0",
      downloadURL: URL(string: "https://example.invalid/fixture.asset")!,
      sha256: String(repeating: "a", count: 64),
      license: "MIT",
      supportedLanguages: [.english],
      requiresAppleSilicon: true
    )
    let checkpointURL = directory.appendingPathComponent("downloads.json")
    let store = ModelStore(
      modelsDirectory: directory.appendingPathComponent("Models"),
      downloadCheckpointURL: checkpointURL
    )

    store.recordDownloadProgress(for: manifest, progress: 1.5, resumeData: Data([1]))

    #expect(store.installationState(for: manifest) == .downloading(progress: 1))
    store.pauseDownload(for: manifest, resumeData: Data([2]))
    #expect(store.installationState(for: manifest) == .paused(progress: 1))
    let restored = ModelStore(
      modelsDirectory: directory.appendingPathComponent("Models"),
      downloadCheckpointURL: checkpointURL
    )
    #expect(restored.installationState(for: manifest) == .paused(progress: 1))
    #expect(restored.downloadCheckpoint(for: manifest)?.resumeData == Data([2]))
    #expect(restored.resumeDownload(for: manifest) == Data([2]))
    #expect(restored.installationState(for: manifest) == .downloading(progress: 1))
  }
}

struct GitHubReleaseManifestFetcherTests {
  @Test("retrieves and validates one versioned manifest from the latest release")
  func retrievesVersionedManifest() async throws {
    let repository = try GitHubReleaseRepository(owner: "owner", name: "models")
    let manifestURL = URL(string: "https://github.com/owner/models/releases/download/v1/models.json")!
    let manifest = VersionedModelManifest(
      schemaVersion: VersionedModelManifest.currentSchemaVersion,
      models: [
        ModelManifest(
          id: "fixture",
          version: "1.0.0",
          downloadURL: URL(string: "https://github.com/owner/models/releases/download/v1/fixture.zip")!,
          sha256: String(repeating: "a", count: 64),
          license: "MIT",
          supportedLanguages: [.english],
          requiresAppleSilicon: true,
          assetSizeBytes: 1_024
        )
      ]
    )
    let requester = TestGitHubReleaseRequester(responses: [
      repository.latestReleaseURL: .init(
        data: try releaseData(
          assetName: GitHubReleaseManifestFetcher.defaultManifestAssetName,
          assetURL: manifestURL
        ),
        statusCode: 200
      ),
      manifestURL: .init(data: try JSONEncoder().encode(manifest), statusCode: 200),
    ])
    let fetcher = GitHubReleaseManifestFetcher(repository: repository, requester: requester)

    let fetched = try await fetcher.fetch()

    #expect(fetched == manifest)
    let requests = await requester.requests
    #expect(requests.map(\.url) == [repository.latestReleaseURL, manifestURL])
    #expect(requests[0].value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
    #expect(requests[0].value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2026-03-10")
  }

  @Test("rejects malformed release manifests without retaining their content")
  func rejectsInvalidManifest() async throws {
    let repository = try GitHubReleaseRepository(owner: "owner", name: "models")
    let manifestURL = URL(string: "https://github.com/owner/models/releases/download/v1/models.json")!
    let requester = TestGitHubReleaseRequester(responses: [
      repository.latestReleaseURL: .init(
        data: try releaseData(
          assetName: GitHubReleaseManifestFetcher.defaultManifestAssetName,
          assetURL: manifestURL
        ),
        statusCode: 200
      ),
      manifestURL: .init(data: Data("{\"schema_version\":2,\"models\":[]}".utf8), statusCode: 200),
    ])
    let fetcher = GitHubReleaseManifestFetcher(repository: repository, requester: requester)

    do {
      _ = try await fetcher.fetch()
      Issue.record("Expected unsupported manifest schema")
    } catch let error as GitHubReleaseManifestError {
      #expect(error == .unsupportedManifestSchema)
    }
  }

  @Test("rejects invalid repositories and releases without exactly one manifest asset")
  func rejectsInvalidRepositoryAndRelease() async throws {
    #expect(throws: GitHubReleaseManifestError.invalidRepository) {
      try GitHubReleaseRepository(owner: "owner/name", name: "models")
    }
    let repository = try GitHubReleaseRepository(owner: "owner", name: "models")
    let requester = TestGitHubReleaseRequester(responses: [
      repository.latestReleaseURL: .init(
        data: Data("{\"draft\":false,\"prerelease\":false,\"assets\":[]}".utf8),
        statusCode: 200
      )
    ])

    do {
      _ = try await GitHubReleaseManifestFetcher(repository: repository, requester: requester).fetch()
      Issue.record("Expected missing manifest asset")
    } catch let error as GitHubReleaseManifestError {
      #expect(error == .manifestAssetUnavailable)
    }
  }
}

struct AccessibilityDeliveryTests {
  @Test("native text control harness replaces the selected range") @MainActor
  func pastesIntoNativeTextControl() {
    let harness = NativeTextControlPasteHarness(
      text: "before selected after",
      selection: NSRange(location: 7, length: 8)
    )

    #expect(harness.paste("recognized"))
    #expect(harness.text == "before recognized after")
  }

  @Test("clipboard-only delivery does not access the captured target") @MainActor
  func copiesWithoutAccessibilityDelivery() async {
    let operations = TestAccessibilityDeliveryOperations()
    let delivery = AccessibilityTextDelivery(operations: operations)

    let outcome = await delivery.deliver(
      DeliveryRequest(
        text: "recognized text",
        target: nil,
        strategy: .clipboard,
        clipboardHandling: .leaveRecognizedText,
        verifyPaste: false
      ))

    #expect(outcome == .clipboard)
    #expect(operations.copiedTexts == ["recognized text"])
    #expect(operations.activatedPIDs.isEmpty)
    #expect(operations.commandKeyCodes.isEmpty)
    #expect(operations.replacedTexts.isEmpty)
  }

  @Test("paste delivery uses the captured target and Command-V") @MainActor
  func pastesIntoCapturedTarget() async {
    let operations = TestAccessibilityDeliveryOperations()
    let delivery = AccessibilityTextDelivery(
      operations: operations,
      targetActivationWaiter: TestTargetActivationWaiter(result: true)
    )
    let target = TargetReference(
      element: AXUIElementCreateApplication(getpid()),
      pid: getpid(),
      bundleIdentifier: "com.gongahkia.writeit.tests",
      displayID: nil
    )

    let outcome = await delivery.deliver(
      DeliveryRequest(
        text: "recognized text",
        target: target,
        strategy: .paste,
        clipboardHandling: .leaveRecognizedText,
        verifyPaste: false
      ))

    #expect(outcome == .pasted(.leaveRecognizedText, .notRequested))
    #expect(operations.copiedTexts == ["recognized text"])
    #expect(operations.activatedPIDs == [getpid()])
    #expect(operations.commandKeyCodes == [9])
    #expect(operations.replacedTexts.isEmpty)
  }

  @Test("paste verification reports the target verification state") @MainActor
  func verifiesPasteWhenRequested() async {
    let operations = TestAccessibilityDeliveryOperations()
    operations.pasteVerification = .verified
    let delivery = AccessibilityTextDelivery(
      operations: operations,
      targetActivationWaiter: TestTargetActivationWaiter(result: true)
    )
    let target = TargetReference(
      element: AXUIElementCreateApplication(getpid()),
      pid: getpid(),
      bundleIdentifier: "com.gongahkia.writeit.tests",
      displayID: nil
    )

    let outcome = await delivery.deliver(
      DeliveryRequest(
        text: "recognized text",
        target: target,
        strategy: .paste,
        clipboardHandling: .leaveRecognizedText,
        verifyPaste: true
      ))

    #expect(outcome == .pasted(.leaveRecognizedText, .verified))
  }

  @Test("Accessibility delivery replaces selected text in the captured target") @MainActor
  func replacesSelectedTextWithAccessibility() async {
    let operations = TestAccessibilityDeliveryOperations()
    let delivery = AccessibilityTextDelivery(
      operations: operations,
      targetActivationWaiter: TestTargetActivationWaiter(result: true)
    )
    let target = TargetReference(
      element: AXUIElementCreateApplication(getpid()),
      pid: getpid(),
      bundleIdentifier: "com.gongahkia.writeit.tests",
      displayID: nil
    )

    let outcome = await delivery.deliver(
      DeliveryRequest(
        text: "recognized text",
        target: target,
        strategy: .accessibility,
        clipboardHandling: .leaveRecognizedText,
        verifyPaste: false
      ))

    #expect(outcome == .accessibilityInserted)
    #expect(operations.copiedTexts == ["recognized text"])
    #expect(operations.activatedPIDs == [getpid()])
    #expect(operations.commandKeyCodes.isEmpty)
    #expect(operations.replacedTexts == ["recognized text"])
  }

  @Test("paste restores the previous clipboard after delivery") @MainActor
  func restoresPreviousClipboardAfterPaste() async {
    let operations = TestAccessibilityDeliveryOperations()
    let scheduler = TestClipboardRestoreScheduler()
    let delivery = AccessibilityTextDelivery(
      operations: operations,
      clipboardRestoreScheduler: scheduler,
      targetActivationWaiter: TestTargetActivationWaiter(result: true)
    )
    let target = TargetReference(
      element: AXUIElementCreateApplication(getpid()),
      pid: getpid(),
      bundleIdentifier: "com.gongahkia.writeit.tests",
      displayID: nil
    )

    let outcome = await delivery.deliver(
      DeliveryRequest(
        text: "recognized text",
        target: target,
        strategy: .paste,
        clipboardHandling: .restorePrevious,
        verifyPaste: false
      ))

    #expect(outcome == .pasted(.restorePrevious, .notRequested))
    #expect(scheduler.pendingCount == 1)
    #expect(operations.restoreCount == 0)
    scheduler.runNext()
    #expect(operations.restoreCount == 1)
  }

  @Test("paste restoration does not overwrite a newer clipboard") @MainActor
  func preservesNewerClipboardAfterPaste() async {
    let operations = TestAccessibilityDeliveryOperations()
    let scheduler = TestClipboardRestoreScheduler()
    let delivery = AccessibilityTextDelivery(
      operations: operations,
      clipboardRestoreScheduler: scheduler,
      targetActivationWaiter: TestTargetActivationWaiter(result: true)
    )
    let target = TargetReference(
      element: AXUIElementCreateApplication(getpid()),
      pid: getpid(),
      bundleIdentifier: "com.gongahkia.writeit.tests",
      displayID: nil
    )

    _ = await delivery.deliver(
      DeliveryRequest(
        text: "recognized text",
        target: target,
        strategy: .paste,
        clipboardHandling: .restorePrevious,
        verifyPaste: false
      ))
    operations.simulateExternalClipboardChange()
    scheduler.runNext()

    #expect(operations.restoreCount == 0)
  }

  @Test("delivery distinguishes activation request failure from timeout") @MainActor
  func reportsActivationFailures() async {
    let target = TargetReference(
      element: AXUIElementCreateApplication(getpid()),
      pid: getpid(),
      bundleIdentifier: "com.gongahkia.writeit.tests",
      displayID: nil
    )
    let failedOperations = TestAccessibilityDeliveryOperations()
    failedOperations.activationSucceeds = false
    let failedWaiter = TestTargetActivationWaiter(result: true)
    let failedDelivery = AccessibilityTextDelivery(
      operations: failedOperations,
      targetActivationWaiter: failedWaiter
    )
    let timedOutOperations = TestAccessibilityDeliveryOperations()
    let timedOutWaiter = TestTargetActivationWaiter(result: false)
    let timedOutDelivery = AccessibilityTextDelivery(
      operations: timedOutOperations,
      targetActivationWaiter: timedOutWaiter
    )
    let request = DeliveryRequest(
      text: "recognized text",
      target: target,
      strategy: .paste,
      clipboardHandling: .leaveRecognizedText,
      verifyPaste: false
    )

    let failedOutcome = await failedDelivery.deliver(request)
    let timedOutOutcome = await timedOutDelivery.deliver(request)

    #expect(failedOutcome == .clipboardFallback(.activationFailed))
    #expect(failedWaiter.requestedPIDs.isEmpty)
    #expect(timedOutOutcome == .clipboardFallback(.activationTimedOut))
    #expect(timedOutWaiter.requestedPIDs == [getpid()])
    #expect(timedOutOperations.commandKeyCodes.isEmpty)
  }

  @Test("direct delivery failures retain a typed clipboard fallback") @MainActor
  func fallsBackToCopiedTextAfterDirectDeliveryFailure() async {
    let target = TargetReference(
      element: AXUIElementCreateApplication(getpid()),
      pid: getpid(),
      bundleIdentifier: "com.gongahkia.writeit.tests",
      displayID: nil
    )
    let pasteOperations = TestAccessibilityDeliveryOperations()
    pasteOperations.commandSucceeds = false
    let pasteDelivery = AccessibilityTextDelivery(
      operations: pasteOperations,
      targetActivationWaiter: TestTargetActivationWaiter(result: true)
    )
    let accessibilityOperations = TestAccessibilityDeliveryOperations()
    accessibilityOperations.replacementSucceeds = false
    let accessibilityDelivery = AccessibilityTextDelivery(
      operations: accessibilityOperations,
      targetActivationWaiter: TestTargetActivationWaiter(result: true)
    )

    let pasteOutcome = await pasteDelivery.deliver(
      DeliveryRequest(
        text: "recognized text",
        target: target,
        strategy: .paste,
        clipboardHandling: .leaveRecognizedText,
        verifyPaste: false
      ))
    let accessibilityOutcome = await accessibilityDelivery.deliver(
      DeliveryRequest(
        text: "recognized text",
        target: target,
        strategy: .accessibility,
        clipboardHandling: .leaveRecognizedText,
        verifyPaste: false
      ))

    #expect(pasteOutcome == .clipboardFallback(.pasteEventUnavailable))
    #expect(accessibilityOutcome == .clipboardFallback(.accessibilityInsertionFailed))
    #expect(pasteOperations.copiedTexts == ["recognized text"])
    #expect(accessibilityOperations.copiedTexts == ["recognized text"])
  }

  @Test("undo is eligible only after a confirmed direct insertion") @MainActor
  func limitsUndoToConfirmedInsertion() async {
    let target = TargetReference(
      element: AXUIElementCreateApplication(getpid()),
      pid: getpid(),
      bundleIdentifier: "com.gongahkia.writeit.tests",
      displayID: nil
    )
    let failedOperations = TestAccessibilityDeliveryOperations()
    failedOperations.commandSucceeds = false
    let failedDelivery = AccessibilityTextDelivery(
      operations: failedOperations,
      targetActivationWaiter: TestTargetActivationWaiter(result: true)
    )
    let successfulOperations = TestAccessibilityDeliveryOperations()
    let successfulDelivery = AccessibilityTextDelivery(
      operations: successfulOperations,
      targetActivationWaiter: TestTargetActivationWaiter(result: true)
    )
    let request = DeliveryRequest(
      text: "recognized text",
      target: target,
      strategy: .paste,
      clipboardHandling: .leaveRecognizedText,
      verifyPaste: false
    )

    _ = await failedDelivery.deliver(request)
    failedDelivery.undo()
    _ = await successfulDelivery.deliver(request)
    successfulDelivery.undo()

    #expect(failedOperations.commandKeyCodes == [9])
    #expect(successfulOperations.commandKeyCodes == [9, 6])
  }
}

struct CaptureModelTests {
  @Test("backend qualification accepts a benchmark at all configured thresholds")
  func qualifiesBenchmarkAtThresholds() throws {
    let report = OCRBenchmarkReport(
      samples: [
        OCRCorpusBenchmarkSample(
          fixtureID: "fixture",
          language: .english,
          expectedText: "hello world",
          outcome: .recognized(text: "hello world", confidence: 1, backendID: "fixture"),
          duration: .milliseconds(100)
        )
      ],
      totalDuration: .milliseconds(100),
      peakResidentMemoryBytes: 1_024
    )
    let thresholds = try OCRBackendQualificationThresholds(
      maximumMeanCharacterErrorRate: 0,
      maximumMeanWordErrorRate: 0,
      maximumSampleDuration: .milliseconds(100),
      maximumTotalDuration: .milliseconds(100),
      maximumPeakResidentMemoryBytes: 1_024
    )

    let qualification = OCRBackendQualifier.qualify(
      report: report,
      backendID: "fixture",
      thresholds: thresholds
    )

    #expect(qualification.isQualified)
    #expect(qualification.metrics.sampleCount == 1)
    #expect(qualification.metrics.meanCharacterErrorRate == 0)
    #expect(qualification.metrics.peakResidentMemoryBytes == 1_024)
  }

  @Test("backend qualification rejects failed, mismatched, and threshold-exceeding samples")
  func rejectsUnqualifiedBenchmark() throws {
    let report = OCRBenchmarkReport(
      samples: [
        OCRCorpusBenchmarkSample(
          fixtureID: "failed",
          language: .english,
          expectedText: "hello",
          outcome: .failed,
          duration: .milliseconds(10)
        ),
        OCRCorpusBenchmarkSample(
          fixtureID: "wrong-backend",
          language: .english,
          expectedText: "hello",
          outcome: .recognized(text: "hello", confidence: 1, backendID: "other"),
          duration: .milliseconds(10)
        ),
        OCRCorpusBenchmarkSample(
          fixtureID: "slow-inaccurate",
          language: .english,
          expectedText: "hello world",
          outcome: .recognized(text: "goodbye", confidence: 1, backendID: "fixture"),
          duration: .seconds(2)
        ),
      ],
      totalDuration: .seconds(3),
      peakResidentMemoryBytes: 2_048
    )
    let thresholds = try OCRBackendQualificationThresholds(
      maximumMeanCharacterErrorRate: 0.1,
      maximumMeanWordErrorRate: 0.1,
      maximumSampleDuration: .seconds(1),
      maximumTotalDuration: .seconds(1),
      maximumPeakResidentMemoryBytes: 1_024
    )

    let qualification = OCRBackendQualifier.qualify(
      report: report,
      backendID: "fixture",
      thresholds: thresholds
    )

    #expect(!qualification.isQualified)
    #expect(qualification.failures == [
      .failedSamples(1),
      .unexpectedBackendSamples(1),
      .characterErrorRate(10.0 / 11.0),
      .wordErrorRate(1),
      .sampleDuration(.seconds(2)),
      .totalDuration(.seconds(3)),
      .peakResidentMemory(2_048),
    ])
  }

  @Test("backend qualification rejects invalid limits and unavailable required memory")
  func rejectsInvalidQualificationThresholds() throws {
    #expect(throws: OCRBackendQualificationThresholdError.invalidErrorRate) {
      try OCRBackendQualificationThresholds(
        maximumMeanCharacterErrorRate: 1.1,
        maximumMeanWordErrorRate: 0,
        maximumSampleDuration: .seconds(1),
        maximumTotalDuration: .seconds(1)
      )
    }
    #expect(throws: OCRBackendQualificationThresholdError.negativeDuration) {
      try OCRBackendQualificationThresholds(
        maximumMeanCharacterErrorRate: 0,
        maximumMeanWordErrorRate: 0,
        maximumSampleDuration: .seconds(-1),
        maximumTotalDuration: .seconds(1)
      )
    }
    let report = OCRBenchmarkReport(
      samples: [
        OCRCorpusBenchmarkSample(
          fixtureID: "fixture",
          language: .english,
          expectedText: "hello",
          outcome: .recognized(text: "hello", confidence: 1, backendID: "fixture"),
          duration: .milliseconds(1)
        )
      ],
      totalDuration: .milliseconds(1),
      peakResidentMemoryBytes: nil
    )
    let thresholds = try OCRBackendQualificationThresholds(
      maximumMeanCharacterErrorRate: 0,
      maximumMeanWordErrorRate: 0,
      maximumSampleDuration: .seconds(1),
      maximumTotalDuration: .seconds(1),
      maximumPeakResidentMemoryBytes: 1
    )

    #expect(OCRBackendQualifier.qualify(
      report: report,
      backendID: "fixture",
      thresholds: thresholds
    ).failures == [.memoryUnavailable])
    #expect(OCRBackendQualifier.qualify(
      report: OCRBenchmarkReport(samples: [], totalDuration: .zero, peakResidentMemoryBytes: nil),
      backendID: "fixture",
      thresholds: thresholds
    ).failures == [.noSamples, .memoryUnavailable])
  }

  @Test("Apple Silicon benchmark runner reports corpus latency and memory")
  func runsAppleSiliconBenchmark() async throws {
    guard OCRBenchmarkRunner.isAppleSilicon else { return }
    let fixture = OCRCorpusFixture(
      entry: OCRCorpusEntry(
        id: "fixture", imagePath: "fixture.png", transcription: "hello", language: .english),
      imageData: Data([1])
    )

    let report = try await OCRBenchmarkRunner.run(
      fixtures: [fixture],
      recognizer: CorpusFixtureRecognition()
    )

    #expect(report.samples.map(\.fixtureID) == ["fixture"])
    #expect(report.totalDuration >= .zero)
    #expect(report.peakResidentMemoryBytes != nil)
  }

  @Test("OCR accuracy evaluators use Unicode characters and normalized words")
  func evaluatesOCRErrorRates() {
    #expect(OCRAccuracyEvaluator.characterErrorRate(expected: "café", actual: "cafe") == 0.25)
    #expect(
      OCRAccuracyEvaluator.wordErrorRate(expected: "the  cat sat", actual: "the dog sat")
        == 1.0 / 3.0)
    #expect(OCRAccuracyEvaluator.characterErrorRate(expected: "", actual: "text") == 1)
  }

  @Test("Latin corpus harness runs fixtures in deterministic order")
  func runsLatinCorpusFixtures() async throws {
    let fixtures = [
      OCRCorpusFixture(
        entry: OCRCorpusEntry(
          id: "fr", imagePath: "fr.png", transcription: "bonjour", language: .french),
        imageData: Data([2])
      ),
      OCRCorpusFixture(
        entry: OCRCorpusEntry(
          id: "de", imagePath: "de.png", transcription: "hallo", language: .german),
        imageData: Data([1])
      ),
    ]

    let samples = try await OCRCorpusBenchmarkHarness.run(
      fixtures: fixtures,
      recognizer: CorpusFixtureRecognition()
    )

    #expect(samples.map(\.fixtureID) == ["de", "fr"])
    #expect(samples.map(\.language) == [.german, .french])
    #expect(
      samples.map(\.outcome) == [
        .recognized(text: "hallo", confidence: 1, backendID: "fixture"),
        .recognized(text: "bonjour", confidence: 1, backendID: "fixture"),
      ])
  }

  @Test("OCR corpus fixtures load in deterministic identifier order")
  func loadsDeterministicOCRCorpusFixtures() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data([2]).write(to: directory.appendingPathComponent("second.png"))
    try Data([1]).write(to: directory.appendingPathComponent("first.png"))
    let manifest = OCRCorpusManifest(
      version: OCRCorpusManifest.currentVersion,
      entries: [
        OCRCorpusEntry(
          id: "b", imagePath: "second.png", transcription: "second", language: .english),
        OCRCorpusEntry(
          id: "a", imagePath: "first.png", transcription: "first", language: .english),
      ]
    )

    let fixtures = try OCRCorpusFixtureLoader.load(
      manifestData: JSONEncoder().encode(manifest),
      directory: directory
    )

    #expect(fixtures.map(\.entry.id) == ["a", "b"])
    #expect(fixtures.map(\.imageData) == [Data([1]), Data([2])])
  }

  @Test("OCR corpus fixtures reject traversal paths")
  func rejectsTraversalImagePaths() throws {
    let manifest = OCRCorpusManifest(
      version: OCRCorpusManifest.currentVersion,
      entries: [
        OCRCorpusEntry(
          id: "fixture", imagePath: "../outside.png", transcription: "text", language: .english)
      ]
    )

    do {
      _ = try OCRCorpusFixtureLoader.load(
        manifestData: JSONEncoder().encode(manifest),
        directory: FileManager.default.temporaryDirectory
      )
      Issue.record("expected invalid corpus path")
    } catch let error as OCRCorpusError {
      #expect(error == .invalidImagePath)
    }
  }

  @Test("handwriting preprocessing produces timed local stages")
  func preprocessesHandwritingImage() throws {
    let bitmap = try #require(
      NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 24,
        pixelsHigh: 12,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      ))
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    let result = try #require(HandwritingImagePreprocessor.process(data))

    #expect(result.image.width == 24)
    #expect(result.image.height == 12)
    #expect(Set(result.stageDurations.keys) == Set(ImagePreprocessingStage.allCases))
  }

  @Test("shortcuts round-trip through storage")
  func shortcutsRoundTrip() throws {
    let shortcut = Shortcut(
      keyCode: 13, modifiers: CGEventFlags.maskCommand.union(.maskShift).rawValue)
    let decoded = try JSONDecoder().decode(Shortcut.self, from: JSONEncoder().encode(shortcut))
    #expect(decoded == shortcut)
    #expect(
      ShortcutDisplayRenderer.displayName(for: decoded, keyName: { _ in "Z" }) == "⇧⌘Z")
    #expect(ShortcutDisplayRenderer.displayName(for: decoded, keyName: { _ in nil }) == "⇧⌘Key 13")
  }

  @Test("reserved capture commands cannot become global shortcuts")
  func rejectsReservedCaptureShortcuts() {
    #expect(ShortcutConflictValidator.message(for: .default) == nil)
    #expect(ShortcutConflictValidator.message(for: Shortcut(keyCode: 53, modifiers: 0)) != nil)
    #expect(ShortcutConflictValidator.message(for: Shortcut(keyCode: 36, modifiers: 0)) != nil)
    #expect(
      ShortcutConflictValidator.message(
        for: Shortcut(keyCode: 51, modifiers: CGEventFlags.maskCommand.rawValue)) != nil)
  }

  @Test("event tap disablement identifies recoverable tap failures")
  func classifiesEventTapDisablement() {
    #expect(EventTapDisablement(type: .tapDisabledByTimeout) == .timeout)
    #expect(EventTapDisablement(type: .tapDisabledByUserInput) == .userInput)
    #expect(EventTapDisablement(type: .keyDown) == nil)
  }

  @Test("event-tap lifecycle diagnostics use redacted stable fields")
  func formatsEventTapLifecycleDiagnostics() {
    #expect(EventTapLifecycleEvent.started.message == "event_tap_lifecycle event=started")
    #expect(
      EventTapLifecycleEvent.disabled(.timeout).message
        == "event_tap_lifecycle event=disabled reason=timeout")
    #expect(EventTapLifecycleEvent.reenableFailed(.userInput).isError)
    #expect(EventTapLifecycleEvent.reenabled(.userInput).isError == false)
  }

  @Test("keyboard input resolves each capture command once")
  func resolvesKeyboardCommands() {
    let shortcut = Shortcut(
      keyCode: 13, modifiers: CGEventFlags.maskCommand.union(.maskShift).rawValue)
    #expect(
      CaptureKeyboardCommandResolver.resolve(
        keyCode: 53, modifiers: 0, isAutorepeat: false, shortcut: shortcut, event: .down) == .cancel)
    #expect(
      CaptureKeyboardCommandResolver.resolve(
        keyCode: 36, modifiers: 0, isAutorepeat: false, shortcut: shortcut, event: .down) == .confirm)
    #expect(
      CaptureKeyboardCommandResolver.resolve(
        keyCode: 51, modifiers: CGEventFlags.maskCommand.rawValue, isAutorepeat: false,
        shortcut: shortcut, event: .down) == .clear)
    #expect(
      CaptureKeyboardCommandResolver.resolve(
        keyCode: shortcut.keyCode, modifiers: shortcut.modifiers, isAutorepeat: false,
        shortcut: shortcut, event: .down) == .shortcut(.down))
    #expect(
      CaptureKeyboardCommandResolver.resolve(
        keyCode: shortcut.keyCode, modifiers: shortcut.modifiers, isAutorepeat: true,
        shortcut: shortcut, event: .down) == nil)
  }

  @Test("history entries may omit ink")
  func historyEntriesMayOmitInk() throws {
    let entry = HistoryEntry(text: "testing", strokes: nil, source: "Apple Vision")
    let decoded = try JSONDecoder().decode(HistoryEntry.self, from: JSONEncoder().encode(entry))
    #expect(decoded.strokes == nil)
    #expect(decoded.text == "testing")
  }

  @Test("ink sessions render submitted strokes") @MainActor
  func inkSessionsRenderSubmittedStrokes() {
    let session = CaptureSession()
    session.begin(target: nil)
    #expect(session.transition(to: .drawing))
    session.canvasSize = CGSize(width: 300, height: 120)
    session.beginStroke(at: InkPoint(x: 20, y: 30, pressure: 1, timestamp: 0))
    session.append(point: InkPoint(x: 190, y: 70, pressure: 1, timestamp: 0.2))
    #expect(session.renderedImageData() != nil)
  }

  @Test("canvas resize preserves live, stored, and rendered alignment") @MainActor
  func canvasResizePreservesCoordinateAlignment() {
    let session = CaptureSession()
    #expect(session.begin(target: nil))
    #expect(session.transition(to: .drawing))
    session.canvasSize = CGSize(width: 300, height: 120)
    session.beginStroke(at: InkPoint(x: 30, y: 24, pressure: 1, timestamp: 0))
    session.append(
      point: InkPoint(x: 270, y: 96, pressure: 1, timestamp: 0.2),
      style: InkStyle(baseWidth: 4, pressureSensitivity: 0.6, smoothing: 0))
    session.resizeCanvas(to: CGSize(width: 600, height: 240))
    let points = session.strokes[0].points
    #expect(points.map(\.x) == [60, 540])
    #expect(points.map(\.y) == [48, 192])
    let rendered = CanvasCoordinateTransformer.renderPoint(
      points[0], canvasSize: session.canvasSize, outputSize: InkRasterLayout.outputSize(for: session.canvasSize))
    #expect(rendered.x == 153.6)
    #expect(rendered.y == 491.52)
  }

  @Test("high-DPI raster export preserves resolution and coordinates") @MainActor
  func highDPIRenderingAcrossCanvasScales() throws {
    let cases: [(CGSize, (Int, Int))] = [
      (CGSize(width: 300, height: 120), (3072, 1229)),
      (CGSize(width: 800, height: 100), (3072, 1024)),
      (CGSize(width: 200, height: 400), (3072, 6144)),
    ]
    for (canvasSize, expectedPixels) in cases {
      let session = CaptureSession()
      #expect(session.begin(target: nil))
      #expect(session.transition(to: .drawing))
      session.canvasSize = canvasSize
      session.beginStroke(
        at: InkPoint(x: canvasSize.width * 0.25, y: canvasSize.height * 0.75, pressure: 1, timestamp: 0))
      session.append(
        point: InkPoint(x: canvasSize.width * 0.75, y: canvasSize.height * 0.25, pressure: 1, timestamp: 0.2),
        style: InkStyle(baseWidth: 4, pressureSensitivity: 0.6, smoothing: 0))
      let data = try #require(session.renderedImageData())
      let bitmap = try #require(NSBitmapImageRep(data: data))
      #expect(bitmap.pixelsWide == expectedPixels.0)
      #expect(bitmap.pixelsHigh == expectedPixels.1)
      #expect(InkRasterLayout.pixelSize(for: canvasSize) == expectedPixels)
      let output = InkRasterLayout.outputSize(for: canvasSize)
      let point = CanvasCoordinateTransformer.renderPoint(
        session.strokes[0].points[0], canvasSize: canvasSize, outputSize: output)
      #expect(point.x == 384)
      #expect(abs(point.y - output.height * 0.25) < 0.001)
    }
  }

  @Test("records first accepted stroke latency once per capture") @MainActor
  func recordsFirstStrokeLatencyOncePerCapture() {
    let session = CaptureSession()
    var latencies: [Duration] = []
    session.onFirstStrokeAccepted = { latencies.append($0) }
    #expect(session.begin(target: nil))
    #expect(session.transition(to: .drawing))
    session.beginStroke(at: InkPoint(x: 20, y: 30, pressure: 1, timestamp: 0))
    session.beginStroke(at: InkPoint(x: 40, y: 50, pressure: 1, timestamp: 0.1))
    #expect(latencies.count == 1)
    #expect(latencies[0] >= .zero)

    #expect(session.transition(to: .recognizing))
    #expect(session.transition(to: .delivering))
    #expect(session.transition(to: .delivered("Copied")))
    #expect(session.transition(to: .dismissing))
    session.completeDismissal()
    #expect(session.begin(target: nil))
    #expect(session.transition(to: .drawing))
    session.beginStroke(at: InkPoint(x: 60, y: 70, pressure: 1, timestamp: 0.2))
    #expect(latencies.count == 2)
  }

  @Test("ink styles smooth points and use pressure for width")
  func inkStylesApplyPressureAndSmoothing() {
    let style = InkStyle(baseWidth: 4, pressureSensitivity: 1, smoothing: 0.5)
    let previous = InkPoint(x: 0, y: 0, pressure: 0.5, timestamp: 0)
    let next = InkPoint(x: 20, y: 10, pressure: 1, timestamp: 1)
    let smoothed = style.smoothed(next, after: previous)
    #expect(smoothed.x > previous.x)
    #expect(smoothed.x < next.x)
    #expect(style.lineWidth(for: 1) > style.lineWidth(for: 0))
  }

  @Test("tablet pressure changes width while mouse baseline remains stable")
  func pressureWidthPreservesMouseBaseline() {
    let style = InkStyle(baseWidth: 4, pressureSensitivity: 1, smoothing: 0)
    #expect(style.lineWidth(for: 0) == 1)
    #expect(style.lineWidth(for: 0.5) == 4)
    #expect(style.lineWidth(for: 1) == 8)
    #expect(style.lineWidth(for: -1) == style.lineWidth(for: 0))
    #expect(style.lineWidth(for: 2) == style.lineWidth(for: 1))
  }

  @Test("base width applies equally to mouse and stylus pressure")
  func baseWidthAppliesAcrossInputSources() {
    let style = InkStyle(baseWidth: 9, pressureSensitivity: 0, smoothing: 0)
    let mouse = InkPoint(x: 0, y: 0, pressure: 0.5, timestamp: 0, inputSource: .mouse)
    let stylus = InkPoint(x: 0, y: 0, pressure: 0.5, timestamp: 0, inputSource: .stylus)
    #expect(style.lineWidth(for: mouse.pressure) == 9)
    #expect(style.lineWidth(for: stylus.pressure) == 9)
  }

  @Test("smoothing is deterministic for mouse and tablet input")
  func smoothingIsDeterministicAcrossInputSources() {
    let style = InkStyle(baseWidth: 4, pressureSensitivity: 0.6, smoothing: 1)
    let previous = InkPoint(x: 0, y: 0, pressure: 0.5, timestamp: 0)
    let mouse = InkPoint(x: 20, y: 10, pressure: 1, timestamp: 1, inputSource: .mouse)
    let stylus = InkPoint(x: 20, y: 10, pressure: 1, timestamp: 1, inputSource: .stylus)
    let smoothedMouse = style.smoothed(mouse, after: previous)
    let smoothedStylus = style.smoothed(stylus, after: previous)
    #expect(smoothedMouse.x == 5)
    #expect(smoothedMouse.y == 2.5)
    #expect(smoothedMouse.pressure == 0.625)
    #expect(smoothedStylus.x == smoothedMouse.x)
    #expect(smoothedStylus.y == smoothedMouse.y)
    #expect(smoothedStylus.inputSource == .stylus)
  }

  @Test("ink preview geometry reflects selected input settings")
  func inkPreviewReflectsSelectedSettings() {
    let raw = InkStyle(baseWidth: 4, pressureSensitivity: 0, smoothing: 0)
    let smooth = InkStyle(baseWidth: 8, pressureSensitivity: 1, smoothing: 1)
    let rawPoints = InkStylePreviewGeometry.smoothedPoints(for: raw)
    let smoothPoints = InkStylePreviewGeometry.smoothedPoints(for: smooth)
    #expect(rawPoints.count == InkStylePreviewGeometry.rawPoints.count)
    #expect(rawPoints[1].x == InkStylePreviewGeometry.rawPoints[1].x)
    #expect(smoothPoints[1].x < rawPoints[1].x)
    #expect(smooth.lineWidth(for: 1) > raw.lineWidth(for: 1))
  }

  @Test("empty and tap-only captures are rejected before OCR") @MainActor
  func captureInputValidation() {
    let session = CaptureSession()
    session.begin(target: nil)
    #expect(session.transition(to: .drawing))
    #expect(session.inputValidationMessage() == "Write something before recognizing.")
    session.beginStroke(at: InkPoint(x: 20, y: 30, pressure: 1, timestamp: 0))
    #expect(session.inputValidationMessage() == "Draw a stroke before recognizing.")
    #expect(session.renderedImageData() == nil)
  }

  @Test("ink points preserve source and decode older records as mouse input")
  func inkPointSourceCompatibility() throws {
    let stylusPoint = InkPoint(
      x: 20,
      y: 30,
      pressure: 1,
      timestamp: 0,
      inputSource: .stylus
    )
    let decoded = try JSONDecoder().decode(InkPoint.self, from: JSONEncoder().encode(stylusPoint))
    #expect(decoded.inputSource == .stylus)
    let legacyData = Data(#"{"x":20,"y":30,"pressure":0.5,"timestamp":0}"#.utf8)
    let legacy = try JSONDecoder().decode(InkPoint.self, from: legacyData)
    #expect(legacy.inputSource == .mouse)
  }

  @Test("tablet input records start, continuation, and normalized pressure") @MainActor
  func tabletInputRegressionCoverage() {
    let session = CaptureSession()
    #expect(session.begin(target: nil))
    #expect(session.transition(to: .drawing))
    let style = InkStyle(baseWidth: 4, pressureSensitivity: 0.6, smoothing: 0)
    session.beginStroke(
      at: InkPoint(
        x: 20, y: 30, pressure: InkInputNormalizer.pressure(0.1), timestamp: 0,
        inputSource: .stylus))
    session.append(
      point: InkPoint(
        x: 80, y: 90, pressure: InkInputNormalizer.pressure(0.8), timestamp: 0.1,
        inputSource: .stylus),
      style: style)
    #expect(session.strokes.count == 1)
    #expect(session.strokes[0].points.count == 2)
    #expect(session.strokes[0].points.map(\.inputSource) == [.stylus, .stylus])
    #expect(session.strokes[0].points.map(\.pressure) == [0.5, 0.8])
  }

  @Test("input normalization clamps pressure and falls back to mouse")
  func inputNormalizationRegressionCoverage() {
    #expect(InkInputNormalizer.source(for: .pen) == .stylus)
    #expect(InkInputNormalizer.source(for: .eraser) == .stylus)
    #expect(InkInputNormalizer.source(for: .cursor) == .mouse)
    #expect(InkInputNormalizer.source(for: .unknown) == .mouse)
    #expect(InkInputNormalizer.pressure(-1) == 0.5)
    #expect(InkInputNormalizer.pressure(0.75) == 0.75)
    #expect(InkInputNormalizer.pressure(2) == 1)
  }
}

struct CaptureLifecycleTests {
  @Test("validates the opening through delivery lifecycle") @MainActor
  func validatesSuccessfulLifecycle() {
    let session = CaptureSession()
    #expect(session.begin(target: nil))
    #expect(session.phase == .opening)
    #expect(session.transition(to: .drawing))
    #expect(session.transition(to: .recognizing))
    #expect(session.transition(to: .reviewing))
    #expect(session.transition(to: .delivering))
    #expect(session.transition(to: .delivered("Inserted")))
    #expect(session.transition(to: .dismissing))
    session.completeDismissal()
    #expect(session.phase == .idle)
  }

  @Test("validates failure retry and rejects illegal lifecycle jumps") @MainActor
  func validatesFailureAndIllegalTransitions() {
    let session = CaptureSession()
    #expect(session.transition(to: .drawing) == false)
    #expect(session.begin(target: nil))
    #expect(session.transition(to: .delivered("Inserted")) == false)
    #expect(session.transition(to: .drawing))
    #expect(session.transition(to: .recognizing))
    #expect(session.transition(to: .failed("No text")))
    #expect(session.transition(to: .drawing))
    #expect(session.transition(to: .dismissing))
    session.completeDismissal()
    #expect(session.phase == .idle)
  }
}

struct PenUpSubmissionEligibilityTests {
  @Test("pen-up submission rejects stale capture state")
  func rejectsStaleCaptureState() {
    let taskID = UUID()
    let eligibility = PenUpSubmissionEligibility(taskID: taskID, strokeCount: 1)
    #expect(
      eligibility.allowsSubmission(
        activeTaskID: taskID, isCancelled: false, phase: .drawing, strokeCount: 1))
    #expect(
      eligibility.allowsSubmission(
        activeTaskID: taskID, isCancelled: false, phase: .drawing, strokeCount: 2) == false)
    #expect(
      eligibility.allowsSubmission(
        activeTaskID: taskID, isCancelled: false, phase: .drawing, strokeCount: 0) == false)
    #expect(
      eligibility.allowsSubmission(
        activeTaskID: nil, isCancelled: false, phase: .drawing, strokeCount: 1) == false)
    #expect(
      eligibility.allowsSubmission(
        activeTaskID: taskID, isCancelled: true, phase: .drawing, strokeCount: 1) == false)
    #expect(
      eligibility.allowsSubmission(
        activeTaskID: taskID, isCancelled: false, phase: .recognizing, strokeCount: 1) == false)
  }
}

struct PreferencesTests {
  @Test("registers defaults and records current schema")
  func registersDefaultsAndRecordsCurrentSchema() {
    let defaults = makeDefaults()
    let preferences = Preferences(defaults: defaults)
    #expect(preferences.historyAutoDelete)
    #expect(preferences.historyRetentionDays == 7)
    #expect(preferences.historyMode == .textOnly)
    #expect(preferences.clipboardHandling == .restorePrevious)
    #expect(preferences.verifyPasteDelivery == false)
    #expect(preferences.customWords == CustomWordList(words: []))
    #expect(preferences.recognitionBackendID == "apple-vision")
    #expect(preferences.penUpDelay == 1.2)
    #expect(preferences.inkStyle == .default)
    #expect(defaults.integer(forKey: "schemaVersion") == Preferences.currentSchemaVersion)
  }

  @Test("migrates invalid retention and delay values")
  func migratesInvalidRetentionAndDelayValues() {
    let defaults = makeDefaults()
    defaults.set(0, forKey: "historyRetentionDays")
    defaults.set(50.0, forKey: "penUpDelay")
    let preferences = Preferences(defaults: defaults)
    #expect(preferences.historyRetentionDays == 1)
    #expect(preferences.penUpDelay == 3)
  }

  @Test("persists the selected delivery strategy")
  func persistsDeliveryStrategy() {
    let defaults = makeDefaults()
    let preferences = Preferences(defaults: defaults)
    preferences.outputStrategy = .accessibility
    #expect(Preferences(defaults: defaults).outputStrategy == .accessibility)
  }

  @Test("persists the selected clipboard handling")
  func persistsClipboardHandling() {
    let defaults = makeDefaults()
    let preferences = Preferences(defaults: defaults)
    preferences.clipboardHandling = .leaveRecognizedText
    #expect(Preferences(defaults: defaults).clipboardHandling == .leaveRecognizedText)
  }

  @Test("persists paste verification preference")
  func persistsPasteVerification() {
    let defaults = makeDefaults()
    let preferences = Preferences(defaults: defaults)
    preferences.verifyPasteDelivery = true
    #expect(Preferences(defaults: defaults).verifyPasteDelivery)
  }

  @Test("persists the selected recognition language")
  func persistsRecognitionLanguage() {
    let defaults = makeDefaults()
    let preferences = Preferences(defaults: defaults)
    preferences.recognitionLanguage = .italian
    #expect(Preferences(defaults: defaults).recognitionLanguage == .italian)
  }

  @Test("persists the global recognition backend")
  func persistsRecognitionBackend() {
    let defaults = makeDefaults()
    let preferences = Preferences(defaults: defaults)
    preferences.recognitionBackendID = "google-cloud-vision"
    #expect(Preferences(defaults: defaults).recognitionBackendID == "google-cloud-vision")
  }

  @Test("persists normalized global custom words")
  func persistsCustomWords() {
    let defaults = makeDefaults()
    let preferences = Preferences(defaults: defaults)
    preferences.customWords = CustomWordList(words: [" WriteIt ", "writeit", "cafe\u{301}", ""])

    #expect(Preferences(defaults: defaults).customWords == CustomWordList(
      words: ["WriteIt", "café"]
    ))
  }

  @Test("persists ordered literal replacement rules")
  func persistsLiteralReplacementRules() throws {
    let defaults = makeDefaults()
    let preferences = Preferences(defaults: defaults)
    preferences.literalReplacementRules = LiteralReplacementRules(rules: [
      try LiteralReplacementRule(find: "teh", replacement: "the"),
      try LiteralReplacementRule(find: "Write It", replacement: "WriteIt"),
    ])
    #expect(Preferences(defaults: defaults).literalReplacementRules.applying(to: "teh Write It")
      == "the WriteIt")
  }

  @Test("persists ordered regular-expression replacement rules")
  func persistsRegexReplacementRules() throws {
    let defaults = makeDefaults()
    let preferences = Preferences(defaults: defaults)
    preferences.regexReplacementRules = try RegexReplacementRules(rules: [
      try RegexReplacementRule(pattern: "teh", replacement: "the"),
      try RegexReplacementRule(pattern: "the (cloud)", replacement: "WriteIt $1"),
    ])
    let saved = Preferences(defaults: defaults).regexReplacementRules
    #expect(try RegexReplacementWorker.apply(saved, to: "teh cloud") == "WriteIt cloud")
  }

  @Test("persists the selected stroke smoothing")
  func persistsStrokeSmoothing() {
    let defaults = makeDefaults()
    let preferences = Preferences(defaults: defaults)
    preferences.strokeSmoothing = 0.8
    #expect(Preferences(defaults: defaults).inkStyle.smoothing == 0.8)
  }

  @Test("persists the selected base stroke width")
  func persistsBaseStrokeWidth() {
    let defaults = makeDefaults()
    let preferences = Preferences(defaults: defaults)
    preferences.strokeWidth = 9
    #expect(Preferences(defaults: defaults).inkStyle.baseWidth == 9)
  }

  @Test("surfaces and resets malformed saved settings")
  func surfacesMalformedSavedSettings() {
    let defaults = makeDefaults()
    defaults.set(Data("not-json".utf8), forKey: "shortcut")
    let preferences = Preferences(defaults: defaults)
    #expect(preferences.shortcut == .default)
    #expect(preferences.error?.kind == .persistence)
    #expect(preferences.error?.message == "Some saved settings could not be read and were reset.")
    #expect(defaults.data(forKey: "shortcut") == nil)
  }
}

struct AppProfileStoreTests {
  @Test("persists app profiles with canonical bundle identifiers") @MainActor
  func persistsProfiles() throws {
    let defaults = makeDefaults()
    let profile = try AppProfile(
      id: UUID(uuidString: "56AB413F-9E9F-425A-AEC4-39B45A5B7AB3")!,
      bundleIdentifier: "COM.Example.Editor"
    )
    let store = AppProfileStore(defaults: defaults)

    try store.replaceProfiles([profile])
    let restored = AppProfileStore(defaults: defaults)

    #expect(restored.profiles == [
      try AppProfile(
        id: UUID(uuidString: "56AB413F-9E9F-425A-AEC4-39B45A5B7AB3")!,
        bundleIdentifier: "com.example.editor"
      ),
    ])
    #expect(defaults.integer(forKey: AppProfileStore.schemaVersionDefaultsKey)
      == AppProfileStore.currentSchemaVersion)
  }

  @Test("migrates a profile store without prior profile data") @MainActor
  func migratesEmptyProfileStore() {
    let defaults = makeDefaults()
    defaults.set(0, forKey: AppProfileStore.schemaVersionDefaultsKey)

    let store = AppProfileStore(defaults: defaults)

    #expect(store.profiles.isEmpty)
    #expect(store.error == nil)
    #expect(defaults.integer(forKey: AppProfileStore.schemaVersionDefaultsKey)
      == AppProfileStore.currentSchemaVersion)
  }

  @Test("preserves unreadable profile archives and rejects invalid identifiers") @MainActor
  func rejectsInvalidProfileStorage() throws {
    let defaults = makeDefaults()
    let original = Data("not-json".utf8)
    defaults.set(original, forKey: AppProfileStore.archiveDefaultsKey)
    let store = AppProfileStore(defaults: defaults)

    #expect(store.profiles.isEmpty)
    #expect(store.error == .unreadableArchive)
    #expect(defaults.data(forKey: AppProfileStore.archiveDefaultsKey) == original)
    #expect(throws: AppProfileError.invalidBundleIdentifier) {
      try AppProfile(bundleIdentifier: "com.example editor")
    }
  }

  @Test("migrates profiles to sparse overrides and resolves global fallback") @MainActor
  func migratesProfilesAndResolvesGlobalFallback() throws {
    let defaults = makeDefaults()
    let legacyData = Data(
      """
      {"schema_version":1,"profiles":[{"id":"56AB413F-9E9F-425A-AEC4-39B45A5B7AB3","bundleIdentifier":"COM.Example.Editor"}]}
      """.utf8
    )
    defaults.set(1, forKey: AppProfileStore.schemaVersionDefaultsKey)
    defaults.set(legacyData, forKey: AppProfileStore.archiveDefaultsKey)

    let store = AppProfileStore(defaults: defaults)
    let profile = try #require(store.profile(matching: "com.example.editor"))
    let archived = try #require(defaults.data(forKey: AppProfileStore.archiveDefaultsKey))
    let archive = try #require(
      try JSONSerialization.jsonObject(with: archived) as? [String: Any]
    )

    #expect(profile.overrides == .init())
    #expect(profile.isEnabled)
    #expect(archive["schema_version"] as? Int == AppProfileStore.currentSchemaVersion)
    #expect(AppProfileOverrideResolution.value(profileOverride: "profile", global: "global") == "profile")
    #expect(AppProfileOverrideResolution.value(profileOverride: Optional<String>.none, global: "global")
      == "global")
    #expect(store.profile(matching: "not a bundle ID") == nil)
  }

  @Test("resolves the first matching profile and prefers its override") @MainActor
  func resolvesProfilePrecedenceDeterministically() throws {
    let store = AppProfileStore(defaults: makeDefaults())
    let first = try AppProfile(
      id: UUID(uuidString: "56AB413F-9E9F-425A-AEC4-39B45A5B7AB3")!,
      bundleIdentifier: "com.example.editor"
    )
    let second = try AppProfile(
      id: UUID(uuidString: "AEC439B4-56AB-413F-9E9F-425AA5B7C3D4")!,
      bundleIdentifier: "COM.Example.Editor"
    )
    try store.replaceProfiles([first, second])

    #expect(store.profile(matching: "com.example.editor") == first)
    #expect(AppProfileOverrideResolution.value(
      profileOverride: OutputStrategy.accessibility,
      global: .paste
    ) == .accessibility)
  }

  @Test("resolves a language override only for its matching profile") @MainActor
  func resolvesProfileLanguageOverride() throws {
    let store = AppProfileStore(defaults: makeDefaults())
    try store.replaceProfiles([
      AppProfile(
        bundleIdentifier: "com.example.editor",
        overrides: .init(recognitionLanguage: .french)
      ),
    ])
    let resolver = AppProfileOverrideResolver(profiles: store)

    #expect(resolver.value(
      for: "COM.Example.Editor",
      override: \.recognitionLanguage,
      global: .english
    ) == .french)
    #expect(resolver.value(
      for: "com.example.other",
      override: \.recognitionLanguage,
      global: .english
    ) == .english)
  }

  @Test("resolves a backend model override only for its matching profile") @MainActor
  func resolvesProfileBackendOverride() throws {
    let store = AppProfileStore(defaults: makeDefaults())
    try store.replaceProfiles([
      AppProfile(
        bundleIdentifier: "com.example.editor",
        overrides: .init(recognitionBackendID: "fixture@1.0.0")
      ),
    ])
    let resolver = AppProfileOverrideResolver(profiles: store)

    #expect(resolver.value(
      for: "com.example.editor",
      override: \.recognitionBackendID,
      global: ModelStore.appleVisionModelID
    ) == "fixture@1.0.0")
    #expect(resolver.value(
      for: "com.example.other",
      override: \.recognitionBackendID,
      global: ModelStore.appleVisionModelID
    ) == ModelStore.appleVisionModelID)
  }

  @Test("persists profile backend and cloud-consent mutations") @MainActor
  func persistsProfileBackendAndConsentMutations() throws {
    let defaults = makeDefaults()
    let store = AppProfileStore(defaults: defaults)
    let profile = try AppProfile(bundleIdentifier: "com.example.editor")
    try store.replaceProfiles([profile])

    try store.setRecognitionBackendID("google-cloud-vision", for: profile.id)
    try store.setCloudOCRConsent(CloudOCRConsent(), for: profile.id)
    try store.setAICleanupConsent(AICleanupConsent(), for: profile.id)

    let restored = try #require(
      AppProfileStore(defaults: defaults).profile(matching: "com.example.editor")
    )
    #expect(restored.overrides.recognitionBackendID == "google-cloud-vision")
    #expect(restored.overrides.cloudOCRConsent?.allowsCloudOCR == true)
    #expect(restored.overrides.aiCleanupConsent?.allowsAICleanup == true)
  }

  @Test("resolves an output strategy override only for its matching profile") @MainActor
  func resolvesProfileOutputStrategyOverride() throws {
    let store = AppProfileStore(defaults: makeDefaults())
    try store.replaceProfiles([
      AppProfile(
        bundleIdentifier: "com.example.editor",
        overrides: .init(outputStrategy: .accessibility)
      ),
    ])
    let resolver = AppProfileOverrideResolver(profiles: store)

    #expect(resolver.value(
      for: "com.example.editor",
      override: \.outputStrategy,
      global: .paste
    ) == .accessibility)
    #expect(resolver.value(
      for: "com.example.other",
      override: \.outputStrategy,
      global: .paste
    ) == .paste)
  }

  @Test("resolves a cleanup override only for its matching profile") @MainActor
  func resolvesProfileCleanupOverride() throws {
    let store = AppProfileStore(defaults: makeDefaults())
    try store.replaceProfiles([
      AppProfile(
        bundleIdentifier: "com.example.editor",
        overrides: .init(aiCleanupEnabled: true, aiCleanupConsent: AICleanupConsent())
      ),
    ])
    let resolver = AppProfileOverrideResolver(profiles: store)

    #expect(resolver.value(
      for: "com.example.editor",
      override: \.aiCleanupEnabled,
      global: false
    ))
    #expect(resolver.value(
      for: "com.example.other",
      override: \.aiCleanupEnabled,
      global: false
    ) == false)
  }

  @Test("requires current AI cleanup consent for a matching profile") @MainActor
  func resolvesProfileAICleanupConsent() throws {
    let store = AppProfileStore(defaults: makeDefaults())
    try store.replaceProfiles([
      AppProfile(
        bundleIdentifier: "com.example.allowed",
        overrides: .init(aiCleanupConsent: AICleanupConsent())
      ),
      AppProfile(
        bundleIdentifier: "com.example.stale",
        overrides: .init(aiCleanupConsent: AICleanupConsent(disclosureVersion: 0))
      ),
    ])
    let resolver = AppProfileOverrideResolver(profiles: store)

    #expect(resolver.allowsAICleanup(for: "com.example.allowed"))
    #expect(resolver.allowsAICleanup(for: "com.example.stale") == false)
    #expect(resolver.allowsAICleanup(for: "com.example.unprofiled"))
  }

  @Test("persists a profile custom-word override with global fallback") @MainActor
  func persistsProfileCustomWords() throws {
    let defaults = makeDefaults()
    let global = CustomWordList(words: ["GlobalTerm"])
    let store = AppProfileStore(defaults: defaults)
    try store.replaceProfiles([
      AppProfile(
        bundleIdentifier: "com.example.editor",
        overrides: .init(customWords: CustomWordList(words: ["ProfileTerm", "profileterm"]))
      ),
    ])
    let restored = AppProfileStore(defaults: defaults)
    let resolver = AppProfileOverrideResolver(profiles: restored)

    #expect(resolver.value(
      for: "com.example.editor",
      override: \.customWords,
      global: global
    ) == CustomWordList(words: ["ProfileTerm"]))
    #expect(resolver.value(
      for: "com.example.other",
      override: \.customWords,
      global: global
    ) == global)
  }

  @Test("requires a current cloud OCR acknowledgement for each profile") @MainActor
  func resolvesProfileCloudOCRConsent() throws {
    let defaults = makeDefaults()
    let store = AppProfileStore(defaults: defaults)
    try store.replaceProfiles([
      AppProfile(
        bundleIdentifier: "com.example.allowed",
        overrides: .init(cloudOCRConsent: CloudOCRConsent())
      ),
      AppProfile(
        bundleIdentifier: "com.example.stale",
        overrides: .init(cloudOCRConsent: CloudOCRConsent(disclosureVersion: 0))
      ),
    ])
    let restored = AppProfileStore(defaults: defaults)
    let resolver = AppProfileOverrideResolver(profiles: restored)

    #expect(CloudOCRDisclosure.message
      == "Cloud OCR sends the capture image to the selected cloud provider for recognition.")
    #expect(resolver.allowsCloudOCR(for: "com.example.allowed"))
    #expect(resolver.allowsCloudOCR(for: "com.example.stale") == false)
    #expect(resolver.allowsCloudOCR(for: "com.example.unconfigured") == false)
  }

  @Test("creates and persists a profile for the resolved foreground app") @MainActor
  func createsCurrentAppProfile() throws {
    let defaults = makeDefaults()
    let resolver = TestForegroundApplicationBundleIdentifierResolver()
    resolver.bundleIdentifier = "com.example.editor"
    let store = AppProfileStore(defaults: defaults)
    let creator = CurrentAppProfileCreator(
      profiles: store,
      foregroundApplicationResolver: resolver
    )

    let profile = try creator.create()

    #expect(profile.bundleIdentifier == "com.example.editor")
    #expect(store.profiles == [profile])
    #expect(resolver.resolveRequests == 1)
    #expect(AppProfileStore(defaults: defaults).profiles == [profile])
  }

  @Test("disables duplicate active profiles without discarding them") @MainActor
  func handlesEnabledProfilesAndDuplicates() throws {
    let store = AppProfileStore(defaults: makeDefaults())
    let first = try AppProfile(
      id: UUID(uuidString: "56AB413F-9E9F-425A-AEC4-39B45A5B7AB3")!,
      bundleIdentifier: "com.example.editor"
    )
    let duplicate = try AppProfile(
      id: UUID(uuidString: "AEC439B4-56AB-413F-9E9F-425AA5B7C3D4")!,
      bundleIdentifier: "COM.Example.Editor"
    )

    try store.replaceProfiles([first, duplicate])

    #expect(store.profiles == [first, duplicate.settingEnabled(false)])
    #expect(store.profile(matching: "com.example.editor") == first)
    try store.setEnabled(false, for: first.id)
    try store.setEnabled(true, for: duplicate.id)
    #expect(store.profile(matching: "com.example.editor") == duplicate)
  }

  @Test("creating a profile for an existing app is idempotent") @MainActor
  func preventsDuplicateCurrentAppProfiles() throws {
    let defaults = makeDefaults()
    let store = AppProfileStore(defaults: defaults)
    let existing = try AppProfile(bundleIdentifier: "com.example.editor")
    try store.replaceProfiles([existing])
    let resolver = TestForegroundApplicationBundleIdentifierResolver()
    resolver.bundleIdentifier = "com.example.editor"
    let creator = CurrentAppProfileCreator(
      profiles: store,
      foregroundApplicationResolver: resolver
    )

    #expect(try creator.create() == existing)
    #expect(store.profiles == [existing])
  }

  @Test("refuses profile creation when no foreground app is available") @MainActor
  func rejectsMissingForegroundAppForProfileCreation() {
    let resolver = TestForegroundApplicationBundleIdentifierResolver()
    let creator = CurrentAppProfileCreator(
      profiles: AppProfileStore(defaults: makeDefaults()),
      foregroundApplicationResolver: resolver
    )

    #expect(throws: AppProfileCreationError.foregroundApplicationUnavailable) {
      try creator.create()
    }
  }
}

struct LocalDataDeletionTests {
  @Test("deletes each selected local data category") @MainActor
  func deletesSelectedCategories() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let historyURL = directory.appendingPathComponent("history.sealed")
    let modelsDirectory = directory.appendingPathComponent("Models", isDirectory: true)
    let diagnosticsDirectory = directory.appendingPathComponent("Diagnostics", isDirectory: true)
    let history = HistoryStore(fileURL: historyURL, key: SymmetricKey(size: .bits256))
    history.append(HistoryEntry(text: "private history", strokes: nil, source: "Vision"))
    let models = ModelStore(modelsDirectory: modelsDirectory)
    try Data("model".utf8).write(to: modelsDirectory.appendingPathComponent("staged.asset"))
    try FileManager.default.createDirectory(at: diagnosticsDirectory, withIntermediateDirectories: true)
    try Data("diagnostic".utf8).write(to: diagnosticsDirectory.appendingPathComponent("events.json"))
    let credentials = TestCredentialDataEraser()
    let controller = LocalDataDeletionController(
      eraser: LocalDataEraser(
        history: history,
        models: models,
        diagnosticDirectory: diagnosticsDirectory,
        credentials: credentials
      ))

    controller.delete(Set(LocalDataCategory.allCases))

    #expect(history.entries.isEmpty)
    #expect(FileManager.default.fileExists(atPath: historyURL.path) == false)
    #expect(try FileManager.default.contentsOfDirectory(atPath: modelsDirectory.path).isEmpty)
    #expect(FileManager.default.fileExists(atPath: diagnosticsDirectory.path) == false)
    #expect(credentials.excludedAccounts == [Set([HistoryStore.keychainAccount])])
    #expect(controller.deletedCategories == LocalDataCategory.allCases)
    #expect(controller.error == nil)
  }

  @Test("retains successful deletion state when a later category fails") @MainActor
  func reportsPartialDeletionFailure() {
    let eraser = TestLocalDataEraser(failingCategory: .models)
    let controller = LocalDataDeletionController(eraser: eraser)

    controller.delete([.history, .models, .credentials])

    #expect(eraser.erasedCategories == [.history])
    #expect(controller.deletedCategories == [.history])
    #expect(controller.error?.message == "WriteIt could not delete downloaded models.")
  }
}

struct HistoryStoreTests {
  @Test("retains ink only when full history is selected") @MainActor
  func retainsInkOnlyForFullHistory() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    let fullURL = directory.appendingPathComponent("full.sealed")
    let textOnlyURL = directory.appendingPathComponent("text-only.sealed")
    let key = SymmetricKey(size: .bits256)
    let strokes = [
      InkStroke(points: [
        InkPoint(x: 13, y: 37, pressure: 0.8, timestamp: 0, inputSource: .stylus),
        InkPoint(x: 89, y: 55, pressure: 0.6, timestamp: 0.2, inputSource: .stylus),
      ]),
    ]

    let fullHistory = HistoryStore(fileURL: fullURL, key: key)
    fullHistory.append(text: "full retention", strokes: strokes, mode: .full, source: "Vision")
    #expect(HistoryStore(fileURL: fullURL, key: key).entries.first?.strokes == strokes)
    #expect(try Data(contentsOf: fullURL).range(of: Data("full retention".utf8)) == nil)

    let textOnlyHistory = HistoryStore(fileURL: textOnlyURL, key: key)
    textOnlyHistory.append(
      text: "text-only retention", strokes: strokes, mode: .textOnly, source: "Vision")
    #expect(HistoryStore(fileURL: textOnlyURL, key: key).entries.first?.strokes == nil)
  }

  @Test("removes only entries older than the cutoff") @MainActor
  func removesOnlyEntriesOlderThanCutoff() {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    let history = HistoryStore(
      fileURL: directory.appendingPathComponent("history.sealed"), key: SymmetricKey(size: .bits256)
    )
    let old = HistoryEntry(
      createdAt: Date(timeIntervalSinceNow: -86_400 * 8), text: "old", strokes: nil,
      source: "Vision")
    let current = HistoryEntry(createdAt: Date(), text: "current", strokes: nil, source: "Vision")
    history.append(old)
    history.append(current)
    history.removeEntries(olderThan: Date(timeIntervalSinceNow: -86_400))
    #expect(history.entries.map(\.text) == ["current"])
  }

  @Test("migrates encrypted legacy history into a versioned archive") @MainActor
  func migratesLegacyHistory() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    let fileURL = directory.appendingPathComponent("history.sealed")
    let key = SymmetricKey(size: .bits256)
    let legacyEntries = [HistoryEntry(text: "legacy", strokes: nil, source: "Vision")]
    let clear = try JSONEncoder().encode(legacyEntries)
    let sealed = try #require(AES.GCM.seal(clear, using: key).combined)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try sealed.write(to: fileURL, options: .atomic)

    let history = HistoryStore(fileURL: fileURL, key: key)
    #expect(history.entries == legacyEntries)

    let migrated = try Data(contentsOf: fileURL)
    let box = try AES.GCM.SealedBox(combined: migrated)
    let archiveData = try AES.GCM.open(box, using: key)
    let archive = try JSONDecoder().decode(HistoryArchive.self, from: archiveData)
    #expect(archive.version == HistoryArchive.currentVersion)
    #expect(archive.entries == legacyEntries)
  }

  @Test("fails closed for encrypted archives from a future version") @MainActor
  func rejectsFutureArchiveVersion() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    let fileURL = directory.appendingPathComponent("history.sealed")
    let key = SymmetricKey(size: .bits256)
    let archive = HistoryArchive(
      version: HistoryArchive.currentVersion + 1,
      entries: [HistoryEntry(text: "future", strokes: nil, source: "Vision")]
    )
    let clear = try JSONEncoder().encode(archive)
    let sealed = try #require(AES.GCM.seal(clear, using: key).combined)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try sealed.write(to: fileURL, options: .atomic)

    let history = HistoryStore(fileURL: fileURL, key: key)
    #expect(history.entries.isEmpty)
    #expect(history.error?.message == "Saved history uses an unsupported format.")
    #expect(try Data(contentsOf: fileURL) == sealed)
  }

  @Test("persists candidate confidence, source, and recognition duration") @MainActor
  func persistsRecognitionMetadata() {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    let fileURL = directory.appendingPathComponent("history.sealed")
    let key = SymmetricKey(size: .bits256)
    let history = HistoryStore(fileURL: fileURL, key: key)
    history.append(
      text: "recognized",
      strokes: [],
      mode: .textOnly,
      source: "Apple Vision",
      confidence: 0.92,
      recognitionDuration: 0.18
    )

    let reloaded = HistoryStore(fileURL: fileURL, key: key)
    let entry = reloaded.entries.first
    #expect(entry?.source == "Apple Vision")
    #expect(entry?.model == nil)
    #expect(entry?.language == nil)
    #expect(entry?.delivery == nil)
    #expect(entry?.confidence == 0.92)
    #expect(entry?.recognitionDuration == 0.18)
    #expect(entry?.strokes == nil)
  }

  @Test("persists history source model language and delivery metadata") @MainActor
  func persistsHistoryCaptureMetadata() {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    let fileURL = directory.appendingPathComponent("history.sealed")
    let key = SymmetricKey(size: .bits256)
    let history = HistoryStore(fileURL: fileURL, key: key)
    history.append(
      text: "recognized",
      strokes: [],
      mode: .textOnly,
      source: "apple-vision",
      model: "apple-vision",
      language: .french,
      delivery: HistoryDeliveryMetadata(.pasted(.restorePrevious, .verified))
    )

    let entry = HistoryStore(fileURL: fileURL, key: key).entries.first
    #expect(entry?.source == "apple-vision")
    #expect(entry?.model == "apple-vision")
    #expect(entry?.language == .french)
    #expect(entry?.delivery == HistoryDeliveryMetadata(.pasted(.restorePrevious, .verified)))
  }

  @Test("surfaces history directory setup failures") @MainActor
  func surfacesDirectorySetupFailure() throws {
    let blockedPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data().write(to: blockedPath)
    let history = HistoryStore(
      fileURL: blockedPath.appendingPathComponent("history.sealed"),
      key: SymmetricKey(size: .bits256)
    )
    #expect(history.entries.isEmpty)
    #expect(history.error?.kind == .persistence)
    #expect(history.error?.message == "WriteIt could not prepare local history storage.")
  }

  @Test("does not mutate visible history when persistence fails") @MainActor
  func retainsEntriesWhenPersistenceFails() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    let fileURL = directory.appendingPathComponent("history.sealed")
    let history = HistoryStore(fileURL: fileURL, key: SymmetricKey(size: .bits256))
    try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)
    history.append(HistoryEntry(text: "unsaved", strokes: nil, source: "Vision"))
    #expect(history.entries.isEmpty)
    #expect(history.error?.kind == .persistence)
    #expect(history.error?.message == "WriteIt could not save local history.")
  }

  @Test("does not overwrite unreadable history after surfacing its error") @MainActor
  func preservesUnreadableHistory() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    let fileURL = directory.appendingPathComponent("history.sealed")
    let original = Data("unreadable-history".utf8)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try original.write(to: fileURL)
    let history = HistoryStore(fileURL: fileURL, key: SymmetricKey(size: .bits256))
    history.append(HistoryEntry(text: "new", strokes: nil, source: "Vision"))
    #expect(history.error?.kind == .persistence)
    #expect(try Data(contentsOf: fileURL) == original)
  }
}

struct HistoryRetentionSchedulerTests {
  @Test("retention runs periodically without app activation") @MainActor
  func schedulesPeriodicCleanup() {
    let dependencies = TestDependencies(trusted: true)
    let old = HistoryEntry(
      createdAt: Date(timeIntervalSinceNow: -86_400 * 8), text: "old", strokes: nil, source: "Vision")
    let current = HistoryEntry(createdAt: .now, text: "current", strokes: nil, source: "Vision")
    dependencies.history.append(old)
    dependencies.history.append(current)
    let capture = dependencies.makeCaptureCoordinator()

    capture.start()
    dependencies.historyRetentionScheduler.fire()

    #expect(dependencies.history.entries.map(\.text) == ["current"])
    #expect(dependencies.historyRetentionScheduler.startCount == 1)
    capture.stop()
    #expect(dependencies.historyRetentionScheduler.stopCount == 1)
  }
}

struct KeychainStoreTests {
  @Test("reads, updates, and removes keychain values")
  func roundTripsValue() throws {
    let account = "WriteItTests.\(UUID().uuidString)"
    try KeychainStore.delete(account)
    try KeychainStore.set(Data("first".utf8), for: account)
    #expect(try KeychainStore.data(for: account) == Data("first".utf8))
    try KeychainStore.set(Data("second".utf8), for: account)
    #expect(try KeychainStore.data(for: account) == Data("second".utf8))
    try KeychainStore.delete(account)
    #expect(try KeychainStore.data(for: account) == nil)
  }
}

struct ForegroundApplicationBundleIdentifierResolverTests {
  @Test("resolves only a nonempty frontmost bundle identifier") @MainActor
  func resolvesFrontmostBundleIdentifier() {
    #expect(ForegroundApplicationBundleIdentifierResolver { "com.example.editor" }.resolve()
      == "com.example.editor")
    #expect(ForegroundApplicationBundleIdentifierResolver { nil }.resolve() == nil)
    #expect(ForegroundApplicationBundleIdentifierResolver { "" }.resolve() == nil)
  }
}

struct CaptureCoordinatorLifecycleTests {
  @Test("history retry re-recognizes retained ink in a fresh capture") @MainActor
  func historyRetryRecognizesRetainedInk() async {
    let dependencies = TestDependencies(trusted: true, recognition: SuccessfulRecognition())
    dependencies.preferences.historyMode = .full
    let capture = dependencies.makeCaptureCoordinator()
    let strokes = [
      InkStroke(points: [
        InkPoint(x: 20, y: 30, pressure: 1, timestamp: 0),
        InkPoint(x: 190, y: 70, pressure: 1, timestamp: 0.2),
      ]),
    ]

    capture.retryCapture(HistoryEntry(text: "old", strokes: strokes, source: "Apple Vision"))
    for _ in 0..<8 { await Task.yield() }

    #expect(dependencies.delivery.deliveredRequests.first?.text == "recognized")
    #expect(dependencies.history.entries.first?.text == "recognized")
    #expect(dependencies.history.entries.first?.strokes == strokes)
  }

  @Test("history retry rejects entries without retained ink") @MainActor
  func historyRetryRequiresRetainedInk() {
    let dependencies = TestDependencies(trusted: true, recognition: SuccessfulRecognition())
    let capture = dependencies.makeCaptureCoordinator()

    capture.retryCapture(HistoryEntry(text: "old", strokes: nil, source: "Apple Vision"))

    #expect(capture.session.phase == .idle)
    #expect(dependencies.delivery.deliveryRequests == 0)
    #expect(capture.statusMessage == "This history entry has no ink to retry")
  }

  @Test("clipboard fallback remains visible as delivery recovery") @MainActor
  func surfacesClipboardRecovery() async {
    let dependencies = TestDependencies(trusted: true, recognition: SuccessfulRecognition())
    dependencies.delivery.outcome = .clipboardFallback(.targetNotEditable)
    let capture = dependencies.makeCaptureCoordinator()
    capture.beginCapture()
    capture.session.canvasSize = CGSize(width: 300, height: 120)
    capture.session.beginStroke(at: InkPoint(x: 20, y: 30, pressure: 1, timestamp: 0))
    capture.session.append(point: InkPoint(x: 190, y: 70, pressure: 1, timestamp: 0.2))

    capture.submitCapture()
    for _ in 0..<8 { await Task.yield() }

    #expect(capture.session.deliveryOutcome == .clipboardFallback(.targetNotEditable))
    #expect(capture.error?.kind == .delivery)
    #expect(capture.error?.title == "Copied to clipboard")
  }

  @Test("capture start retains the exact focused editable target") @MainActor
  func retainsFocusedTargetAtCaptureStart() throws {
    let dependencies = TestDependencies(trusted: true)
    let expected = TargetReference(
      element: AXUIElementCreateApplication(getpid()),
      pid: getpid(),
      bundleIdentifier: "com.gongahkia.writeit.tests",
      displayID: 42
    )
    dependencies.delivery.capturedTarget = expected
    let capture = dependencies.makeCaptureCoordinator()

    capture.beginCapture()

    let target = try #require(capture.session.target)
    #expect(CFEqual(target.element, expected.element))
    #expect(target.pid == expected.pid)
    #expect(target.bundleIdentifier == expected.bundleIdentifier)
    #expect(target.displayID == expected.displayID)
    #expect(dependencies.delivery.captureTargetRequests == 1)
    #expect(dependencies.delivery.clearCapturedTargetRequests == 1)

    capture.cancelCapture()

    #expect(capture.session.target == nil)
    #expect(dependencies.delivery.clearCapturedTargetRequests == 2)
  }

  @Test("capture start retains the foreground app bundle identifier") @MainActor
  func retainsForegroundBundleIdentifierAtCaptureStart() {
    let dependencies = TestDependencies(trusted: true)
    dependencies.foregroundApplicationResolver.bundleIdentifier = "com.example.editor"
    let capture = dependencies.makeCaptureCoordinator()

    capture.beginCapture()

    #expect(capture.session.foregroundBundleIdentifier == "com.example.editor")
    #expect(dependencies.foregroundApplicationResolver.resolveRequests == 1)
  }

  @Test("capture uses the matching profile language override") @MainActor
  func usesProfileLanguageOverrideForRecognition() async throws {
    let recognition = RecordingRecognition()
    let dependencies = TestDependencies(trusted: true, recognition: recognition)
    dependencies.foregroundApplicationResolver.bundleIdentifier = "com.example.editor"
    try dependencies.profiles.replaceProfiles([
      AppProfile(
        bundleIdentifier: "com.example.editor",
        overrides: .init(recognitionLanguage: .french)
      ),
    ])
    let capture = dependencies.makeCaptureCoordinator()
    capture.beginCapture()
    capture.session.canvasSize = CGSize(width: 300, height: 120)
    capture.session.beginStroke(at: InkPoint(x: 20, y: 30, pressure: 1, timestamp: 0))
    capture.session.append(point: InkPoint(x: 190, y: 70, pressure: 1, timestamp: 0.2))

    capture.submitCapture()
    for _ in 0..<8 { await Task.yield() }

    let request = try #require(await recognition.requests.first)
    #expect(request.language == .french)
    #expect(request.allowsCloudOCR == false)
  }

  @Test("capture uses the matching profile custom words") @MainActor
  func usesProfileCustomWordsForRecognition() async throws {
    let recognition = RecordingRecognition()
    let dependencies = TestDependencies(trusted: true, recognition: recognition)
    dependencies.preferences.customWords = CustomWordList(words: ["GlobalTerm"])
    dependencies.foregroundApplicationResolver.bundleIdentifier = "com.example.editor"
    try dependencies.profiles.replaceProfiles([
      AppProfile(
        bundleIdentifier: "com.example.editor",
        overrides: .init(customWords: CustomWordList(words: ["ProfileTerm", "profileterm"]))
      ),
    ])
    let capture = dependencies.makeCaptureCoordinator()
    capture.beginCapture()
    capture.session.canvasSize = CGSize(width: 300, height: 120)
    capture.session.beginStroke(at: InkPoint(x: 20, y: 30, pressure: 1, timestamp: 0))
    capture.session.append(point: InkPoint(x: 190, y: 70, pressure: 1, timestamp: 0.2))

    capture.submitCapture()
    for _ in 0..<8 { await Task.yield() }

    let request = try #require(await recognition.requests.first)
    #expect(request.customWords == CustomWordList(words: ["ProfileTerm"]))
  }

  @Test("capture applies literal replacements before optional cleanup") @MainActor
  func appliesLiteralReplacementsBeforeCleanup() async throws {
    let dependencies = TestDependencies(trusted: true, recognition: SuccessfulRecognition())
    dependencies.preferences.aiEnabled = true
    dependencies.preferences.literalReplacementRules = LiteralReplacementRules(rules: [
      try LiteralReplacementRule(find: "recognized", replacement: "corrected"),
    ])
    let capture = dependencies.makeCaptureCoordinator()
    capture.beginCapture()
    capture.session.canvasSize = CGSize(width: 300, height: 120)
    capture.session.beginStroke(at: InkPoint(x: 20, y: 30, pressure: 1, timestamp: 0))
    capture.session.append(point: InkPoint(x: 190, y: 70, pressure: 1, timestamp: 0.2))

    capture.submitCapture()
    for _ in 0..<8 { await Task.yield() }

    #expect(dependencies.enhancer.requests.first?.text == "corrected")
    #expect(dependencies.delivery.deliveredRequests.first?.text == "corrected")
  }

  @Test("capture applies regex replacements after literal replacements") @MainActor
  func appliesRegexReplacementsBeforeCleanup() async throws {
    let dependencies = TestDependencies(trusted: true, recognition: SuccessfulRecognition())
    dependencies.preferences.aiEnabled = true
    dependencies.preferences.literalReplacementRules = LiteralReplacementRules(rules: [
      try LiteralReplacementRule(find: "recognized", replacement: "corrected"),
    ])
    dependencies.preferences.regexReplacementRules = try RegexReplacementRules(rules: [
      try RegexReplacementRule(pattern: "correct(ed)", replacement: "regex-$1"),
    ])
    let capture = dependencies.makeCaptureCoordinator()
    capture.beginCapture()
    capture.session.canvasSize = CGSize(width: 300, height: 120)
    capture.session.beginStroke(at: InkPoint(x: 20, y: 30, pressure: 1, timestamp: 0))
    capture.session.append(point: InkPoint(x: 190, y: 70, pressure: 1, timestamp: 0.2))

    capture.submitCapture()
    for _ in 0..<8 { await Task.yield() }

    #expect(dependencies.enhancer.requests.first?.text == "regex-ed")
    #expect(dependencies.delivery.deliveredRequests.first?.text == "regex-ed")
  }

  @Test("cleanup failure delivers unchanged recognized text with a notice") @MainActor
  func cleanupFailureFallsBackWithoutDataLoss() async throws {
    let dependencies = TestDependencies(trusted: true, recognition: SuccessfulRecognition())
    dependencies.preferences.aiEnabled = true
    dependencies.enhancer.cleanError = RecognitionError.failed("unavailable")
    let capture = dependencies.makeCaptureCoordinator()
    capture.beginCapture()
    capture.session.canvasSize = CGSize(width: 300, height: 120)
    capture.session.beginStroke(at: InkPoint(x: 20, y: 30, pressure: 1, timestamp: 0))
    capture.session.append(point: InkPoint(x: 190, y: 70, pressure: 1, timestamp: 0.2))

    capture.submitCapture()
    for _ in 0..<8 { await Task.yield() }

    #expect(dependencies.delivery.deliveredRequests.first?.text == "recognized")
    #expect(capture.statusMessage.contains("AI cleanup failed; used recognized text unchanged."))
  }

  @Test("capture exposes regular-expression timeout failures") @MainActor
  func exposesRegexReplacementTimeout() async throws {
    let dependencies = TestDependencies(trusted: true, recognition: SuccessfulRecognition())
    dependencies.preferences.regexReplacementRules = try RegexReplacementRules(rules: [
      try RegexReplacementRule(pattern: "recognized", replacement: "corrected"),
    ])
    dependencies.regexReplacer.failure = .timedOut
    let capture = dependencies.makeCaptureCoordinator()
    capture.beginCapture()
    capture.session.canvasSize = CGSize(width: 300, height: 120)
    capture.session.beginStroke(at: InkPoint(x: 20, y: 30, pressure: 1, timestamp: 0))
    capture.session.append(point: InkPoint(x: 190, y: 70, pressure: 1, timestamp: 0.2))

    capture.submitCapture()
    for _ in 0..<8 { await Task.yield() }

    #expect(capture.session.phase == .failed("Regular-expression processing exceeded the time limit."))
    #expect(capture.error?.message == "Regular-expression processing exceeded the time limit.")
  }

  @Test("capture resolves a profile backend before the global default") @MainActor
  func resolvesProfileBackendBeforeGlobalDefault() async throws {
    let dependencies = TestDependencies(trusted: true, recognition: SuccessfulRecognition())
    dependencies.preferences.recognitionBackendID = "global-backend"
    dependencies.foregroundApplicationResolver.bundleIdentifier = "com.example.editor"
    try dependencies.profiles.replaceProfiles([
      AppProfile(
        bundleIdentifier: "com.example.editor",
        overrides: .init(recognitionBackendID: "profile-backend")
      ),
    ])
    let capture = dependencies.makeCaptureCoordinator()
    capture.beginCapture()
    capture.session.canvasSize = CGSize(width: 300, height: 120)
    capture.session.beginStroke(at: InkPoint(x: 20, y: 30, pressure: 1, timestamp: 0))
    capture.session.append(point: InkPoint(x: 190, y: 70, pressure: 1, timestamp: 0.2))

    capture.submitCapture()
    for _ in 0..<8 { await Task.yield() }

    #expect(dependencies.recognitionRegistry.requestedIdentifiers == ["profile-backend"])
  }

  @Test("capture fails visibly when the selected backend is unavailable") @MainActor
  func failsForUnavailableSelectedBackend() {
    let dependencies = TestDependencies(trusted: true, recognition: SuccessfulRecognition())
    dependencies.preferences.recognitionBackendID = "unavailable-backend"
    dependencies.recognitionRegistry.unavailableIdentifiers = ["unavailable-backend"]
    let capture = dependencies.makeCaptureCoordinator()
    capture.beginCapture()
    capture.session.canvasSize = CGSize(width: 300, height: 120)
    capture.session.beginStroke(at: InkPoint(x: 20, y: 30, pressure: 1, timestamp: 0))
    capture.session.append(point: InkPoint(x: 190, y: 70, pressure: 1, timestamp: 0.2))

    capture.submitCapture()

    #expect(capture.session.phase == .failed("The selected OCR provider is unavailable."))
    #expect(capture.statusMessage == "The selected OCR provider is unavailable.")
  }

  @Test("capture passes cloud OCR consent from only the matching profile") @MainActor
  func passesProfileCloudOCRConsentToRecognition() async throws {
    let recognition = RecordingRecognition()
    let dependencies = TestDependencies(trusted: true, recognition: recognition)
    dependencies.foregroundApplicationResolver.bundleIdentifier = "com.example.editor"
    try dependencies.profiles.replaceProfiles([
      AppProfile(
        bundleIdentifier: "com.example.editor",
        overrides: .init(cloudOCRConsent: CloudOCRConsent())
      ),
    ])
    let capture = dependencies.makeCaptureCoordinator()
    capture.beginCapture()
    capture.session.canvasSize = CGSize(width: 300, height: 120)
    capture.session.beginStroke(at: InkPoint(x: 20, y: 30, pressure: 1, timestamp: 0))
    capture.session.append(point: InkPoint(x: 190, y: 70, pressure: 1, timestamp: 0.2))

    capture.submitCapture()
    for _ in 0..<8 { await Task.yield() }

    let request = try #require(await recognition.requests.first)
    #expect(request.allowsCloudOCR)
  }

  @Test("capture uses the matching profile output strategy") @MainActor
  func usesProfileOutputStrategyForDelivery() async throws {
    let dependencies = TestDependencies(trusted: true, recognition: SuccessfulRecognition())
    dependencies.foregroundApplicationResolver.bundleIdentifier = "com.example.editor"
    try dependencies.profiles.replaceProfiles([
      AppProfile(
        bundleIdentifier: "com.example.editor",
        overrides: .init(outputStrategy: .clipboard)
      ),
    ])
    let capture = dependencies.makeCaptureCoordinator()
    capture.beginCapture()
    capture.session.canvasSize = CGSize(width: 300, height: 120)
    capture.session.beginStroke(at: InkPoint(x: 20, y: 30, pressure: 1, timestamp: 0))
    capture.session.append(point: InkPoint(x: 190, y: 70, pressure: 1, timestamp: 0.2))

    capture.submitCapture()
    for _ in 0..<8 { await Task.yield() }

    #expect(dependencies.delivery.deliveredRequests.first?.strategy == .clipboard)
  }

  @Test("explicit clipboard result mode overrides a profile output strategy") @MainActor
  func preservesExplicitClipboardResultMode() async throws {
    let dependencies = TestDependencies(trusted: true, recognition: SuccessfulRecognition())
    dependencies.preferences.resultMode = .clipboard
    dependencies.foregroundApplicationResolver.bundleIdentifier = "com.example.editor"
    try dependencies.profiles.replaceProfiles([
      AppProfile(
        bundleIdentifier: "com.example.editor",
        overrides: .init(outputStrategy: .accessibility)
      ),
    ])
    let capture = dependencies.makeCaptureCoordinator()
    capture.beginCapture()
    capture.session.canvasSize = CGSize(width: 300, height: 120)
    capture.session.beginStroke(at: InkPoint(x: 20, y: 30, pressure: 1, timestamp: 0))
    capture.session.append(point: InkPoint(x: 190, y: 70, pressure: 1, timestamp: 0.2))

    capture.submitCapture()
    for _ in 0..<8 { await Task.yield() }

    #expect(dependencies.delivery.deliveredRequests.first?.strategy == .clipboard)
  }

  @Test("capture uses the matching profile cleanup override") @MainActor
  func usesProfileCleanupOverrideForRecognition() async throws {
    let dependencies = TestDependencies(trusted: true, recognition: SuccessfulRecognition())
    dependencies.foregroundApplicationResolver.bundleIdentifier = "com.example.editor"
    try dependencies.profiles.replaceProfiles([
      AppProfile(
        bundleIdentifier: "com.example.editor",
        overrides: .init(aiCleanupEnabled: true, aiCleanupConsent: AICleanupConsent())
      ),
    ])
    let capture = dependencies.makeCaptureCoordinator()
    capture.beginCapture()
    capture.session.canvasSize = CGSize(width: 300, height: 120)
    capture.session.beginStroke(at: InkPoint(x: 20, y: 30, pressure: 1, timestamp: 0))
    capture.session.append(point: InkPoint(x: 190, y: 70, pressure: 1, timestamp: 0.2))

    capture.submitCapture()
    for _ in 0..<8 { await Task.yield() }

    #expect(dependencies.enhancer.requests.first?.enabled == true)
  }

  @Test("starts and stops shortcut monitoring with Accessibility") @MainActor
  func startsAndStopsShortcutMonitoringWithAccessibility() {
    let dependencies = TestDependencies(trusted: false)
    let model = dependencies.makeCaptureCoordinator()
    model.start()
    #expect(dependencies.shortcutMonitor.starts == 0)
    dependencies.delivery.trusted = true
    model.refreshAccessibility()
    #expect(model.accessibilityGranted)
    #expect(dependencies.shortcutMonitor.starts == 1)
    dependencies.delivery.trusted = false
    model.refreshAccessibility()
    #expect(model.accessibilityGranted == false)
    #expect(dependencies.shortcutMonitor.stops >= 2)
    model.stop()
  }

  @Test("capture commands route shortcut, clear, confirm, and cancel") @MainActor
  func routesCaptureCommands() async {
    let dependencies = TestDependencies(trusted: true, recognition: SuccessfulRecognition())
    dependencies.preferences.resultMode = .review
    let capture = dependencies.makeCaptureCoordinator()
    capture.execute(.shortcut(.down))
    #expect(capture.session.phase == .drawing)
    capture.session.beginStroke(at: InkPoint(x: 20, y: 30, pressure: 1, timestamp: 0))
    capture.execute(.clear)
    #expect(capture.session.strokes.isEmpty)
    capture.session.beginStroke(at: InkPoint(x: 20, y: 30, pressure: 1, timestamp: 0))
    capture.session.append(point: InkPoint(x: 190, y: 70, pressure: 1, timestamp: 0.2))
    capture.execute(.confirm)
    for _ in 0..<8 { await Task.yield() }
    #expect(capture.session.phase == .reviewing)
    capture.execute(.cancel)
    #expect(capture.session.phase == .idle)
  }

  @Test("reviewed captures retain candidate metadata in history") @MainActor
  func retainsCandidateMetadataAfterReview() async throws {
    let dependencies = TestDependencies(trusted: true, recognition: SuccessfulRecognition())
    dependencies.preferences.resultMode = .review
    let capture = dependencies.makeCaptureCoordinator()
    capture.beginCapture()
    capture.session.canvasSize = CGSize(width: 300, height: 120)
    capture.session.beginStroke(at: InkPoint(x: 20, y: 30, pressure: 1, timestamp: 0))
    capture.session.append(point: InkPoint(x: 190, y: 70, pressure: 1, timestamp: 0.2))

    capture.submitCapture()
    for _ in 0..<8 { await Task.yield() }
    #expect(capture.session.phase == .reviewing)
    capture.insertReviewedText()
    for _ in 0..<8 { await Task.yield() }

    let entry = try #require(dependencies.history.entries.first)
    #expect(entry.source == "successful-test")
    #expect(entry.confidence == 1)
    #expect(entry.recognitionDuration != nil)
  }

  @Test("failed recognition preserves ink for an explicit retry") @MainActor
  func retriesFailedRecognition() async {
    let dependencies = TestDependencies(trusted: true)
    let capture = dependencies.makeCaptureCoordinator()
    capture.beginCapture()
    capture.session.canvasSize = CGSize(width: 300, height: 120)
    capture.session.beginStroke(at: InkPoint(x: 20, y: 30, pressure: 1, timestamp: 0))
    capture.session.append(point: InkPoint(x: 190, y: 70, pressure: 1, timestamp: 0.2))
    capture.submitCapture()
    for _ in 0..<4 { await Task.yield() }
    guard case .failed = capture.session.phase else {
      Issue.record("recognition should enter the failed state")
      return
    }
    let strokeCount = capture.session.strokes.count
    capture.retryRecognition()
    for _ in 0..<4 { await Task.yield() }
    guard case .failed = capture.session.phase else {
      Issue.record("retry should surface a recoverable recognition failure")
      return
    }
    #expect(capture.session.strokes.count == strokeCount)
  }

  @Test("cancelling recognition prevents late delivery and history writes") @MainActor
  func cancellingRecognitionPreventsLateEffects() async {
    let dependencies = TestDependencies(trusted: true, recognition: DelayedRecognition())
    let capture = dependencies.makeCaptureCoordinator()
    capture.beginCapture()
    capture.session.canvasSize = CGSize(width: 300, height: 120)
    capture.session.beginStroke(at: InkPoint(x: 20, y: 30, pressure: 1, timestamp: 0))
    capture.session.append(point: InkPoint(x: 190, y: 70, pressure: 1, timestamp: 0.2))
    capture.submitCapture()
    await Task.yield()
    capture.cancelCapture()
    try? await Task.sleep(for: .milliseconds(30))
    #expect(capture.session.phase == .idle)
    #expect(dependencies.delivery.deliveryRequests == 0)
    #expect(dependencies.history.entries.isEmpty)
  }

  @Test("recognition progress reports elapsed time and clears on cancel") @MainActor
  func reportsRecognitionProgress() async throws {
    let dependencies = TestDependencies(trusted: true, recognition: DelayedRecognition())
    let capture = dependencies.makeCaptureCoordinator()
    capture.beginCapture()
    capture.session.canvasSize = CGSize(width: 300, height: 120)
    capture.session.beginStroke(at: InkPoint(x: 20, y: 30, pressure: 1, timestamp: 0))
    capture.session.append(point: InkPoint(x: 190, y: 70, pressure: 1, timestamp: 0.2))
    capture.submitCapture()
    let startedAt = try #require(capture.recognitionStartedAt)
    #expect(capture.recognitionElapsedSeconds(at: startedAt.addingTimeInterval(2.4)) == 2)
    capture.execute(.cancel)
    #expect(capture.recognitionStartedAt == nil)
    #expect(capture.recognitionElapsedSeconds() == nil)
  }

  @Test("new captures discard stale recognition results from prior owned work") @MainActor
  func newCaptureDiscardsStaleRecognition() async {
    let dependencies = TestDependencies(trusted: true, recognition: StaleThenFreshRecognition())
    let capture = dependencies.makeCaptureCoordinator()
    capture.beginCapture()
    capture.session.canvasSize = CGSize(width: 300, height: 120)
    capture.session.beginStroke(at: InkPoint(x: 20, y: 30, pressure: 1, timestamp: 0))
    capture.session.append(point: InkPoint(x: 190, y: 70, pressure: 1, timestamp: 0.2))
    capture.submitCapture()
    await Task.yield()

    capture.beginCapture()
    capture.session.canvasSize = CGSize(width: 300, height: 120)
    capture.session.beginStroke(at: InkPoint(x: 30, y: 40, pressure: 1, timestamp: 0))
    capture.session.append(point: InkPoint(x: 180, y: 80, pressure: 1, timestamp: 0.2))
    capture.submitCapture()
    for _ in 0..<100 {
      guard dependencies.delivery.deliveryRequests == 0 else { break }
      try? await Task.sleep(for: .milliseconds(10))
    }

    #expect(dependencies.delivery.deliveryRequests == 1)
    #expect(dependencies.history.entries.map(\.text) == ["fresh"])
  }

  @Test("cancelling reviewed text prevents its queued delivery") @MainActor
  func cancellingReviewPreventsQueuedDelivery() async {
    let dependencies = TestDependencies(trusted: true, recognition: SuccessfulRecognition())
    dependencies.preferences.resultMode = .review
    let capture = dependencies.makeCaptureCoordinator()
    capture.beginCapture()
    capture.session.canvasSize = CGSize(width: 300, height: 120)
    capture.session.beginStroke(at: InkPoint(x: 20, y: 30, pressure: 1, timestamp: 0))
    capture.session.append(point: InkPoint(x: 190, y: 70, pressure: 1, timestamp: 0.2))
    capture.submitCapture()
    for _ in 0..<8 { await Task.yield() }
    #expect(capture.session.phase == .reviewing)

    capture.insertReviewedText()
    capture.cancelCapture()
    for _ in 0..<4 { await Task.yield() }

    #expect(capture.session.phase == .idle)
    #expect(dependencies.delivery.deliveryRequests == 0)
    #expect(dependencies.history.entries.isEmpty)
  }

  @Test("termination cancels owned recognition before delivery") @MainActor
  func terminationCancelsRecognition() async {
    let dependencies = TestDependencies(trusted: true, recognition: DelayedRecognition())
    let capture = dependencies.makeCaptureCoordinator()
    capture.beginCapture()
    capture.session.canvasSize = CGSize(width: 300, height: 120)
    capture.session.beginStroke(at: InkPoint(x: 20, y: 30, pressure: 1, timestamp: 0))
    capture.session.append(point: InkPoint(x: 190, y: 70, pressure: 1, timestamp: 0.2))
    capture.submitCapture()
    await Task.yield()
    capture.stop()
    try? await Task.sleep(for: .milliseconds(30))
    #expect(capture.session.phase == .idle)
    #expect(dependencies.delivery.deliveryRequests == 0)
    #expect(dependencies.history.entries.isEmpty)
  }

  @Test("retry starts a fresh owned recognition after failure") @MainActor
  func retryStartsFreshRecognition() async {
    let dependencies = TestDependencies(trusted: true, recognition: FailThenSucceedRecognition())
    let capture = dependencies.makeCaptureCoordinator()
    capture.beginCapture()
    capture.session.canvasSize = CGSize(width: 300, height: 120)
    capture.session.beginStroke(at: InkPoint(x: 20, y: 30, pressure: 1, timestamp: 0))
    capture.session.append(point: InkPoint(x: 190, y: 70, pressure: 1, timestamp: 0.2))
    capture.submitCapture()
    for _ in 0..<8 { await Task.yield() }
    guard case .failed = capture.session.phase else {
      Issue.record("first recognition should fail")
      return
    }

    capture.retryRecognition()
    for _ in 0..<8 { await Task.yield() }

    #expect(dependencies.delivery.deliveryRequests == 1)
    #expect(dependencies.history.entries.map(\.text) == ["retried"])
  }
}

private func makeDefaults() -> UserDefaults {
  let name = "WriteItTests.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: name)!
  defaults.removePersistentDomain(forName: name)
  return defaults
}

private func releaseData(assetName: String, assetURL: URL) throws -> Data {
  try JSONSerialization.data(withJSONObject: [
    "draft": false,
    "prerelease": false,
    "assets": [[
      "name": assetName,
      "browser_download_url": assetURL.absoluteString,
    ]],
  ])
}

private actor TestGitHubReleaseRequester: GitHubReleaseRequesting {
  let responses: [URL: GitHubReleaseHTTPResponse]
  private(set) var requests: [URLRequest] = []

  init(responses: [URL: GitHubReleaseHTTPResponse]) {
    self.responses = responses
  }

  func data(for request: URLRequest) async throws -> GitHubReleaseHTTPResponse {
    requests.append(request)
    guard let url = request.url, let response = responses[url] else {
      throw GitHubReleaseManifestError.networkUnavailable
    }
    return response
  }
}

private actor TestGoogleVisionRequester: GoogleVisionRequesting {
  let response: GoogleVisionHTTPResponse
  private(set) var requests: [URLRequest] = []

  init(response: GoogleVisionHTTPResponse) {
    self.response = response
  }

  func data(for request: URLRequest) async throws -> GoogleVisionHTTPResponse {
    requests.append(request)
    return response
  }
}

private actor TestAzureVisionRequester: AzureVisionRequesting {
  let response: AzureVisionHTTPResponse
  private(set) var requests: [URLRequest] = []

  init(response: AzureVisionHTTPResponse) {
    self.response = response
  }

  func data(for request: URLRequest) async throws -> AzureVisionHTTPResponse {
    requests.append(request)
    return response
  }
}

private actor TestCustomOCRProviderRequester: CustomOCRProviderRequesting {
  let response: CustomOCRProviderHTTPResponse
  private(set) var requests: [URLRequest] = []

  init(response: CustomOCRProviderHTTPResponse) {
    self.response = response
  }

  func data(for request: URLRequest) async throws -> CustomOCRProviderHTTPResponse {
    requests.append(request)
    return response
  }
}

@MainActor
private final class TestCloudOCRCredentialStore: CloudOCRCredentialStoring {
  private var values: [String: Data] = [:]

  func data(for account: String) throws -> Data? { values[account] }
  func set(_ data: Data, for account: String) throws { values[account] = data }
  func delete(_ account: String) throws { values.removeValue(forKey: account) }
}

@MainActor
private final class TestConfigurationState: ConfigurationStateManaging {
  private(set) var current: ConfigurationArchive
  private(set) var applied: [ConfigurationArchive] = []
  private(set) var validationStatuses: [CloudOCRProvider: CloudCredentialValidation] = [
    .azureVision: .invalidCredentials
  ]
  private let failingArchive: ConfigurationArchive

  init(current: ConfigurationArchive, failingArchive: ConfigurationArchive) {
    self.current = current
    self.failingArchive = failingArchive
  }

  func snapshot() -> ConfigurationRuntimeSnapshot {
    ConfigurationRuntimeSnapshot(
      archive: current,
      cloudOCRProviders: [],
      cloudOCRValidationStatuses: validationStatuses
    )
  }

  func apply(_ archive: ConfigurationArchive) throws {
    current = archive
    applied.append(archive)
    if archive == failingArchive { throw ConfigurationArchiveError.invalidArchive }
  }

  func restore(_ snapshot: ConfigurationRuntimeSnapshot) throws {
    current = snapshot.archive
    applied.append(snapshot.archive)
    validationStatuses = snapshot.cloudOCRValidationStatuses
  }
}

@MainActor
private final class TestCredentialDataEraser: CredentialDataErasing {
  private(set) var excludedAccounts: [Set<String>] = []

  func eraseAll(excluding accounts: Set<String>) throws { excludedAccounts.append(accounts) }
}

@MainActor
private final class TestLocalDataEraser: LocalDataErasing {
  private(set) var erasedCategories: [LocalDataCategory] = []
  private let failingCategory: LocalDataCategory?

  init(failingCategory: LocalDataCategory? = nil) {
    self.failingCategory = failingCategory
  }

  func erase(_ category: LocalDataCategory) throws {
    if category == failingCategory { throw LocalDataDeletionError.failed(category) }
    erasedCategories.append(category)
  }
}

private struct TestCloudOCRProviderTester: CloudOCRProviderTesting {
  let status: CloudCredentialValidation

  func validate(
    provider: CloudOCRProvider,
    endpoint: URL?,
    apiKey: String
  ) async -> CloudCredentialValidation { status }
}

@MainActor
private final class TestDependencies {
  let defaults = makeDefaults()
  let shortcutMonitor = TestShortcutMonitor()
  let delivery: TestDelivery
  let recognition: any TextRecognizing
  let recognitionRegistry: TestRecognitionBackendSelector
  let regexReplacer = TestRegexReplacer()
  let enhancer = TestEnhancer()
  let overlay = TestOverlay()
  let loginItem = TestLoginItem()
  let historyRetentionScheduler = TestHistoryRetentionScheduler()
  let foregroundApplicationResolver = TestForegroundApplicationBundleIdentifierResolver()
  let profiles: AppProfileStore
  let profileOverrideResolver: AppProfileOverrideResolver
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    UUID().uuidString, isDirectory: true)
  let preferences: Preferences
  let history: HistoryStore

  init(trusted: Bool, recognition: any TextRecognizing = TestRecognition()) {
    delivery = TestDelivery(trusted: trusted)
    self.recognition = recognition
    recognitionRegistry = TestRecognitionBackendSelector(recognizer: recognition)
    preferences = Preferences(defaults: defaults)
    let profileStore = AppProfileStore(defaults: defaults)
    profiles = profileStore
    profileOverrideResolver = AppProfileOverrideResolver(profiles: profileStore)
    history = HistoryStore(
      fileURL: directory.appendingPathComponent("history.sealed"),
      key: SymmetricKey(size: .bits256)
    )
  }

  func makeCaptureCoordinator() -> CaptureCoordinator {
    CaptureCoordinator(
      preferences: preferences,
      history: history,
      session: CaptureSession(),
      shortcutMonitor: shortcutMonitor,
      delivery: delivery,
      recognitionRegistry: recognitionRegistry,
      regexReplacer: regexReplacer,
      enhancer: enhancer,
      overlay: overlay,
      loginItem: loginItem,
      historyRetentionScheduler: historyRetentionScheduler,
      foregroundApplicationResolver: foregroundApplicationResolver,
      profileOverrideResolver: profileOverrideResolver
    )
  }
}

@MainActor
private final class TestRegexReplacementWorkerRunner: RegexReplacementWorkerRunning {
  let failure: RegexReplacementExecutionError?

  init(failure: RegexReplacementExecutionError? = nil) {
    self.failure = failure
  }

  func run(input: Data, timeout: Duration) async throws -> Data {
    if let failure { throw failure }
    return try JSONEncoder().encode(RegexReplacementWorkerResponse(text: input.base64EncodedString(), error: nil))
  }
}

@MainActor
private final class TestRegexReplacer: RegexReplacementApplying {
  var failure: RegexReplacementExecutionError?
  private(set) var requests: [(RegexReplacementRules, String)] = []

  func apply(_ rules: RegexReplacementRules, to text: String) async throws -> String {
    requests.append((rules, text))
    if let failure { throw failure }
    return try RegexReplacementWorker.apply(rules, to: text)
  }
}

private final class TestShortcutMonitor: GlobalShortcutMonitoring {
  var starts = 0
  var stops = 0

  func start(shortcut: Shortcut, handler: @escaping (CaptureCommand) -> Void) { starts += 1 }
  func stop() { stops += 1 }
}

@MainActor
private final class TestForegroundApplicationBundleIdentifierResolver:
  ForegroundApplicationBundleIdentifierResolving
{
  var bundleIdentifier: String?
  private(set) var resolveRequests = 0

  func resolve() -> String? {
    resolveRequests += 1
    return bundleIdentifier
  }
}

@MainActor
private final class TestAccessibilityDeliveryOperations: AccessibilityDeliveryOperating {
  var copySucceeds = true
  var applicationRunning = true
  var editable = true
  var activationSucceeds = true
  var commandSucceeds = true
  var replacementSucceeds = true
  var pasteVerification: PasteDeliveryVerification = .unavailable
  var currentClipboardChangeCount = 0
  private(set) var copiedTexts: [String] = []
  private(set) var activatedPIDs: [pid_t] = []
  private(set) var commandKeyCodes: [CGKeyCode] = []
  private(set) var replacedTexts: [String] = []
  private(set) var restoreCount = 0

  func captureClipboard() -> ClipboardSnapshot { ClipboardSnapshot(items: []) }

  func copy(_ text: String) -> Bool {
    copiedTexts.append(text)
    currentClipboardChangeCount += 1
    return copySucceeds
  }
  func clipboardChangeCount() -> Int { currentClipboardChangeCount }
  func restoreClipboard(_ snapshot: ClipboardSnapshot) -> Bool {
    restoreCount += 1
    return true
  }
  func simulateExternalClipboardChange() { currentClipboardChangeCount += 1 }
  func isApplicationRunning(pid: pid_t) -> Bool { applicationRunning }
  func isActive(pid: pid_t) -> Bool { true }
  func isEditable(_ element: AXUIElement) -> Bool { editable }
  func activate(pid: pid_t) -> Bool {
    activatedPIDs.append(pid)
    return activationSucceeds
  }
  func postCommand(keyCode: CGKeyCode) -> Bool {
    commandKeyCodes.append(keyCode)
    return commandSucceeds
  }
  func verifyPastedText(_ text: String, in element: AXUIElement) async -> PasteDeliveryVerification {
    pasteVerification
  }
  func replaceSelectedText(in element: AXUIElement, with text: String) -> Bool {
    replacedTexts.append(text)
    return replacementSucceeds
  }
}

@MainActor
private final class TestTargetActivationWaiter: TargetActivationWaiting {
  let result: Bool
  private(set) var requestedPIDs: [pid_t] = []

  init(result: Bool) { self.result = result }
  func waitForActivation(pid: pid_t, isActive: @escaping (pid_t) -> Bool) async -> Bool {
    requestedPIDs.append(pid)
    return result
  }
}

@MainActor
private final class TestClipboardRestoreScheduler: ClipboardRestoreScheduling {
  private var actions: [() -> Void] = []
  var pendingCount: Int { actions.count }

  func schedule(_ action: @escaping () -> Void) {
    actions.append(action)
  }
  func runNext() {
    guard actions.isEmpty == false else { return }
    actions.removeFirst()()
  }
}

@MainActor
private final class TestDelivery: AccessibilityDelivering {
  var trusted: Bool
  var capturedTarget: TargetReference?
  private(set) var captureTargetRequests = 0
  private(set) var clearCapturedTargetRequests = 0
  private(set) var deliveryRequests = 0
  private(set) var deliveredRequests: [DeliveryRequest] = []
  var outcome: DeliveryOutcome = .clipboard
  var isTrusted: Bool { trusted }

  init(trusted: Bool) { self.trusted = trusted }
  func requestTrust() {}
  func captureTarget() -> TargetReference? {
    captureTargetRequests += 1
    return capturedTarget
  }
  func clearCapturedTarget() {
    clearCapturedTargetRequests += 1
  }
  func deliver(_ request: DeliveryRequest) async -> DeliveryOutcome {
    deliveryRequests += 1
    deliveredRequests.append(request)
    return outcome
  }
  func undo() {}
}

@MainActor
private final class TestRecognitionBackendSelector: RecognitionBackendSelecting {
  let service: any TextRecognizing
  private(set) var requestedIdentifiers: [String] = []
  var unavailableIdentifiers: Set<String> = []

  init(recognizer: any TextRecognizing) {
    service = recognizer
  }

  var availableBackends: [RecognitionBackendCapabilities] { [service.capabilities] }

  func recognizer(for identifier: String) throws -> any TextRecognizing {
    requestedIdentifiers.append(identifier)
    guard unavailableIdentifiers.contains(identifier) == false else {
      throw RecognitionError.unavailable("The selected OCR provider is unavailable.")
    }
    return service
  }
}

private actor TestRecognition: TextRecognizing {
  nonisolated let capabilities = RecognitionBackendCapabilities(
    identifier: "test",
    displayName: "Test",
    supportedLanguages: [.english],
    isLocal: true,
    supportsStreaming: false,
    availability: .available
  )

  func recognize(_ request: RecognitionRequest) async throws -> RecognitionResult {
    throw RecognitionError.noText
  }
}

private actor CorpusFixtureRecognition: TextRecognizing {
  nonisolated let capabilities = RecognitionBackendCapabilities(
    identifier: "fixture",
    displayName: "Fixture",
    supportedLanguages: Set(RecognitionLanguage.allCases),
    isLocal: true,
    supportsStreaming: false,
    availability: .available
  )

  func recognize(_ request: RecognitionRequest) async throws -> RecognitionResult {
    RecognitionResult(
      text: request.imageData == Data([1]) ? "hallo" : "bonjour",
      confidence: 1,
      backendID: "fixture",
      languageResolution: .identity(request.language)
    )
  }
}

private actor DelayedRecognition: TextRecognizing {
  nonisolated let capabilities = RecognitionBackendCapabilities(
    identifier: "delayed-test",
    displayName: "Delayed Test",
    supportedLanguages: [.english],
    isLocal: true,
    supportsStreaming: false,
    availability: .available
  )

  func recognize(_ request: RecognitionRequest) async throws -> RecognitionResult {
    try await Task.sleep(for: .seconds(1))
    return RecognitionResult(text: "late", confidence: 1, backendID: "delayed-test")
  }
}

private actor SuccessfulRecognition: TextRecognizing {
  nonisolated let capabilities = RecognitionBackendCapabilities(
    identifier: "successful-test",
    displayName: "Successful Test",
    supportedLanguages: [.english],
    isLocal: true,
    supportsStreaming: false,
    availability: .available
  )

  func recognize(_ request: RecognitionRequest) async throws -> RecognitionResult {
    RecognitionResult(text: "recognized", confidence: 1, backendID: "successful-test")
  }
}

private actor RecordingRecognition: TextRecognizing {
  nonisolated let capabilities = RecognitionBackendCapabilities(
    identifier: "recording-test",
    displayName: "Recording Test",
    supportedLanguages: Set(RecognitionLanguage.allCases),
    isLocal: true,
    supportsStreaming: false,
    availability: .available
  )
  private(set) var requests: [RecognitionRequest] = []

  func recognize(_ request: RecognitionRequest) async throws -> RecognitionResult {
    requests.append(request)
    return RecognitionResult(
      text: "recognized",
      confidence: 1,
      backendID: "recording-test",
      languageResolution: .identity(request.language)
    )
  }
}

private actor StaleThenFreshRecognition: TextRecognizing {
  nonisolated let capabilities = RecognitionBackendCapabilities(
    identifier: "sequenced-test",
    displayName: "Sequenced Test",
    supportedLanguages: [.english],
    isLocal: true,
    supportsStreaming: false,
    availability: .available
  )
  private var calls = 0

  func recognize(_ request: RecognitionRequest) async throws -> RecognitionResult {
    calls += 1
    if calls == 1 {
      try? await Task.sleep(for: .milliseconds(20))
      return RecognitionResult(text: "stale", confidence: 1, backendID: "sequenced-test")
    }
    try? await Task.sleep(for: .milliseconds(60))
    return RecognitionResult(text: "fresh", confidence: 1, backendID: "sequenced-test")
  }
}

private actor FailThenSucceedRecognition: TextRecognizing {
  nonisolated let capabilities = RecognitionBackendCapabilities(
    identifier: "retry-test",
    displayName: "Retry Test",
    supportedLanguages: [.english],
    isLocal: true,
    supportsStreaming: false,
    availability: .available
  )
  private var calls = 0

  func recognize(_ request: RecognitionRequest) async throws -> RecognitionResult {
    calls += 1
    if calls == 1 { throw RecognitionError.noText }
    return RecognitionResult(text: "retried", confidence: 1, backendID: "retry-test")
  }
}

@MainActor
private final class TestEnhancer: TextEnhancing {
  private(set) var requests: [TextEnhancementRequest] = []
  var cleanError: Error?

  func clean(_ request: TextEnhancementRequest) async throws -> String {
    requests.append(request)
    if let cleanError { throw cleanError }
    return request.text
  }
  func saveAPIKey(_ value: String) {}
  func hasAPIKey() -> Bool { false }
  func testConnection(baseURL: String, model: String) async -> AICleanupConnectionStatus {
    .notConfigured
  }
}

@MainActor
private final class TestCustomOCRProviderCredentialStore: CustomOCRProviderCredentialStoring {
  private var values: [String: Data] = [:]

  func data(for account: String) throws -> Data? { values[account] }
  func set(_ data: Data, for account: String) throws { values[account] = data }
  func delete(_ account: String) throws { values.removeValue(forKey: account) }
}

private actor TestAICleanupRequester: AICleanupRequesting {
  let response: AICleanupHTTPResponse
  private(set) var requests: [URLRequest] = []

  init(response: AICleanupHTTPResponse) {
    self.response = response
  }

  func data(for request: URLRequest) async throws -> AICleanupHTTPResponse {
    requests.append(request)
    return response
  }
}

@MainActor
private final class TestOverlay: CaptureOverlayPresenting {
  func present(
    session: CaptureSession,
    coordinator: CaptureCoordinator,
    preferences: Preferences
  ) {}
  func dismiss() {}
}

@MainActor
private final class TestLoginItem: LoginItemManaging {
  func update(enabled: Bool) {}
}

@MainActor
private final class TestHistoryRetentionScheduler: HistoryRetentionScheduling {
  private var action: (() -> Void)?
  private(set) var startCount = 0
  private(set) var stopCount = 0

  func start(_ action: @escaping @MainActor @Sendable () -> Void) {
    startCount += 1
    self.action = action
  }

  func stop() {
    stopCount += 1
    action = nil
  }

  func fire() { action?() }
}
