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

    var title: String {
      switch self {
      case .builtIn: "Built in"
      case .available: "Not installed"
      case .installed: "Installed"
      }
    }

    var icon: String {
      switch self {
      case .builtIn, .installed: "checkmark.circle"
      case .available: "arrow.down.circle"
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
