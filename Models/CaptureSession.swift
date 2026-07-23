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

  func append(point: InkPoint) {
    guard phase == .drawing, !strokes.isEmpty else { return }
    strokes[strokes.count - 1].points.append(point)
  }

  func finishStroke() {
    onStrokeFinished?()
  }

  func clear() {
    guard phase == .drawing else { return }
    strokes = []
  }

  func renderedImageData() -> Data? {
    renderedImage()?.tiffRepresentation
  }

  private func renderedImage() -> NSImage? {
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
      let path = NSBezierPath()
      path.lineCapStyle = .round
      path.lineJoinStyle = .round
      path.lineWidth = 7
      for (index, point) in stroke.points.enumerated() {
        let location = NSPoint(x: point.x * xScale, y: output.height - point.y * yScale)
        if index == 0 { path.move(to: location) } else { path.line(to: location) }
      }
      path.stroke()
    }
    image.unlockFocus()
    return image
  }
}
