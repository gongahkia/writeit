import Foundation
import Testing
@testable import cerberusCore

@Test func commandAllowlistAllowsReadOnlyGitStatus() throws {
    let allowlist = CommandAllowlist(allowedExecutablePaths: ["git": ["/usr/bin/git"]])
    let command = ShellCommand(executable: "git", arguments: ["status"])

    let validated = try allowlist.validate(command)

    #expect(validated.executableURL.path == "/usr/bin/git")
    #expect(validated.arguments == ["status"])
}

@Test func commandAllowlistDeniesDangerousShellFragments() throws {
    let allowlist = CommandAllowlist(allowedExecutablePaths: ["ls": ["/bin/ls"]])
    let command = ShellCommand(executable: "ls", arguments: [";", "rm", "-rf", "/"])

    var denied = false
    do {
        _ = try allowlist.validate(command)
    } catch ToolExecutionError.denied {
        denied = true
    }

    #expect(denied)
}

@Test func auditLogCreatesHashChain() async throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("audit.log")
    let auditLog = AuditLog(fileURL: fileURL)

    let first = try await auditLog.append(toolName: "one", argumentsSummary: "a", resultSummary: "b")
    let second = try await auditLog.append(toolName: "two", argumentsSummary: "c", resultSummary: "d")

    #expect(first.previousHash == "genesis")
    #expect(second.previousHash == first.hash)
    #expect(try await auditLog.entries().count == 2)
}

@Test func voiceConfirmationParserClassifiesShortApprovalsAndDenials() {
    #expect(VoiceConfirmationParser.decision(in: "yes go ahead") == .accept)
    #expect(VoiceConfirmationParser.decision(in: "do it") == .accept)
    #expect(VoiceConfirmationParser.decision(in: "no cancel that") == .deny)
    #expect(VoiceConfirmationParser.decision(in: "maybe later") == nil)
}
