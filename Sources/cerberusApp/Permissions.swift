@preconcurrency import ApplicationServices
import AVFoundation
import CoreGraphics
import EventKit
import Foundation
import Speech

enum SystemPermission: String, CaseIterable, Identifiable {
    case microphone
    case speechRecognition = "speech_recognition"
    case calendar
    case reminders
    case accessibility
    case inputMonitoring = "input_monitoring"
    case screenRecording = "screen_recording"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .microphone:
            "Microphone"
        case .speechRecognition:
            "Speech Recognition"
        case .calendar:
            "Calendar"
        case .reminders:
            "Reminders"
        case .accessibility:
            "Accessibility"
        case .inputMonitoring:
            "Input Monitoring"
        case .screenRecording:
            "Screen Recording"
        }
    }
}

enum PermissionState: String, Equatable {
    case notDetermined = "not_determined"
    case granted
    case denied
    case restricted
    case unknown

    var displayName: String {
        switch self {
        case .notDetermined:
            "Not requested"
        case .granted:
            "Granted"
        case .denied:
            "Denied"
        case .restricted:
            "Restricted"
        case .unknown:
            "Unknown"
        }
    }
}

struct PermissionSnapshot: Identifiable, Equatable {
    let kind: SystemPermission
    var state: PermissionState

    var id: String {
        kind.id
    }
}

@MainActor
final class PermissionCenter {
    private let eventStore = EKEventStore()

    func currentSnapshots() -> [PermissionSnapshot] {
        SystemPermission.allCases.map { kind in
            PermissionSnapshot(kind: kind, state: currentState(for: kind))
        }
    }

    func request(_ kind: SystemPermission) async -> PermissionSnapshot {
        let state: PermissionState

        switch kind {
        case .microphone:
            state = await requestMicrophone()
        case .speechRecognition:
            state = await requestSpeechRecognition()
        case .calendar:
            state = await requestCalendar()
        case .reminders:
            state = await requestReminders()
        case .accessibility:
            state = requestAccessibility()
        case .inputMonitoring:
            state = requestInputMonitoring()
        case .screenRecording:
            state = requestScreenRecording()
        }

        return PermissionSnapshot(kind: kind, state: state)
    }

    private func currentState(for kind: SystemPermission) -> PermissionState {
        switch kind {
        case .microphone:
            Self.mapMediaAuthorization(AVCaptureDevice.authorizationStatus(for: .audio))
        case .speechRecognition:
            Self.mapSpeechAuthorization(SFSpeechRecognizer.authorizationStatus())
        case .calendar:
            Self.mapEventKitAuthorization(EKEventStore.authorizationStatus(for: .event))
        case .reminders:
            Self.mapEventKitAuthorization(EKEventStore.authorizationStatus(for: .reminder))
        case .accessibility:
            AXIsProcessTrusted() ? .granted : .notDetermined
        case .inputMonitoring:
            CGPreflightListenEventAccess() ? .granted : .notDetermined
        case .screenRecording:
            CGPreflightScreenCaptureAccess() ? .granted : .notDetermined
        }
    }

    private func requestMicrophone() async -> PermissionState {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        return granted ? .granted : currentState(for: .microphone)
    }

    private func requestSpeechRecognition() async -> PermissionState {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: Self.mapSpeechAuthorization(status))
            }
        }
    }

    private func requestCalendar() async -> PermissionState {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            return granted ? .granted : currentState(for: .calendar)
        } catch {
            return currentState(for: .calendar)
        }
    }

    private func requestReminders() async -> PermissionState {
        do {
            let granted = try await eventStore.requestFullAccessToReminders()
            return granted ? .granted : currentState(for: .reminders)
        } catch {
            return currentState(for: .reminders)
        }
    }

    private func requestAccessibility() -> PermissionState {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary

        return AXIsProcessTrustedWithOptions(options) ? .granted : currentState(for: .accessibility)
    }

    private func requestInputMonitoring() -> PermissionState {
        CGRequestListenEventAccess() ? .granted : currentState(for: .inputMonitoring)
    }

    private func requestScreenRecording() -> PermissionState {
        CGRequestScreenCaptureAccess() ? .granted : currentState(for: .screenRecording)
    }

    nonisolated private static func mapMediaAuthorization(_ status: AVAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized:
            .granted
        case .denied:
            .denied
        case .restricted:
            .restricted
        case .notDetermined:
            .notDetermined
        @unknown default:
            .unknown
        }
    }

    nonisolated private static func mapSpeechAuthorization(_ status: SFSpeechRecognizerAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized:
            .granted
        case .denied:
            .denied
        case .restricted:
            .restricted
        case .notDetermined:
            .notDetermined
        @unknown default:
            .unknown
        }
    }

    nonisolated private static func mapEventKitAuthorization(_ status: EKAuthorizationStatus) -> PermissionState {
        switch status {
        case .fullAccess, .writeOnly:
            .granted
        case .denied:
            .denied
        case .restricted:
            .restricted
        case .notDetermined:
            .notDetermined
        @unknown default:
            .unknown
        }
    }
}
