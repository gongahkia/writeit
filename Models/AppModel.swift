import AppKit
import Combine

@MainActor
final class AppModel: ObservableObject {
  @Published private(set) var statusMessage = "Ready"
  @Published private(set) var accessibilityGranted: Bool

  let preferences: Preferences
  let history: HistoryStore
  let models: ModelStore
  let session: CaptureSession

  private let shortcutMonitor: any GlobalShortcutMonitoring
  private let delivery: any AccessibilityDelivering
  private let recognition: any TextRecognizing
  private let enhancer: any TextEnhancing
  private let overlay: any CaptureOverlayPresenting
  private let loginItem: any LoginItemManaging
  private var penUpTask: Task<Void, Never>?
  private var accessibilityTimer: Timer?

  init(
    preferences: Preferences,
    history: HistoryStore,
    models: ModelStore,
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
    self.models = models
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
    refreshAccessibility()
    if accessibilityGranted == false { delivery.requestTrust() }
    session.begin(target: delivery.captureTarget())
    overlay.present(session: session, model: self)
    statusMessage =
      session.target == nil
      ? "No text field captured; result will be copied"
      : "Write, then press \(preferences.shortcut.displayName) to submit"
  }

  func cancelCapture() {
    penUpTask?.cancel()
    session.cancel()
    overlay.dismiss()
    statusMessage = "Cancelled"
  }

  func submitCapture() {
    guard session.phase == .drawing, let image = session.renderedImage() else {
      if session.phase == .drawing { statusMessage = "Write something first" }
      return
    }
    penUpTask?.cancel()
    session.phase = .recognizing
    let strokes = session.strokes
    let target = session.target
    Task { [weak self] in
      guard let self else { return }
      guard let candidate = await recognition.recognize(image: image), !candidate.text.isEmpty
      else {
        self.session.phase = .drawing
        self.statusMessage = "No handwriting recognized"
        return
      }
      let result = await enhancer.clean(candidate.text, preferences: preferences)
      guard self.session.phase == .recognizing else { return }
      self.session.recognizedText = result
      if self.preferences.resultMode == .review {
        self.session.phase = .reviewing
        self.statusMessage = "Review before inserting"
      } else {
        self.finish(text: result, source: candidate.source, target: target, strokes: strokes)
      }
    }
  }

  func insertReviewedText() {
    guard !session.recognizedText.isEmpty else { return }
    finish(
      text: session.recognizedText, source: "Reviewed", target: session.target,
      strokes: session.strokes)
  }

  func undoInsertion() {
    delivery.undo()
    cancelCapture()
    statusMessage = "Undo sent"
  }

  func saveAPIKey(_ key: String) { enhancer.saveAPIKey(key) }
  func hasAPIKey() -> Bool { enhancer.hasAPIKey() }
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
      if event == .down { session.phase.isActive ? submitCapture() : beginCapture() }
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

  private func finish(text: String, source: String, target: TargetReference?, strokes: [InkStroke])
  {
    let outcome = delivery.deliver(text, to: target, mode: preferences.resultMode)
    history.append(text: text, strokes: strokes, mode: preferences.historyMode, source: source)
    session.phase = .delivered(outcome.message)
    statusMessage = outcome.message
    if preferences.resultMode != .review {
      Task { [weak self] in
        try? await Task.sleep(for: .seconds(1.6))
        guard let self, self.session.phase.isActive else { return }
        self.session.cancel()
        self.overlay.dismiss()
      }
    }
  }
}
