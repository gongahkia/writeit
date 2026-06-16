import Foundation
import FoundationModels
import Testing
@testable import cerberusCore

private struct EchoTool: AssistantTool {
    @Generable
    struct Arguments: Codable, Sendable {
        let text: String
    }

    let name = "test.echo"
    let capability = "Echo test text."
    let mutatesState = false
    let argumentSchema = #"{"text":"hello"}"#

    func run(arguments: Arguments) async throws -> ToolResult {
        ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: arguments.text,
            untrustedPayload: arguments.text
        )
    }
}

@Test func registryRunsTypedTool() async throws {
    let registry = try ToolRegistry(tools: [AnyAssistantTool(EchoTool())])
    let invocation = try ToolInvocation(
        toolName: "test.echo",
        arguments: EchoTool.Arguments(text: "hello")
    )

    let result = try await registry.run(invocation)

    #expect(result.succeeded)
    #expect(result.spokenSummary == "hello")
}

@Test func foundationModelToolAdapterRunsAssistantTool() async throws {
    let adapter = FoundationModelToolAdapter(EchoTool())

    let output = try await adapter.call(arguments: EchoTool.Arguments(text: "hello"))

    #expect(output.contains("hello"))
}

@Test func defaultNativeToolCatalogIsReadOnly() {
    #expect(DefaultToolCatalog.readOnlyToolNames.contains("calendar.read"))
    #expect(DefaultToolCatalog.readOnlyToolNames.contains("memory.read"))
    #expect(DefaultToolCatalog.readOnlyToolNames.contains("web.search"))
    #expect(!DefaultToolCatalog.readOnlyToolNames.contains("app.control"))
    #expect(!DefaultToolCatalog.readOnlyToolNames.contains("memory.write"))
}

@Test func registryRequiresConfirmationForMutatingTools() async throws {
    struct MutatingTool: AssistantTool {
        struct Arguments: Codable, Sendable {}

        let name = "test.mutate"
        let capability = "Mutate test state."
        let mutatesState = true
        let argumentSchema = #"{}"#

        func run(arguments: Arguments) async throws -> ToolResult {
            ToolResult(toolName: name, succeeded: true, spokenSummary: "mutated")
        }
    }

    let registry = try ToolRegistry(tools: [AnyAssistantTool(MutatingTool())])
    let invocation = try ToolInvocation(toolName: "test.mutate", arguments: MutatingTool.Arguments())

    var requiredConfirmation = false
    do {
        _ = try await registry.run(invocation)
    } catch ToolExecutionError.confirmationRequired(let name) {
        requiredConfirmation = name == "test.mutate"
    } catch {
        requiredConfirmation = false
    }

    #expect(requiredConfirmation)
}
