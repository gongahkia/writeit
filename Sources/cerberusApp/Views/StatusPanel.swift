import SwiftUI
import cerberusCore

struct StatusPanel: View {
    @ObservedObject var model: CerberusAppModel
    @State private var selectedSection: PanelSection = .session
    @State private var isToolAllowlistExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            setupBanner
            sectionPicker

            switch selectedSection {
            case .session:
                controls
                transcript
                recentEvents
            case .history:
                history
            case .audit:
                audit
            case .permissions:
                permissions
            case .settings:
                settings
            }
        }
        .onAppear {
            showOnboardingIfNeeded()
        }
        .onChange(of: model.shouldShowOnboarding) {
            showOnboardingIfNeeded()
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
    private var setupBanner: some View {
        if model.shouldShowOnboarding, let next = model.nextPermissionSnapshot {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    statusDot(for: next.state)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Setup \(model.grantedPermissionCount + 1) of \(model.permissionSnapshots.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(next.kind.displayName)
                            .font(.body)
                    }

                    Spacer()
                }

                HStack(spacing: 8) {
                    Button {
                        selectedSection = .permissions
                        model.requestNextPermission()
                    } label: {
                        Label("Request", systemImage: "lock.open")
                    }

                    Button {
                        selectedSection = .permissions
                    } label: {
                        Label("Access", systemImage: "slider.horizontal.3")
                    }

                    Spacer()

                    Button {
                        model.skipOnboarding()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .help("Skip setup")
                }
                .buttonStyle(.bordered)
            }
            .padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
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

        if let pendingMCPClientRequest = model.pendingMCPClientRequest {
            mcpClientRequestControls(pendingMCPClientRequest)
        }
    }

    private func mcpClientRequestControls(_ request: PendingMCPClientRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(request.title, systemImage: "server.rack")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(request.summary)
                .font(.caption)
                .lineLimit(3)

            Text(request.detail)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(4)

            Text(request.draftLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            if request.kind == .elicitation, !model.mcpElicitationFieldDrafts.isEmpty {
                ForEach($model.mcpElicitationFieldDrafts) { $draft in
                    elicitationField($draft)
                }
            } else {
                TextEditor(text: $model.mcpClientDraft)
                    .font(.caption.monospaced())
                    .frame(minHeight: 82)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.quaternary)
                    }
            }

            HStack(spacing: 8) {
                Button {
                    model.approveMCPClientRequest()
                } label: {
                    Label(request.approveTitle, systemImage: "checkmark")
                }

                if request.allowsDecline {
                    Button {
                        model.declineMCPClientRequest()
                    } label: {
                        Label("Decline", systemImage: "minus.circle")
                    }
                }

                Button(role: .cancel) {
                    model.cancelMCPClientRequest()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func elicitationField(_ draft: Binding<MCPClientElicitationFieldDraft>) -> some View {
        let field = draft.wrappedValue.field
        VStack(alignment: .leading, spacing: 4) {
            if field.type == .boolean {
                Toggle(field.displayName, isOn: Binding(
                    get: { draft.wrappedValue.value == "true" },
                    set: { draft.wrappedValue.value = $0 ? "true" : "false" }
                ))
                .font(.caption)
            } else if !field.enumValues.isEmpty {
                Picker(field.displayName, selection: draft.value) {
                    ForEach(Array(field.enumValues.enumerated()), id: \.element) { index, value in
                        Text(index < field.enumNames.count ? field.enumNames[index] : value)
                            .tag(value)
                    }
                }
                .font(.caption)
            } else {
                TextField(field.displayName, text: draft.value)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }

            if let description = field.description, !description.isEmpty {
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
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
                    model.exportTranscriptRecords()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .help("Export transcript history")
                .disabled(model.transcriptRecords.isEmpty)

                Button(role: .destructive) {
                    model.deleteTranscriptRecords()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Delete transcript history")
                .disabled(model.transcriptRecords.isEmpty)

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

    private var audit: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tool calls")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    model.answerLastToolAction()
                } label: {
                    Label("What did cerberus just do?", systemImage: "questionmark.circle")
                }
                .buttonStyle(.bordered)

                Button {
                    model.refreshAuditEntries()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh tool calls")
            }

            if model.recentAuditEntries.isEmpty {
                Text("No tool calls yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.recentAuditEntries, id: \.hash) { entry in
                            auditRow(entry)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .task {
            model.refreshAuditEntries()
        }
    }

    private func auditRow(_ entry: AuditLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(entry.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Text(entry.toolName)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            Text(entry.argumentsSummary.isEmpty ? "No arguments" : entry.argumentsSummary)
                .font(.caption)
                .lineLimit(2)

            Text(entry.resultSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
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
            onboardingStep

            Divider()

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

    @ViewBuilder
    private var onboardingStep: some View {
        if let next = model.nextPermissionSnapshot {
            VStack(alignment: .leading, spacing: 8) {
                Text("Setup \(model.grantedPermissionCount + 1) of \(model.permissionSnapshots.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    statusDot(for: next.state)
                    Text(next.kind.displayName)
                        .font(.body)

                    Spacer()

                    Button {
                        model.requestNextPermission()
                    } label: {
                        Label("Request", systemImage: "lock.open")
                    }

                    Button {
                        model.skipOnboarding()
                    } label: {
                        Label("Skip", systemImage: "xmark")
                    }
                }
            }
        } else {
            Label("Setup complete", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.green)
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Auto-run after silence", isOn: $model.isAutoSilenceEnabled)
            Toggle("Voice confirmation", isOn: $model.isVoiceConfirmationEnabled)
            Toggle("Wake phrase", isOn: $model.isWakeWordEnabled)
            TextField("Wake phrase", text: $model.wakePhrase)
                .textFieldStyle(.roundedBorder)
                .disabled(model.isWakeWordMonitoring)
            Toggle("Use sound wake model", isOn: $model.prefersSoundWakeWordClassifier)
                .disabled(model.isWakeWordMonitoring)
            Text(model.wakeWordMonitorLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Button {
                selectedSection = .permissions
                model.resetOnboarding()
            } label: {
                Label("Reset setup", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            Toggle("MCP tool", isOn: $model.isMCPToolEnabled)
            Label(model.mcpListenerStatusLine, systemImage: "network")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Toggle("Shell tool", isOn: $model.isShellToolEnabled)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Foundation Models")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        model.refreshFoundationModelStatus()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Refresh Foundation Models status")
                }

                Label(model.foundationModelAvailabilityLine, systemImage: "brain")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Label(model.foundationModelAdapterStatusLine, systemImage: "shippingbox")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Screen snapshots")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        model.refreshScreenSnapshotStatus()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Refresh screen snapshot status")
                }

                Label(model.screenSnapshotStatusLine, systemImage: "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Button {
                        model.openLatestScreenSnapshot()
                    } label: {
                        Label("Open latest", systemImage: "photo")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.screenSnapshotCount == 0)

                    Button(role: .destructive) {
                        model.deleteScreenSnapshots()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.screenSnapshotCount == 0)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Hotkey")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Control Option Space")
                    .font(.caption.monospaced())
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Speech output")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        model.refreshAudioOutputRoute()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Refresh speech output route")
                }

                Label(model.audioOutputRouteLine, systemImage: model.isAudioOutputLikelyAirPods ? "airpodspro" : "speaker.wave.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Toggle("Route speech directly to AirPods", isOn: $model.routesSpeechDirectlyToAirPods)
                    .font(.caption)

                Text(model.speechOutputRoutingLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Button {
                model.calibrateHeadGestures()
            } label: {
                Label("Calibrate AirPods", systemImage: "airpodspro")
            }
            .buttonStyle(.bordered)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("AirPods gestures")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        model.resetHeadGestureThresholds()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Reset gesture thresholds")
                }

                gestureSlider("Nod", value: $model.headNodThreshold)
                gestureSlider("Shake", value: $model.headShakeThreshold)
                Toggle("Log gesture validation CSV", isOn: $model.isHeadGestureValidationLoggingEnabled)
                    .font(.caption)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Enabled tools")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.enabledToolDisplayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("File search folders")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        model.addFileSearchScope()
                    } label: {
                        Label("Add", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.bordered)
                }

                if model.fileSearchScopePaths.isEmpty {
                    Text("No folders approved")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(model.fileSearchScopePaths, id: \.self) { path in
                        HStack(spacing: 8) {
                            Text(path)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer()

                            Button {
                                model.removeFileSearchScope(path)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .help("Remove file search folder")
                        }
                    }
                }
            }

            DisclosureGroup(isExpanded: $isToolAllowlistExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.availableAmbientToolSummaries, id: \.name) { summary in
                        Toggle(isOn: Binding(
                            get: { model.isAmbientToolEnabled(summary.name) },
                            set: { model.setAmbientTool(summary.name, enabled: $0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(summary.name)
                                    .font(.caption.monospaced())
                                Text(summary.capability)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }

                    Button {
                        model.resetAmbientToolAllowlist()
                    } label: {
                        Label("Reset tool allowlist", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.disabledAmbientToolCount == 0)
                }
                .padding(.top, 6)
            } label: {
                Label("Tool allowlist", systemImage: "checklist")
                    .font(.caption)
            }
        }
        .toggleStyle(.switch)
    }

    private func gestureSlider(_ label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)

                Spacer()

                Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(value: value, in: 0.15...0.8, step: 0.05)
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
        case .writeOnly:
            .yellow
        case .denied, .restricted:
            .red
        case .notDetermined:
            .orange
        case .unknown:
            .gray
        }
    }

    private func showOnboardingIfNeeded() {
        if model.shouldShowOnboarding {
            selectedSection = .permissions
        }
    }
}

private enum PanelSection: String, CaseIterable, Identifiable {
    case session
    case history
    case audit
    case permissions
    case settings

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .session:
            "Session"
        case .history:
            "History"
        case .audit:
            "Audit"
        case .permissions:
            "Access"
        case .settings:
            "Settings"
        }
    }
}
