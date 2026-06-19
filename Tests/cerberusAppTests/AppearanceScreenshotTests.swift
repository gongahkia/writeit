import AppKit
import Foundation
import FoundationModels
import SwiftUI
import Testing
@testable import cerberusApp
import cerberusCore

@MainActor
private final class AppearanceScreenshotPermissionCenter: PermissionChecking {
    func currentSnapshots() -> [PermissionSnapshot] {
        SystemPermission.allCases.map { PermissionSnapshot(kind: $0, state: .granted) }
    }

    func request(_ kind: SystemPermission) async -> PermissionSnapshot {
        PermissionSnapshot(kind: kind, state: .granted)
    }
}

@MainActor
private final class AppearanceScreenshotTranscriber: AppTranscribing {
    var isRunning = false

    func start(
        locale requestedLocale: Locale,
        onUpdate: @escaping @MainActor @Sendable (TranscriptionUpdate) -> Void
    ) async throws {}

    func stop() async {}
    func cancel() async {}
}

@MainActor
private final class AppearanceScreenshotSpeaker: AppSpeaking {
    func setPreferredOutputDevice(_ device: AudioOutputDevice?) {}

    func speak(
        _ text: String,
        rate: Float,
        completion: (@MainActor @Sendable () -> Void)?
    ) {}

    func stop() {}
}

private actor AppearanceScreenshotAssistant: AppAssistanting {
    func updateToolConfiguration(
        toolSummaries: [ToolSummary],
        readOnlyNativeTools: [any FoundationModels.Tool]
    ) async {}

    func updateModel(_ model: SystemLanguageModel) async {}

    func plan(for request: String, context: AssistantContext) async throws -> AssistantPlan {
        AssistantPlan(intent: .answerDirectly, spokenResponse: "ready", requiresConfirmation: false)
    }

    func answerWithReadOnlyTools(for request: String, context: AssistantContext) async throws -> String {
        "ready"
    }

    func sampleForMCP(messagesText: String, systemPrompt: String?) async throws -> String {
        "sample"
    }

    func summarize(toolResult: ToolResult, for request: String) async throws -> String {
        "done"
    }
}

@MainActor
@Test func renderDarkLightAppearanceReviewScreenshots() throws {
    guard let outputDirectory = ProcessInfo.processInfo.environment["CERBERUS_APPEARANCE_SCREENSHOT_DIR"] else {
        return
    }

    let outputURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

    try renderAppearanceScreenshot(
        colorScheme: .light,
        outputURL: outputURL.appendingPathComponent("appearance-review-light.png")
    )
    try renderAppearanceScreenshot(
        colorScheme: .dark,
        outputURL: outputURL.appendingPathComponent("appearance-review-dark.png")
    )
}

@MainActor
private func renderAppearanceScreenshot(colorScheme: ColorScheme, outputURL: URL) throws {
    let model = CerberusAppModel(
        transcriber: AppearanceScreenshotTranscriber(),
        wakeWordTranscriber: AppearanceScreenshotTranscriber(),
        speaker: AppearanceScreenshotSpeaker(),
        assistant: AppearanceScreenshotAssistant(),
        permissionCenter: AppearanceScreenshotPermissionCenter(),
        startsRuntimeServices: false,
        skipsFoundationModelAvailabilityCheck: true
    )
    model.selectedPanelSection = .session

    let appearanceName: NSAppearance.Name = colorScheme == .dark ? .darkAqua : .aqua
    let backgroundColor = colorScheme == .dark ? Color.black : Color.white
    let hostingView = NSHostingView(
        rootView: ZStack(alignment: .topLeading) {
            backgroundColor
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            StatusPanel(model: model)
                .frame(width: 340)
                .padding(14)
        }
        .environment(\.colorScheme, colorScheme)
    )
    hostingView.appearance = NSAppearance(named: appearanceName)
    hostingView.frame = NSRect(x: 0, y: 0, width: 368, height: 640)
    hostingView.layoutSubtreeIfNeeded()

    guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
        throw CocoaError(.fileWriteUnknown)
    }
    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: outputURL, options: .atomic)
}
