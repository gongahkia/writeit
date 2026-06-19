import Foundation

enum ShellOutputSpokenSummary {
    static func summary(for command: ValidatedCommand, output: String) -> String {
        let executable = command.executableURL.lastPathComponent
        guard executable == "git" else {
            return "Command completed."
        }

        switch command.arguments.first {
        case "status":
            return gitStatusSummary(arguments: command.arguments, output: output)
        case "diff":
            return gitDiffSummary(output: output)
        case "log":
            return gitLinesSummary(prefix: "Git log", empty: "No git log output.", output: output)
        case "show":
            return gitLinesSummary(prefix: "Git show", empty: "No git show output.", output: output)
        default:
            return "Command completed."
        }
    }

    private static func gitStatusSummary(arguments: [String], output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Git status is empty."
        }
        if trimmed.contains("nothing to commit, working tree clean") {
            return "Git working tree is clean."
        }
        if arguments.contains("--short") || arguments.contains("-s") {
            let count = nonEmptyLineCount(in: trimmed)
            return "Git status shows \(count) changed \(plural("file", count))."
        }
        return gitLinesSummary(prefix: "Git status", empty: "Git status is empty.", output: output)
    }

    private static func gitDiffSummary(output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "No git diff output."
        }

        let lines = trimmed.split(whereSeparator: \.isNewline)
        let fileCount = lines.filter { $0.hasPrefix("diff --git ") }.count
        let additions = lines.filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.count
        let deletions = lines.filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }.count

        if fileCount > 0 {
            return "Git diff changes \(fileCount) \(plural("file", fileCount)) with \(additions) \(plural("addition", additions)) and \(deletions) \(plural("deletion", deletions))."
        }

        return gitLinesSummary(prefix: "Git diff", empty: "No git diff output.", output: output)
    }

    private static func gitLinesSummary(prefix: String, empty: String, output: String) -> String {
        let count = nonEmptyLineCount(in: output)
        guard count > 0 else {
            return empty
        }
        return "\(prefix) returned \(count) \(plural("line", count))."
    }

    private static func nonEmptyLineCount(in output: String) -> Int {
        output.split(whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }

    private static func plural(_ word: String, _ count: Int) -> String {
        count == 1 ? word : "\(word)s"
    }
}
