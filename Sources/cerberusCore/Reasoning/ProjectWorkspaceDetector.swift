import Foundation

public struct ProjectWorkspaceHint: Codable, Equatable, Sendable {
    public let name: String
    public let path: String
    public let kind: String
    public let marker: String

    public init(name: String, path: String, kind: String, marker: String) {
        self.name = name
        self.path = path
        self.kind = kind
        self.marker = marker
    }

    public var promptLine: String {
        "- \(name) (\(kind)): \(path) [\(marker)]"
    }
}

public enum ProjectWorkspaceDetector {
    private struct Marker {
        let name: String
        let kind: String
        let isDirectory: Bool?
    }

    private static let markers: [Marker] = [
        Marker(name: "Package.swift", kind: "swift_package", isDirectory: false),
        Marker(name: "*.xcworkspace", kind: "xcode_workspace", isDirectory: true),
        Marker(name: "*.xcodeproj", kind: "xcode_project", isDirectory: true),
        Marker(name: "package.json", kind: "node_package", isDirectory: false),
        Marker(name: "pyproject.toml", kind: "python_project", isDirectory: false),
        Marker(name: "Cargo.toml", kind: "rust_package", isDirectory: false),
        Marker(name: "go.mod", kind: "go_module", isDirectory: false),
        Marker(name: ".git", kind: "git_repository", isDirectory: true)
    ]

    public static func detect(in scopePaths: [String], limit: Int = 8) -> [ProjectWorkspaceHint] {
        let candidates = scopePaths.flatMap(candidateDirectories(in:))
        var seen = Set<String>()
        return candidates
            .compactMap(detectWorkspace(at:))
            .filter { seen.insert($0.path).inserted }
            .sorted { $0.path < $1.path }
            .prefix(max(0, limit))
            .map { $0 }
    }

    private static func candidateDirectories(in scopePath: String) -> [URL] {
        let root = URL(fileURLWithPath: scopePath, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        var candidates = [root]
        let children = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsPackageDescendants]
        )) ?? []
        candidates += children.filter { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey])
            return values?.isDirectory == true && values?.isHidden != true
        }
        return candidates
    }

    private static func detectWorkspace(at url: URL) -> ProjectWorkspaceHint? {
        for marker in markers {
            if marker.name.hasPrefix("*.") {
                if let matched = wildcardMarker(in: url, suffix: String(marker.name.dropFirst())) {
                    return hint(for: url, marker: matched.lastPathComponent, kind: marker.kind)
                }
                continue
            }
            let markerURL = url.appendingPathComponent(marker.name)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: markerURL.path, isDirectory: &isDirectory) else {
                continue
            }
            if let expectedDirectory = marker.isDirectory, isDirectory.boolValue != expectedDirectory {
                continue
            }
            return hint(for: url, marker: marker.name, kind: marker.kind)
        }
        return nil
    }

    private static func wildcardMarker(in url: URL, suffix: String) -> URL? {
        ((try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? [])
            .filter {
                let values = try? $0.resourceValues(forKeys: [.isDirectoryKey])
                return $0.lastPathComponent.hasSuffix(suffix) && values?.isDirectory == true
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
    }

    private static func hint(for url: URL, marker: String, kind: String) -> ProjectWorkspaceHint {
        ProjectWorkspaceHint(
            name: url.lastPathComponent,
            path: url.path,
            kind: kind,
            marker: marker
        )
    }
}
