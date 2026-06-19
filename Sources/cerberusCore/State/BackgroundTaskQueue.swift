import Foundation

public enum BackgroundTaskStatus: String, Codable, Sendable {
    case queued
    case running
    case succeeded
    case failed
    case cancelled
}

public struct BackgroundTaskRecord: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let displayName: String
    public let status: BackgroundTaskStatus
    public let createdAt: Date
    public let startedAt: Date?
    public let finishedAt: Date?
    public let resultSummary: String?

    public init(
        id: UUID,
        displayName: String,
        status: BackgroundTaskStatus,
        createdAt: Date,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        resultSummary: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.status = status
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.resultSummary = resultSummary
    }
}

public actor BackgroundTaskQueue {
    public typealias Operation = @Sendable () async throws -> String

    private var recordsByID: [UUID: BackgroundTaskRecord] = [:]
    private var tasksByID: [UUID: Task<Void, Never>] = [:]
    private let auditLog: AuditLog?
    private let now: @Sendable () -> Date

    public init(auditLog: AuditLog? = nil, now: @escaping @Sendable () -> Date = Date.init) {
        self.auditLog = auditLog
        self.now = now
    }

    @discardableResult
    public func enqueue(
        displayName: String,
        argumentsSummary: String = "",
        operation: @escaping Operation
    ) -> UUID {
        let id = UUID()
        recordsByID[id] = BackgroundTaskRecord(
            id: id,
            displayName: displayName,
            status: .queued,
            createdAt: now()
        )
        tasksByID[id] = Task { [weak self] in
            await self?.run(id: id, argumentsSummary: argumentsSummary, operation: operation)
        }
        return id
    }

    public func cancel(id: UUID) async {
        tasksByID[id]?.cancel()
        tasksByID[id] = nil
        guard let record = recordsByID[id],
              record.status == .queued || record.status == .running else {
            return
        }
        let cancelled = BackgroundTaskRecord(
            id: record.id,
            displayName: record.displayName,
            status: .cancelled,
            createdAt: record.createdAt,
            startedAt: record.startedAt,
            finishedAt: now(),
            resultSummary: "cancelled"
        )
        recordsByID[id] = cancelled
        await appendAudit(record: cancelled, argumentsSummary: "cancel")
    }

    public func record(id: UUID) -> BackgroundTaskRecord? {
        recordsByID[id]
    }

    public func records() -> [BackgroundTaskRecord] {
        recordsByID.values.sorted { $0.createdAt < $1.createdAt }
    }

    private func run(id: UUID, argumentsSummary: String, operation: @escaping Operation) async {
        guard let queued = recordsByID[id], queued.status == .queued else {
            return
        }
        recordsByID[id] = BackgroundTaskRecord(
            id: queued.id,
            displayName: queued.displayName,
            status: .running,
            createdAt: queued.createdAt,
            startedAt: now()
        )

        do {
            try Task.checkCancellation()
            let summary = try await operation()
            await finish(id: id, status: .succeeded, resultSummary: summary, argumentsSummary: argumentsSummary)
        } catch is CancellationError {
            await finish(id: id, status: .cancelled, resultSummary: "cancelled", argumentsSummary: argumentsSummary)
        } catch {
            await finish(id: id, status: .failed, resultSummary: error.localizedDescription, argumentsSummary: argumentsSummary)
        }
    }

    private func finish(id: UUID, status: BackgroundTaskStatus, resultSummary: String, argumentsSummary: String) async {
        guard let running = recordsByID[id], running.status == .running else {
            return
        }
        let finished = BackgroundTaskRecord(
            id: running.id,
            displayName: running.displayName,
            status: status,
            createdAt: running.createdAt,
            startedAt: running.startedAt,
            finishedAt: now(),
            resultSummary: resultSummary
        )
        recordsByID[id] = finished
        tasksByID[id] = nil
        await appendAudit(record: finished, argumentsSummary: argumentsSummary)
    }

    private func appendAudit(record: BackgroundTaskRecord, argumentsSummary: String) async {
        guard let auditLog else {
            return
        }
        _ = try? await auditLog.append(
            toolName: "background.task",
            argumentsSummary: "\(record.displayName): \(argumentsSummary)",
            resultSummary: "\(record.status.rawValue): \(record.resultSummary ?? "")"
        )
    }
}
