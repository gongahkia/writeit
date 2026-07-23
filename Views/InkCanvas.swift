import AppKit
import SwiftUI

struct InkCanvas: View {
  @ObservedObject var session: CaptureSession
  var style: InkStyle

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        Canvas { context, _ in
          for stroke in session.strokes where stroke.points.count > 1 {
            for (previous, point) in zip(stroke.points, stroke.points.dropFirst()) {
              var path = Path()
              path.move(to: CGPoint(x: previous.x, y: previous.y))
              path.addLine(to: CGPoint(x: point.x, y: point.y))
              context.stroke(
                path,
                with: .color(.white),
                style: StrokeStyle(
                  lineWidth: style.lineWidth(for: (previous.pressure + point.pressure) / 2),
                  lineCap: .round,
                  lineJoin: .round
                )
              )
            }
          }
        }
        InkInputView(session: session, style: style)
      }
      .task(id: proxy.size) { session.canvasSize = proxy.size }
    }
  }
}

private struct InkInputView: NSViewRepresentable {
  @ObservedObject var session: CaptureSession
  var style: InkStyle

  func makeNSView(context: Context) -> InkInputNSView {
    InkInputNSView(session: session, style: style)
  }

  func updateNSView(_ nsView: InkInputNSView, context: Context) {
    nsView.session = session
    nsView.style = style
  }
}

private final class InkInputNSView: NSView {
  weak var session: CaptureSession?
  var style: InkStyle
  private var activeInputSource: InkInputSource = .mouse
  override var isFlipped: Bool { true }

  init(session: CaptureSession, style: InkStyle) {
    self.session = session
    self.style = style
    super.init(frame: .zero)
  }

  required init?(coder: NSCoder) { nil }
  override var acceptsFirstResponder: Bool { true }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    activeInputSource = inputSource(for: event)
    session?.beginStroke(at: point(from: event, source: activeInputSource))
  }

  override func mouseDragged(with event: NSEvent) {
    session?.append(point: point(from: event, source: activeInputSource), style: style)
  }

  override func mouseUp(with event: NSEvent) {
    session?.append(point: point(from: event, source: activeInputSource), style: style)
    session?.finishStroke()
  }

  override func tabletPoint(with event: NSEvent) {
    guard event.type == .tabletPoint else { return }
    activeInputSource = .stylus
    session?.append(point: point(from: event, source: .stylus), style: style)
  }

  private func inputSource(for event: NSEvent) -> InkInputSource {
    switch event.pointingDeviceType {
    case .pen, .eraser: .stylus
    case .unknown, .cursor: .mouse
    @unknown default: .mouse
    }
  }

  private func point(from event: NSEvent, source: InkInputSource) -> InkPoint {
    let location = convert(event.locationInWindow, from: nil)
    return InkPoint(
      x: location.x,
      y: location.y,
      pressure: CGFloat(max(event.pressure, 0.5)),
      timestamp: event.timestamp,
      inputSource: source
    )
  }
}
