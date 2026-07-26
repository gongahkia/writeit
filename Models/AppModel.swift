import AppKit
import Combine

@MainActor
final class CaptureCoordinator: ObservableObject {
  @Published private(set) var statusMessage = "Ready"
  @Published private(set) var accessibilityGranted: Bool
  @Published private(set) var error: AppErrorPresentation?
  @Published private(set) var recognitionStartedAt: Date?
  @Published private(set) var deliveryTestOutcome: DeliveryOutcome?

  private let preferences: Preferences
  private let history: HistoryStore
  let session: CaptureSession

  private let shortcutMonitor: any GlobalShortcutMonitoring
  private let delivery: any AccessibilityDelivering
  private let recognitionRegistry: any RecognitionBackendSelecting
  private let regexReplacer: any RegexReplacementApplying
  private let enhancer: any TextEnhancing
  private let diagramTranslator: any DiagramTranslating
  private let overlay: any CaptureOverlayPresenting
  private let loginItem: any LoginItemManaging
  private let foregroundApplicationResolver: any ForegroundApplicationBundleIdentifierResolving
  private let profileOverrideResolver: AppProfileOverrideResolver
  private let historyRetentionScheduler: any HistoryRetentionScheduling
  private var penUpTask: Task<Void, Never>?
  private var penUpTaskID: UUID?
  private var captureTask: Task<Void, Never>?
  private var captureTaskID: UUID?
  private var deliveryTask: Task<Void, Never>?
  private var deliveryTaskID: UUID?
  private var dismissalTask: Task<Void, Never>?
  private var dismissalTaskID: UUID?
  private var deliveryTestTask: Task<Void, Never>?
  private var deliveryTestTaskID: UUID?
  private var accessibilityTimer: Timer?

  init(
    preferences: Preferences,
    history: HistoryStore,
    session: CaptureSession,
    shortcutMonitor: any GlobalShortcutMonitoring,
    delivery: any AccessibilityDelivering,
    recognitionRegistry: any RecognitionBackendSelecting,
    regexReplacer: any RegexReplacementApplying,
    enhancer: any TextEnhancing,
    diagramTranslator: any DiagramTranslating,
    overlay: any CaptureOverlayPresenting,
    loginItem: any LoginItemManaging,
    historyRetentionScheduler: any HistoryRetentionScheduling = HistoryRetentionScheduler(),
    foregroundApplicationResolver: any ForegroundApplicationBundleIdentifierResolving =
      ForegroundApplicationBundleIdentifierResolver(),
    profileOverrideResolver: AppProfileOverrideResolver
  ) {
    self.preferences = preferences
    self.history = history
    self.session = session
    self.shortcutMonitor = shortcutMonitor
    self.delivery = delivery
    self.recognitionRegistry = recognitionRegistry
    self.regexReplacer = regexReplacer
    self.enhancer = enhancer
    self.diagramTranslator = diagramTranslator
    self.overlay = overlay
    self.loginItem = loginItem
    self.historyRetentionScheduler = historyRetentionScheduler
    self.foregroundApplicationResolver = foregroundApplicationResolver
    self.profileOverrideResolver = profileOverrideResolver
    accessibilityGranted = delivery.isTrusted
    session.onStrokeFinished = { [weak self] in self?.schedulePenUpSubmit() }
  }

  func start() {
    refreshAccessibility(force: true)
    updateLaunchAtLogin()
    cleanupHistory()
    historyRetentionScheduler.start { [weak self] in self?.cleanupHistory() }
    accessibilityTimer?.invalidate()
    accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refreshAccessibility() }
    }
  }

  func stop() {
    cancelOwnedWork()
    recognitionStartedAt = nil
    accessibilityTimer?.invalidate()
    accessibilityTimer = nil
    historyRetentionScheduler.stop()
    shortcutMonitor.stop()
    dismissPanel()
  }

  func restartShortcutMonitor() {
    guard delivery.isTrusted else {
      shortcutMonitor.stop()
      return
    }
    shortcutMonitor.start(shortcut: preferences.shortcut) { [weak self] command in
      Task { @MainActor in self?.execute(command) }
    }
  }

  func requestAccessibility() {
    delivery.requestTrust()
    refreshAccessibility(force: true)
  }

  func runClipboardDeliveryTest() {
    cancelDeliveryTestTask()
    deliveryTestOutcome = nil
    let taskID = UUID()
    deliveryTestTaskID = taskID
    let request = DeliveryRequest(
      text: "WriteIt delivery test",
      target: nil,
      strategy: .clipboard,
      clipboardHandling: .leaveRecognizedText,
      verifyPaste: false
    )
    deliveryTestTask = Task { [weak self, delivery] in
      defer { self?.completeDeliveryTestTask(id: taskID) }
      let outcome = await delivery.deliver(request)
      guard let self, ownsDeliveryTestTask(taskID) else { return }
      deliveryTestOutcome = outcome
    }
  }

  func refreshAccessibility(force: Bool = false) {
    let trusted = delivery.isTrusted
    guard force || trusted != accessibilityGranted else { return }
    accessibilityGranted = trusted
    if trusted {
      statusMessage = "Accessibility enabled"
      restartShortcutMonitor()
    } else {
      statusMessage = "Enable Accessibility in System Settings"
      shortcutMonitor.stop()
    }
  }

  func beginCapture() {
    cancelOwnedWork()
    recognitionStartedAt = nil
    dismissPanel()
    clearError()
    refreshAccessibility()
    if accessibilityGranted == false { delivery.requestTrust() }
    let foregroundBundleIdentifier = foregroundApplicationResolver.resolve()
    let target = delivery.captureTarget()
    guard session.begin(target: target, foregroundBundleIdentifier: foregroundBundleIdentifier) else {
      return
    }
    overlay.present(session: session, coordinator: self, preferences: preferences)
    guard session.transition(to: .drawing) else {
      dismissPanel()
      return
    }
    AppLog.capture.info(
      "capture_started target_available=\(self.session.target != nil, privacy: .public)")
    statusMessage =
      session.target == nil
      ? "No text field captured; result will be copied"
      : "Write, then press \(preferences.shortcut.displayName) to submit"
  }

  func presentUITestReview() {
    guard UITestConfiguration.isEnabled else { return }
    beginCapture()
    guard session.phase == .drawing else { return }
    session.beginStroke(at: InkPoint(x: 20, y: 20, pressure: 0.5, timestamp: 0))
    session.append(point: InkPoint(x: 180, y: 80, pressure: 0.5, timestamp: 0.1))
    guard session.transition(to: .recognizing) else { return }
    session.recognizedText = "UI test capture"
    session.recordRecognitionMetadata(RecognitionCaptureMetadata(
      source: "apple-vision", model: "apple-vision", language: .english, confidence: 1, duration: 0
    ))
    guard session.transition(to: .reviewing) else { return }
    statusMessage = "Review before inserting"
  }

  func cancelCapture() {
    cancelOwnedWork()
    recognitionStartedAt = nil
    dismissPanel()
    AppLog.capture.info("capture_cancelled")
    statusMessage = "Cancelled"
  }

  func execute(_ command: CaptureCommand) {
    switch command {
    case .cancel:
      guard session.phase.isActive else { return }
      cancelCapture()
    case .clear:
      session.clear()
    case .confirm:
      switch session.phase {
      case .drawing: submitCapture()
      case .reviewing: insertReviewedText()
      case .failed: retryRecognition()
      case .idle, .opening, .recognizing, .delivering, .delivered, .dismissing: break
      }
    case .shortcut(let event):
      handleShortcut(event)
    }
  }

  func clearError() { error = nil }

  func recognitionElapsedSeconds(at date: Date = .now) -> Int? {
    guard session.phase == .recognizing, let recognitionStartedAt else { return nil }
    return max(0, Int(date.timeIntervalSince(recognitionStartedAt)))
  }

  func retryRecognition() {
    guard case .failed = session.phase else { return }
    clearError()
    guard session.transition(to: .drawing) else { return }
    submitCapture()
  }

  func retryCapture(_ entry: HistoryEntry) {
    guard let strokes = entry.strokes, strokes.contains(where: { $0.points.count > 1 }) else {
      statusMessage = "This history entry has no ink to retry"
      return
    }
    beginCapture()
    guard session.phase == .drawing else { return }
    session.strokes = strokes
    statusMessage = "Retrying saved capture"
    submitCapture()
  }

  func submitCapture() {
    guard session.phase == .drawing else { return }
    guard let imageData = session.renderedImageData(style: preferences.inkStyle) else {
      let presentation = AppErrorPresentation.captureInput(
        session.inputValidationMessage() ?? "Write something before recognizing."
      )
      error = presentation
      statusMessage = presentation.message
      return
    }
    clearError()
    cancelPenUpTask()
    cancelCaptureTask()
    cancelDeliveryTask()
    guard session.transition(to: .recognizing) else { return }
    let recognitionStartedAt = Date.now
    self.recognitionStartedAt = recognitionStartedAt
    session.clearRecognitionMetadata()
    let strokes = session.strokes
    let target = session.target
    let recognitionRequest = RecognitionRequest(
      imageData: imageData,
      language: profileOverrideResolver.value(
        for: session.foregroundBundleIdentifier,
        override: \.recognitionLanguage,
        global: preferences.recognitionLanguage
      ),
      allowsCloudOCR: profileOverrideResolver.allowsCloudOCR(
        for: session.foregroundBundleIdentifier
      ),
      customWords: profileOverrideResolver.value(
        for: session.foregroundBundleIdentifier,
        override: \.customWords,
        global: preferences.customWords
      )
    )
    let selectedBackendID = profileOverrideResolver.value(
      for: session.foregroundBundleIdentifier,
      override: \.recognitionBackendID,
      global: preferences.recognitionBackendID
    )
    let literalReplacementRules = preferences.literalReplacementRules
    let regexReplacementRules = preferences.regexReplacementRules
    let mathematicalNotationFormat = preferences.mathematicalNotationFormat
    let aiDiagramFallbackEnabled = preferences.aiDiagramFallbackEnabled
      && profileOverrideResolver.allowsAIDiagramTranslation(
        for: session.foregroundBundleIdentifier,
        globalConsent: preferences.aiDiagramConsent
      )
    let aiDiagramImageData = aiDiagramFallbackEnabled
      ? session.renderedPNGData(style: preferences.inkStyle)
      : nil
    let aiDiagramOutputFormat = preferences.aiDiagramOutputFormat
    let selectedRecognizer: any TextRecognizing
    do {
      selectedRecognizer = try recognitionRegistry.recognizer(for: selectedBackendID)
    } catch {
      completeRecognitionFailure(error)
      return
    }
    let enhancementRequest = TextEnhancementRequest(
      text: "",
      enabled: profileOverrideResolver.value(
        for: session.foregroundBundleIdentifier,
        override: \.aiCleanupEnabled,
        global: preferences.aiEnabled
      ) && profileOverrideResolver.allowsAICleanup(for: session.foregroundBundleIdentifier),
      baseURL: preferences.aiBaseURL,
      model: preferences.aiModel
    )
    AppLog.recognition.info(
      "recognition_started language=\(recognitionRequest.language.rawValue, privacy: .public)"
    )
    let taskID = UUID()
    captureTaskID = taskID
    captureTask = Task { [weak self, selectedRecognizer, regexReplacer, enhancer, diagramTranslator] in
      defer { self?.completeCaptureTask(id: taskID) }
      guard let self, self.ownsCaptureTask(taskID) else { return }
      do {
        let candidate = try await selectedRecognizer.recognize(recognitionRequest)
        try Task.checkCancellation()
        guard self.ownsCaptureTask(taskID) else { return }
        guard !candidate.text.isEmpty else { throw RecognitionError.noText }
        let literalReplacedText = literalReplacementRules.applying(to: candidate.text)
        let replacedText = try await regexReplacer.apply(regexReplacementRules, to: literalReplacedText)
        guard replacedText.isEmpty == false else { throw RecognitionError.noText }
        let metadata = RecognitionCaptureMetadata(
          source: candidate.backendID,
          model: candidate.backendID,
          language: candidate.languageResolution.resolved,
          confidence: candidate.confidence,
          duration: max(0, Date.now.timeIntervalSince(recognitionStartedAt))
        )
        self.session.recordRecognitionMetadata(metadata)
        AppLog.recognition.info(
          "recognition_completed backend=\(candidate.backendID, privacy: .public)"
        )
        let result: String
        var notices: [String] = []
        if candidate.languageResolution.usedFallback {
          notices.append(
            "Used English because \(candidate.languageResolution.requested.displayName) is unavailable.")
        }
        do {
          result = try await enhancer.clean(
            TextEnhancementRequest(
              text: replacedText,
              enabled: enhancementRequest.enabled,
              baseURL: enhancementRequest.baseURL,
              model: enhancementRequest.model
            ))
        } catch is CancellationError {
          return
        } catch {
          guard self.ownsCaptureTask(taskID) else { return }
          result = replacedText
          if error is KeychainError {
            let presentation = AppErrorPresentation.security(error)
            self.error = presentation
            notices.append(presentation.message)
          } else {
            notices.append("AI cleanup failed; used recognized text unchanged.")
          }
        }
        try Task.checkCancellation()
        guard self.ownsCaptureTask(taskID), self.session.phase == .recognizing else { return }
        let formattedResult = MathematicalNotationFormatter.format(result, as: mathematicalNotationFormat)
        self.recognitionStartedAt = nil
        self.session.recognizedText = formattedResult
        let diagram = FlowchartDiagramAnalyzer.analyze(
          strokes: strokes,
          canvasSize: self.session.canvasSize,
          recognizedText: formattedResult
        )
        let aiDiagramTranslation: AIDiagramTranslation?
        if diagram == nil, aiDiagramFallbackEnabled, let aiDiagramImageData {
          do {
            aiDiagramTranslation = try await diagramTranslator.translate(
              AIDiagramTranslationRequest(
                imageData: aiDiagramImageData,
                recognizedText: formattedResult,
                preferredFormat: aiDiagramOutputFormat,
                enabled: true,
                baseURL: enhancementRequest.baseURL,
                model: enhancementRequest.model
              ))
          } catch is CancellationError {
            return
          } catch {
            notices.append("AI diagram translation failed; used recognized text unchanged.")
            aiDiagramTranslation = nil
          }
        } else {
          aiDiagramTranslation = nil
        }
        try Task.checkCancellation()
        guard self.ownsCaptureTask(taskID), self.session.phase == .recognizing else { return }
        self.session.setFlowchartDiagram(diagram)
        self.session.setAIDiagramTranslation(aiDiagramTranslation)
        if self.preferences.resultMode == .review || diagram != nil || aiDiagramTranslation != nil {
          guard self.session.transition(to: .reviewing) else { return }
          self.statusMessage = switch (diagram, aiDiagramTranslation) {
          case (.some, _): "Flowchart detected; review an export or insert text"
          case (_, .some): "AI diagram translated; review an export or insert text"
          case (.none, .none): "Review before inserting"
          }
        } else {
          let notice = notices.joined(separator: " ")
          self.finish(
            text: formattedResult,
            source: candidate.backendID,
            target: target,
            strokes: strokes,
            metadata: metadata,
            notice: notice.isEmpty ? nil : notice
          )
        }
      } catch is CancellationError {
        return
      } catch {
        guard self.ownsCaptureTask(taskID), self.session.phase == .recognizing else { return }
        self.completeRecognitionFailure(error)
      }
    }
  }

  func insertReviewedText() {
    guard session.phase == .reviewing, !session.recognizedText.isEmpty else { return }
    let metadata = session.recognitionMetadata
    finish(
      text: session.recognizedText, source: metadata?.source ?? "Reviewed", target: session.target,
      strokes: session.strokes,
      metadata: metadata,
      notice: nil)
  }

  func undoInsertion() {
    delivery.undo()
    execute(.cancel)
    statusMessage = "Undo sent"
  }

  func saveAPIKey(_ key: String) {
    do {
      try enhancer.saveAPIKey(key)
      clearError()
    } catch {
      self.error = AppErrorPresentation.security(error)
      statusMessage = self.error?.message ?? statusMessage
    }
  }

  func hasAPIKey() -> Bool {
    do {
      return try enhancer.hasAPIKey()
    } catch {
      self.error = .security(error)
      statusMessage = self.error?.message ?? statusMessage
      return false
    }
  }

  func testAIConnection() async -> AICleanupConnectionStatus {
    await enhancer.testConnection(baseURL: preferences.aiBaseURL, model: preferences.aiModel)
  }
  func updateLaunchAtLogin() { loginItem.update(enabled: preferences.launchAtLogin) }

  func cleanupHistory() {
    guard preferences.historyAutoDelete else { return }
    let cutoff =
      Calendar.current.date(byAdding: .day, value: -preferences.historyRetentionDays, to: Date())
      ?? .distantPast
    history.removeEntries(olderThan: cutoff)
  }

  private func handleShortcut(_ event: ShortcutEvent) {
    switch preferences.captureMode {
    case .toggle, .penUpDelay:
      if event == .down {
        switch session.phase {
        case .drawing, .failed: execute(.confirm)
        case .idle: beginCapture()
        case .opening, .recognizing, .reviewing, .delivering, .delivered, .dismissing: break
        }
      }
    case .holdToCapture:
      if event == .down, session.phase.isActive == false { beginCapture() }
      if event == .up, session.phase == .drawing { submitCapture() }
    }
  }

  private func schedulePenUpSubmit() {
    guard preferences.captureMode == .penUpDelay, session.phase == .drawing else { return }
    cancelPenUpTask()
    let taskID = UUID()
    let eligibility = PenUpSubmissionEligibility(taskID: taskID, strokeCount: session.strokes.count)
    penUpTaskID = taskID
    penUpTask = Task { [weak self] in
      defer { self?.completePenUpTask(id: taskID) }
      guard let self else { return }
      do {
        try await Task.sleep(for: .seconds(self.preferences.penUpDelay))
      } catch {
        return
      }
      guard eligibility.allowsSubmission(
        activeTaskID: self.penUpTaskID,
        isCancelled: Task.isCancelled,
        phase: self.session.phase,
        strokeCount: self.session.strokes.count
      )
      else { return }
      self.submitCapture()
    }
  }

  private func finish(
    text: String,
    source: String,
    target: TargetReference?,
    strokes: [InkStroke],
    metadata: RecognitionCaptureMetadata?,
    notice: String?
  ) {
    guard session.transition(to: .delivering) else { return }
    cancelDeliveryTask()
    let foregroundBundleIdentifier = session.foregroundBundleIdentifier
    let taskID = UUID()
    deliveryTaskID = taskID
    deliveryTask = Task { [weak self, delivery] in
      defer { self?.completeDeliveryTask(id: taskID) }
      guard let self, self.ownsDeliveryTask(taskID), self.session.phase == .delivering else { return }
      let strategy: OutputStrategy =
        self.preferences.resultMode == .clipboard
        ? .clipboard
        : self.profileOverrideResolver.value(
          for: foregroundBundleIdentifier,
          override: \.outputStrategy,
          global: self.preferences.outputStrategy
        )
      let outcome = await delivery.deliver(
        DeliveryRequest(
          text: text,
          target: target,
          strategy: strategy,
          clipboardHandling: self.preferences.clipboardHandling,
          verifyPaste: self.preferences.verifyPasteDelivery
        ))
      guard self.ownsDeliveryTask(taskID), self.session.phase == .delivering else { return }
      self.session.recordDeliveryOutcome(outcome)
      self.error = AppErrorPresentation.delivery(outcome)
      self.history.append(
        text: text,
        strokes: strokes,
        mode: self.preferences.historyMode,
        source: source,
        model: metadata?.model,
        language: metadata?.language,
        delivery: HistoryDeliveryMetadata(outcome),
        confidence: metadata?.confidence,
        recognitionDuration: metadata?.duration
      )
      let message = [outcome.message, notice].compactMap { $0 }.joined(separator: " ")
      guard self.session.transition(to: .delivered(message)) else { return }
      self.statusMessage = message
      if self.preferences.resultMode != .review { self.scheduleDismissal() }
    }
  }

  private func completeRecognitionFailure(_ error: Error) {
    recognitionStartedAt = nil
    let presentation = AppErrorPresentation.recognition(error)
    AppLog.recognition.error(
      "recognition_failed type=\(AppLog.errorType(error), privacy: .public)"
    )
    guard session.transition(to: .failed(presentation.message)) else { return }
    self.error = presentation
    statusMessage = presentation.message
  }

  private func cancelOwnedWork() {
    cancelPenUpTask()
    cancelCaptureTask()
    cancelDeliveryTask()
    cancelDeliveryTestTask()
    cancelDismissalTask()
  }

  private func cancelPenUpTask() {
    penUpTask?.cancel()
    penUpTask = nil
    penUpTaskID = nil
  }

  private func cancelCaptureTask() {
    captureTask?.cancel()
    captureTask = nil
    captureTaskID = nil
  }

  private func cancelDeliveryTask() {
    deliveryTask?.cancel()
    deliveryTask = nil
    deliveryTaskID = nil
  }

  private func cancelDeliveryTestTask() {
    deliveryTestTask?.cancel()
    deliveryTestTask = nil
    deliveryTestTaskID = nil
  }

  private func cancelDismissalTask() {
    dismissalTask?.cancel()
    dismissalTask = nil
    dismissalTaskID = nil
  }

  private func ownsCaptureTask(_ taskID: UUID) -> Bool {
    captureTaskID == taskID && Task.isCancelled == false
  }

  private func ownsDeliveryTask(_ taskID: UUID) -> Bool {
    deliveryTaskID == taskID && Task.isCancelled == false
  }

  private func ownsDeliveryTestTask(_ taskID: UUID) -> Bool {
    deliveryTestTaskID == taskID && Task.isCancelled == false
  }

  private func completePenUpTask(id: UUID) {
    guard penUpTaskID == id else { return }
    penUpTask = nil
    penUpTaskID = nil
  }

  private func completeCaptureTask(id: UUID) {
    guard captureTaskID == id else { return }
    captureTask = nil
    captureTaskID = nil
  }

  private func completeDeliveryTask(id: UUID) {
    guard deliveryTaskID == id else { return }
    deliveryTask = nil
    deliveryTaskID = nil
  }

  private func completeDeliveryTestTask(id: UUID) {
    guard deliveryTestTaskID == id else { return }
    deliveryTestTask = nil
    deliveryTestTaskID = nil
  }

  private func scheduleDismissal() {
    cancelDismissalTask()
    let taskID = UUID()
    dismissalTaskID = taskID
    dismissalTask = Task { [weak self] in
      defer { self?.completeDismissalTask(id: taskID) }
      do {
        try await Task.sleep(for: .seconds(1.6))
      } catch {
        return
      }
      guard let self, self.dismissalTaskID == taskID, Task.isCancelled == false,
        self.session.phase.isActive
      else { return }
      self.dismissPanel()
    }
  }

  private func completeDismissalTask(id: UUID) {
    guard dismissalTaskID == id else { return }
    dismissalTask = nil
    dismissalTaskID = nil
  }

  private func dismissPanel() {
    guard session.transition(to: .dismissing) else {
      if session.phase == .idle { delivery.clearCapturedTarget() }
      return
    }
    overlay.dismiss()
    session.completeDismissal()
    delivery.clearCapturedTarget()
  }
}
