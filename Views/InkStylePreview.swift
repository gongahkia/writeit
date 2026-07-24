import SwiftUI

struct InkStylePreview: View {
  let style: InkStyle

  var body: some View {
    let points = InkStylePreviewGeometry.smoothedPoints(for: style)
    Canvas { context, _ in
      for (previous, point) in zip(points, points.dropFirst()) {
        var path = Path()
        path.move(to: CGPoint(x: previous.x, y: previous.y))
        path.addLine(to: CGPoint(x: point.x, y: point.y))
        context.stroke(
          path,
          with: .color(.primary),
          style: StrokeStyle(
            lineWidth: style.lineWidth(for: (previous.pressure + point.pressure) / 2),
            lineCap: .round,
            lineJoin: .round
          )
        )
      }
    }
    .frame(height: 68)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Ink style preview")
  }
}

enum InkStylePreviewGeometry {
  static let rawPoints = [
    InkPoint(x: 8, y: 48, pressure: 0.5, timestamp: 0, inputSource: .stylus),
    InkPoint(x: 42, y: 18, pressure: 1, timestamp: 0.1, inputSource: .stylus),
    InkPoint(x: 80, y: 58, pressure: 0.35, timestamp: 0.2, inputSource: .stylus),
    InkPoint(x: 118, y: 24, pressure: 0.9, timestamp: 0.3, inputSource: .stylus),
    InkPoint(x: 152, y: 48, pressure: 0.5, timestamp: 0.4, inputSource: .stylus),
  ]

  static func smoothedPoints(for style: InkStyle) -> [InkPoint] {
    guard let first = rawPoints.first else { return [] }
    var points = [first]
    for point in rawPoints.dropFirst() {
      guard let previous = points.last else { continue }
      points.append(style.smoothed(point, after: previous))
    }
    return points
  }
}
