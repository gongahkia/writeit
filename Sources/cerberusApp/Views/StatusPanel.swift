import AppKit
import SwiftUI
import cerberusCore

struct StatusPanel: View {
    @ObservedObject var model: CerberusAppModel
    @State private var isToolAllowlistExpanded = false
    @State private var isToolConfirmationExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            setupBanner
            sectionPicker

            switch model.selectedPanelSection {
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
                ScrollView(.vertical) {
                    settings
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 520)
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
        Picker("Panel", selection: $model.selectedPanelSection) {
            ForEach(PanelSection.allCases) { section in
                Text(section.title).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var header: some View {
        HStack(spacing: 10) {
            MascotSpriteView(
                state: model.state,
                tint: model.menuBarStatusTint == .red ? .red : .primary
            )
                .frame(width: 36, height: 36)

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
                    MascotSpriteView(
                        state: model.state,
                        tint: model.menuBarStatusTint == .red ? .red : .primary
                    )
                        .frame(width: 26, height: 26)
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
                        model.openSetupAccessPanelIfNeeded()
                        model.requestNextPermission()
                    } label: {
                        Label("Request", systemImage: "lock.open")
                    }

                    Button {
                        model.openSetupAccessPanelIfNeeded()
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
                    .accessibilityLabel("Skip setup")
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
                .accessibilityLabel("Export transcript history")
                .help("Export transcript history")
                .disabled(model.transcriptRecords.isEmpty)

                Button(role: .destructive) {
                    model.deleteTranscriptRecords()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete transcript history")
                .help("Delete transcript history")
                .disabled(model.transcriptRecords.isEmpty)

                Button {
                    model.refreshTranscriptRecords()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh transcript history")
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

                Button(role: .destructive) {
                    model.deleteAuditEntries()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear tool calls")
                .help("Clear tool calls")
                .disabled(model.recentAuditEntries.isEmpty)

                Button {
                    model.refreshAuditEntries()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh tool calls")
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
                .accessibilityLabel("Refresh permission status")
                .help("Refresh permission status")
            }

            ForEach(model.permissionSnapshots) { snapshot in
                VStack(alignment: .leading, spacing: 3) {
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
                        .accessibilityLabel("Request \(snapshot.kind.displayName)")
                        .disabled(snapshot.state == .granted)
                        .help("Request \(snapshot.kind.displayName)")
                    }

                    if let recoveryCopy = snapshot.recoveryCopy {
                        Text(recoveryCopy)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
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
            VStack(alignment: .leading, spacing: 4) {
                Label("Setup complete", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)

                Text(model.setupChecklistSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Vision only", systemImage: "eye")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Auto-run after silence", isOn: $model.isAutoSilenceEnabled)
            Toggle("Voice confirmation", isOn: $model.isVoiceConfirmationEnabled)
            Toggle("Confirm every action", isOn: $model.requiresConfirmationForAllTools)
            toolConfirmationOverrides
            Toggle("Wake phrase", isOn: $model.isWakeWordEnabled)
            TextField("Wake phrase", text: $model.wakePhrase)
                .textFieldStyle(.roundedBorder)
                .disabled(model.isWakeWordMonitoring)
            Toggle("Use wake sound detector", isOn: $model.prefersSoundWakeWordClassifier)
                .disabled(model.isWakeWordMonitoring)
            Text(model.wakeWordMonitorLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Button {
                model.selectedPanelSection = .permissions
                model.resetOnboarding()
            } label: {
                Label("Reset setup", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            Toggle("Keep model local", isOn: $model.requiresLocalFoundationModels)
            Toggle("Use custom model add-on", isOn: $model.usesConfiguredAdapter)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Local model")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        model.refreshFoundationModelStatus()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Refresh local model status")
                    .help("Refresh local model status")
                }

                Label(model.foundationModelAvailabilityLine, systemImage: "brain")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(model.foundationModelAvailabilityDetailLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                Label(model.foundationModelAdapterStatusLine, systemImage: "shippingbox")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Label(model.localVLMStatusLine, systemImage: "eye")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text("Non-local VLM endpoints receive screenshots and prompts; localhost is required unless config explicitly allows a remote host.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                Label(model.foundationModelPrivacyStatusLine, systemImage: "lock")
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
                    .accessibilityLabel("Refresh screen snapshot status")
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
                Picker("Hotkey", selection: $model.hotKeyConfigurationID) {
                    ForEach(model.hotKeyPresets) { preset in
                        Text(preset.displayName).tag(preset.id)
                    }
                }
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
                    .accessibilityLabel("Refresh speech output route")
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
                    .accessibilityLabel("Reset gesture thresholds")
                    .help("Reset gesture thresholds")
                }

                gestureSlider("Nod", value: $model.headNodThreshold)
                gestureSlider("Shake", value: $model.headShakeThreshold)
                cooldownSlider("Cooldown", value: $model.headGestureCooldownSeconds)
                HStack {
                    Button {
                        model.exportHeadGestureThresholdProfile()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        model.importHeadGestureThresholdProfile()
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                }
                Toggle("Save gesture test log", isOn: $model.isHeadGestureValidationLoggingEnabled)
                    .font(.caption)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Available actions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.enabledToolDisplayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("App data")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    model.exportDiagnosticsBundle()
                } label: {
                    Label("Export diagnostics", systemImage: "stethoscope")
                }
                .buttonStyle(.bordered)

                ForEach(model.appDataLocations) { location in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(location.name)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(location.url.path)
                                .font(.caption2.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        Button {
                            model.revealAppDataLocation(location)
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Reveal \(location.name) in Finder")
                        .help("Reveal \(location.name) in Finder")
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
                        Label("Reset actions", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.disabledAmbientToolCount == 0)
                }
                .padding(.top, 6)
            } label: {
                Label("Available actions", systemImage: "checklist")
                    .font(.caption)
            }

            Divider()

            Button("Quit cerberus", systemImage: "power", action: quit)
                .buttonStyle(.bordered)
        }
        .toggleStyle(.switch)
    }

    private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private var toolConfirmationOverrides: some View {
        DisclosureGroup(isExpanded: $isToolConfirmationExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.availableAmbientToolSummaries, id: \.name) { summary in
                    Toggle(isOn: Binding(
                        get: { model.requiresConfirmationOverride(summary.name) },
                        set: { model.setConfirmationOverride(summary.name, requiresConfirmation: $0) }
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
                    model.resetConfirmationOverrides()
                } label: {
                    Label("Reset confirmations", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .disabled(model.toolConfirmationOverrideCount == 0)
            }
            .padding(.top, 6)
        } label: {
            Label("Confirm actions", systemImage: "checkmark.shield")
                .font(.caption)
        }
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

    private func cooldownSlider(_ label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)

                Spacer()

                Text("\(value.wrappedValue, format: .number.precision(.fractionLength(1)))s")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(value: value, in: 0.3...3.0, step: 0.1)
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
        model.openSetupAccessPanelIfNeeded()
    }
}

enum PanelSection: String, CaseIterable, Identifiable {
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
