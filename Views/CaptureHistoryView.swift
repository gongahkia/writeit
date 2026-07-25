import AppKit
import SwiftUI

struct CaptureHistoryView: View {
  @ObservedObject var history: HistoryStore
  @ObservedObject var preferences: Preferences
  var onCleanup: () -> Void
  var onRetryCapture: (HistoryEntry) -> Void

  @State private var query = ""
  @State private var expandedID: HistoryEntry.ID?
  @State private var showSettings = false

  private var entries: [HistoryEntry] {
    guard !query.isEmpty else { return history.entries }
    return history.entries.filter { HistorySearch.matches(text: $0.text, query: query) }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        TextField("Search captures…", text: $query)
          .textFieldStyle(.roundedBorder)
        Button(action: { showSettings = true }) { Image(systemName: "gearshape") }
          .buttonStyle(.bordered).help("History settings")
      }
      .padding(20)
      historyPrivacySummary
      if let error = history.error {
        CaptureErrorBanner(error: error, dismiss: history.clearError)
          .padding(.horizontal, 20)
          .padding(.bottom, 20)
      }
      Divider()
      if entries.isEmpty {
        ContentUnavailableView(
          query.isEmpty ? "No history" : "No matches",
          systemImage: query.isEmpty ? "clock" : "magnifyingglass",
          description: Text(
            query.isEmpty
              ? "Completed captures appear here when history is enabled."
              : "Try a different search."))
      } else {
        ScrollView {
          LazyVStack(spacing: 12) {
            ForEach(entries) { entry in
              HistoryEntryCard(
                entry: entry, isExpanded: expandedID == entry.id,
                onToggle: { expandedID = expandedID == entry.id ? nil : entry.id },
                onDelete: { history.delete(entry) },
                onRetryCapture: { onRetryCapture(entry) })
            }
          }
          .padding(20)
        }
      }
    }
    .navigationTitle("History")
    .sheet(isPresented: $showSettings) {
      HistorySettingsSheet(
        history: history, preferences: preferences, onCleanup: onCleanup, isPresented: $showSettings
      )
    }
  }

  private var historyPrivacySummary: some View {
    let privacy = HistoryPrivacyPresentation(
      mode: preferences.historyMode,
      autoDelete: preferences.historyAutoDelete,
      retentionDays: preferences.historyRetentionDays
    )
    return HStack(alignment: .top, spacing: 8) {
      Image(systemName: "lock.shield").foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 2) {
        Text(privacy.title).font(.caption.weight(.semibold))
        Text(privacy.detail).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
    }
    .padding(.horizontal, 20)
    .padding(.bottom, 12)
  }
}

private struct HistoryEntryCard: View {
  var entry: HistoryEntry
  var isExpanded: Bool
  var onToggle: () -> Void
  var onDelete: () -> Void
  var onRetryCapture: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button(action: onToggle) {
        HStack(alignment: .top, spacing: 14) {
          Image(systemName: isExpanded ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(isExpanded ? Color.accentColor : Color.secondary)
            .font(.title3)
          VStack(alignment: .leading, spacing: 6) {
            Text(entry.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
              .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(entry.text).font(.body).lineLimit(isExpanded ? nil : 2).multilineTextAlignment(
              .leading)
          }
          Spacer(minLength: 6)
          Image(systemName: isExpanded ? "chevron.up" : "chevron.right").foregroundStyle(.secondary)
        }
      }
      .buttonStyle(.plain)
      if isExpanded { detail }
    }
    .padding(18)
    .background(
      WriteItTheme.cardFill,
      in: RoundedRectangle(cornerRadius: WriteItTheme.cardCornerRadius, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: WriteItTheme.cardCornerRadius, style: .continuous).stroke(
        WriteItTheme.cardStroke)
    )
    .contextMenu {
      Button("Copy", action: copy)
      if hasRetainedInk { Button("Retry capture", action: onRetryCapture) }
      Button("Delete", role: .destructive, action: onDelete)
    }
  }

  @ViewBuilder private var detail: some View {
    Divider()
    if let strokes = entry.strokes, !strokes.isEmpty {
      HistoryInkPreview(strokes: strokes).frame(height: 72)
    }
    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
      ForEach(presentation.metadata) { item in
        GridRow {
          Text(item.title).foregroundStyle(.secondary)
          Label(item.value, systemImage: item.symbol)
        }
      }
    }
    .font(.caption)
    Label(
      presentation.privacyDetail,
      systemImage: presentation.hasRetainedInk ? "lock.fill" : "lock.slash"
    )
    .font(.caption)
    .foregroundStyle(.secondary)
    if let retryUnavailableDetail = presentation.retryUnavailableDetail {
      Text(retryUnavailableDetail).font(.caption).foregroundStyle(.secondary)
    }
    HStack {
      Spacer()
      if presentation.hasRetainedInk {
        Button("Retry capture", action: onRetryCapture).buttonStyle(.bordered)
      }
      Button("Copy", action: copy).buttonStyle(.bordered)
      Button("Delete", role: .destructive, action: onDelete).buttonStyle(.bordered)
    }
  }

  private var hasRetainedInk: Bool { presentation.hasRetainedInk }
  private var presentation: HistoryEntryPresentation { HistoryEntryPresentation(entry: entry) }

  private func copy() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(entry.text, forType: .string)
  }
}

private struct HistoryInkPreview: View {
  var strokes: [InkStroke]

  var body: some View {
    GeometryReader { proxy in
      Canvas { context, _ in
        let sourceWidth = max(strokes.flatMap(\.points).map(\.x).max() ?? 1, 1)
        let sourceHeight = max(strokes.flatMap(\.points).map(\.y).max() ?? 1, 1)
        let scale = min(proxy.size.width / sourceWidth, proxy.size.height / sourceHeight)
        for stroke in strokes where stroke.points.count > 1 {
          var path = Path()
          for (index, point) in stroke.points.enumerated() {
            let location = CGPoint(x: point.x * scale, y: point.y * scale)
            if index == 0 { path.move(to: location) } else { path.addLine(to: location) }
          }
          context.stroke(
            path, with: .color(.secondary),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
      }
    }
    .background(.tertiary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
}

private struct HistorySettingsSheet: View {
  @ObservedObject var history: HistoryStore
  @ObservedObject var preferences: Preferences
  var onCleanup: () -> Void
  @Binding var isPresented: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack {
        Text("History Settings").font(.title2.bold())
        Spacer()
        Button(action: { isPresented = false }) { Image(systemName: "xmark") }.buttonStyle(
          .bordered)
      }
      GroupBox("Capture History") {
        VStack(alignment: .leading, spacing: 14) {
          Picker("Retain captures", selection: $preferences.historyMode) {
            ForEach(HistoryMode.allCases) { Text($0.title).tag($0) }
          }
          Text(privacy.detail).font(.caption).foregroundStyle(.secondary)
          Toggle("Auto-delete capture history", isOn: $preferences.historyAutoDelete)
          if preferences.historyAutoDelete {
            Stepper(value: $preferences.historyRetentionDays, in: 1...365) {
              LabeledContent("Delete after", value: "\(preferences.historyRetentionDays) days")
            }
          }
          Button("Run cleanup now", action: onCleanup)
        }
        .padding(6)
      }
      Spacer()
    }
    .padding(24)
    .frame(width: 480, height: 340)
  }

  private var privacy: HistoryPrivacyPresentation {
    HistoryPrivacyPresentation(
      mode: preferences.historyMode,
      autoDelete: preferences.historyAutoDelete,
      retentionDays: preferences.historyRetentionDays
    )
  }
}
