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
    #expect(DeliveryOutcome.pasted(.leaveRecognizedText) != .pasted(.restorePrevious))
  }
}

struct CaptureModelTests {
  @Test("shortcuts round-trip through storage")
  func shortcutsRoundTrip() throws {
    let shortcut = Shortcut(
      keyCode: 13, modifiers: CGEventFlags.maskCommand.union(.maskShift).rawValue)
    let decoded = try JSONDecoder().decode(Shortcut.self, from: JSONEncoder().encode(shortcut))
    #expect(decoded == shortcut)
    #expect(decoded.displayName == "⇧⌘W")
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
private final class TestDelivery: AccessibilityDelivering {
  var trusted: Bool
  private(set) var deliveryRequests = 0
  var isTrusted: Bool { trusted }

  init(trusted: Bool) { self.trusted = trusted }
  func requestTrust() {}
  func captureTarget() -> TargetReference? { nil }
  func deliver(_ request: DeliveryRequest) -> DeliveryOutcome {
    deliveryRequests += 1
    return .clipboard
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
