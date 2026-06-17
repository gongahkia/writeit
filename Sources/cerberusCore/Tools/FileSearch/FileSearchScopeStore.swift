import Foundation

public final class FileSearchScopeStore: @unchecked Sendable {
    public static let defaultDefaultsKey = "fileSearchApprovedScopePaths"

    private let defaults: UserDefaults
    private let defaultsKey: String
    private let lock = NSLock()
    private var cachedPaths: [String]

    public init(
        defaults: UserDefaults = .standard,
        defaultsKey: String = FileSearchScopeStore.defaultDefaultsKey
    ) {
        self.defaults = defaults
        self.defaultsKey = defaultsKey
        cachedPaths = Self.normalizedUniquePaths(defaults.stringArray(forKey: defaultsKey) ?? [])
        persist(cachedPaths)
    }

    public func approvedScopePaths() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return cachedPaths
    }

    @discardableResult
    public func add(_ path: String) throws -> [String] {
        let normalizedPath = try Self.normalizedDirectoryInHome(path)
        lock.lock()
        defer { lock.unlock() }
        cachedPaths = Self.normalizedUniquePaths(cachedPaths + [normalizedPath])
        persist(cachedPaths)
        return cachedPaths
    }

    @discardableResult
    public func remove(_ path: String) -> [String] {
        let normalizedPath = (try? Self.normalizedDirectoryInHome(path)) ?? path
        lock.lock()
        defer { lock.unlock() }
        cachedPaths.removeAll { $0 == normalizedPath || $0 == path }
        persist(cachedPaths)
        return cachedPaths
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        cachedPaths = []
        persist(cachedPaths)
    }

    public static func normalizedDirectoryInHome(_ path: String) throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ToolExecutionError.denied("File search scope must be an existing directory.")
        }

        let expandedPath = (trimmed as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
            .standardizedFileURL
            .resolvingSymlinksInPath()

        guard contains(url.path, in: homeURL.path) else {
            throw ToolExecutionError.denied("File search scope must be inside the user's home directory.")
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ToolExecutionError.denied("File search scope must be an existing directory.")
        }

        return url.path
    }

    public static func contains(_ candidatePath: String, in scopePath: String) -> Bool {
        candidatePath == scopePath || candidatePath.hasPrefix(scopePath + "/")
    }

    private static func normalizedUniquePaths(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths
            .compactMap { try? normalizedDirectoryInHome($0) }
            .filter { seen.insert($0).inserted }
            .sorted()
    }

    private func persist(_ paths: [String]) {
        defaults.set(paths, forKey: defaultsKey)
    }
}
