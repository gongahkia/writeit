import Foundation

public protocol AssistantTool: Sendable {
    associatedtype Arguments: Codable & Sendable

    var name: String { get }
    var capability: String { get }
    var mutatesState: Bool { get }

    func validate(_ arguments: Arguments) throws
    func run(arguments: Arguments) async throws -> ToolResult
}

public extension AssistantTool {
    var summary: ToolSummary {
        ToolSummary(name: name, capability: capability, mutatesState: mutatesState)
    }

    func validate(_ arguments: Arguments) throws {}
}

public struct AnyAssistantTool: Sendable {
    public let name: String
    public let capability: String
    public let mutatesState: Bool

    private let runClosure: @Sendable (Data) async throws -> ToolResult

    public init<Tool: AssistantTool>(_ tool: Tool) {
        name = tool.name
        capability = tool.capability
        mutatesState = tool.mutatesState

        runClosure = { data in
            do {
                let arguments = try JSONDecoder().decode(Tool.Arguments.self, from: data)
                try tool.validate(arguments)
                return try await tool.run(arguments: arguments)
            } catch let error as DecodingError {
                throw ToolExecutionError.invalidArguments(String(describing: error))
            }
        }
    }

    public var summary: ToolSummary {
        ToolSummary(name: name, capability: capability, mutatesState: mutatesState)
    }

    public func run(encodedArguments: Data) async throws -> ToolResult {
        try await runClosure(encodedArguments)
    }
}
