import AppKit
import SwiftUI

struct CaptureOverlayView: View {
  @ObservedObject var session: CaptureSession
  @ObservedObject var coordinator: CaptureCoordinator
  @ObservedObject var preferences: Preferences

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        Color.black.opacity(0.78).ignoresSafeArea()
          .contentShape(Rectangle())
          .onTapGesture { coordinator.execute(.cancel) }
        VStack(spacing: 0) {
          Spacer()
          captureCard
            .frame(width: min(840, max(560, proxy.size.width - 48)))
            .padding(.bottom, 30)
        }
      }
    }
  }

  @ViewBuilder private var captureCard: some View {
    VStack(spacing: 0) {
      header
      Divider().overlay(Color.white.opacity(0.14))
      switch session.phase {
      case .drawing:
        InkCanvas(session: session, style: preferences.inkStyle)
          .frame(height: 250)
          .background(Color.white.opacity(0.035))
      case .opening:
        progress("Opening capture…")
          .frame(height: 250)
      case .recognizing:
        progress("Recognizing locally…")
          .frame(height: 250)
      case .reviewing:
        review
          .frame(height: 250)
      case .delivering:
        progress("Inserting text…")
          .frame(height: 250)
      case .delivered(let message):
        delivered(message)
          .frame(height: 250)
      case .failed(let message):
        failed(message)
          .frame(height: 250)
      case .dismissing, .idle:
        EmptyView()
      }
      Divider().overlay(Color.white.opacity(0.14))
      footer
    }
    .background(WriteItTheme.overlayFill)
    .clipShape(RoundedRectangle(cornerRadius: WriteItTheme.panelCornerRadius, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: WriteItTheme.panelCornerRadius, style: .continuous).stroke(
        Color.white.opacity(0.08))
    )
    .shadow(color: .black.opacity(0.6), radius: 24, y: 12)
  }

  private var header: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.headline.weight(.semibold)).foregroundStyle(.white)
        Text(coordinator.error?.message ?? subtitle).font(.caption).foregroundStyle(
          .white.opacity(0.56))
      }
      Spacer()
      if session.phase == .drawing {
        Button(action: { coordinator.execute(.clear) }) { Image(systemName: "trash") }
          .buttonStyle(.plain).foregroundStyle(.white.opacity(0.7)).help("Clear ink (⌘⌫)")
      }
      Button(action: { coordinator.execute(.cancel) }) { Image(systemName: "xmark") }
        .buttonStyle(.plain).foregroundStyle(.white.opacity(0.7)).help("Cancel (Esc)")
    }
    .padding(.horizontal, 22).padding(.vertical, 16)
  }

  private var footer: some View {
    HStack {
      Text("Esc to cancel").font(.caption).foregroundStyle(.white.opacity(0.48))
      Spacer()
      if case .reviewing = session.phase {
        Button("Insert", action: { coordinator.execute(.confirm) }).buttonStyle(.borderedProminent)
      } else if case .delivered = session.phase {
        Button("Undo", action: coordinator.undoInsertion).buttonStyle(.bordered)
      } else if case .failed = session.phase {
        Button("Retry", action: { coordinator.execute(.confirm) }).buttonStyle(.borderedProminent)
      } else if case .drawing = session.phase {
        Text("Press \(preferences.shortcut.displayName) to submit")
          .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.8))
      }
    }
    .padding(.horizontal, 22).padding(.vertical, 14)
  }

  private func progress(_ message: String) -> some View {
    VStack(spacing: 16) {
      ProgressView().controlSize(.large).tint(.white)
      Text(message).foregroundStyle(.white.opacity(0.8))
    }
  }

  private var review: some View {
    TextEditor(text: Binding(get: { session.recognizedText }, set: { session.recognizedText = $0 }))
      .font(.title3)
      .scrollContentBackground(.hidden)
      .foregroundStyle(.white)
      .padding(18)
  }

  private func delivered(_ message: String) -> some View {
    VStack(spacing: 14) {
      Image(systemName: "checkmark.circle.fill").font(.system(size: 38)).foregroundStyle(.green)
      Text(message).font(.title3.weight(.semibold)).foregroundStyle(.white)
      Text(session.recognizedText).lineLimit(3).multilineTextAlignment(.center).foregroundStyle(
        .white.opacity(0.64))
    }
    .padding(30)
  }

  private func failed(_ message: String) -> some View {
    VStack(spacing: 14) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 34))
        .foregroundStyle(.orange)
      Text("Couldn’t read handwriting").font(.title3.weight(.semibold)).foregroundStyle(.white)
      Text(message).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.64))
      Button("Retry", action: { coordinator.execute(.confirm) }).buttonStyle(.borderedProminent)
    }
    .padding(30)
  }

  private var title: String {
    switch session.phase {
    case .drawing: "Write naturally"
    case .opening: "Opening capture"
    case .recognizing: "Reading handwriting"
    case .reviewing: "Review result"
    case .delivering: "Sending text"
    case .delivered: "Done"
    case .failed: "Recognition failed"
    case .dismissing: "Closing capture"
    case .idle: "WriteIt"
    }
  }

  private var subtitle: String {
    session.target == nil ? "Will copy to clipboard" : "Will insert into the previous text field"
  }
}
