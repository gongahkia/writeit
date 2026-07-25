import Foundation
import UserNotifications
import cerberusCore

protocol LocalTaskNotificationScheduling: Sendable {
    func deliver(_ notification: LongRunningTaskNotification) async
}

struct UserNotificationTaskScheduler: LocalTaskNotificationScheduling {
    func deliver(_ notification: LongRunningTaskNotification) async {
        let center = UNUserNotificationCenter.current()
        let status = await authorizationStatus(center)
        if status == .notDetermined {
            guard await requestAuthorization(center) else {
                return
            }
        } else if status != .authorized && status != .provisional {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: notification.identifier,
            content: content,
            trigger: nil
        )
        await add(request, center: center)
    }

    private func authorizationStatus(_ center: UNUserNotificationCenter) async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    private func requestAuthorization(_ center: UNUserNotificationCenter) async -> Bool {
        await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    private func add(_ request: UNNotificationRequest, center: UNUserNotificationCenter) async {
        await withCheckedContinuation { continuation in
            center.add(request) { _ in
                continuation.resume()
            }
        }
    }
}
