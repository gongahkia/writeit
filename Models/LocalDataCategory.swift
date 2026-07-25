import Foundation

enum LocalDataCategory: String, CaseIterable, Hashable, Identifiable {
  case history
  case models
  case diagnostics
  case metrics
  case credentials

  var id: String { rawValue }
  var title: String {
    switch self {
    case .history: "History"
    case .models: "Downloaded models"
    case .diagnostics: "Diagnostic logs"
    case .metrics: "Anonymous metrics"
    case .credentials: "Saved credentials"
    }
  }
  var detail: String {
    switch self {
    case .history: "Recognized text and retained ink"
    case .models: "Downloaded model assets and paused downloads"
    case .diagnostics: "App-owned local diagnostic files"
    case .metrics: "Locally queued anonymous lifecycle events"
    case .credentials: "API keys and bearer tokens in Keychain"
    }
  }
}

enum LocalDataDeletionError: LocalizedError, Equatable {
  case noCategories
  case failed(LocalDataCategory)

  var errorDescription: String? {
    switch self {
    case .noCategories: "Choose at least one data category to delete."
    case .failed(let category): "WriteIt could not delete \(category.title.lowercased())."
    }
  }
}
