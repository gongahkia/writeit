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
            AnyAssistantTool(CalendarTool()),
            AnyAssistantTool(fileSearchTool),
            AnyAssistantTool(mailSearchTool),
            AnyAssistantTool(MemoryReadTool()),
            AnyAssistantTool(MemoryWriteTool()),
            AnyAssistantTool(MusicControlTool()),
            AnyAssistantTool(MusicNowPlayingTool()),
            AnyAssistantTool(RemindersCompleteTool()),
            AnyAssistantTool(RemindersCreateTool()),
            AnyAssistantTool(RemindersTool()),
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
            FoundationModelToolAdapter(fileSearchTool, auditLog: auditLog),
            FoundationModelToolAdapter(mailSearchTool, auditLog: auditLog),
            FoundationModelToolAdapter(MemoryReadTool(), auditLog: auditLog),
            FoundationModelToolAdapter(MusicNowPlayingTool(), auditLog: auditLog),
            FoundationModelToolAdapter(RemindersTool(), auditLog: auditLog),
            FoundationModelToolAdapter(ScreenOCRTool(), auditLog: auditLog),
            FoundationModelToolAdapter(ScreenSnapshotTool(), auditLog: auditLog),
            FoundationModelToolAdapter(WebSearchTool(), auditLog: auditLog)
        ]
    }

    public static var readOnlyToolNames: Set<String> {
        Set(summaries.filter { !$0.mutatesState }.map(\.name))
    }
}
