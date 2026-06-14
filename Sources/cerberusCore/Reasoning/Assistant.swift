import Foundation
import FoundationModels

public actor Assistant {
    private var session: LanguageModelSession
    private var toolSummaries: [ToolSummary]

    public init(toolSummaries: [ToolSummary] = []) {
        self.toolSummaries = toolSummaries
        session = LanguageModelSession(
            instructions: SystemPrompt.render(toolSummaries: toolSummaries)
        )
    }

    public func updateTools(_ toolSummaries: [ToolSummary]) {
        self.toolSummaries = toolSummaries
        session = LanguageModelSession(
            instructions: SystemPrompt.render(toolSummaries: toolSummaries)
        )
    }

    public func prewarm() {
        session.prewarm()
    }

    public func plan(for request: String, context: AssistantContext = AssistantContext()) async throws -> AssistantPlan {
        let prompt = """
        Context:
        \(context.promptFragment)

        User request:
        \(request)
        """

        let response = try await session.respond(
            to: prompt,
            generating: AssistantPlan.self
        )
        return response.content
    }
}
