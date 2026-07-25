import Foundation

public struct LongRunningTaskRecord: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let startedAt: Date
    public let finishedAt: Date
    public let succeeded: Bool

    public init(id: String, displayName: String, startedAt: Date, finishedAt: Date, succeeded: Bool) {
        self.id = id
        self.displayName = displayName
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.succeeded = succeeded
    }
}

public struct LongRunningTaskNotification: Equatable, Sendable {
    public let identifier: String
    public let title: String
    public let body: String

    public init(identifier: String, title: String, body: String) {
        self.identifier = identifier
        self.title = title
        self.body = body
    }
}

public struct LongRunningTaskNotificationPolicy: Equatable, Sendable {
    public let minimumDuration: TimeInterval

    public init(minimumDuration: TimeInterval = 30) {
        self.minimumDuration = minimumDuration
    }

    public func completionNotification(for record: LongRunningTaskRecord) -> LongRunningTaskNotification? {
        let duration = max(0, record.finishedAt.timeIntervalSince(record.startedAt))
        guard duration >= minimumDuration else {
            return nil
        }

        let elapsedSeconds = Int(duration.rounded())
        let status = record.succeeded ? "finished" : "failed"
        return LongRunningTaskNotification(
            identifier: "cerberus.long-running.\(record.id)",
            title: "\(record.displayName) \(status)",
            body: "Completed after \(elapsedSeconds) seconds."
        )
    }
}
