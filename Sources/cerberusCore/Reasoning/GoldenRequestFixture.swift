import Foundation

public struct GoldenRequestFixture: Codable, Equatable, Sendable {
    public let id: String
    public let request: String
    public let activeApplicationName: String?
    public let allowedToolNames: [String]
    public let projectWorkspaceHints: [ProjectWorkspaceHint]
    public let activeApplicationHints: [String]
    public let expectedIntent: String
    public let expectedToolName: String
    public let expectedRequiresConfirmation: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case request
        case activeApplicationName
        case allowedToolNames
        case projectWorkspaceHints
        case activeApplicationHints
        case expectedIntent
        case expectedToolName
        case expectedRequiresConfirmation
    }

    public init(
        id: String,
        request: String,
        activeApplicationName: String? = nil,
        allowedToolNames: [String],
        projectWorkspaceHints: [ProjectWorkspaceHint] = [],
        activeApplicationHints: [String] = [],
        expectedIntent: String,
        expectedToolName: String = "",
        expectedRequiresConfirmation: Bool
    ) {
        self.id = id
        self.request = request
        self.activeApplicationName = activeApplicationName
        self.allowedToolNames = allowedToolNames
        self.projectWorkspaceHints = projectWorkspaceHints
        self.activeApplicationHints = activeApplicationHints
        self.expectedIntent = expectedIntent
        self.expectedToolName = expectedToolName
        self.expectedRequiresConfirmation = expectedRequiresConfirmation
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        request = try container.decode(String.self, forKey: .request)
        activeApplicationName = try container.decodeIfPresent(String.self, forKey: .activeApplicationName)
        allowedToolNames = try container.decode([String].self, forKey: .allowedToolNames)
        projectWorkspaceHints = try container.decodeIfPresent([ProjectWorkspaceHint].self, forKey: .projectWorkspaceHints) ?? []
        activeApplicationHints = try container.decodeIfPresent([String].self, forKey: .activeApplicationHints) ?? []
        expectedIntent = try container.decode(String.self, forKey: .expectedIntent)
        expectedToolName = try container.decodeIfPresent(String.self, forKey: .expectedToolName) ?? ""
        expectedRequiresConfirmation = try container.decode(Bool.self, forKey: .expectedRequiresConfirmation)
    }

    public var context: AssistantContext {
        AssistantContext(
            activeApplicationName: activeApplicationName,
            allowedToolNames: allowedToolNames,
            projectWorkspaceHints: projectWorkspaceHints,
            activeApplicationHints: activeApplicationHints
        )
    }
}

public struct GoldenRequestFixtureResult: Equatable, Sendable {
    public let fixture: GoldenRequestFixture
    public let actualIntent: String
    public let actualToolName: String
    public let actualRequiresConfirmation: Bool
    public let matches: Bool

    public init(fixture: GoldenRequestFixture, plan: AssistantPlan) {
        self.fixture = fixture
        actualIntent = String(describing: plan.intent)
        actualToolName = plan.toolName
        actualRequiresConfirmation = plan.requiresConfirmation
        matches = actualIntent == fixture.expectedIntent
            && actualToolName == fixture.expectedToolName
            && actualRequiresConfirmation == fixture.expectedRequiresConfirmation
    }
}

public enum GoldenRequestFixtures {
    public static func parseJSONL(_ data: Data) throws -> [GoldenRequestFixture] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ToolExecutionError.invalidArguments("Golden request fixtures must be UTF-8 JSONL.")
        }
        return try text
            .split(separator: "\n")
            .enumerated()
            .filter { !$0.element.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { index, line in
                let fixture = try JSONDecoder().decode(GoldenRequestFixture.self, from: Data(line.utf8))
                try validate(fixture, line: index + 1)
                return fixture
            }
    }

    public static func validate(_ fixture: GoldenRequestFixture, line: Int? = nil) throws {
        let prefix = line.map { "Golden request fixture line \($0)" } ?? "Golden request fixture"
        guard !fixture.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolExecutionError.invalidArguments("\(prefix) has an empty id.")
        }
        guard !fixture.request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolExecutionError.invalidArguments("\(prefix) has an empty request.")
        }
        guard AssistantIntent.allowedGoldenNames.contains(fixture.expectedIntent) else {
            throw ToolExecutionError.invalidArguments("\(prefix) has invalid expectedIntent.")
        }
        let allowedTools = Set(fixture.allowedToolNames)
        guard fixture.expectedToolName.isEmpty || allowedTools.contains(fixture.expectedToolName) else {
            throw ToolExecutionError.invalidArguments("\(prefix) expectedToolName is not allowed.")
        }
    }
}

extension AssistantIntent {
    fileprivate static let allowedGoldenNames: Set<String> = [
        "answerDirectly",
        "askClarifyingQuestion",
        "callTool",
        "refuseUnsafeRequest"
    ]
}
