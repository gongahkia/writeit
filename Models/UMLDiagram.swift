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

  var title: String {
    switch self {
    case .classDiagram: "class diagram"
    case .sequenceDiagram: "sequence diagram"
    }
  }
  var isQualified: Bool {
    switch self {
    case .classDiagram(let diagram): diagram.isQualified
    case .sequenceDiagram(let diagram): diagram.isQualified
    }
  }
  var availableExportFormats: [UMLDiagramExportFormat] {
    switch self {
    case .classDiagram: UMLDiagramExportFormat.allCases
    case .sequenceDiagram: UMLDiagramExportFormat.allCases
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
    }
  }
}
