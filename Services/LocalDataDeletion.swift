import Combine
import Foundation

@MainActor
protocol LocalDataErasing: AnyObject {
  func erase(_ category: LocalDataCategory) throws
}

@MainActor
protocol CredentialDataErasing: AnyObject {
  func eraseAll(excluding accounts: Set<String>) throws
}

@MainActor
final class KeychainCredentialDataEraser: CredentialDataErasing {
  func eraseAll(excluding accounts: Set<String>) throws {
    for account in try KeychainStore.accounts() where accounts.contains(account) == false {
      try KeychainStore.delete(account)
    }
  }
}

enum DiagnosticLogStore {
  static var defaultDirectory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("WriteIt/Diagnostics", isDirectory: true)
  }

  static func erase(at directory: URL) throws {
    guard FileManager.default.fileExists(atPath: directory.path) else { return }
    do {
      try FileManager.default.removeItem(at: directory)
    } catch {
      throw LocalDataDeletionError.failed(.diagnostics)
    }
  }
}

@MainActor
final class LocalDataEraser: LocalDataErasing {
  private let history: HistoryStore
  private let models: ModelStore
  private let diagnosticDirectory: URL
  private let credentials: any CredentialDataErasing

  init(
    history: HistoryStore,
    models: ModelStore,
    diagnosticDirectory: URL = DiagnosticLogStore.defaultDirectory,
    credentials: any CredentialDataErasing = KeychainCredentialDataEraser()
  ) {
    self.history = history
    self.models = models
    self.diagnosticDirectory = diagnosticDirectory
    self.credentials = credentials
  }

  func erase(_ category: LocalDataCategory) throws {
    switch category {
    case .history: try history.erase()
    case .models: try models.eraseAll()
    case .diagnostics: try DiagnosticLogStore.erase(at: diagnosticDirectory)
    case .credentials: try credentials.eraseAll(excluding: [HistoryStore.keychainAccount])
    }
  }
}

@MainActor
final class LocalDataDeletionController: ObservableObject {
  @Published private(set) var deletedCategories: [LocalDataCategory] = []
  @Published private(set) var error: AppErrorPresentation?

  private let eraser: any LocalDataErasing

  init(eraser: any LocalDataErasing) {
    self.eraser = eraser
  }

  func delete(_ categories: Set<LocalDataCategory>) {
    guard categories.isEmpty == false else {
      deletedCategories = []
      error = .persistence(LocalDataDeletionError.noCategories)
      return
    }
    deletedCategories = []
    error = nil
    for category in LocalDataCategory.allCases where categories.contains(category) {
      do {
        try eraser.erase(category)
        deletedCategories.append(category)
      } catch {
        self.error = .persistence(LocalDataDeletionError.failed(category))
        return
      }
    }
  }

  func clearError() { error = nil }
}
