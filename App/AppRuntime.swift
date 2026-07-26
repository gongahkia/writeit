import Foundation

@MainActor
final class AppRuntime {
  let preferences: Preferences
  let history: HistoryStore
  let models: ModelStore
  let customModelSource: CustomHTTPSModelSourceStore
  let dataDeletion: LocalDataDeletionController
  let onboarding: OnboardingStore
  let diagnostics: DiagnosticEventStore
  let metrics: AnonymousMetricsQueue
  let configurationImport: ConfigurationImportController
  let cloudProviders: CloudOCRProviderStore
  let recognitionRegistry: RecognitionBackendRegistry
  let profiles: AppProfileStore
  let profileCreator: CurrentAppProfileCreator
  let session: CaptureSession
  let recognition: RecognitionService
  let capture: CaptureCoordinator

  init(defaults: UserDefaults = .standard) {
    let runtimeDefaults = UITestConfiguration.defaults(fallback: defaults)
    preferences = Preferences(defaults: runtimeDefaults)
    onboarding = OnboardingStore(defaults: runtimeDefaults)
    let historyStore = HistoryStore()
    let modelStore = ModelStore()
    let customModelSourceStore = CustomHTTPSModelSourceStore(defaults: runtimeDefaults)
    let diagnosticStore = DiagnosticEventStore(retainsLocalLogs: preferences.retainsLocalLogs)
    let metricsQueue = AnonymousMetricsQueue(hasConsent: preferences.allowsAnonymousMetrics)
    history = historyStore
    models = modelStore
    customModelSource = customModelSourceStore
    dataDeletion = LocalDataDeletionController(
      eraser: LocalDataEraser(
        history: historyStore,
        models: modelStore,
        diagnostics: diagnosticStore,
        metrics: metricsQueue
      ))
    diagnostics = diagnosticStore
    metrics = metricsQueue
    let recognitionService = RecognitionService()
    let cloudProviderStore = CloudOCRProviderStore(defaults: defaults)
    let backendRegistry = RecognitionBackendRegistry(
      localRecognizer: UITestConfiguration.isEnabled ? UITestRecognitionBackend() : recognitionService,
      cloudProviders: cloudProviderStore
    )
    let profileStore = AppProfileStore(defaults: runtimeDefaults)
    let foregroundApplicationResolver = ForegroundApplicationBundleIdentifierResolver()
    let profileOverrideResolver = AppProfileOverrideResolver(profiles: profileStore)
    profiles = profileStore
    configurationImport = ConfigurationImportController(
      state: ConfigurationStateStore(
        preferences: preferences,
        profiles: profileStore,
        cloudProviders: cloudProviderStore
      ))
    profileCreator = CurrentAppProfileCreator(
      profiles: profileStore,
      foregroundApplicationResolver: foregroundApplicationResolver
    )
    session = CaptureSession()
    cloudProviders = cloudProviderStore
    recognitionRegistry = backendRegistry
    recognition = recognitionService
    capture = CaptureCoordinator(
      preferences: preferences,
      history: history,
      session: session,
      shortcutMonitor: UITestConfiguration.isEnabled ? UITestShortcutMonitor() : GlobalShortcutMonitor(),
      delivery: UITestConfiguration.isEnabled ? UITestAccessibilityDelivery() : AccessibilityTextDelivery(),
      recognitionRegistry: backendRegistry,
      regexReplacer: RegexReplacementService(),
      enhancer: AIEnhancer(),
      overlay: CaptureOverlayController.shared,
      loginItem: LoginItemService(),
      historyRetentionScheduler: HistoryRetentionScheduler(),
      foregroundApplicationResolver: foregroundApplicationResolver,
      profileOverrideResolver: profileOverrideResolver
    )
  }

  func start() {
    diagnostics.record(.runtimeStarted)
    metrics.enqueue(.runtimeStarted)
    AppLog.app.info("runtime_started")
    capture.start()
  }

  func stop() {
    diagnostics.record(.runtimeStopped)
    metrics.enqueue(.runtimeStopped)
    AppLog.app.info("runtime_stopped")
    capture.stop()
  }
}
