import AppKit
import Combine

@MainActor
final class CaptureCoordinator: ObservableObject {
  @Published private(set) var statusMessage = "Ready"
  @Published private(set) var accessibilityGranted: Bool
  @Published private(set) var error: AppErrorPresentation?
  @Published private(set) var recognitionStartedAt: Date?

  private let preferences: Preferences
  private let history: HistoryStore
  let session: CaptureSession

  private let shortcutMonitor: any GlobalShortcutMonitoring
  private let delivery: any AccessibilityDelivering
  private let recognitionRegistry: any RecognitionBackendSelecting
  private let enhancer: any TextEnhancing
  private let overlay: any CaptureOverlayPresenting
  private let loginItem: any LoginItemManaging
  private let foregroundApplicationResolver: any ForegroundApplicationBundleIdentifierResolving
  private let profileOverrideResolver: AppProfileOverrideResolver
  private var penUpTask: Task<Void, Never>?
  private var penUpTaskID: UUID?
  private var captureTask: Task<Void, Never>?
  private var captureTaskID: UUID?
  private var deliveryTask: Task<Void, Never>?
  private var deliveryTaskID: UUID?
  private var dismissalTask: Task<Void, Never>?
  private var dismissalTaskID: UUID?
  private var accessibilityTimer: Timer?

  init(
    preferences: Preferences,
    history: HistoryStore,
    session: CaptureSession,
    shortcutMonitor: any GlobalShortcutMonitoring,
    delivery: any AccessibilityDelivering,
    recognitionRegistry: any RecognitionBackendSelecting,
    enhancer: any TextEnhancing,
    overlay: any CaptureOverlayPresenting,
    loginItem: any LoginItemManaging,
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
    self.enhancer = enhancer
    self.overlay = overlay
    self.loginItem = loginItem
    self.foregroundApplicationResolver = foregroundApplicationResolver
    self.profileOverrideResolver = profileOverrideResolver
    accessibilityGranted = delivery.isTrusted
    session.onStrokeFinished = { [weak self] in self?.schedulePenUpSubmit() }
  }

  func start() {
    refreshAccessibility(force: true)
    updateLaunchAtLogin()
    cleanupHistory()
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
      )
    )
    let selectedBackendID = profileOverrideResolver.value(
      for: session.foregroundBundleIdentifier,
      override: \.recognitionBackendID,
      global: preferences.recognitionBackendID
    )
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
      ),
      baseURL: preferences.aiBaseURL,
      model: preferences.aiModel
    )
    AppLog.recognition.info(
      "recognition_started language=\(recognitionRequest.language.rawValue, privacy: .public)"
    )
    let taskID = UUID()
    captureTaskID = taskID
    captureTask = Task { [weak self, selectedRecognizer, enhancer] in
      defer { self?.completeCaptureTask(id: taskID) }
      guard let self, self.ownsCaptureTask(taskID) else { return }
      do {
        let candidate = try await selectedRecognizer.recognize(recognitionRequest)
        try Task.checkCancellation()
        guard self.ownsCaptureTask(taskID) else { return }
        guard !candidate.text.isEmpty else { throw RecognitionError.noText }
        let metadata = RecognitionCaptureMetadata(
          source: candidate.backendID,
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
              text: candidate.text,
              enabled: enhancementRequest.enabled,
              baseURL: enhancementRequest.baseURL,
              model: enhancementRequest.model
            ))
        } catch is CancellationError {
          return
        } catch {
          guard self.ownsCaptureTask(taskID) else { return }
          result = candidate.text
          if error is KeychainError {
            let presentation = AppErrorPresentation.security(error)
            self.error = presentation
            notices.append(presentation.message)
          }
        }
        try Task.checkCancellation()
        guard self.ownsCaptureTask(taskID), self.session.phase == .recognizing else { return }
        self.recognitionStartedAt = nil
        self.session.recognizedText = result
        if self.preferences.resultMode == .review {
          guard self.session.transition(to: .reviewing) else { return }
          self.statusMessage = "Review before inserting"
        } else {
          let notice = notices.joined(separator: " ")
          self.finish(
            text: result,
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
