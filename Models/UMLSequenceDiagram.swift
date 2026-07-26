import Foundation

enum UMLSequenceMessageKind: String, Equatable {
  case call
  case `return`
}

struct UMLSequenceParticipant: Equatable {
  let id: String
  let name: String
  let bounds: CGRect
  let lifeline: CGRect
}

struct UMLSequenceMessage: Equatable {
  let sourceID: String
  let destinationID: String
  let label: String
  let kind: UMLSequenceMessageKind
  let y: CGFloat
}

struct UMLSequenceDiagram: Equatable {
  static let minimumConfidence = 0.9

  let participants: [UMLSequenceParticipant]
  let messages: [UMLSequenceMessage]
  let confidence: Double

  var isQualified: Bool {
    confidence >= Self.minimumConfidence && participants.count >= 2 && !messages.isEmpty
  }
}

enum UMLSequenceDiagramAnalyzer {
  static func analyze(
    strokes: [InkStroke],
    canvasSize: CGSize,
    recognizedText: String
  ) -> UMLSequenceDiagram? {
    guard canvasSize.width > 0, canvasSize.height > 0 else { return nil }
    let geometries = UMLDiagramGeometry.geometries(from: strokes)
    let headers = geometries.filter {
      UMLDiagramGeometry.isRectangle($0) && $0.bounds.minY <= canvasSize.height * 0.35
    }.sorted { $0.bounds.minX < $1.bounds.minX }
    guard headers.count >= 2 else { return nil }
    let headerIndexes = Set(headers.map(\.index))
    let lifelines = lifelineAssignments(from: geometries, headers: headers, excludedIndexes: headerIndexes)
    guard lifelines.count == headers.count else { return nil }
    let lifelineIndexes = Set(lifelines.map(\.index))
    let labels = UMLDiagramGeometry.labelParts(from: recognizedText)
    let participants = headers.enumerated().map { index, header in
      UMLSequenceParticipant(
        id: "participant-\(index + 1)",
        name: index < labels.count ? labels[index] : "Participant \(index + 1)",
        bounds: header.bounds,
        lifeline: lifelines[index].bounds
      )
    }
    let messageLabels = Array(labels.dropFirst(participants.count))
    let messageCandidates = geometries.filter {
      !headerIndexes.contains($0.index) && !lifelineIndexes.contains($0.index) && $0.isHorizontal
    }
    let messages = messageGroups(messageCandidates).enumerated().compactMap { index, group in
      message(from: group, participants: participants, label: index < messageLabels.count ? messageLabels[index] : "Message \(index + 1)")
    }
    let participantEvidence = 0.14 * Double(min(participants.count, 2))
    let lifelineEvidence = 0.1
    let messageEvidence = messages.isEmpty ? 0 : 0.12
    let confidence = min(1, 0.5 + participantEvidence + lifelineEvidence + messageEvidence)
    let diagram = UMLSequenceDiagram(participants: participants, messages: messages, confidence: confidence)
    return diagram.isQualified ? diagram : nil
  }

  private static func lifelineAssignments(
    from geometries: [UMLStrokeGeometry],
    headers: [UMLStrokeGeometry],
    excludedIndexes: Set<Int>
  ) -> [UMLStrokeGeometry] {
    headers.compactMap { header in
      geometries.filter { geometry in
        !excludedIndexes.contains(geometry.index) && geometry.isVertical
          && abs(geometry.bounds.midX - header.bounds.midX) <= 18
          && geometry.bounds.minY <= header.bounds.maxY + 20
          && geometry.bounds.maxY >= header.bounds.maxY + 48
      }.max { $0.bounds.height < $1.bounds.height }
    }
  }

  private static func messageGroups(_ geometries: [UMLStrokeGeometry]) -> [[UMLStrokeGeometry]] {
    var groups: [[UMLStrokeGeometry]] = []
    for geometry in geometries.sorted(by: { $0.bounds.midY < $1.bounds.midY }) {
      guard let index = groups.indices.last else {
        groups.append([geometry])
        continue
      }
      let average = groups[index].reduce(CGFloat.zero) { $0 + $1.bounds.midY }
        / CGFloat(groups[index].count)
      if abs(average - geometry.bounds.midY) <= 12 {
        groups[index].append(geometry)
      } else {
        groups.append([geometry])
      }
    }
    return groups
  }

  private static func message(
    from group: [UMLStrokeGeometry],
    participants: [UMLSequenceParticipant],
    label: String
  ) -> UMLSequenceMessage? {
    guard group.isEmpty == false else { return nil }
    let bounds = participants.map(\.lifeline)
    let minimumX = group.map { $0.bounds.minX }.min() ?? 0
    let maximumX = group.map { $0.bounds.maxX }.max() ?? 0
    let leftParticipant = UMLDiagramGeometry.nearestIndex(
      to: CGPoint(x: minimumX, y: group[0].bounds.midY), bounds: bounds, maximumDistance: 30)
    let rightParticipant = UMLDiagramGeometry.nearestIndex(
      to: CGPoint(x: maximumX, y: group[0].bounds.midY), bounds: bounds, maximumDistance: 30)
    guard let leftParticipant, let rightParticipant, leftParticipant != rightParticipant else { return nil }
    let arrowTip = group.compactMap(arrowTip).first
    if group.count == 1 {
      guard let geometry = group.first, let arrowTip,
        let source = UMLDiagramGeometry.nearestIndex(to: geometry.first, bounds: bounds, maximumDistance: 30),
        let destination = UMLDiagramGeometry.nearestIndex(to: geometry.last, bounds: bounds, maximumDistance: 30),
        source != destination
      else { return nil }
      return UMLSequenceMessage(
        sourceID: participants[source].id,
        destinationID: participants[destination].id,
        label: label,
        kind: .call,
        y: arrowTip.y
      )
    }
    guard let arrowTip,
      let destination = UMLDiagramGeometry.nearestIndex(to: arrowTip, bounds: bounds, maximumDistance: 30)
    else { return nil }
    let source = destination == leftParticipant ? rightParticipant : leftParticipant
    return UMLSequenceMessage(
      sourceID: participants[source].id,
      destinationID: participants[destination].id,
      label: label,
      kind: .return,
      y: arrowTip.y
    )
  }

  private static func arrowTip(_ geometry: UMLStrokeGeometry) -> CGPoint? {
    guard geometry.points.count >= 4 else { return nil }
    let penultimate = geometry.points[geometry.points.count - 2]
    let beforePenultimate = geometry.points[geometry.points.count - 3]
    let tail = geometry.last
    let finalVector = CGPoint(x: tail.x - penultimate.x, y: tail.y - penultimate.y)
    let previousVector = CGPoint(x: penultimate.x - beforePenultimate.x, y: penultimate.y - beforePenultimate.y)
    let dot = finalVector.x * previousVector.x + finalVector.y * previousVector.y
    return dot < 0 ? tail : nil
  }
}

enum UMLSequenceDiagramExportCodec {
  static func encode(_ diagram: UMLSequenceDiagram, format: UMLDiagramExportFormat) throws -> Data {
    guard diagram.isQualified else { throw UMLDiagramExportError.noDiagram }
    return switch format {
    case .plantUML: Data(plantUML(diagram).utf8)
    case .mermaid: Data(mermaid(diagram).utf8)
    case .svg: Data(svg(diagram).utf8)
    case .excalidraw: try excalidraw(diagram)
    }
  }

  static func plantUML(_ diagram: UMLSequenceDiagram) -> String {
    let identifiers = identifiers(for: diagram.participants)
    var lines = ["@startuml"]
    for participant in diagram.participants {
      guard let identifier = identifiers[participant.id] else { continue }
      lines.append("participant \"\(escapePlantUML(participant.name))\" as \(identifier)")
    }
    for message in diagram.messages {
      guard let source = identifiers[message.sourceID], let destination = identifiers[message.destinationID] else { continue }
      let arrow = message.kind == .call ? "->" : "-->"
      lines.append("\(source) \(arrow) \(destination): \(escapePlantUML(message.label))")
    }
    lines.append("@enduml")
    return lines.joined(separator: "\n")
  }

  static func mermaid(_ diagram: UMLSequenceDiagram) -> String {
    let identifiers = identifiers(for: diagram.participants)
    var lines = ["sequenceDiagram"]
    for participant in diagram.participants {
      guard let identifier = identifiers[participant.id] else { continue }
      lines.append("  participant \(identifier) as \(escapeMermaid(participant.name))")
    }
    for message in diagram.messages {
      guard let source = identifiers[message.sourceID], let destination = identifiers[message.destinationID] else { continue }
      let arrow = message.kind == .call ? "->>" : "-->>"
      lines.append("  \(source)\(arrow)\(destination): \(escapeMermaid(message.label))")
    }
    return lines.joined(separator: "\n")
  }

  private static func svg(_ diagram: UMLSequenceDiagram) -> String {
    let width = (diagram.participants.map { $0.bounds.maxX }.max() ?? 0) + 24
    let height = max(
      (diagram.participants.map { $0.lifeline.maxY }.max() ?? 0) + 24,
      (diagram.messages.map(\.y).max() ?? 0) + 36
    )
    let participants = Dictionary(uniqueKeysWithValues: diagram.participants.map { ($0.id, $0) })
    var lines = [
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
      "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(UMLDiagramGeometry.number(width))\" height=\"\(UMLDiagramGeometry.number(height))\" viewBox=\"0 0 \(UMLDiagramGeometry.number(width)) \(UMLDiagramGeometry.number(height))\">",
      "  <defs><marker id=\"arrow\" markerWidth=\"8\" markerHeight=\"8\" refX=\"7\" refY=\"4\" orient=\"auto\"><path d=\"M 0 0 L 8 4 L 0 8 z\" fill=\"#1e1e1e\"/></marker></defs>",
    ]
    for participant in diagram.participants {
      lines.append("  <rect x=\"\(UMLDiagramGeometry.number(participant.bounds.minX))\" y=\"\(UMLDiagramGeometry.number(participant.bounds.minY))\" width=\"\(UMLDiagramGeometry.number(participant.bounds.width))\" height=\"\(UMLDiagramGeometry.number(participant.bounds.height))\" fill=\"white\" stroke=\"#1e1e1e\" stroke-width=\"2\"/>")
      lines.append("  <text x=\"\(UMLDiagramGeometry.number(participant.bounds.midX))\" y=\"\(UMLDiagramGeometry.number(participant.bounds.midY))\" text-anchor=\"middle\" dominant-baseline=\"middle\" font-family=\"system-ui\" font-size=\"16\">\(UMLDiagramGeometry.escapedXML(participant.name))</text>")
      lines.append("  <line x1=\"\(UMLDiagramGeometry.number(participant.lifeline.midX))\" y1=\"\(UMLDiagramGeometry.number(participant.lifeline.minY))\" x2=\"\(UMLDiagramGeometry.number(participant.lifeline.midX))\" y2=\"\(UMLDiagramGeometry.number(participant.lifeline.maxY))\" stroke=\"#1e1e1e\" stroke-width=\"1\" stroke-dasharray=\"5 4\"/>")
    }
    for message in diagram.messages {
      guard let source = participants[message.sourceID], let destination = participants[message.destinationID] else { continue }
      let dash = message.kind == .return ? " stroke-dasharray=\"5 4\"" : ""
      lines.append("  <line x1=\"\(UMLDiagramGeometry.number(source.lifeline.midX))\" y1=\"\(UMLDiagramGeometry.number(message.y))\" x2=\"\(UMLDiagramGeometry.number(destination.lifeline.midX))\" y2=\"\(UMLDiagramGeometry.number(message.y))\" stroke=\"#1e1e1e\" stroke-width=\"2\" marker-end=\"url(#arrow)\"\(dash)/>")
      lines.append("  <text x=\"\(UMLDiagramGeometry.number((source.lifeline.midX + destination.lifeline.midX) / 2))\" y=\"\(UMLDiagramGeometry.number(message.y - 7))\" text-anchor=\"middle\" font-family=\"system-ui\" font-size=\"14\">\(UMLDiagramGeometry.escapedXML(message.label))</text>")
    }
    lines.append("</svg>")
    return lines.joined(separator: "\n")
  }

  private static func excalidraw(_ diagram: UMLSequenceDiagram) throws -> Data {
    var elements: [[String: Any]] = []
    for (index, participant) in diagram.participants.enumerated() {
      elements += participantElements(participant, index: index)
    }
    let participants = Dictionary(uniqueKeysWithValues: diagram.participants.map { ($0.id, $0) })
    for (index, message) in diagram.messages.enumerated() {
      guard let source = participants[message.sourceID], let destination = participants[message.destinationID] else { continue }
      elements.append(baseElement(
        id: "message-\(index + 1)", type: "arrow", x: source.lifeline.midX, y: message.y,
        width: destination.lifeline.midX - source.lifeline.midX, height: 0, seed: 20_000 + index,
        extra: ["strokeStyle": message.kind == .return ? "dashed" : "solid", "points": [[0, 0], [destination.lifeline.midX - source.lifeline.midX, 0]], "lastCommittedPoint": NSNull(), "startBinding": NSNull(), "endBinding": NSNull(), "startArrowhead": NSNull(), "endArrowhead": "arrow"]
      ))
    }
    let payload: [String: Any] = ["type": "excalidraw", "version": 2, "source": "https://writeit.app", "elements": elements, "appState": [:], "files": [:]]
    guard JSONSerialization.isValidJSONObject(payload) else { throw UMLDiagramExportError.encodingFailed }
    return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
  }

  private static func participantElements(_ participant: UMLSequenceParticipant, index: Int) -> [[String: Any]] {
    [
      baseElement(id: participant.id, type: "rectangle", x: participant.bounds.minX, y: participant.bounds.minY, width: participant.bounds.width, height: participant.bounds.height, seed: index + 1, extra: [:]),
      baseElement(id: "text-\(participant.id)", type: "text", x: participant.bounds.minX + 8, y: participant.bounds.minY + 8, width: max(1, participant.bounds.width - 16), height: 20, seed: 10_000 + index, extra: ["fontSize": 16, "fontFamily": 1, "text": participant.name, "textAlign": "center", "verticalAlign": "middle", "containerId": NSNull(), "originalText": participant.name, "autoResize": true, "lineHeight": 1.25]),
      baseElement(id: "lifeline-\(participant.id)", type: "line", x: participant.lifeline.midX, y: participant.lifeline.minY, width: 0, height: participant.lifeline.height, seed: 15_000 + index, extra: ["strokeStyle": "dashed", "points": [[0, 0], [0, participant.lifeline.height]], "lastCommittedPoint": NSNull(), "startBinding": NSNull(), "endBinding": NSNull(), "startArrowhead": NSNull(), "endArrowhead": NSNull()]),
    ]
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

  private static func identifiers(for participants: [UMLSequenceParticipant]) -> [String: String] {
    Dictionary(uniqueKeysWithValues: participants.enumerated().map { ($0.element.id, "P\($0.offset + 1)") })
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
}
