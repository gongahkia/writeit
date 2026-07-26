import Foundation

enum UMLDiagramExportFormat: String, CaseIterable, Identifiable, Sendable {
  case plantUML = "plantuml"
  case mermaid
  case svg
  case excalidraw

  var id: String { rawValue }
  var title: String {
    switch self {
    case .plantUML: "PlantUML"
    case .mermaid: "Mermaid"
    case .svg: "SVG"
    case .excalidraw: "Excalidraw JSON"
    }
  }
  var fileExtension: String {
    switch self {
    case .plantUML: "puml"
    case .mermaid: "mmd"
    case .svg: "svg"
    case .excalidraw: "excalidraw"
    }
  }
}

enum UMLDiagramExportError: LocalizedError, Equatable {
  case noDiagram
  case unsupportedFormat
  case encodingFailed

  var errorDescription: String? {
    switch self {
    case .noDiagram: "No qualified UML diagram was detected in this capture."
    case .unsupportedFormat: "This UML diagram cannot be exported in that format."
    case .encodingFailed: "WriteIt could not encode this UML diagram."
    }
  }
}

enum UMLDiagram: Equatable {
  case classDiagram(UMLClassDiagram)
  case sequenceDiagram(UMLSequenceDiagram)
  case stateDiagram(UMLStateDiagram)
  case useCaseDiagram(UMLUseCaseDiagram)

  var title: String {
    switch self {
    case .classDiagram: "class diagram"
    case .sequenceDiagram: "sequence diagram"
    case .stateDiagram: "state diagram"
    case .useCaseDiagram: "use-case diagram"
    }
  }
  var isQualified: Bool {
    switch self {
    case .classDiagram(let diagram): diagram.isQualified
    case .sequenceDiagram(let diagram): diagram.isQualified
    case .stateDiagram(let diagram): diagram.isQualified
    case .useCaseDiagram(let diagram): diagram.isQualified
    }
  }
  var availableExportFormats: [UMLDiagramExportFormat] {
    switch self {
    case .classDiagram: UMLDiagramExportFormat.allCases
    case .sequenceDiagram: UMLDiagramExportFormat.allCases
    case .stateDiagram: UMLDiagramExportFormat.allCases
    case .useCaseDiagram: [.plantUML, .svg, .excalidraw]
    }
  }
  var compatibilityNote: String? {
    switch self {
    case .useCaseDiagram:
      "Mermaid has no native UML use-case syntax; export this diagram as PlantUML, SVG, or Excalidraw."
    case .classDiagram, .sequenceDiagram, .stateDiagram: nil
    }
  }
}

enum UMLDiagramAnalyzer {
  static func analyze(strokes: [InkStroke], canvasSize: CGSize, recognizedText: String) -> UMLDiagram? {
    if let diagram = UMLClassDiagramAnalyzer.analyze(
      strokes: strokes,
      canvasSize: canvasSize,
      recognizedText: recognizedText
    ) {
      return .classDiagram(diagram)
    }
    if let diagram = UMLSequenceDiagramAnalyzer.analyze(
      strokes: strokes,
      canvasSize: canvasSize,
      recognizedText: recognizedText
    ) {
      return .sequenceDiagram(diagram)
    }
    if let diagram = UMLStateDiagramAnalyzer.analyze(
      strokes: strokes,
      canvasSize: canvasSize,
      recognizedText: recognizedText
    ) {
      return .stateDiagram(diagram)
    }
    if let diagram = UMLUseCaseDiagramAnalyzer.analyze(
      strokes: strokes,
      canvasSize: canvasSize,
      recognizedText: recognizedText
    ) {
      return .useCaseDiagram(diagram)
    }
    return nil
  }
}

enum UMLDiagramExportCodec {
  static func encode(_ diagram: UMLDiagram, format: UMLDiagramExportFormat) throws -> Data {
    guard diagram.isQualified else { throw UMLDiagramExportError.noDiagram }
    guard diagram.availableExportFormats.contains(format) else {
      throw UMLDiagramExportError.unsupportedFormat
    }
    switch diagram {
    case .classDiagram(let classDiagram):
      return try UMLClassDiagramExportCodec.encode(classDiagram, format: format)
    case .sequenceDiagram(let sequenceDiagram):
      return try UMLSequenceDiagramExportCodec.encode(sequenceDiagram, format: format)
    case .stateDiagram(let stateDiagram):
      return try UMLStateDiagramExportCodec.encode(stateDiagram, format: format)
    case .useCaseDiagram(let useCaseDiagram):
      return try UMLUseCaseDiagramExportCodec.encode(useCaseDiagram, format: format)
    }
  }
}
