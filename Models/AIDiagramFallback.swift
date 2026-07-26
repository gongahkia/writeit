import Foundation

enum AIDiagramOutputFormat: String, CaseIterable, Codable, Identifiable, Sendable {
  case mermaid
  case plantUML = "plantuml"

  var id: String { rawValue }
  var title: String {
    switch self {
    case .mermaid: "Mermaid"
    case .plantUML: "PlantUML"
    }
  }
  var fileExtension: String {
    switch self {
    case .mermaid: "mmd"
    case .plantUML: "puml"
    }
  }
}

enum AIDiagramType: String, Codable, Sendable {
  case flowchart
  case classDiagram = "class"
  case sequence
  case state
  case useCase = "usecase"

  var title: String {
    switch self {
    case .flowchart: "flowchart"
    case .classDiagram: "class diagram"
    case .sequence: "sequence diagram"
    case .state: "state diagram"
    case .useCase: "use-case diagram"
    }
  }
}

struct AIDiagramTranslation: Equatable, Sendable {
  let type: AIDiagramType
  let format: AIDiagramOutputFormat
  let source: String
}

struct AIDiagramTranslationRequest: Sendable {
  let imageData: Data
  let recognizedText: String
  let preferredFormat: AIDiagramOutputFormat
  let enabled: Bool
  let baseURL: String
  let model: String
}

enum AIDiagramTranslationError: LocalizedError, Equatable {
  case invalidModel
  case invalidImage
  case invalidResponse
  case responseTooLarge

  var errorDescription: String? {
    switch self {
    case .invalidModel: "AI diagram model is invalid."
    case .invalidImage: "AI diagram translation requires a PNG capture image."
    case .invalidResponse: "AI diagram translation did not return a usable diagram."
    case .responseTooLarge: "AI diagram translation returned too much data."
    }
  }
}
