import Foundation

public struct PendingConfirmation: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let summary: String
    public let createdAt: Date

    public init(id: UUID = UUID(), summary: String, createdAt: Date = Date()) {
        self.id = id
        self.summary = summary
        self.createdAt = createdAt
    }
}

public actor ConfirmationGate {
    private var pending: PendingConfirmation?

    public init() {}

    public func request(summary: String) -> PendingConfirmation {
        let confirmation = PendingConfirmation(summary: summary)
        pending = confirmation
        return confirmation
    }

    public func accept(id: UUID) -> Bool {
        guard pending?.id == id else {
            return false
        }

        pending = nil
        return true
    }

    public func deny(id: UUID) -> Bool {
        guard pending?.id == id else {
            return false
        }

        pending = nil
        return true
    }

    public func current() -> PendingConfirmation? {
        pending
    }

    public func clear() {
        pending = nil
    }
}
