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

struct HistoryStoreTests {
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

struct CaptureCoordinatorLifecycleTests {
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

@MainActor
private final class TestDependencies {
  let defaults = makeDefaults()
  let shortcutMonitor = TestShortcutMonitor()
  let delivery: TestDelivery
  let recognition: any TextRecognizing
  let enhancer = TestEnhancer()
  let overlay = TestOverlay()
  let loginItem = TestLoginItem()
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    UUID().uuidString, isDirectory: true)
  let preferences: Preferences
  let history: HistoryStore

  init(trusted: Bool, recognition: any TextRecognizing = TestRecognition()) {
    delivery = TestDelivery(trusted: trusted)
    self.recognition = recognition
    preferences = Preferences(defaults: defaults)
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
      recognition: recognition,
      enhancer: enhancer,
      overlay: overlay,
      loginItem: loginItem
    )
  }
}

private final class TestShortcutMonitor: GlobalShortcutMonitoring {
  var starts = 0
  var stops = 0

  func start(shortcut: Shortcut, handler: @escaping (CaptureCommand) -> Void) { starts += 1 }
  func stop() { stops += 1 }
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
    return outcome
  }
  func undo() {}
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
  func clean(_ request: TextEnhancementRequest) async throws -> String { request.text }
  func saveAPIKey(_ value: String) {}
  func hasAPIKey() -> Bool { false }
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
