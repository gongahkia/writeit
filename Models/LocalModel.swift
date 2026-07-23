import Foundation

enum ModelCatalogTab: String, CaseIterable, Identifiable {
  case local
  case cloud
  case custom

  var id: String { rawValue }
  var title: String { rawValue.capitalized }
}

struct LocalModel: Identifiable, Hashable {
  enum Status: Hashable {
    case builtIn
    case available
    case installed
    case experimental
    case configurationRequired
    case unavailable

    var title: String {
      switch self {
      case .builtIn: "Built in"
      case .available: "Not installed"
      case .installed: "Installed"
      case .experimental: "Experimental"
      case .configurationRequired: "Configuration required"
      case .unavailable: "Unavailable"
      }
    }

    var icon: String {
      switch self {
      case .builtIn, .installed: "checkmark.circle"
      case .available: "arrow.down.circle"
      case .experimental: "flask"
      case .configurationRequired: "key"
      case .unavailable: "exclamationmark.triangle"
      }
    }
  }

  var id: String
  var name: String
  var language: String
  var footprint: String
  var description: String
  var status: Status
}
