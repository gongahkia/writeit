import Foundation

public enum DefaultToolCatalog {
    public static var tools: [AnyAssistantTool] {
        [
            AnyAssistantTool(AppControlTool()),
            AnyAssistantTool(CalendarTool()),
            AnyAssistantTool(RemindersTool())
        ]
    }

    public static var summaries: [ToolSummary] {
        tools
            .map(\.summary)
            .sorted { $0.name < $1.name }
    }
}
