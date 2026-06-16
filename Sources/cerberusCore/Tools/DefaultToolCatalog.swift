import Foundation
import FoundationModels

public enum DefaultToolCatalog {
    public static var tools: [AnyAssistantTool] {
        [
            AnyAssistantTool(AppControlTool()),
            AnyAssistantTool(CalendarTool()),
            AnyAssistantTool(FileSearchTool()),
            AnyAssistantTool(MailSearchTool()),
            AnyAssistantTool(MemoryReadTool()),
            AnyAssistantTool(MemoryWriteTool()),
            AnyAssistantTool(MusicNowPlayingTool()),
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

    public static func readOnlyFoundationModelTools(auditLog: AuditLog? = nil) -> [any FoundationModels.Tool] {
        [
            FoundationModelToolAdapter(CalendarTool(), auditLog: auditLog),
            FoundationModelToolAdapter(FileSearchTool(), auditLog: auditLog),
            FoundationModelToolAdapter(MailSearchTool(), auditLog: auditLog),
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
