import Foundation

public struct DelayedTaskScheduler: Sendable {
    public let sleep: @Sendable (UInt64) async throws -> Void

    public init(sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) {
        self.sleep = sleep
    }

    public func schedule(
        afterNanoseconds delay: UInt64,
        operation: @escaping @Sendable () async -> Void
    ) -> Task<Void, Never> {
        Task {
            do {
                try await sleep(delay)
                guard !Task.isCancelled else {
                    return
                }
                await operation()
            } catch {}
        }
    }
}
