import Foundation

enum UMLStatePseudostateKind: String, Equatable {
  case initial
  case final
}

struct UMLState: Equatable {
  let id: String
  let name: String
  let bounds: CGRect
}

struct UMLStatePseudostate: Equatable {
  let kind: UMLStatePseudostateKind
  let bounds: CGRect
}

enum UMLStateEndpoint: Equatable {
  case state(String)
  case initial
  case final
}

struct UMLStateTransition: Equatable {
  let source: UMLStateEndpoint
  let destination: UMLStateEndpoint
  let label: String?
}

struct UMLStateDiagram: Equatable {
  static let minimumConfidence = 0.9

  let states: [UMLState]
  let initial: UMLStatePseudostate
  let final: UMLStatePseudostate
  let transitions: [UMLStateTransition]
  let confidence: Double

  var isQualified: Bool {
    confidence >= Self.minimumConfidence && states.count >= 2 && transitions.count >= 3
  }
}

enum UMLStateDiagramAnalyzer {
  private enum RawEndpoint: Equatable {
    case state(Int)
    case circle(Int)
  }

  private struct RawTransition: Equatable {
    let source: RawEndpoint
    let destination: RawEndpoint
  }

  static func analyze(
    strokes: [InkStroke],
    canvasSize: CGSize,
    recognizedText: String
  ) -> UMLStateDiagram? {
    guard canvasSize.width > 0, canvasSize.height > 0 else { return nil }
    let geometries = UMLDiagramGeometry.geometries(from: strokes)
    let stateGeometries = geometries.filter(UMLDiagramGeometry.isRectangle).sorted {
      $0.bounds.minY == $1.bounds.minY ? $0.bounds.minX < $1.bounds.minX : $0.bounds.minY < $1.bounds.minY
    }
    guard stateGeometries.count >= 2 else { return nil }
    let circleGeometries = geometries.filter(isPseudostateCircle)
    guard circleGeometries.count >= 2 else { return nil }
    let excludedIndexes = Set(stateGeometries.map(\.index)).union(circleGeometries.map(\.index))
    let rawTransitions = rawTransitions(
      geometries: geometries,
      states: stateGeometries,
      circles: circleGeometries,
      excludedIndexes: excludedIndexes
    )
    guard let initialIndex = pseudostateIndex(kind: .initial, transitions: rawTransitions, circleCount: circleGeometries.count),
      let finalIndex = pseudostateIndex(kind: .final, transitions: rawTransitions, circleCount: circleGeometries.count),
      initialIndex != finalIndex
    else { return nil }
    let labels = UMLDiagramGeometry.labelParts(from: recognizedText)
    let states = stateGeometries.enumerated().map { index, geometry in
      UMLState(
        id: "state-\(index + 1)",
        name: index < labels.count ? labels[index] : "State \(index + 1)",
        bounds: geometry.bounds
      )
    }
    let transitionLabels = Array(labels.dropFirst(states.count))
    let transitions: [UMLStateTransition] = rawTransitions.enumerated().compactMap { item in
      let index = item.offset
      let raw = item.element
      guard let source = endpoint(raw.source, states: states, initialIndex: initialIndex, finalIndex: finalIndex),
        let destination = endpoint(raw.destination, states: states, initialIndex: initialIndex, finalIndex: finalIndex)
      else { return nil }
      return UMLStateTransition(
        source: source,
        destination: destination,
        label: index < transitionLabels.count ? transitionLabels[index] : nil
      )
    }
    guard transitions.contains(where: { $0.source == .initial }),
      transitions.contains(where: { $0.destination == .final })
    else { return nil }
    let stateEvidence = 0.13 * Double(min(states.count, 2))
    let pseudostateEvidence = 0.2
    let transitionEvidence = transitions.count >= 3 ? 0.1 : 0
    let confidence = min(1, 0.45 + stateEvidence + pseudostateEvidence + transitionEvidence)
    let diagram = UMLStateDiagram(
      states: states,
      initial: UMLStatePseudostate(kind: .initial, bounds: circleGeometries[initialIndex].bounds),
      final: UMLStatePseudostate(kind: .final, bounds: circleGeometries[finalIndex].bounds),
      transitions: transitions,
      confidence: confidence
    )
    return diagram.isQualified ? diagram : nil
  }

  private static func isPseudostateCircle(_ geometry: UMLStrokeGeometry) -> Bool {
    guard geometry.isClosed, geometry.bounds.width >= 10, geometry.bounds.width <= 38,
      geometry.bounds.height >= 10, geometry.bounds.height <= 38
    else { return false }
    let aspect = geometry.bounds.width / geometry.bounds.height
    let circumference = .pi * (geometry.bounds.width + geometry.bounds.height) / 2
    return (0.65...1.5).contains(aspect) && geometry.length >= circumference * 0.5
      && geometry.length <= circumference * 2.5
  }

  private static func rawTransitions(
    geometries: [UMLStrokeGeometry],
    states: [UMLStrokeGeometry],
    circles: [UMLStrokeGeometry],
    excludedIndexes: Set<Int>
  ) -> [RawTransition] {
    let endpoints = states.indices.map { RawEndpoint.state($0) }
      + circles.indices.map { RawEndpoint.circle($0) }
    let bounds = states.map(\.bounds) + circles.map(\.bounds)
    var transitions: [RawTransition] = []
    for geometry in geometries where !excludedIndexes.contains(geometry.index) {
      guard hasArrowTip(geometry),
        let sourceIndex = UMLDiagramGeometry.nearestIndex(to: geometry.first, bounds: bounds, maximumDistance: 30),
        let destinationIndex = UMLDiagramGeometry.nearestIndex(to: geometry.last, bounds: bounds, maximumDistance: 30),
        sourceIndex != destinationIndex
      else { continue }
      let transition = RawTransition(source: endpoints[sourceIndex], destination: endpoints[destinationIndex])
      if !transitions.contains(transition) { transitions.append(transition) }
    }
    return transitions
  }

  private static func pseudostateIndex(
    kind: UMLStatePseudostateKind,
    transitions: [RawTransition],
    circleCount: Int
  ) -> Int? {
    let candidates = (0..<circleCount).filter { index in
      switch kind {
      case .initial:
        return transitions.contains { $0.source == .circle(index) }
          && !transitions.contains { $0.destination == .circle(index) }
      case .final:
        return transitions.contains { $0.destination == .circle(index) }
          && !transitions.contains { $0.source == .circle(index) }
      }
    }
    return candidates.count == 1 ? candidates[0] : nil
  }

  private static func endpoint(
    _ endpoint: RawEndpoint,
    states: [UMLState],
    initialIndex: Int,
    finalIndex: Int
  ) -> UMLStateEndpoint? {
    switch endpoint {
    case .state(let index):
      guard states.indices.contains(index) else { return nil }
      return .state(states[index].id)
    case .circle(let index) where index == initialIndex: return .initial
    case .circle(let index) where index == finalIndex: return .final
    case .circle: return nil
    }
  }

  private static func hasArrowTip(_ geometry: UMLStrokeGeometry) -> Bool {
    guard geometry.points.count >= 4 else { return false }
    let tail = geometry.last
    let previous = geometry.points[geometry.points.count - 2]
    let beforePrevious = geometry.points[geometry.points.count - 3]
    let finalVector = CGPoint(x: tail.x - previous.x, y: tail.y - previous.y)
    let previousVector = CGPoint(x: previous.x - beforePrevious.x, y: previous.y - beforePrevious.y)
    return finalVector.x * previousVector.x + finalVector.y * previousVector.y < 0
  }
}

enum UMLStateDiagramExportCodec {
  static func encode(_ diagram: UMLStateDiagram, format: UMLDiagramExportFormat) throws -> Data {
    guard diagram.isQualified else { throw UMLDiagramExportError.noDiagram }
    return switch format {
    case .plantUML: Data(plantUML(diagram).utf8)
    case .mermaid: Data(mermaid(diagram).utf8)
    case .svg: Data(svg(diagram).utf8)
    case .excalidraw: try excalidraw(diagram)
    }
  }

  static func plantUML(_ diagram: UMLStateDiagram) -> String {
    let identifiers = identifiers(for: diagram.states)
    var lines = ["@startuml"]
    for state in diagram.states {
      guard let identifier = identifiers[state.id] else { continue }
      lines.append("state \"\(escapePlantUML(state.name))\" as \(identifier)")
    }
    lines += transitionLines(diagram.transitions, identifiers: identifiers, style: .plantUML)
    lines.append("@enduml")
    return lines.joined(separator: "\n")
  }

  static func mermaid(_ diagram: UMLStateDiagram) -> String {
    let identifiers = identifiers(for: diagram.states)
    var lines = ["stateDiagram-v2"]
    for state in diagram.states {
      guard let identifier = identifiers[state.id] else { continue }
      lines.append("  state \"\(escapeMermaid(state.name))\" as \(identifier)")
    }
    lines += transitionLines(diagram.transitions, identifiers: identifiers, style: .mermaid)
    return lines.joined(separator: "\n")
  }

  private enum Syntax { case plantUML, mermaid }

  private static func transitionLines(
    _ transitions: [UMLStateTransition],
    identifiers: [String: String],
    style: Syntax
  ) -> [String] {
    transitions.compactMap { transition in
      guard let source = endpoint(transition.source, identifiers: identifiers),
        let destination = endpoint(transition.destination, identifiers: identifiers)
      else { return nil }
      let prefix = style == .mermaid ? "  " : ""
      let label = transition.label.map { ": \(style == .mermaid ? escapeMermaid($0) : escapePlantUML($0))" } ?? ""
      return "\(prefix)\(source) --> \(destination)\(label)"
    }
  }

  private static func svg(_ diagram: UMLStateDiagram) -> String {
    let allBounds = diagram.states.map(\.bounds) + [diagram.initial.bounds, diagram.final.bounds]
    let width = (allBounds.map(\.maxX).max() ?? 0) + 24
    let height = (allBounds.map(\.maxY).max() ?? 0) + 24
    let states = Dictionary(uniqueKeysWithValues: diagram.states.map { ($0.id, $0) })
    var lines = [
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
      "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(UMLDiagramGeometry.number(width))\" height=\"\(UMLDiagramGeometry.number(height))\" viewBox=\"0 0 \(UMLDiagramGeometry.number(width)) \(UMLDiagramGeometry.number(height))\">",
      "  <defs><marker id=\"arrow\" markerWidth=\"8\" markerHeight=\"8\" refX=\"7\" refY=\"4\" orient=\"auto\"><path d=\"M 0 0 L 8 4 L 0 8 z\" fill=\"#1e1e1e\"/></marker></defs>",
    ]
    for transition in diagram.transitions {
      guard let source = center(transition.source, states: states, initial: diagram.initial, final: diagram.final),
        let destination = center(transition.destination, states: states, initial: diagram.initial, final: diagram.final)
      else { continue }
      lines.append("  <line x1=\"\(UMLDiagramGeometry.number(source.x))\" y1=\"\(UMLDiagramGeometry.number(source.y))\" x2=\"\(UMLDiagramGeometry.number(destination.x))\" y2=\"\(UMLDiagramGeometry.number(destination.y))\" stroke=\"#1e1e1e\" stroke-width=\"2\" marker-end=\"url(#arrow)\"/>")
      if let label = transition.label {
        lines.append("  <text x=\"\(UMLDiagramGeometry.number((source.x + destination.x) / 2))\" y=\"\(UMLDiagramGeometry.number((source.y + destination.y) / 2 - 7))\" text-anchor=\"middle\" font-family=\"system-ui\" font-size=\"14\">\(UMLDiagramGeometry.escapedXML(label))</text>")
      }
    }
    for state in diagram.states {
      lines.append("  <rect x=\"\(UMLDiagramGeometry.number(state.bounds.minX))\" y=\"\(UMLDiagramGeometry.number(state.bounds.minY))\" width=\"\(UMLDiagramGeometry.number(state.bounds.width))\" height=\"\(UMLDiagramGeometry.number(state.bounds.height))\" rx=\"10\" fill=\"white\" stroke=\"#1e1e1e\" stroke-width=\"2\"/>")
      lines.append("  <text x=\"\(UMLDiagramGeometry.number(state.bounds.midX))\" y=\"\(UMLDiagramGeometry.number(state.bounds.midY))\" text-anchor=\"middle\" dominant-baseline=\"middle\" font-family=\"system-ui\" font-size=\"16\">\(UMLDiagramGeometry.escapedXML(state.name))</text>")
    }
    lines += pseudostateSVG(diagram.initial, filled: true)
    lines += pseudostateSVG(diagram.final, filled: false)
    lines.append("</svg>")
    return lines.joined(separator: "\n")
  }

  private static func pseudostateSVG(_ pseudostate: UMLStatePseudostate, filled: Bool) -> [String] {
    let radius = min(pseudostate.bounds.width, pseudostate.bounds.height) / 2
    let center = CGPoint(x: pseudostate.bounds.midX, y: pseudostate.bounds.midY)
    var lines = ["  <circle cx=\"\(UMLDiagramGeometry.number(center.x))\" cy=\"\(UMLDiagramGeometry.number(center.y))\" r=\"\(UMLDiagramGeometry.number(radius))\" fill=\"\(filled ? "#1e1e1e" : "white")\" stroke=\"#1e1e1e\" stroke-width=\"2\"/>"]
    if !filled {
      lines.append("  <circle cx=\"\(UMLDiagramGeometry.number(center.x))\" cy=\"\(UMLDiagramGeometry.number(center.y))\" r=\"\(UMLDiagramGeometry.number(max(1, radius - 5)))\" fill=\"#1e1e1e\"/>")
    }
    return lines
  }

  private static func excalidraw(_ diagram: UMLStateDiagram) throws -> Data {
    var elements: [[String: Any]] = []
    for (index, state) in diagram.states.enumerated() {
      elements += stateElements(state, index: index)
    }
    elements += pseudostateElements(diagram.initial, index: 1, filled: true)
    elements += pseudostateElements(diagram.final, index: 2, filled: false)
    let states = Dictionary(uniqueKeysWithValues: diagram.states.map { ($0.id, $0) })
    for (index, transition) in diagram.transitions.enumerated() {
      guard let source = center(transition.source, states: states, initial: diagram.initial, final: diagram.final),
        let destination = center(transition.destination, states: states, initial: diagram.initial, final: diagram.final)
      else { continue }
      elements.append(baseElement(id: "transition-\(index + 1)", type: "arrow", x: source.x, y: source.y, width: destination.x - source.x, height: destination.y - source.y, seed: 20_000 + index, extra: ["points": [[0, 0], [destination.x - source.x, destination.y - source.y]], "lastCommittedPoint": NSNull(), "startBinding": NSNull(), "endBinding": NSNull(), "startArrowhead": NSNull(), "endArrowhead": "arrow"]))
    }
    let payload: [String: Any] = ["type": "excalidraw", "version": 2, "source": "https://writeit.app", "elements": elements, "appState": [:], "files": [:]]
    guard JSONSerialization.isValidJSONObject(payload) else { throw UMLDiagramExportError.encodingFailed }
    return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
  }

  private static func stateElements(_ state: UMLState, index: Int) -> [[String: Any]] {
    [
      baseElement(id: state.id, type: "rectangle", x: state.bounds.minX, y: state.bounds.minY, width: state.bounds.width, height: state.bounds.height, seed: index + 1, extra: ["roundness": ["type": 3]]),
      baseElement(id: "text-\(state.id)", type: "text", x: state.bounds.minX + 8, y: state.bounds.midY - 10, width: max(1, state.bounds.width - 16), height: 20, seed: 10_000 + index, extra: ["fontSize": 16, "fontFamily": 1, "text": state.name, "textAlign": "center", "verticalAlign": "middle", "containerId": NSNull(), "originalText": state.name, "autoResize": true, "lineHeight": 1.25]),
    ]
  }

  private static func pseudostateElements(_ pseudostate: UMLStatePseudostate, index: Int, filled: Bool) -> [[String: Any]] {
    [baseElement(id: pseudostate.kind.rawValue, type: "ellipse", x: pseudostate.bounds.minX, y: pseudostate.bounds.minY, width: pseudostate.bounds.width, height: pseudostate.bounds.height, seed: 15_000 + index, extra: ["backgroundColor": filled ? "#1e1e1e" : "transparent"])]
  }

  private static func center(_ endpoint: UMLStateEndpoint, states: [String: UMLState], initial: UMLStatePseudostate, final: UMLStatePseudostate) -> CGPoint? {
    switch endpoint {
    case .state(let id): states[id].map { CGPoint(x: $0.bounds.midX, y: $0.bounds.midY) }
    case .initial: CGPoint(x: initial.bounds.midX, y: initial.bounds.midY)
    case .final: CGPoint(x: final.bounds.midX, y: final.bounds.midY)
    }
  }

  private static func endpoint(_ endpoint: UMLStateEndpoint, identifiers: [String: String]) -> String? {
    switch endpoint {
    case .state(let id): identifiers[id]
    case .initial, .final: "[*]"
    }
  }

  private static func identifiers(for states: [UMLState]) -> [String: String] {
    Dictionary(uniqueKeysWithValues: states.enumerated().map { ($0.element.id, "S\($0.offset + 1)") })
  }

  private static func escapePlantUML(_ value: String) -> String {
    value.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\n", with: " ")
  }

  private static func escapeMermaid(_ value: String) -> String {
    value.replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: ";", with: "#59;")
      .replacingOccurrences(of: ":", with: "#58;")
  }

  private static func baseElement(id: String, type: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, seed: Int, extra: [String: Any]) -> [String: Any] {
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
}
