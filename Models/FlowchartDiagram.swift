import Foundation

enum DiagramExportFormat: String, CaseIterable, Identifiable {
  case ascii
  case excalidraw
  case svg

  var id: String { rawValue }
  var title: String {
    switch self {
    case .ascii: "ASCII"
    case .excalidraw: "Excalidraw JSON"
    case .svg: "SVG"
    }
  }
  var fileExtension: String {
    switch self {
    case .ascii: "txt"
    case .excalidraw: "excalidraw"
    case .svg: "svg"
    }
  }
}

enum DiagramExportError: LocalizedError, Equatable {
  case noDiagram
  case encodingFailed

  var errorDescription: String? {
    switch self {
    case .noDiagram: "No flowchart was detected in this capture."
    case .encodingFailed: "WriteIt could not encode this flowchart."
    }
  }
}

struct FlowchartNode: Equatable {
  let id: String
  let label: String
  let bounds: CGRect
}

struct FlowchartEdge: Equatable {
  let sourceID: String
  let destinationID: String
}

struct FlowchartDiagram: Equatable {
  static let minimumConfidence = 0.85

  let nodes: [FlowchartNode]
  let edges: [FlowchartEdge]
  let confidence: Double

  var isQualified: Bool {
    confidence >= Self.minimumConfidence && nodes.count >= 2 && !edges.isEmpty
  }
}

enum FlowchartDiagramAnalyzer {
  private struct StrokeGeometry {
    let index: Int
    let points: [InkPoint]
    let bounds: CGRect
    let length: CGFloat

    var first: CGPoint? { points.first.map { CGPoint(x: $0.x, y: $0.y) } }
    var last: CGPoint? { points.last.map { CGPoint(x: $0.x, y: $0.y) } }
  }

  static func analyze(
    strokes: [InkStroke],
    canvasSize: CGSize,
    recognizedText: String
  ) -> FlowchartDiagram? {
    guard canvasSize.width > 0, canvasSize.height > 0 else { return nil }
    let geometries = strokes.enumerated().compactMap { index, stroke -> StrokeGeometry? in
      guard stroke.points.count > 2 else { return nil }
      let points = stroke.points
      let xs = points.map(\.x)
      let ys = points.map(\.y)
      guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
        return nil
      }
      let length = zip(points, points.dropFirst()).reduce(CGFloat.zero) { partial, pair in
        partial + hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y)
      }
      return StrokeGeometry(
        index: index,
        points: points,
        bounds: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
        length: length
      )
    }
    let nodeGeometries = geometries.filter(isNode)
      .sorted { lhs, rhs in
        lhs.bounds.minY == rhs.bounds.minY ? lhs.bounds.minX < rhs.bounds.minX : lhs.bounds.minY < rhs.bounds.minY
      }
    guard nodeGeometries.count >= 2 else { return nil }
    let labels = labels(from: recognizedText, count: nodeGeometries.count)
    let nodes = nodeGeometries.enumerated().map { index, geometry in
      FlowchartNode(id: "node-\(index + 1)", label: labels[index], bounds: geometry.bounds)
    }
    let nodeIndexes = Set(nodeGeometries.map(\.index))
    var edges: [FlowchartEdge] = []
    for geometry in geometries where !nodeIndexes.contains(geometry.index) {
      guard let start = geometry.first, let end = geometry.last,
        let source = nearestNode(to: start, nodes: nodes), let destination = nearestNode(to: end, nodes: nodes),
        source.id != destination.id
      else { continue }
      let edge = FlowchartEdge(sourceID: source.id, destinationID: destination.id)
      if !edges.contains(edge) { edges.append(edge) }
    }
    let confidence = min(1, 0.45 + 0.15 * Double(min(nodes.count, 2)) + (edges.isEmpty ? 0 : 0.25))
    let diagram = FlowchartDiagram(nodes: nodes, edges: edges, confidence: confidence)
    return diagram.isQualified ? diagram : nil
  }

  private static func isNode(_ geometry: StrokeGeometry) -> Bool {
    guard let first = geometry.first, let last = geometry.last,
      geometry.bounds.width >= 36, geometry.bounds.height >= 24
    else { return false }
    let closureTolerance = max(18, min(geometry.bounds.width, geometry.bounds.height) * 0.18)
    guard hypot(first.x - last.x, first.y - last.y) <= closureTolerance else { return false }
    let perimeter = 2 * (geometry.bounds.width + geometry.bounds.height)
    return geometry.length >= perimeter * 0.55 && geometry.length <= perimeter * 2.4
  }

  private static func labels(from recognizedText: String, count: Int) -> [String] {
    let parts = recognizedText
      .split(whereSeparator: { $0 == "\n" || $0 == "→" })
      .map { TextSanitizer.normalize(String($0)).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    return (0..<count).map { index in
      guard parts.count == count else { return "Step \(index + 1)" }
      return parts[index]
    }
  }

  private static func nearestNode(to point: CGPoint, nodes: [FlowchartNode]) -> FlowchartNode? {
    nodes
      .map { node in (node, distance(from: point, to: node.bounds)) }
      .filter { $0.1 <= 28 }
      .min { $0.1 < $1.1 }?
      .0
  }

  private static func distance(from point: CGPoint, to bounds: CGRect) -> CGFloat {
    let x = max(bounds.minX, min(point.x, bounds.maxX))
    let y = max(bounds.minY, min(point.y, bounds.maxY))
    return hypot(point.x - x, point.y - y)
  }
}

enum FlowchartDiagramExportCodec {
  static func encode(_ diagram: FlowchartDiagram, format: DiagramExportFormat) throws -> Data {
    guard diagram.isQualified else { throw DiagramExportError.noDiagram }
    return switch format {
    case .ascii: Data(ascii(diagram).utf8)
    case .excalidraw: try excalidraw(diagram)
    case .svg: Data(svg(diagram).utf8)
    }
  }

  static func ascii(_ diagram: FlowchartDiagram) -> String {
    let names = Dictionary(uniqueKeysWithValues: diagram.nodes.map { ($0.id, $0.label) })
    return diagram.edges.compactMap { edge in
      guard let source = names[edge.sourceID], let destination = names[edge.destinationID] else { return nil }
      return "[\(source)] --> [\(destination)]"
    }.joined(separator: "\n")
  }

  private static func excalidraw(_ diagram: FlowchartDiagram) throws -> Data {
    var elements: [[String: Any]] = []
    for (index, node) in diagram.nodes.enumerated() {
      let nodeID = node.id
      elements.append([
        "id": nodeID, "type": "rectangle", "x": node.bounds.minX, "y": node.bounds.minY,
        "width": node.bounds.width, "height": node.bounds.height, "angle": 0, "strokeColor": "#1e1e1e",
        "backgroundColor": "transparent", "fillStyle": "solid", "strokeWidth": 2,
        "strokeStyle": "solid", "roughness": 1, "opacity": 100, "groupIds": [], "frameId": NSNull(),
        "roundness": ["type": 3], "seed": index + 1, "version": 1, "versionNonce": index + 1,
        "isDeleted": false, "boundElements": [], "updated": 0, "link": NSNull(), "locked": false,
      ])
      elements.append([
        "id": "text-\(nodeID)", "type": "text", "x": node.bounds.minX + 12,
        "y": node.bounds.midY - 10, "width": max(1, node.bounds.width - 24), "height": 24,
        "angle": 0, "strokeColor": "#1e1e1e", "backgroundColor": "transparent", "fillStyle": "solid",
        "strokeWidth": 1, "strokeStyle": "solid", "roughness": 0, "opacity": 100, "groupIds": [],
        "frameId": NSNull(), "roundness": NSNull(), "seed": index + 10_001, "version": 1,
        "versionNonce": index + 10_001, "isDeleted": false, "boundElements": [], "updated": 0,
        "link": NSNull(), "locked": false, "fontSize": 20, "fontFamily": 1, "text": node.label,
        "textAlign": "center", "verticalAlign": "middle", "containerId": NSNull(), "originalText": node.label,
        "autoResize": true, "lineHeight": 1.25,
      ])
    }
    let nodes = Dictionary(uniqueKeysWithValues: diagram.nodes.map { ($0.id, $0) })
    for (index, edge) in diagram.edges.enumerated() {
      guard let source = nodes[edge.sourceID], let destination = nodes[edge.destinationID] else { continue }
      let start = CGPoint(x: source.bounds.midX, y: source.bounds.midY)
      let end = CGPoint(x: destination.bounds.midX, y: destination.bounds.midY)
      elements.append([
        "id": "edge-\(index + 1)", "type": "arrow", "x": start.x, "y": start.y,
        "width": end.x - start.x, "height": end.y - start.y, "angle": 0, "strokeColor": "#1e1e1e",
        "backgroundColor": "transparent", "fillStyle": "solid", "strokeWidth": 2, "strokeStyle": "solid",
        "roughness": 1, "opacity": 100, "groupIds": [], "frameId": NSNull(), "roundness": NSNull(),
        "seed": index + 20_001, "version": 1, "versionNonce": index + 20_001, "isDeleted": false,
        "boundElements": [], "updated": 0, "link": NSNull(), "locked": false, "points": [[0, 0], [end.x - start.x, end.y - start.y]],
        "lastCommittedPoint": NSNull(), "startBinding": NSNull(), "endBinding": NSNull(), "startArrowhead": NSNull(), "endArrowhead": "arrow",
      ])
    }
    let payload: [String: Any] = [
      "type": "excalidraw", "version": 2, "source": "https://writeit.app", "elements": elements,
      "appState": [:], "files": [:],
    ]
    guard JSONSerialization.isValidJSONObject(payload) else { throw DiagramExportError.encodingFailed }
    return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
  }

  private static func svg(_ diagram: FlowchartDiagram) -> String {
    let width = (diagram.nodes.map { $0.bounds.maxX }.max() ?? 0) + 24
    let height = (diagram.nodes.map { $0.bounds.maxY }.max() ?? 0) + 24
    let nodes = Dictionary(uniqueKeysWithValues: diagram.nodes.map { ($0.id, $0) })
    var lines = [
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
      "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(number(width))\" height=\"\(number(height))\" viewBox=\"0 0 \(number(width)) \(number(height))\">",
      "  <defs><marker id=\"arrow\" markerWidth=\"8\" markerHeight=\"8\" refX=\"7\" refY=\"4\" orient=\"auto\"><path d=\"M 0 0 L 8 4 L 0 8 z\" fill=\"#1e1e1e\"/></marker></defs>",
    ]
    for edge in diagram.edges {
      guard let source = nodes[edge.sourceID], let destination = nodes[edge.destinationID] else { continue }
      lines.append("  <line x1=\"\(number(source.bounds.midX))\" y1=\"\(number(source.bounds.midY))\" x2=\"\(number(destination.bounds.midX))\" y2=\"\(number(destination.bounds.midY))\" stroke=\"#1e1e1e\" stroke-width=\"2\" marker-end=\"url(#arrow)\"/>")
    }
    for node in diagram.nodes {
      lines.append("  <rect x=\"\(number(node.bounds.minX))\" y=\"\(number(node.bounds.minY))\" width=\"\(number(node.bounds.width))\" height=\"\(number(node.bounds.height))\" rx=\"8\" fill=\"white\" stroke=\"#1e1e1e\" stroke-width=\"2\"/>")
      lines.append("  <text x=\"\(number(node.bounds.midX))\" y=\"\(number(node.bounds.midY))\" text-anchor=\"middle\" dominant-baseline=\"middle\" font-family=\"system-ui\" font-size=\"16\">\(escapeXML(node.label))</text>")
    }
    lines.append("</svg>")
    return lines.joined(separator: "\n")
  }

  private static func number(_ value: CGFloat) -> String {
    String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), Double(value))
  }

  private static func escapeXML(_ value: String) -> String {
    value.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&apos;")
  }
}
