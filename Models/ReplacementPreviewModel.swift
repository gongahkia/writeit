import Combine
import Foundation

@MainActor
final class ReplacementPreviewModel: ObservableObject {
  @Published var sampleText = "" { didSet { refresh() } }
  @Published private(set) var previewText = ""
  @Published private(set) var errorMessage: String?

  private let regexReplacer: any RegexReplacementApplying
  private var literalRules = LiteralReplacementRules()
  private var regexRules = RegexReplacementRules()
  private var task: Task<Void, Never>?
  private var taskID: UUID?

  init(regexReplacer: any RegexReplacementApplying) {
    self.regexReplacer = regexReplacer
  }

  func updateRules(literal: LiteralReplacementRules, regex: RegexReplacementRules) {
    literalRules = literal
    regexRules = regex
    refresh()
  }

  func clear() { sampleText = "" }

  private func refresh() {
    task?.cancel()
    task = nil
    taskID = nil
    let literalPreview = literalRules.applying(to: sampleText)
    previewText = literalPreview
    errorMessage = nil
    guard regexRules.rules.isEmpty == false else { return }
    let id = UUID()
    taskID = id
    let regexRules = regexRules
    let regexReplacer = regexReplacer
    task = Task { [weak self, regexRules, regexReplacer] in
      do {
        let preview = try await regexReplacer.apply(regexRules, to: literalPreview)
        try Task.checkCancellation()
        guard let self, self.taskID == id else { return }
        self.previewText = preview
        self.task = nil
        self.taskID = nil
      } catch is CancellationError {
        return
      } catch {
        guard let self, self.taskID == id else { return }
        self.errorMessage = (error as? LocalizedError)?.errorDescription
          ?? "Replacement preview failed."
        self.task = nil
        self.taskID = nil
      }
    }
  }
}
