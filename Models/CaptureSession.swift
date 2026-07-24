import AppKit
import Combine

@MainActor
final class CaptureSession: ObservableObject {
  @Published private(set) var phase: CapturePhase = .idle
  @Published var strokes: [InkStroke] = []
  @Published var recognizedText = ""
  @Published var canvasSize = CGSize(width: 760, height: 250)
  @Published private(set) var deliveryOutcome: DeliveryOutcome?

  var target: TargetReference?
  var onStrokeFinished: (() -> Void)?
  var onFirstStrokeAccepted: ((Duration) -> Void)?
  private let clock = ContinuousClock()
  private var captureActivatedAt: ContinuousClock.Instant?
  private var hasAcceptedFirstStroke = false

  @discardableResult
  func begin(target: TargetReference?) -> Bool {
    guard transition(to: .opening) else { return false }
    self.target = target
    strokes = []
    recognizedText = ""
    deliveryOutcome = nil
    captureActivatedAt = clock.now
    hasAcceptedFirstStroke = false
    return true
  }

  @discardableResult
  func transition(to next: CapturePhase) -> Bool {
    guard phase.allowsTransition(to: next) else { return false }
    phase = next
    return true
  }

  func completeDismissal() {
    guard transition(to: .idle) else { return }
    strokes = []
    recognizedText = ""
    deliveryOutcome = nil
    target = nil
    captureActivatedAt = nil
    hasAcceptedFirstStroke = false
  }

  func beginStroke(at point: InkPoint) {
    guard phase == .drawing else { return }
    recordFirstStrokeLatency()
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

  func resizeCanvas(to size: CGSize) {
    guard size.width > 0, size.height > 0, size != canvasSize else { return }
    strokes = strokes.map { stroke in
      InkStroke(
        id: stroke.id,
        points: stroke.points.map { CanvasCoordinateTransformer.resize($0, from: canvasSize, to: size) }
      )
    }
    canvasSize = size
  }

  func clear() {
    guard phase == .drawing else { return }
    strokes = []
  }

  func recordDeliveryOutcome(_ outcome: DeliveryOutcome) {
    deliveryOutcome = outcome
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

  private func recordFirstStrokeLatency() {
    guard hasAcceptedFirstStroke == false, let captureActivatedAt else { return }
    hasAcceptedFirstStroke = true
    let duration = clock.now - captureActivatedAt
    let components = duration.components
    let milliseconds = components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000
    AppLog.capture.info("first_stroke_latency_ms=\(milliseconds, privacy: .public)")
    AppLog.captureSignposter.emitEvent(
      "FirstStrokeLatency", "milliseconds=\(milliseconds, privacy: .public)")
    onFirstStrokeAccepted?(duration)
  }

  private func renderedImage(style: InkStyle) -> NSBitmapImageRep? {
    guard !strokes.isEmpty, canvasSize.width > 0, canvasSize.height > 0 else { return nil }
    let output = InkRasterLayout.outputSize(for: canvasSize)
    let pixels = InkRasterLayout.pixelSize(for: canvasSize)
    let xScale = output.width / canvasSize.width
    let yScale = output.height / canvasSize.height
    guard let image = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: pixels.width,
      pixelsHigh: pixels.height,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ) else { return nil }
    image.size = output
    guard let context = NSGraphicsContext(bitmapImageRep: image) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }
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
        path.move(to: CanvasCoordinateTransformer.renderPoint(
          previous, canvasSize: canvasSize, outputSize: output))
        path.line(to: CanvasCoordinateTransformer.renderPoint(
          point, canvasSize: canvasSize, outputSize: output))
        path.stroke()
      }
    }
    return image
  }
}
