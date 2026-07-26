import Foundation

enum UMLClassRelationshipKind: String, Equatable {
  case association
  case inheritance
  case composition
}

struct UMLClass: Equatable {
  let id: String
  let name: String
  let attributes: [String]
  let operations: [String]
  let bounds: CGRect
  let compartmentYs: [CGFloat]
}

struct UMLClassRelationship: Equatable {
  let sourceID: String
  let destinationID: String
  let kind: UMLClassRelationshipKind
}

struct UMLClassDiagram: Equatable {
  static let minimumConfidence = 0.9

  let classes: [UMLClass]
  let relationships: [UMLClassRelationship]
  let confidence: Double

  var isQualified: Bool {
    confidence >= Self.minimumConfidence && classes.count >= 2 && !relationships.isEmpty
  }
}

enum UMLClassDiagramAnalyzer {
  static func analyze(
    strokes: [InkStroke],
    canvasSize: CGSize,
    recognizedText: String
  ) -> UMLClassDiagram? {
    guard canvasSize.width > 0, canvasSize.height > 0 else { return nil }
    let geometries = UMLDiagramGeometry.geometries(from: strokes)
    let boxes = geometries.filter(UMLDiagramGeometry.isRectangle).sorted {
      $0.bounds.minY == $1.bounds.minY ? $0.bounds.minX < $1.bounds.minX : $0.bounds.minY < $1.bounds.minY
    }
    guard boxes.count >= 2 else { return nil }
    let boxIndexes = Set(boxes.map(\.index))
    let dividers = dividerAssignments(from: geometries, boxes: boxes, excludedIndexes: boxIndexes)
    guard dividers.values.allSatisfy({ $0.isEmpty == false }) else { return nil }
    let dividerIndexes = Set(dividers.values.flatMap { $0.map(\.index) })
    let labels = UMLDiagramGeometry.labelParts(from: recognizedText)
    let memberLabels = Array(labels.dropFirst(boxes.count))
    let classes = boxes.enumerated().map { index, box in
      let memberLines = index < memberLabels.count ? [memberLabels[index]] : []
      return UMLClass(
        id: "class-\(index + 1)",
        name: index < labels.count ? labels[index] : "Class \(index + 1)",
        attributes: Array(memberLines.filter { $0.contains("()") == false }),
        operations: Array(memberLines.filter { $0.contains("()") }),
        bounds: box.bounds,
        compartmentYs: dividers[index, default: []].map { $0.bounds.midY }.sorted()
      )
    }
    let markerIndexes = Set(geometries.filter { isMarker($0) }.map(\.index))
    let relationships = relationships(
      geometries: geometries,
      classes: classes,
      excludedIndexes: boxIndexes.union(dividerIndexes).union(markerIndexes),
      markers: geometries.filter { markerIndexes.contains($0.index) }
    )
    let classEvidence = 0.1 * Double(min(classes.count, 2))
    let compartmentEvidence = 0.08 * Double(min(dividerIndexes.count, 2))
    let relationshipEvidence = relationships.isEmpty ? 0 : 0.12
    let confidence = min(1, 0.62 + classEvidence + compartmentEvidence + relationshipEvidence)
    let diagram = UMLClassDiagram(classes: classes, relationships: relationships, confidence: confidence)
    return diagram.isQualified ? diagram : nil
  }

  private static func dividerAssignments(
    from geometries: [UMLStrokeGeometry],
    boxes: [UMLStrokeGeometry],
    excludedIndexes: Set<Int>
  ) -> [Int: [UMLStrokeGeometry]] {
    var result = Dictionary(uniqueKeysWithValues: boxes.indices.map { ($0, [UMLStrokeGeometry]()) })
    for geometry in geometries where !excludedIndexes.contains(geometry.index) && geometry.isHorizontal {
      guard let boxIndex = boxes.firstIndex(where: { box in
        geometry.bounds.minX >= box.bounds.minX - 12
          && geometry.bounds.maxX <= box.bounds.maxX + 12
          && geometry.bounds.width >= box.bounds.width * 0.55
          && geometry.bounds.midY > box.bounds.minY + 10
          && geometry.bounds.midY < box.bounds.maxY - 10
      }) else { continue }
      result[boxIndex, default: []].append(geometry)
    }
    return result
  }

  private static func isMarker(_ geometry: UMLStrokeGeometry) -> Bool {
    geometry.isClosed && geometry.bounds.width >= 8 && geometry.bounds.width <= 36
      && geometry.bounds.height >= 8 && geometry.bounds.height <= 36
  }

  private static func relationships(
    geometries: [UMLStrokeGeometry],
    classes: [UMLClass],
    excludedIndexes: Set<Int>,
    markers: [UMLStrokeGeometry]
  ) -> [UMLClassRelationship] {
    var result: [UMLClassRelationship] = []
    let bounds = classes.map(\.bounds)
    for geometry in geometries where !excludedIndexes.contains(geometry.index) {
      guard let sourceIndex = UMLDiagramGeometry.nearestIndex(to: geometry.first, bounds: bounds, maximumDistance: 30),
        let destinationIndex = UMLDiagramGeometry.nearestIndex(to: geometry.last, bounds: bounds, maximumDistance: 30),
        sourceIndex != destinationIndex
      else { continue }
      let source = classes[sourceIndex]
      let destination = classes[destinationIndex]
      let sourceMarker = markers.contains { UMLDiagramGeometry.distance(from: geometry.first, to: $0.bounds) <= 18 }
      let destinationMarker = markers.contains { UMLDiagramGeometry.distance(from: geometry.last, to: $0.bounds) <= 18 }
      let kind: UMLClassRelationshipKind
      if let marker = markers.first(where: {
        UMLDiagramGeometry.distance(from: geometry.first, to: $0.bounds) <= 18
          || UMLDiagramGeometry.distance(from: geometry.last, to: $0.bounds) <= 18
      }) {
        kind = marker.points.count <= 4 ? .inheritance : .composition
      } else {
        kind = .association
      }
      let relationship: UMLClassRelationship
      switch kind {
      case .composition where destinationMarker:
        relationship = UMLClassRelationship(sourceID: destination.id, destinationID: source.id, kind: kind)
      case .inheritance where sourceMarker:
        relationship = UMLClassRelationship(sourceID: destination.id, destinationID: source.id, kind: kind)
      default:
        relationship = UMLClassRelationship(sourceID: source.id, destinationID: destination.id, kind: kind)
      }
      if !result.contains(relationship) { result.append(relationship) }
    }
    return result
  }
}

enum UMLClassDiagramExportCodec {
  static func encode(_ diagram: UMLClassDiagram, format: UMLDiagramExportFormat) throws -> Data {
    guard diagram.isQualified else { throw UMLDiagramExportError.noDiagram }
    return switch format {
    case .plantUML: Data(plantUML(diagram).utf8)
    case .mermaid: Data(mermaid(diagram).utf8)
    case .svg: Data(svg(diagram).utf8)
    case .excalidraw: try excalidraw(diagram)
    }
  }

  static func plantUML(_ diagram: UMLClassDiagram) -> String {
    var lines = ["@startuml"]
    for (index, item) in diagram.classes.enumerated() {
      lines.append("class \"\(escapePlantUML(item.name))\" as C\(index + 1) {")
      lines += item.attributes.map { "  \(escapePlantUML($0))" }
      if !item.attributes.isEmpty && !item.operations.isEmpty { lines.append("  --") }
      lines += item.operations.map { "  \(escapePlantUML($0))" }
      lines.append("}")
    }
    lines += relationships(diagram.relationships, classes: diagram.classes)
    lines.append("@enduml")
    return lines.joined(separator: "\n")
  }

  static func mermaid(_ diagram: UMLClassDiagram) -> String {
    var lines = ["classDiagram"]
    for (index, item) in diagram.classes.enumerated() {
      let identifier = "C\(index + 1)"
      lines.append("  class \(identifier)[\"\(escapeMermaid(item.name))\"] {")
      lines += item.attributes.map { "    \(escapeMermaid($0))" }
      lines += item.operations.map { "    \(escapeMermaid($0))" }
      lines.append("  }")
    }
    lines += relationships(diagram.relationships, classes: diagram.classes)
    return lines.joined(separator: "\n")
  }

  private static func relationships(
    _ relationships: [UMLClassRelationship],
    classes: [UMLClass]
  ) -> [String] {
    let identifiers = Dictionary(uniqueKeysWithValues: classes.enumerated().map { ($0.element.id, "C\($0.offset + 1)") })
    return relationships.compactMap { relationship in
      guard let source = identifiers[relationship.sourceID], let destination = identifiers[relationship.destinationID]
      else { return nil }
      return switch relationship.kind {
      case .association: "  \(source) -- \(destination)"
      case .composition: "  \(source) *-- \(destination)"
      case .inheritance: "  \(destination) <|-- \(source)"
      }
    }
  }

  private static func svg(_ diagram: UMLClassDiagram) -> String {
    let width = (diagram.classes.map { $0.bounds.maxX }.max() ?? 0) + 24
    let height = (diagram.classes.map { $0.bounds.maxY }.max() ?? 0) + 24
    let classes = Dictionary(uniqueKeysWithValues: diagram.classes.map { ($0.id, $0) })
    var lines = [
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
      "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(UMLDiagramGeometry.number(width))\" height=\"\(UMLDiagramGeometry.number(height))\" viewBox=\"0 0 \(UMLDiagramGeometry.number(width)) \(UMLDiagramGeometry.number(height))\">",
      "  <defs><marker id=\"arrow\" markerWidth=\"8\" markerHeight=\"8\" refX=\"7\" refY=\"4\" orient=\"auto\"><path d=\"M 0 0 L 8 4 L 0 8 z\" fill=\"#1e1e1e\"/></marker><marker id=\"triangle\" markerWidth=\"10\" markerHeight=\"10\" refX=\"9\" refY=\"5\" orient=\"auto\"><path d=\"M 0 0 L 10 5 L 0 10 z\" fill=\"white\" stroke=\"#1e1e1e\"/></marker><marker id=\"diamond\" markerWidth=\"10\" markerHeight=\"10\" refX=\"9\" refY=\"5\" orient=\"auto\"><path d=\"M 0 5 L 5 0 L 10 5 L 5 10 z\" fill=\"#1e1e1e\"/></marker></defs>",
    ]
    for relationship in diagram.relationships {
      guard let source = classes[relationship.sourceID], let destination = classes[relationship.destinationID] else { continue }
      let marker = switch relationship.kind {
      case .association: ""
      case .inheritance: " marker-end=\"url(#triangle)\""
      case .composition: " marker-start=\"url(#diamond)\""
      }
      lines.append("  <line x1=\"\(UMLDiagramGeometry.number(source.bounds.midX))\" y1=\"\(UMLDiagramGeometry.number(source.bounds.midY))\" x2=\"\(UMLDiagramGeometry.number(destination.bounds.midX))\" y2=\"\(UMLDiagramGeometry.number(destination.bounds.midY))\" stroke=\"#1e1e1e\" stroke-width=\"2\"\(marker)/>")
    }
    for item in diagram.classes {
      lines.append("  <rect x=\"\(UMLDiagramGeometry.number(item.bounds.minX))\" y=\"\(UMLDiagramGeometry.number(item.bounds.minY))\" width=\"\(UMLDiagramGeometry.number(item.bounds.width))\" height=\"\(UMLDiagramGeometry.number(item.bounds.height))\" fill=\"white\" stroke=\"#1e1e1e\" stroke-width=\"2\"/>")
      for y in item.compartmentYs {
        lines.append("  <line x1=\"\(UMLDiagramGeometry.number(item.bounds.minX))\" y1=\"\(UMLDiagramGeometry.number(y))\" x2=\"\(UMLDiagramGeometry.number(item.bounds.maxX))\" y2=\"\(UMLDiagramGeometry.number(y))\" stroke=\"#1e1e1e\" stroke-width=\"2\"/>")
      }
      lines.append("  <text x=\"\(UMLDiagramGeometry.number(item.bounds.midX))\" y=\"\(UMLDiagramGeometry.number(item.bounds.minY + 20))\" text-anchor=\"middle\" font-family=\"system-ui\" font-size=\"16\">\(UMLDiagramGeometry.escapedXML(item.name))</text>")
    }
    lines.append("</svg>")
    return lines.joined(separator: "\n")
  }

  private static func excalidraw(_ diagram: UMLClassDiagram) throws -> Data {
    var elements: [[String: Any]] = []
    for (index, item) in diagram.classes.enumerated() {
      elements += rectangleElements(for: item, index: index)
    }
    let classes = Dictionary(uniqueKeysWithValues: diagram.classes.map { ($0.id, $0) })
    for (index, relationship) in diagram.relationships.enumerated() {
      guard let source = classes[relationship.sourceID], let destination = classes[relationship.destinationID] else { continue }
      let start = CGPoint(x: source.bounds.midX, y: source.bounds.midY)
      let end = CGPoint(x: destination.bounds.midX, y: destination.bounds.midY)
      elements.append(baseElement(
        id: "relationship-\(index + 1)", type: "arrow", x: start.x, y: start.y,
        width: end.x - start.x, height: end.y - start.y, seed: 20_000 + index,
        extra: ["points": [[0, 0], [end.x - start.x, end.y - start.y]], "lastCommittedPoint": NSNull(),
          "startBinding": NSNull(), "endBinding": NSNull(),
          "startArrowhead": relationship.kind == .composition ? "diamond" : NSNull(),
          "endArrowhead": relationship.kind == .inheritance ? "triangle_outline" : NSNull()]
      ))
    }
    let payload: [String: Any] = ["type": "excalidraw", "version": 2, "source": "https://writeit.app", "elements": elements, "appState": [:], "files": [:]]
    guard JSONSerialization.isValidJSONObject(payload) else { throw UMLDiagramExportError.encodingFailed }
    return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
  }

  private static func rectangleElements(for item: UMLClass, index: Int) -> [[String: Any]] {
    var elements = [baseElement(
      id: item.id, type: "rectangle", x: item.bounds.minX, y: item.bounds.minY,
      width: item.bounds.width, height: item.bounds.height, seed: index + 1, extra: [:]
    )]
    elements.append(baseElement(
      id: "text-\(item.id)", type: "text", x: item.bounds.minX + 8, y: item.bounds.minY + 8,
      width: max(1, item.bounds.width - 16), height: 20, seed: 10_000 + index,
      extra: ["fontSize": 16, "fontFamily": 1, "text": item.name, "textAlign": "center", "verticalAlign": "middle", "containerId": NSNull(), "originalText": item.name, "autoResize": true, "lineHeight": 1.25]
    ))
    for (dividerIndex, y) in item.compartmentYs.enumerated() {
      elements.append(baseElement(
        id: "divider-\(item.id)-\(dividerIndex)", type: "line", x: item.bounds.minX, y: y,
        width: item.bounds.width, height: 0, seed: 15_000 + index * 10 + dividerIndex,
        extra: ["points": [[0, 0], [item.bounds.width, 0]], "lastCommittedPoint": NSNull(), "startBinding": NSNull(), "endBinding": NSNull(), "startArrowhead": NSNull(), "endArrowhead": NSNull()]
      ))
    }
    return elements
  }

  private static func baseElement(
    id: String, type: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, seed: Int,
    extra: [String: Any]
  ) -> [String: Any] {
    var result: [String: Any] = [
      "id": id, "type": type, "x": x, "y": y, "width": width, "height": height, "angle": 0,
      "strokeColor": "#1e1e1e", "backgroundColor": "transparent", "fillStyle": "solid", "strokeWidth": 2,
      "strokeStyle": "solid", "roughness": 1, "opacity": 100, "groupIds": [], "frameId": NSNull(),
      "roundness": type == "rectangle" ? ["type": 0] : NSNull(), "seed": seed, "version": 1,
      "versionNonce": seed, "isDeleted": false, "boundElements": [], "updated": 0, "link": NSNull(), "locked": false,
    ]
    extra.forEach { result[$0.key] = $0.value }
    return result
  }

  private static func escapePlantUML(_ value: String) -> String {
    value.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\n", with: " ")
  }

  private static func escapeMermaid(_ value: String) -> String {
    value.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\n", with: " ")
  }
}
