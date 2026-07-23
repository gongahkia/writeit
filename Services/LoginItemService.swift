import ServiceManagement

@MainActor
final class LoginItemService: LoginItemManaging {
  func update(enabled: Bool) {
    if enabled {
      try? SMAppService.mainApp.register()
    } else {
      try? SMAppService.mainApp.unregister()
    }
  }
}
