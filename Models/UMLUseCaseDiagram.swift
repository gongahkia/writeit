import Foundation

struct UMLUseCaseActor: Equatable {
  let id: String
  let name: String
  let bounds: CGRect
}

struct UMLUseCase: Equatable {
  let id: String
  let name: String
  let bounds: CGRect
}

struct UMLUseCaseAssociation: Equatable {
  let actorID: String
  let useCaseID: String
}

struct UMLUseCaseDiagram: Equatable {
  static let minimumConfidence = 0.9

  let actors: [UMLUseCaseActor]
  let useCases: [UMLUseCase]
  let associations: [UMLUseCaseAssociation]
  let confidence: Double

  var isQualified: Bool {
    confidence >= Self.minimumConfidence && !actors.isEmpty && !useCases.isEmpty && !associations.isEmpty
  }
}

enum UMLUseCaseDiagramAnalyzer {
  private struct ActorGeometry {
    let head: UMLStrokeGeometry
    let componentIndexes: Set<Int>
    let bounds: CGRect
  }

  static func analyze(
    strokes: [InkStroke],
    canvasSize: CGSize,
    recognizedText: String
  ) -> UMLUseCaseDiagram? {
    guard canvasSize.width > 0, canvasSize.height > 0 else { return nil }
    let geometries = UMLDiagramGeometry.geometries(from: strokes)
    let actorGeometries = actorGeometries(from: geometries)
    guard actorGeometries.isEmpty == false else { return nil }
    let actorIndexes = Set(actorGeometries.flatMap(\.componentIndexes))
    let useCaseGeometries = geometries.filter { !actorIndexes.contains($0.index) && isUseCaseEllipse($0) }
    guard useCaseGeometries.isEmpty == false else { return nil }
    let useCaseIndexes = Set(useCaseGeometries.map(\.index))
    let labels = UMLDiagramGeometry.labelParts(from: recognizedText)
    let actors = actorGeometries.enumerated().map { index, geometry in
      UMLUseCaseActor(
        id: "actor-\(index + 1)",
        name: index < labels.count ? labels[index] : "Actor \(index + 1)",
        bounds: geometry.bounds
      )
    }
    let useCases = useCaseGeometries.enumerated().map { index, geometry in
      let labelIndex = actors.count + index
      return UMLUseCase(
        id: "usecase-\(index + 1)",
        name: labelIndex < labels.count ? labels[labelIndex] : "Use case \(index + 1)",
        bounds: geometry.bounds
      )
    }
    let associations = associations(
      geometries: geometries,
      actors: actors,
      useCases: useCases,
      excludedIndexes: actorIndexes.union(useCaseIndexes)
    )
    let actorEvidence = actors.isEmpty ? 0 : 0.16
    let useCaseEvidence = useCases.isEmpty ? 0 : 0.16
    let associationEvidence = associations.isEmpty ? 0 : 0.16
    let confidence = min(1, 0.54 + actorEvidence + useCaseEvidence + associationEvidence)
    let diagram = UMLUseCaseDiagram(
      actors: actors,
      useCases: useCases,
      associations: associations,
      confidence: confidence
    )
    return diagram.isQualified ? diagram : nil
  }

  private static func actorGeometries(from geometries: [UMLStrokeGeometry]) -> [ActorGeometry] {
    geometries.compactMap { head in
      guard isActorHead(head) else { return nil }
      let nearby = geometries.filter { $0.index != head.index }
      guard let body = nearby.first(where: {
        $0.isVertical && abs($0.bounds.midX - head.bounds.midX) <= 14
          && $0.bounds.minY <= head.bounds.maxY + 12 && $0.bounds.maxY >= head.bounds.maxY + 24
      }), let arms = nearby.first(where: {
        $0.isHorizontal && $0.bounds.midX >= head.bounds.minX - 24 && $0.bounds.midX <= head.bounds.maxX + 24
          && $0.bounds.midY >= body.bounds.minY + 8 && $0.bounds.midY <= body.bounds.maxY + 8
      })
      else { return nil }
      let bodyFoot = CGPoint(x: body.bounds.midX, y: body.bounds.maxY)
      let legs = nearby.filter { geometry in
        !geometry.isHorizontal && !geometry.isVertical && !isActorHead(geometry)
          && min(hypot(geometry.first.x - bodyFoot.x, geometry.first.y - bodyFoot.y), hypot(geometry.last.x - bodyFoot.x, geometry.last.y - bodyFoot.y)) <= 16
      }
      guard legs.count >= 2 else { return nil }
      let components = [head, body, arms] + Array(legs.prefix(2))
      let bounds = components.map(\.bounds).reduce(CGRect.null) { $0.union($1) }
      return ActorGeometry(head: head, componentIndexes: Set(components.map(\.index)), bounds: bounds)
    }
  }

  private static func isActorHead(_ geometry: UMLStrokeGeometry) -> Bool {
    guard geometry.isClosed, geometry.bounds.width >= 10, geometry.bounds.width <= 34,
      geometry.bounds.height >= 10, geometry.bounds.height <= 34
    else { return false }
    let aspect = geometry.bounds.width / geometry.bounds.height
    return (0.65...1.5).contains(aspect)
  }

  private static func isUseCaseEllipse(_ geometry: UMLStrokeGeometry) -> Bool {
    guard geometry.isClosed, geometry.bounds.width >= 56, geometry.bounds.height >= 28 else { return false }
    let aspect = geometry.bounds.width / geometry.bounds.height
    let circumference = .pi * (geometry.bounds.width + geometry.bounds.height) / 2
    return (1.3...4).contains(aspect) && geometry.length >= circumference * 0.5
      && geometry.length <= circumference * 2.5
  }

  private static func associations(
    geometries: [UMLStrokeGeometry],
    actors: [UMLUseCaseActor],
    useCases: [UMLUseCase],
    excludedIndexes: Set<Int>
  ) -> [UMLUseCaseAssociation] {
    let bounds = actors.map(\.bounds) + useCases.map(\.bounds)
    var associations: [UMLUseCaseAssociation] = []
    for geometry in geometries where !excludedIndexes.contains(geometry.index) {
      guard let firstIndex = UMLDiagramGeometry.nearestIndex(to: geometry.first, bounds: bounds, maximumDistance: 26),
        let lastIndex = UMLDiagramGeometry.nearestIndex(to: geometry.last, bounds: bounds, maximumDistance: 26),
        firstIndex != lastIndex
      else { continue }
      let association: UMLUseCaseAssociation?
      if firstIndex < actors.count, lastIndex >= actors.count {
        association = UMLUseCaseAssociation(actorID: actors[firstIndex].id, useCaseID: useCases[lastIndex - actors.count].id)
      } else if lastIndex < actors.count, firstIndex >= actors.count {
        association = UMLUseCaseAssociation(actorID: actors[lastIndex].id, useCaseID: useCases[firstIndex - actors.count].id)
      } else {
        association = nil
      }
      if let association, !associations.contains(association) { associations.append(association) }
    }
    return associations
  }
}

enum UMLUseCaseDiagramExportCodec {
  static func encode(_ diagram: UMLUseCaseDiagram, format: UMLDiagramExportFormat) throws -> Data {
    guard diagram.isQualified else { throw UMLDiagramExportError.noDiagram }
    return switch format {
    case .plantUML: Data(plantUML(diagram).utf8)
    case .svg: Data(svg(diagram).utf8)
    case .excalidraw: try excalidraw(diagram)
    case .mermaid: throw UMLDiagramExportError.unsupportedFormat
    }
  }

  static func plantUML(_ diagram: UMLUseCaseDiagram) -> String {
    let actorIdentifiers = Dictionary(uniqueKeysWithValues: diagram.actors.enumerated().map { ($0.element.id, "A\($0.offset + 1)") })
    let useCaseIdentifiers = Dictionary(uniqueKeysWithValues: diagram.useCases.enumerated().map { ($0.element.id, "U\($0.offset + 1)") })
    var lines = ["@startuml"]
    for actor in diagram.actors {
      guard let identifier = actorIdentifiers[actor.id] else { continue }
      lines.append("actor \"\(escapePlantUML(actor.name))\" as \(identifier)")
    }
    for useCase in diagram.useCases {
      guard let identifier = useCaseIdentifiers[useCase.id] else { continue }
      lines.append("usecase \"\(escapePlantUML(useCase.name))\" as \(identifier)")
    }
    for association in diagram.associations {
      guard let actor = actorIdentifiers[association.actorID], let useCase = useCaseIdentifiers[association.useCaseID] else { continue }
      lines.append("\(actor) -- \(useCase)")
    }
    lines.append("@enduml")
    return lines.joined(separator: "\n")
  }

  private static func svg(_ diagram: UMLUseCaseDiagram) -> String {
    let allBounds = diagram.actors.map(\.bounds) + diagram.useCases.map(\.bounds)
    let width = (allBounds.map(\.maxX).max() ?? 0) + 24
    let height = (allBounds.map(\.maxY).max() ?? 0) + 24
    let actors = Dictionary(uniqueKeysWithValues: diagram.actors.map { ($0.id, $0) })
    let useCases = Dictionary(uniqueKeysWithValues: diagram.useCases.map { ($0.id, $0) })
    var lines = [
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
      "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(UMLDiagramGeometry.number(width))\" height=\"\(UMLDiagramGeometry.number(height))\" viewBox=\"0 0 \(UMLDiagramGeometry.number(width)) \(UMLDiagramGeometry.number(height))\">",
    ]
    for association in diagram.associations {
      guard let actor = actors[association.actorID], let useCase = useCases[association.useCaseID] else { continue }
      lines.append("  <line x1=\"\(UMLDiagramGeometry.number(actor.bounds.midX))\" y1=\"\(UMLDiagramGeometry.number(actor.bounds.midY))\" x2=\"\(UMLDiagramGeometry.number(useCase.bounds.midX))\" y2=\"\(UMLDiagramGeometry.number(useCase.bounds.midY))\" stroke=\"#1e1e1e\" stroke-width=\"2\"/>")
    }
    for actor in diagram.actors {
      lines += actorSVG(actor)
    }
    for useCase in diagram.useCases {
      lines.append("  <ellipse cx=\"\(UMLDiagramGeometry.number(useCase.bounds.midX))\" cy=\"\(UMLDiagramGeometry.number(useCase.bounds.midY))\" rx=\"\(UMLDiagramGeometry.number(useCase.bounds.width / 2))\" ry=\"\(UMLDiagramGeometry.number(useCase.bounds.height / 2))\" fill=\"white\" stroke=\"#1e1e1e\" stroke-width=\"2\"/>")
      lines.append("  <text x=\"\(UMLDiagramGeometry.number(useCase.bounds.midX))\" y=\"\(UMLDiagramGeometry.number(useCase.bounds.midY))\" text-anchor=\"middle\" dominant-baseline=\"middle\" font-family=\"system-ui\" font-size=\"16\">\(UMLDiagramGeometry.escapedXML(useCase.name))</text>")
    }
    lines.append("</svg>")
    return lines.joined(separator: "\n")
  }

  private static func actorSVG(_ actor: UMLUseCaseActor) -> [String] {
    let center = CGPoint(x: actor.bounds.midX, y: actor.bounds.midY)
    let headRadius = min(actor.bounds.width, actor.bounds.height) * 0.13
    let shoulderY = center.y - actor.bounds.height * 0.03
    let hipY = center.y + actor.bounds.height * 0.28
    return [
      "  <circle cx=\"\(UMLDiagramGeometry.number(center.x))\" cy=\"\(UMLDiagramGeometry.number(center.y - actor.bounds.height * 0.29))\" r=\"\(UMLDiagramGeometry.number(headRadius))\" fill=\"white\" stroke=\"#1e1e1e\" stroke-width=\"2\"/>",
      "  <line x1=\"\(UMLDiagramGeometry.number(center.x))\" y1=\"\(UMLDiagramGeometry.number(center.y - actor.bounds.height * 0.16))\" x2=\"\(UMLDiagramGeometry.number(center.x))\" y2=\"\(UMLDiagramGeometry.number(hipY))\" stroke=\"#1e1e1e\" stroke-width=\"2\"/>",
      "  <line x1=\"\(UMLDiagramGeometry.number(actor.bounds.minX))\" y1=\"\(UMLDiagramGeometry.number(shoulderY))\" x2=\"\(UMLDiagramGeometry.number(actor.bounds.maxX))\" y2=\"\(UMLDiagramGeometry.number(shoulderY))\" stroke=\"#1e1e1e\" stroke-width=\"2\"/>",
      "  <line x1=\"\(UMLDiagramGeometry.number(center.x))\" y1=\"\(UMLDiagramGeometry.number(hipY))\" x2=\"\(UMLDiagramGeometry.number(actor.bounds.minX))\" y2=\"\(UMLDiagramGeometry.number(actor.bounds.maxY))\" stroke=\"#1e1e1e\" stroke-width=\"2\"/>",
      "  <line x1=\"\(UMLDiagramGeometry.number(center.x))\" y1=\"\(UMLDiagramGeometry.number(hipY))\" x2=\"\(UMLDiagramGeometry.number(actor.bounds.maxX))\" y2=\"\(UMLDiagramGeometry.number(actor.bounds.maxY))\" stroke=\"#1e1e1e\" stroke-width=\"2\"/>",
      "  <text x=\"\(UMLDiagramGeometry.number(center.x))\" y=\"\(UMLDiagramGeometry.number(actor.bounds.maxY + 16))\" text-anchor=\"middle\" font-family=\"system-ui\" font-size=\"16\">\(UMLDiagramGeometry.escapedXML(actor.name))</text>",
    ]
  }

  private static func excalidraw(_ diagram: UMLUseCaseDiagram) throws -> Data {
    var elements: [[String: Any]] = []
    for (index, actor) in diagram.actors.enumerated() { elements += actorElements(actor, index: index) }
    for (index, useCase) in diagram.useCases.enumerated() { elements += useCaseElements(useCase, index: index) }
    let actors = Dictionary(uniqueKeysWithValues: diagram.actors.map { ($0.id, $0) })
    let useCases = Dictionary(uniqueKeysWithValues: diagram.useCases.map { ($0.id, $0) })
    for (index, association) in diagram.associations.enumerated() {
      guard let actor = actors[association.actorID], let useCase = useCases[association.useCaseID] else { continue }
      elements.append(baseElement(id: "association-\(index + 1)", type: "line", x: actor.bounds.midX, y: actor.bounds.midY, width: useCase.bounds.midX - actor.bounds.midX, height: useCase.bounds.midY - actor.bounds.midY, seed: 20_000 + index, extra: ["points": [[0, 0], [useCase.bounds.midX - actor.bounds.midX, useCase.bounds.midY - actor.bounds.midY]], "lastCommittedPoint": NSNull(), "startBinding": NSNull(), "endBinding": NSNull(), "startArrowhead": NSNull(), "endArrowhead": NSNull()]))
    }
    let payload: [String: Any] = ["type": "excalidraw", "version": 2, "source": "https://writeit.app", "elements": elements, "appState": [:], "files": [:]]
    guard JSONSerialization.isValidJSONObject(payload) else { throw UMLDiagramExportError.encodingFailed }
    return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
  }

  private static func actorElements(_ actor: UMLUseCaseActor, index: Int) -> [[String: Any]] {
    let headSize = min(actor.bounds.width, actor.bounds.height) * 0.26
    let headX = actor.bounds.midX - headSize / 2
    let headY = actor.bounds.minY
    return [
      baseElement(id: actor.id, type: "ellipse", x: headX, y: headY, width: headSize, height: headSize, seed: index + 1, extra: [:]),
      baseElement(id: "text-\(actor.id)", type: "text", x: actor.bounds.minX, y: actor.bounds.maxY + 2, width: actor.bounds.width, height: 20, seed: 10_000 + index, extra: ["fontSize": 16, "fontFamily": 1, "text": actor.name, "textAlign": "center", "verticalAlign": "middle", "containerId": NSNull(), "originalText": actor.name, "autoResize": true, "lineHeight": 1.25]),
    ]
  }

  private static func useCaseElements(_ useCase: UMLUseCase, index: Int) -> [[String: Any]] {
    [
      baseElement(id: useCase.id, type: "ellipse", x: useCase.bounds.minX, y: useCase.bounds.minY, width: useCase.bounds.width, height: useCase.bounds.height, seed: 5_000 + index, extra: [:]),
      baseElement(id: "text-\(useCase.id)", type: "text", x: useCase.bounds.minX + 8, y: useCase.bounds.midY - 10, width: max(1, useCase.bounds.width - 16), height: 20, seed: 12_000 + index, extra: ["fontSize": 16, "fontFamily": 1, "text": useCase.name, "textAlign": "center", "verticalAlign": "middle", "containerId": NSNull(), "originalText": useCase.name, "autoResize": true, "lineHeight": 1.25]),
    ]
  }

  private static func baseElement(id: String, type: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, seed: Int, extra: [String: Any]) -> [String: Any] {
    var result: [String: Any] = [
      "id": id, "type": type, "x": x, "y": y, "width": width, "height": height, "angle": 0,
      "strokeColor": "#1e1e1e", "backgroundColor": "transparent", "fillStyle": "solid", "strokeWidth": 2,
      "strokeStyle": "solid", "roughness": 1, "opacity": 100, "groupIds": [], "frameId": NSNull(),
      "roundness": NSNull(), "seed": seed, "version": 1, "versionNonce": seed, "isDeleted": false,
      "boundElements": [], "updated": 0, "link": NSNull(), "locked": false,
    ]
    extra.forEach { result[$0.key] = $0.value }
    return result
  }

  private static func escapePlantUML(_ value: String) -> String {
    value.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\n", with: " ")
  }
}
