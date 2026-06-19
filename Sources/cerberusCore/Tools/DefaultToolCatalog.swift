import Foundation
import FoundationModels

public enum DefaultToolCatalog {
    public static var tools: [AnyAssistantTool] {
        makeTools()
    }

    public static func makeTools(
        fileSearchTool: FileSearchTool = FileSearchTool(),
        mailSearchTool: MailSearchTool = MailSearchTool()
    ) -> [AnyAssistantTool] {
        [
            AnyAssistantTool(AppControlTool()),
            AnyAssistantTool(CalendarCreateTool()),
            AnyAssistantTool(CalendarDeleteTool()),
            AnyAssistantTool(CalendarEditTool()),
            AnyAssistantTool(CalendarTool()),
            AnyAssistantTool(ContactsTool()),
            AnyAssistantTool(fileSearchTool),
            AnyAssistantTool(mailSearchTool),
            AnyAssistantTool(MemoryDeleteTool()),
            AnyAssistantTool(MemoryReadTool()),
            AnyAssistantTool(MemoryWriteTool()),
            AnyAssistantTool(MusicControlTool()),
            AnyAssistantTool(MusicNowPlayingTool()),
            AnyAssistantTool(NotesSearchTool()),
            AnyAssistantTool(RemindersCompleteTool()),
            AnyAssistantTool(RemindersCreateTool()),
            AnyAssistantTool(RemindersDeleteTool()),
            AnyAssistantTool(RemindersEditTool()),
            AnyAssistantTool(RemindersTool()),
            AnyAssistantTool(ScreenBarcodeTool()),
            AnyAssistantTool(ScreenOCRTool()),
            AnyAssistantTool(ScreenSnapshotTool()),
            AnyAssistantTool(WebSearchTool())
        ]
    }

    public static var summaries: [ToolSummary] {
        tools
            .map(\.summary)
            .sorted { $0.name < $1.name }
    }

    public static func readOnlyFoundationModelTools(
        auditLog: AuditLog? = nil,
        fileSearchTool: FileSearchTool = FileSearchTool(),
        mailSearchTool: MailSearchTool = MailSearchTool()
    ) -> [any FoundationModels.Tool] {
        [
            FoundationModelToolAdapter(CalendarTool(), auditLog: auditLog),
            FoundationModelToolAdapter(ContactsTool(), auditLog: auditLog),
            FoundationModelToolAdapter(fileSearchTool, auditLog: auditLog),
            FoundationModelToolAdapter(mailSearchTool, auditLog: auditLog),
            FoundationModelToolAdapter(MemoryReadTool(), auditLog: auditLog),
            FoundationModelToolAdapter(MusicNowPlayingTool(), auditLog: auditLog),
            FoundationModelToolAdapter(NotesSearchTool(), auditLog: auditLog),
            FoundationModelToolAdapter(RemindersTool(), auditLog: auditLog),
            FoundationModelToolAdapter(ScreenBarcodeTool(), auditLog: auditLog),
            FoundationModelToolAdapter(ScreenOCRTool(), auditLog: auditLog),
            FoundationModelToolAdapter(ScreenSnapshotTool(), auditLog: auditLog),
            FoundationModelToolAdapter(WebSearchTool(), auditLog: auditLog)
        ]
    }

    public static var readOnlyToolNames: Set<String> {
        Set(summaries.filter { !$0.mutatesState }.map(\.name))
    }
}
