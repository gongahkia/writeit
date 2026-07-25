import Foundation

@MainActor
final class AppRuntime {
  let preferences: Preferences
  let history: HistoryStore
  let models: ModelStore
  let cloudProviders: CloudOCRProviderStore
  let recognitionRegistry: RecognitionBackendRegistry
  let profiles: AppProfileStore
  let profileCreator: CurrentAppProfileCreator
  let session: CaptureSession
  let recognition: RecognitionService
  let capture: CaptureCoordinator

  init(defaults: UserDefaults = .standard) {
    preferences = Preferences(defaults: defaults)
    history = HistoryStore()
    models = ModelStore()
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
      enhancer: AIEnhancer(),
      overlay: CaptureOverlayController.shared,
      loginItem: LoginItemService(),
      foregroundApplicationResolver: foregroundApplicationResolver,
      profileOverrideResolver: profileOverrideResolver
    )
  }

  func start() {
    AppLog.app.info("runtime_started")
    capture.start()
  }

  func stop() {
    AppLog.app.info("runtime_stopped")
    capture.stop()
  }
}
