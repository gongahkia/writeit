import Foundation

struct UMLStrokeGeometry: Equatable {
  let index: Int
  let points: [CGPoint]
  let bounds: CGRect
  let length: CGFloat

  init?(index: Int, stroke: InkStroke) {
    guard stroke.points.count >= 2 else { return nil }
    let points = stroke.points.map { CGPoint(x: $0.x, y: $0.y) }
    let xs = points.map(\.x)
    let ys = points.map(\.y)
    guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
      return nil
    }
    self.index = index
    self.points = points
    bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    length = zip(points, points.dropFirst()).reduce(CGFloat.zero) { total, pair in
      total + hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y)
    }
  }

  var first: CGPoint { points[0] }
  var last: CGPoint { points[points.count - 1] }
  var isClosed: Bool {
    hypot(first.x - last.x, first.y - last.y) <= max(10, min(bounds.width, bounds.height) * 0.22)
  }
  var isHorizontal: Bool { bounds.width >= max(24, bounds.height * 4) }
  var isVertical: Bool { bounds.height >= max(24, bounds.width * 4) }
}

enum UMLDiagramGeometry {
  static func geometries(from strokes: [InkStroke]) -> [UMLStrokeGeometry] {
    strokes.enumerated().compactMap { UMLStrokeGeometry(index: $0.offset, stroke: $0.element) }
  }

  static func isRectangle(_ geometry: UMLStrokeGeometry) -> Bool {
    guard geometry.isClosed, geometry.bounds.width >= 44, geometry.bounds.height >= 32 else { return false }
    let perimeter = 2 * (geometry.bounds.width + geometry.bounds.height)
    return geometry.length >= perimeter * 0.5 && geometry.length <= perimeter * 2.5
  }

  static func distance(from point: CGPoint, to bounds: CGRect) -> CGFloat {
    let x = max(bounds.minX, min(point.x, bounds.maxX))
    let y = max(bounds.minY, min(point.y, bounds.maxY))
    return hypot(point.x - x, point.y - y)
  }

  static func nearestIndex(to point: CGPoint, bounds: [CGRect], maximumDistance: CGFloat) -> Int? {
    bounds.enumerated().map { index, bounds in (index, distance(from: point, to: bounds)) }
      .filter { $0.1 <= maximumDistance }
      .min { $0.1 < $1.1 }?.0
  }

  static func escapedXML(_ value: String) -> String {
    value.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&apos;")
  }

  static func number(_ value: CGFloat) -> String {
    String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), Double(value))
  }

  static func labelParts(from recognizedText: String) -> [String] {
    recognizedText
      .split(whereSeparator: { $0 == "\n" || $0 == "→" })
      .map { TextSanitizer.normalize(String($0)).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }
}
