enum ProviderConfigurationStatus: Equatable {
  case notConfigured
  case requiresValidation
  case selectable

  init(isConfigured: Bool, isSelectable: Bool) {
    if isSelectable {
      self = .selectable
    } else if isConfigured {
      self = .requiresValidation
    } else {
      self = .notConfigured
    }
  }

  var title: String {
    switch self {
    case .notConfigured: "Not configured"
    case .requiresValidation: "Test required"
    case .selectable: "Ready"
    }
  }

  var symbol: String {
    switch self {
    case .notConfigured: "key"
    case .requiresValidation: "exclamationmark.triangle"
    case .selectable: "checkmark.circle.fill"
    }
  }
}
