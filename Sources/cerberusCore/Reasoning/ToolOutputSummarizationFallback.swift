import Foundation

public enum ToolOutputSummarizationFallback {
    public static func spokenResponse(
        for result: ToolResult,
        request: String,
        summarize: @Sendable (ToolResult, String) async throws -> String
    ) async -> String {
        do {
            return try await summarize(result, request)
        } catch {
            return result.spokenSummary
        }
    }
}
