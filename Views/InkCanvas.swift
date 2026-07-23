import AppKit
import SwiftUI

struct InkCanvas: View {
  @ObservedObject var session: CaptureSession

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        Canvas { context, _ in
          for stroke in session.strokes where stroke.points.count > 1 {
            var path = Path()
            for (index, point) in stroke.points.enumerated() {
              if index == 0 { path.move(to: CGPoint(x: point.x, y: point.y)) }
              else { path.addLine(to: CGPoint(x: point.x, y: point.y)) }
            }
            context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
          }
        }
        InkInputView(session: session)
      }
      .task(id: proxy.size) { session.canvasSize = proxy.size }
    }
  }
}

private struct InkInputView: NSViewRepresentable {
  @ObservedObject var session: CaptureSession

  func makeNSView(context: Context) -> InkInputNSView {
    InkInputNSView(session: session)
  }

  func updateNSView(_ nsView: InkInputNSView, context: Context) {
    nsView.session = session
  }
}

private final class InkInputNSView: NSView {
  weak var session: CaptureSession?
  override var isFlipped: Bool { true }

  init(session: CaptureSession) {
    self.session = session
    super.init(frame: .zero)
  }

  required init?(coder: NSCoder) { nil }
  override var acceptsFirstResponder: Bool { true }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    session?.beginStroke(at: point(from: event))
  }

  override func mouseDragged(with event: NSEvent) {
    session?.append(point: point(from: event))
  }

  override func mouseUp(with event: NSEvent) {
    session?.append(point: point(from: event))
    session?.finishStroke()
  }

  override func tabletPoint(with event: NSEvent) {
    if event.type == .tabletPoint { session?.append(point: point(from: event)) }
  }

  private func point(from event: NSEvent) -> InkPoint {
    let location = convert(event.locationInWindow, from: nil)
    return InkPoint(x: location.x, y: location.y, pressure: CGFloat(max(event.pressure, 0.5)), timestamp: event.timestamp)
  }
}
