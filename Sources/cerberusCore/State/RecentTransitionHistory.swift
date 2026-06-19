import Foundation

public struct RecentTransitionHistory: Sendable {
    public static let limit = 5

    public private(set) var events: [String]

    public init(events: [String] = []) {
        self.events = Array(events.prefix(Self.limit))
    }

    @discardableResult
    public mutating func record(_ transition: AssistantTransition) -> [String] {
        events.insert("\(transition.from.rawValue) -> \(transition.to.rawValue)", at: 0)
        events = Array(events.prefix(Self.limit))
        return events
    }
}
