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

private actor RecordingMCPToolRunner: MCPToolRunning {
    private(set) var calls: [(serverName: String, toolName: String, argumentsJSON: String)] = []

    func call(serverName: String, toolName: String, argumentsJSON: String) async throws -> MCPToolCallResult {
        calls.append((serverName, toolName, argumentsJSON))
        return MCPToolCallResult(isError: false, contentText: #"{"ok":true}"#)
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
    #expect(DefaultToolCatalog.readOnlyToolNames.contains("mail.search"))
    #expect(DefaultToolCatalog.readOnlyToolNames.contains("memory.read"))
    #expect(DefaultToolCatalog.readOnlyToolNames.contains("screen.ocr"))
    #expect(DefaultToolCatalog.readOnlyToolNames.contains("screen.snapshot"))
    #expect(DefaultToolCatalog.readOnlyToolNames.contains("web.search"))
    #expect(!DefaultToolCatalog.readOnlyToolNames.contains("app.control"))
    #expect(!DefaultToolCatalog.readOnlyToolNames.contains("memory.write"))
}

@Test func mcpDynamicNativeToolAdapterCallsConfiguredRunner() async throws {
    let descriptor = MCPToolDescriptor(
        name: "lookup",
        title: "Lookup",
        description: "Lookup local data.",
        inputSchemaJSON: """
        {"type":"object","properties":{"limit":{"type":"integer"},"query":{"type":"string"}},"required":["query"]}
        """
    )
    let runner = RecordingMCPToolRunner()
    let adapter = try MCPDynamicNativeToolAdapter(serverName: "local demo", descriptor: descriptor, runner: runner)

    let output = try await adapter.call(arguments: GeneratedContent(json: #"{"query":"mail","limit":2}"#))
    let calls = await runner.calls

    #expect(adapter.name == "mcp.local_demo.lookup")
    #expect(output.contains(#""ok":true"#))
    #expect(calls.count == 1)
    #expect(calls.first?.serverName == "local demo")
    #expect(calls.first?.toolName == "lookup")
    let argumentsData = Data((calls.first?.argumentsJSON ?? "{}").utf8)
    let arguments = try JSONSerialization.jsonObject(with: argumentsData) as? [String: Any]
    #expect(arguments?["query"] as? String == "mail")
    #expect(arguments?["limit"] as? Int == 2)
}

@Test func mcpDynamicNativeToolSchemaRejectsNestedSchemas() throws {
    let descriptor = MCPToolDescriptor(
        name: "nested",
        title: nil,
        description: nil,
        inputSchemaJSON: #"{"type":"object","properties":{"item":{"type":"object","properties":{"name":{"type":"string"}}}}}"#
    )

    #expect(throws: ToolExecutionError.self) {
        try MCPDynamicNativeToolSchema.parameters(for: descriptor, serverName: "local")
    }
}

@Test func mcpConfigurationDecodesNativeReadOnlyAllowlist() throws {
    let data = Data("""
    {"servers":[{"name":"local","executable":"node","nativeReadOnlyTools":["lookup"]}]}
    """.utf8)

    let file = try JSONDecoder().decode(MCPConfigurationFile.self, from: data)

    #expect(file.servers.first?.nativeReadOnlyTools == ["lookup"])
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
