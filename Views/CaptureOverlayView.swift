import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CaptureOverlayView: View {
  @ObservedObject var session: CaptureSession
  @ObservedObject var coordinator: CaptureCoordinator
  @ObservedObject var preferences: Preferences
  @State private var exportMessage: String?
  @State private var diagramFormat: DiagramExportFormat = .ascii
  @State private var showsDiagramReview = false

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
        recognitionProgress
          .frame(height: 250)
      case .reviewing:
        if showsDiagramReview && session.flowchartDiagram != nil {
          diagramReview.frame(height: 250)
        } else {
          review.frame(height: 250)
        }
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
      if canExportInk {
        Menu {
          ForEach(InkExportFormat.allCases) { format in
            Button("Export \(format.title)") { exportInk(format) }
          }
        } label: {
          Label("Export ink", systemImage: "square.and.arrow.up")
        }
        .menuStyle(.borderlessButton)
        .labelStyle(.iconOnly)
        .foregroundStyle(.white.opacity(0.7))
        .help("Export ink")
      }
      if session.flowchartDiagram != nil {
        Button(showsDiagramReview ? "Text review" : "Review flowchart") {
          showsDiagramReview.toggle()
        }
        .buttonStyle(.bordered)
      }
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
      Text(exportMessage ?? "Esc to cancel").font(.caption).foregroundStyle(.white.opacity(0.48))
      Spacer()
      if case .reviewing = session.phase {
        if showsDiagramReview {
          Button("Text review") { showsDiagramReview = false }.buttonStyle(.bordered)
        } else {
          Button("Insert", action: { coordinator.execute(.confirm) }).buttonStyle(.borderedProminent)
        }
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

  private var recognitionProgress: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      VStack(spacing: 16) {
        ProgressView().controlSize(.large).tint(.white)
        Text("Recognizing locally…").foregroundStyle(.white.opacity(0.8))
        if let seconds = coordinator.recognitionElapsedSeconds(at: context.date) {
          Text("Elapsed \(seconds)s").font(.caption).foregroundStyle(.white.opacity(0.56))
        }
        Button("Cancel", action: { coordinator.execute(.cancel) }).buttonStyle(.bordered)
      }
    }
  }

  private var review: some View {
    TextEditor(text: Binding(get: { session.recognizedText }, set: { session.recognizedText = $0 }))
      .font(.title3)
      .scrollContentBackground(.hidden)
      .foregroundStyle(.white)
      .padding(18)
  }

  private var diagramReview: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Detected flowchart").font(.title3.weight(.semibold)).foregroundStyle(.white)
        Spacer()
        Picker("Export format", selection: $diagramFormat) {
          ForEach(DiagramExportFormat.allCases) { Text($0.title).tag($0) }
        }
        .labelsHidden()
        .frame(width: 160)
      }
      ScrollView {
        Text(diagramPreview)
          .font(diagramFormat == .ascii ? .body.monospaced() : .caption.monospaced())
          .foregroundStyle(.white.opacity(0.86))
          .frame(maxWidth: .infinity, alignment: .leading)
          .textSelection(.enabled)
      }
      HStack {
        Button("Copy \(diagramFormat.title)", action: copyDiagram).buttonStyle(.bordered)
        Button("Save \(diagramFormat.title)", action: saveDiagram).buttonStyle(.borderedProminent)
        Spacer()
        Text("Text delivery remains unchanged.").font(.caption).foregroundStyle(.white.opacity(0.56))
      }
    }
    .padding(18)
  }

  private func delivered(_ message: String) -> some View {
    let outcome = session.deliveryOutcome
    let requiresRecovery = outcome?.needsClipboardRecovery == true
    let failed = outcome?.failed == true
    return VStack(spacing: 14) {
      Image(
        systemName: failed
          ? "exclamationmark.triangle.fill"
          : requiresRecovery ? "doc.on.clipboard.fill" : "checkmark.circle.fill"
      )
      .font(.system(size: 38))
      .foregroundStyle(failed || requiresRecovery ? .orange : .green)
      Text(requiresRecovery ? "Copied to clipboard" : message)
        .font(.title3.weight(.semibold))
        .foregroundStyle(.white)
      if requiresRecovery { Text(message).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.64)) }
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

  private var canExportInk: Bool {
    guard session.inputValidationMessage() == nil else { return false }
    return switch session.phase {
    case .drawing, .reviewing, .delivered, .failed: true
    case .idle, .opening, .recognizing, .delivering, .dismissing: false
    }
  }

  private func exportInk(_ format: InkExportFormat) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [format.contentType]
    panel.nameFieldStringValue = "WriteItInk.\(format.fileExtension)"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try InkExportFileStore.write(
        session.exportedInkData(format: format, style: preferences.inkStyle), to: url)
      exportMessage = "Ink exported as \(format.title)."
    } catch {
      exportMessage = (error as? LocalizedError)?.errorDescription ?? "Ink export failed."
    }
  }

  private var diagramPreview: String {
    guard let diagram = session.flowchartDiagram,
      let data = try? FlowchartDiagramExportCodec.encode(diagram, format: diagramFormat)
    else { return "Diagram preview unavailable." }
    return String(decoding: data, as: UTF8.self)
  }

  private func copyDiagram() {
    guard let diagram = session.flowchartDiagram,
      let data = try? FlowchartDiagramExportCodec.encode(diagram, format: diagramFormat),
      let value = String(data: data, encoding: .utf8)
    else {
      exportMessage = "Diagram export failed."
      return
    }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(value, forType: .string)
    exportMessage = "Copied \(diagramFormat.title)."
  }

  private func saveDiagram() {
    guard let diagram = session.flowchartDiagram else { return }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [diagramFormat.contentType]
    panel.nameFieldStringValue = "WriteItFlowchart.\(diagramFormat.fileExtension)"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try InkExportFileStore.write(
        FlowchartDiagramExportCodec.encode(diagram, format: diagramFormat), to: url)
      exportMessage = "Flowchart exported as \(diagramFormat.title)."
    } catch {
      exportMessage = (error as? LocalizedError)?.errorDescription ?? "Diagram export failed."
    }
  }
}

private extension InkExportFormat {
  var contentType: UTType {
    switch self {
    case .png: .png
    case .svg: UTType(filenameExtension: "svg") ?? .xml
    case .pdf: .pdf
    }
  }
}

private extension DiagramExportFormat {
  var contentType: UTType {
    switch self {
    case .ascii: .plainText
    case .excalidraw: UTType(filenameExtension: "excalidraw") ?? .json
    case .svg: UTType(filenameExtension: "svg") ?? .xml
    }
  }
}
