import AppKit
import Combine

@MainActor
final class CaptureSession: ObservableObject {
  @Published var phase: CapturePhase = .idle
  @Published var strokes: [InkStroke] = []
  @Published var recognizedText = ""
  @Published var canvasSize = CGSize(width: 760, height: 250)

  var target: TargetReference?
  var onStrokeFinished: (() -> Void)?

  func begin(target: TargetReference?) {
    self.target = target
    strokes = []
    recognizedText = ""
    phase = .drawing
  }

  func cancel() {
    phase = .idle
    strokes = []
    recognizedText = ""
    target = nil
  }

  func beginStroke(at point: InkPoint) {
    guard phase == .drawing else { return }
    strokes.append(InkStroke(points: [point]))
  }

  func append(point: InkPoint, style: InkStyle = .default) {
    guard phase == .drawing, !strokes.isEmpty else { return }
    guard let previous = strokes.last?.points.last else { return }
    strokes[strokes.count - 1].points.append(style.smoothed(point, after: previous))
  }

  func finishStroke() {
    onStrokeFinished?()
  }

  func clear() {
    guard phase == .drawing else { return }
    strokes = []
  }

  func inputValidationMessage() -> String? {
    guard !strokes.isEmpty else { return "Write something before recognizing." }
    guard strokes.contains(where: { $0.points.count > 1 }) else {
      return "Draw a stroke before recognizing."
    }
    return nil
  }

  func renderedImageData(style: InkStyle = .default) -> Data? {
    guard inputValidationMessage() == nil else { return nil }
    return renderedImage(style: style)?.tiffRepresentation
  }

  private func renderedImage(style: InkStyle) -> NSImage? {
    guard !strokes.isEmpty, canvasSize.width > 0, canvasSize.height > 0 else { return nil }
    let output = CGSize(width: 1536, height: max(512, 1536 * canvasSize.height / canvasSize.width))
    let xScale = output.width / canvasSize.width
    let yScale = output.height / canvasSize.height
    let image = NSImage(size: output)
    image.lockFocus()
    NSColor.white.setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: output)).fill()
    NSColor.black.setStroke()
    for stroke in strokes where stroke.points.count > 1 {
      for (previous, point) in zip(stroke.points, stroke.points.dropFirst()) {
        let path = NSBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.lineWidth = style.lineWidth(
          for: (previous.pressure + point.pressure) / 2,
          scale: min(xScale, yScale)
        )
        path.move(to: NSPoint(x: previous.x * xScale, y: output.height - previous.y * yScale))
        path.line(to: NSPoint(x: point.x * xScale, y: output.height - point.y * yScale))
        path.stroke()
      }
    }
    image.unlockFocus()
    return image
  }
}
