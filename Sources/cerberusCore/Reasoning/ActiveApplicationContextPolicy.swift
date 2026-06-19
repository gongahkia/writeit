import Foundation

public enum ActiveApplicationContextPolicy {
    public static func hints(for applicationName: String?, allowedToolNames: [String]) -> [String] {
        guard let applicationName = applicationName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !applicationName.isEmpty else {
            return []
        }

        let allowed = Set(allowedToolNames)
        guard let pack = AppToolPacks.matching(applicationName: applicationName),
              pack.toolNames.contains(where: allowed.contains) else {
            return []
        }

        let enabledTools = pack.toolNames.filter(allowed.contains).joined(separator: ", ")
        return ["\(pack.appName) tool pack enabled: \(enabledTools). \(pack.guidance)"]
    }
}
