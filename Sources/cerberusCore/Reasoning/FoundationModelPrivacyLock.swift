import Foundation

public enum FoundationModelPrivacyLock {
    public static func allows(profile: String, requiresLocalOnly: Bool) -> Bool {
        guard requiresLocalOnly else {
            return true
        }
        let normalized = profile.lowercased()
        let deniedMarkers = ["cloud", "remote", "server", "nonlocal", "non-local", "pcc", "private_cloud"]
        return !deniedMarkers.contains { normalized.contains($0) }
    }

    public static func statusLine(requiresLocalOnly: Bool) -> String {
        requiresLocalOnly ? "Local-only model lock enabled" : "Local-only model lock disabled"
    }
}
