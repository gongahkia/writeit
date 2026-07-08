import Foundation
import FoundationModels

public enum DefaultToolCatalog {
    public static var tools: [AnyAssistantTool] {
        makeTools()
    }

    public static func makeTools(includesUIElementTool: Bool = true) -> [AnyAssistantTool] {
        var tools = [
            AnyAssistantTool(ScreenBarcodeTool()),
            AnyAssistantTool(ScreenOCRTool()),
            AnyAssistantTool(ScreenSnapshotTool())
        ]
        if includesUIElementTool {
            tools.append(AnyAssistantTool(ScreenUIElementsTool()))
        }
        return tools
    }

    public static var summaries: [ToolSummary] {
        tools
            .map(\.summary)
            .sorted { $0.name < $1.name }
    }

    public static func readOnlyFoundationModelTools(
        auditLog: AuditLog? = nil
    ) -> [any FoundationModels.Tool] {
        [
            FoundationModelToolAdapter(ScreenBarcodeTool(), auditLog: auditLog),
            FoundationModelToolAdapter(ScreenOCRTool(), auditLog: auditLog),
            FoundationModelToolAdapter(ScreenSnapshotTool(), auditLog: auditLog),
            FoundationModelToolAdapter(ScreenUIElementsTool(), auditLog: auditLog)
        ]
    }

    public static var readOnlyToolNames: Set<String> {
        Set(summaries.filter { !$0.mutatesState }.map(\.name))
    }
}
