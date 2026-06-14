import Foundation

enum ToolArgumentSupport {
    static func clampLimit(_ limit: Int, default defaultLimit: Int = 10, maximum: Int = 25) -> Int {
        guard limit > 0 else {
            return defaultLimit
        }
        return min(limit, maximum)
    }
}
