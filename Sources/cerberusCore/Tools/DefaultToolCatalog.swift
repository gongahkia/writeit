import Foundation
import FoundationModels

public enum DefaultToolCatalog {
    public static var tools: [AnyAssistantTool] {
        makeTools()
    }

    public static func makeTools(
        includesUIElementTool: Bool = true,
        localVLMProvider: (any LocalVLMProviding)? = nil,
        localVLMOptions: LocalVLMRequestOptions = LocalVLMRequestOptions()
    ) -> [AnyAssistantTool] {
        var tools = [
            AnyAssistantTool(ScreenBarcodeTool()),
            AnyAssistantTool(ScreenOCRTool()),
            AnyAssistantTool(ScreenSnapshotTool())
        ]
        if let localVLMProvider {
            tools.append(AnyAssistantTool(ScreenDescribeTool(provider: localVLMProvider, options: localVLMOptions)))
        }
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
        auditLog: AuditLog? = nil,
        localVLMProvider: (any LocalVLMProviding)? = nil,
        localVLMOptions: LocalVLMRequestOptions = LocalVLMRequestOptions()
    ) -> [any FoundationModels.Tool] {
        var tools: [any FoundationModels.Tool] = [
            FoundationModelToolAdapter(ScreenBarcodeTool(), auditLog: auditLog),
            FoundationModelToolAdapter(ScreenOCRTool(), auditLog: auditLog),
            FoundationModelToolAdapter(ScreenSnapshotTool(), auditLog: auditLog),
            FoundationModelToolAdapter(ScreenUIElementsTool(), auditLog: auditLog)
        ]
        if let localVLMProvider {
            tools.append(FoundationModelToolAdapter(
                ScreenDescribeTool(provider: localVLMProvider, options: localVLMOptions),
                auditLog: auditLog
            ))
        }
        return tools
    }

    public static var readOnlyToolNames: Set<String> {
        Set(summaries.filter { !$0.mutatesState }.map(\.name))
    }

    public static var allReadOnlyToolNames: Set<String> {
        readOnlyToolNames.union(["screen.describe"])
    }
}
