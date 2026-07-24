import AppKit
import Combine

@MainActor
final class CaptureCoordinator: ObservableObject {
  @Published private(set) var statusMessage = "Ready"
  @Published private(set) var accessibilityGranted: Bool
  @Published private(set) var error: AppErrorPresentation?

  private let preferences: Preferences
  private let history: HistoryStore
  let session: CaptureSession

  private let shortcutMonitor: any GlobalShortcutMonitoring
  private let delivery: any AccessibilityDelivering
  private let recognition: any TextRecognizing
  private let enhancer: any TextEnhancing
  private let overlay: any CaptureOverlayPresenting
  private let loginItem: any LoginItemManaging
  private var penUpTask: Task<Void, Never>?
  private var captureTask: Task<Void, Never>?
  private var dismissalTask: Task<Void, Never>?
  private var accessibilityTimer: Timer?

  init(
    preferences: Preferences,
    history: HistoryStore,
    session: CaptureSession,
    shortcutMonitor: any GlobalShortcutMonitoring,
    delivery: any AccessibilityDelivering,
    recognition: any TextRecognizing,
    enhancer: any TextEnhancing,
    overlay: any CaptureOverlayPresenting,
    loginItem: any LoginItemManaging
  ) {
    self.preferences = preferences
    self.history = history
    self.session = session
    self.shortcutMonitor = shortcutMonitor
    self.delivery = delivery
    self.recognition = recognition
    self.enhancer = enhancer
    self.overlay = overlay
    self.loginItem = loginItem
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
    penUpTask?.cancel()
    captureTask?.cancel()
    dismissalTask?.cancel()
    accessibilityTimer?.invalidate()
    accessibilityTimer = nil
    shortcutMonitor.stop()
    session.cancel()
    overlay.dismiss()
  }

  func restartShortcutMonitor() {
    guard delivery.isTrusted else {
      shortcutMonitor.stop()
      return
    }
    shortcutMonitor.start(shortcut: preferences.shortcut) { [weak self] event in
      Task { @MainActor in self?.handleShortcut(event) }
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
    clearError()
    refreshAccessibility()
    if accessibilityGranted == false { delivery.requestTrust() }
    session.begin(target: delivery.captureTarget())
    overlay.present(session: session, coordinator: self, preferences: preferences)
    AppLog.capture.info(
      "capture_started target_available=\(self.session.target != nil, privacy: .public)")
    statusMessage =
      session.target == nil
      ? "No text field captured; result will be copied"
      : "Write, then press \(preferences.shortcut.displayName) to submit"
  }

  func cancelCapture() {
    penUpTask?.cancel()
    captureTask?.cancel()
    dismissalTask?.cancel()
    session.cancel()
    overlay.dismiss()
    AppLog.capture.info("capture_cancelled")
    statusMessage = "Cancelled"
  }

  func clearError() { error = nil }

  func retryRecognition() {
    guard case .failed = session.phase else { return }
    clearError()
    session.phase = .drawing
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
    penUpTask?.cancel()
    captureTask?.cancel()
    session.phase = .recognizing
    let strokes = session.strokes
    let target = session.target
    let recognitionRequest = RecognitionRequest(
      imageData: imageData,
      language: preferences.recognitionLanguage
    )
    let enhancementRequest = TextEnhancementRequest(
      text: "",
      enabled: preferences.aiEnabled,
      baseURL: preferences.aiBaseURL,
      model: preferences.aiModel
    )
    AppLog.recognition.info(
      "recognition_started language=\(recognitionRequest.language.rawValue, privacy: .public)"
    )
    captureTask = Task { [weak self, recognition, enhancer] in
      guard let self else { return }
      defer { self.captureTask = nil }
      do {
        let candidate = try await recognition.recognize(recognitionRequest)
        try Task.checkCancellation()
        guard !candidate.text.isEmpty else { throw RecognitionError.noText }
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
          result = candidate.text
          if error is KeychainError {
            let presentation = AppErrorPresentation.security(error)
            self.error = presentation
            notices.append(presentation.message)
          }
        }
        try Task.checkCancellation()
        guard self.session.phase == .recognizing else { return }
        self.session.recognizedText = result
        if self.preferences.resultMode == .review {
          self.session.phase = .reviewing
          self.statusMessage = "Review before inserting"
        } else {
          let notice = notices.joined(separator: " ")
          self.finish(
            text: result,
            source: candidate.backendID,
            target: target,
            strokes: strokes,
            notice: notice.isEmpty ? nil : notice
          )
        }
      } catch is CancellationError {
        return
      } catch {
        guard self.session.phase == .recognizing else { return }
        let presentation = AppErrorPresentation.recognition(error)
        AppLog.recognition.error(
          "recognition_failed type=\(AppLog.errorType(error), privacy: .public)"
        )
        self.session.phase = .failed(presentation.message)
        self.error = presentation
        self.statusMessage = presentation.message
      }
    }
  }

  func insertReviewedText() {
    guard !session.recognizedText.isEmpty else { return }
    finish(
      text: session.recognizedText, source: "Reviewed", target: session.target,
      strokes: session.strokes,
      notice: nil)
  }

  func undoInsertion() {
    delivery.undo()
    cancelCapture()
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
        case .drawing: submitCapture()
        case .failed: retryRecognition()
        case .idle: beginCapture()
        case .recognizing, .reviewing, .delivered: break
        }
      }
    case .holdToCapture:
      if event == .down, session.phase.isActive == false { beginCapture() }
      if event == .up, session.phase == .drawing { submitCapture() }
    }
  }

  private func schedulePenUpSubmit() {
    guard preferences.captureMode == .penUpDelay, session.phase == .drawing else { return }
    penUpTask?.cancel()
    let count = session.strokes.count
    penUpTask = Task { [weak self] in
      guard let self else { return }
      try? await Task.sleep(for: .seconds(self.preferences.penUpDelay))
      guard Task.isCancelled == false, self.session.phase == .drawing,
        self.session.strokes.count == count
      else { return }
      self.submitCapture()
    }
  }

  private func finish(
    text: String,
    source: String,
    target: TargetReference?,
    strokes: [InkStroke],
    notice: String?
  ) {
    let strategy: OutputStrategy =
      preferences.resultMode == .clipboard ? .clipboard : preferences.outputStrategy
    let outcome = delivery.deliver(
      DeliveryRequest(
        text: text,
        target: target,
        strategy: strategy,
        clipboardHandling: .leaveRecognizedText
      ))
    history.append(text: text, strokes: strokes, mode: preferences.historyMode, source: source)
    let message = [outcome.message, notice].compactMap { $0 }.joined(separator: " ")
    session.phase = .delivered(message)
    statusMessage = message
    if preferences.resultMode != .review {
      dismissalTask?.cancel()
      dismissalTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(1.6))
        guard Task.isCancelled == false, let self, self.session.phase.isActive else { return }
        self.session.cancel()
        self.overlay.dismiss()
        self.dismissalTask = nil
      }
    }
  }
}
