import SwiftUI
import cerberusCore

struct StatusPanel: View {
    @ObservedObject var model: CerberusAppModel
    @State private var selectedSection: PanelSection = .session

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            sectionPicker

            switch selectedSection {
            case .session:
                controls
                transcript
                recentEvents
            case .history:
                history
            case .permissions:
                permissions
            }
        }
    }

    private var sectionPicker: some View {
        Picker("Panel", selection: $selectedSection) {
            ForEach(PanelSection.allCases) { section in
                Text(section.title).tag(section)
            }
        }
        .pickerStyle(.segmented)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: model.menuBarSystemImage)
                .font(.title2)
                .foregroundStyle(model.isMicrophoneActive ? .red : .primary)

            VStack(alignment: .leading, spacing: 2) {
                Text("cerberus")
                    .font(.headline)
                Text(model.state.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 8) {
            Button {
                model.startListening()
            } label: {
                Label("Listen", systemImage: "mic")
            }
            .disabled(model.state != .idle)

            Button {
                model.finishListeningAndProcess()
            } label: {
                Label("Run", systemImage: "play.fill")
            }
            .disabled(model.state != .listening)

            Button {
                model.cancel()
            } label: {
                Label("Cancel", systemImage: "xmark")
            }
            .disabled(model.state == .idle)
        }
        .buttonStyle(.bordered)

        if model.state == .awaitingConfirm {
            HStack(spacing: 8) {
                Button {
                    model.approvePendingConfirmation()
                } label: {
                    Label("Approve", systemImage: "checkmark")
                }

                Button(role: .cancel) {
                    model.denyPendingConfirmation()
                } label: {
                    Label("Deny", systemImage: "xmark")
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var transcript: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Request")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $model.transcriptDraft)
                .font(.body)
                .frame(minHeight: 78)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.quaternary)
                }
                .disabled(model.state != .listening)

            Text(model.statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let pendingConfirmation = model.pendingConfirmation {
                Text(pendingConfirmation.summary)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            }
        }
    }

    private var recentEvents: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent transitions")
                .font(.caption)
                .foregroundStyle(.secondary)

            if model.recentEvents.isEmpty {
                Text("No activity yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(model.recentEvents, id: \.self) { event in
                    Text(event)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Transcript history")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    model.refreshTranscriptRecords()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh transcript history")
            }

            if model.transcriptRecords.isEmpty {
                Text("No transcripts yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.transcriptRecords.prefix(20)) { record in
                            transcriptRow(record)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .task {
            model.refreshTranscriptRecords()
        }
    }

    private func transcriptRow(_ record: TranscriptRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(record.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if let toolName = record.toolName {
                    Text(toolName)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            Text(record.request)
                .font(.caption)
                .lineLimit(2)

            Text(record.response)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Permissions")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    model.refreshPermissions()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh permission status")
            }

            ForEach(model.permissionSnapshots) { snapshot in
                HStack(spacing: 8) {
                    statusDot(for: snapshot.state)

                    Text(snapshot.kind.displayName)
                        .font(.caption)

                    Spacer()

                    Text(snapshot.state.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        model.requestPermission(snapshot.kind)
                    } label: {
                        Image(systemName: "lock.open")
                    }
                    .buttonStyle(.plain)
                    .disabled(snapshot.state == .granted)
                    .help("Request \(snapshot.kind.displayName)")
                }
            }
        }
    }

    private func statusDot(for state: PermissionState) -> some View {
        Circle()
            .fill(color(for: state))
            .frame(width: 8, height: 8)
            .accessibilityLabel(state.displayName)
    }

    private func color(for state: PermissionState) -> Color {
        switch state {
        case .granted:
            .green
        case .denied, .restricted:
            .red
        case .notDetermined:
            .orange
        case .unknown:
            .gray
        }
    }
}

private enum PanelSection: String, CaseIterable, Identifiable {
    case session
    case history
    case permissions

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .session:
            "Session"
        case .history:
            "History"
        case .permissions:
            "Access"
        }
    }
}
