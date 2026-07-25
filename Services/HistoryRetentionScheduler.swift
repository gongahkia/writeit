import Foundation

@MainActor
protocol HistoryRetentionScheduling: AnyObject {
  func start(_ action: @escaping @MainActor @Sendable () -> Void)
  func stop()
}

@MainActor
final class HistoryRetentionScheduler: HistoryRetentionScheduling {
  static let interval: TimeInterval = 60 * 60

  private var timer: Timer?

  func start(_ action: @escaping @MainActor @Sendable () -> Void) {
    stop()
    timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { _ in
      Task { @MainActor in action() }
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }
}
