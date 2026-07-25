import Foundation

@MainActor
final class AppRuntime {
  let preferences: Preferences
  let history: HistoryStore
  let models: ModelStore
  let dataDeletion: LocalDataDeletionController
  let diagnostics: DiagnosticEventStore
  let configurationImport: ConfigurationImportController
  let cloudProviders: CloudOCRProviderStore
  let recognitionRegistry: RecognitionBackendRegistry
  let profiles: AppProfileStore
  let profileCreator: CurrentAppProfileCreator
  let session: CaptureSession
  let recognition: RecognitionService
  let capture: CaptureCoordinator

  init(defaults: UserDefaults = .standard) {
    preferences = Preferences(defaults: defaults)
    let historyStore = HistoryStore()
    let modelStore = ModelStore()
    history = historyStore
    models = modelStore
    dataDeletion = LocalDataDeletionController(
      eraser: LocalDataEraser(history: historyStore, models: modelStore))
    diagnostics = DiagnosticEventStore()
    let recognitionService = RecognitionService()
    let cloudProviderStore = CloudOCRProviderStore(defaults: defaults)
    let backendRegistry = RecognitionBackendRegistry(
      localRecognizer: recognitionService,
      cloudProviders: cloudProviderStore
    )
    let profileStore = AppProfileStore(defaults: defaults)
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
      shortcutMonitor: GlobalShortcutMonitor(),
      delivery: AccessibilityTextDelivery(),
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
    AppLog.app.info("runtime_started")
    capture.start()
  }

  func stop() {
    diagnostics.record(.runtimeStopped)
    AppLog.app.info("runtime_stopped")
    capture.stop()
  }
}
