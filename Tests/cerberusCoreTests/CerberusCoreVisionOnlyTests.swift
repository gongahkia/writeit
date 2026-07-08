import Foundation
import Testing
@testable import cerberusCore

@Test func defaultToolCatalogContainsOnlyScreenTools() {
    let names = DefaultToolCatalog.summaries.map(\.name)

    #expect(names == [
        "screen.barcodes",
        "screen.ocr",
        "screen.snapshot",
        "screen.ui_elements"
    ])
    #expect(DefaultToolCatalog.summaries.allSatisfy { !$0.mutatesState })
}

@Test func defaultNativeToolCatalogContainsOnlyScreenTools() {
    let names = DefaultToolCatalog.readOnlyFoundationModelTools().map(\.name).sorted()

    #expect(names == [
        "screen.barcodes",
        "screen.ocr",
        "screen.snapshot",
        "screen.ui_elements"
    ])
}

@Test func toolProfileIsVisionOnly() {
    let configuration = ToolProfile.visionOnly.configuration(ambientSummaries: DefaultToolCatalog.summaries)

    #expect(ToolProfile.allCases == [.visionOnly])
    #expect(ToolProfile.profile(id: "unknown") == .visionOnly)
    #expect(configuration.disabledAmbientToolNames.isEmpty)
    #expect(!configuration.requiresConfirmationForAllTools)
}

@Test func toolEnablementFiltersOnlyAmbientScreenTools() {
    var allowlist = ToolSessionAllowlist()
    allowlist.setEnabled("screen.ocr", enabled: false)

    let names = ToolEnablementPolicy(ambientAllowlist: allowlist)
        .enabledSummaries(ambientSummaries: DefaultToolCatalog.summaries)
        .map(\.name)

    #expect(names == [
        "screen.barcodes",
        "screen.snapshot",
        "screen.ui_elements"
    ])
}

@Test func systemPromptRefusesComputerUse() {
    let prompt = SystemPrompt.render(toolSummaries: DefaultToolCatalog.summaries)
    func toolName(_ lhs: String, _ rhs: String) -> String {
        "\(lhs).\(rhs)"
    }

    #expect(prompt.contains("screen-reading assistant"))
    #expect(prompt.contains("Never claim that you opened apps, clicked, typed"))
    #expect(prompt.contains("Refuse requests that require operating the computer"))
    #expect(!prompt.contains(toolName("shell", "run")))
    #expect(!prompt.contains(toolName("mcp", "call")))
    #expect(!prompt.contains(toolName("app", "control")))
}

@Test func assistantContextExposesOnlyScreenToolContext() {
    let context = AssistantContext(
        activeApplicationName: "Xcode",
        allowedToolNames: DefaultToolCatalog.summaries.map(\.name),
        activeApplicationHints: ["Use screen reads only; never operate the app."]
    )

    #expect(context.promptFragment.contains("Active app: Xcode"))
    #expect(context.promptFragment.contains("Allowed tools: screen.barcodes, screen.ocr, screen.snapshot, screen.ui_elements"))
    #expect(!context.promptFragment.contains("File search folders"))
}

@Test func screenSnapshotPayloadPointsBackToScreenTools() {
    let payload = ScreenSnapshotTool.payload(
        fileURL: URL(fileURLWithPath: "/tmp/screen.png"),
        imageSize: CGSize(width: 1200, height: 800)
    )

    #expect(payload.contains("screen.ocr"))
    #expect(payload.contains("1200x800"))
}

@Test func forbiddenComputerUseToolNamesAreAbsent() {
    func name(_ parts: String...) -> String {
        parts.joined(separator: ".")
    }

    let forbidden = [
        name("app", "control"),
        name("browser", "open_url"),
        name("browser", "tabs"),
        name("calendar", "read"),
        name("contacts", "search"),
        name("files", "search"),
        name("finder", "reveal"),
        name("mail", "search"),
        name("mcp", "call"),
        name("memory", "write"),
        name("music", "control"),
        name("notes", "search"),
        name("reminders", "create"),
        name("shell", "run"),
        name("shortcuts", "run"),
        name("web", "search")
    ]
    let names = Set(DefaultToolCatalog.summaries.map(\.name))

    #expect(forbidden.allSatisfy { !names.contains($0) })
}
