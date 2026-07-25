@preconcurrency import ApplicationServices
import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import Speech

enum SystemPermission: String, CaseIterable, Identifiable {
    case microphone
    case speechRecognition = "speech_recognition"
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
        case .accessibility:
            "Accessibility"
        case .inputMonitoring:
            "Input Monitoring"
        case .screenRecording:
            "Screen Recording"
        }
    }

    var recoveryCopy: String {
        switch self {
        case .microphone:
            "Enable Microphone in System Settings > Privacy & Security."
        case .speechRecognition:
            "Enable Speech Recognition in System Settings > Privacy & Security."
        case .accessibility:
            "Enable Accessibility for cerberus in System Settings > Privacy & Security."
        case .inputMonitoring:
            "Enable Input Monitoring for cerberus in System Settings > Privacy & Security."
        case .screenRecording:
            "Enable Screen Recording for cerberus in System Settings > Privacy & Security."
        }
    }

    var systemSettingsURL: URL? {
        switch self {
        case .inputMonitoring:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        case .microphone, .speechRecognition, .accessibility, .screenRecording:
            nil
        }
    }
}

enum PermissionState: String, Equatable {
    case notDetermined = "not_determined"
    case granted
    case writeOnly = "write_only"
    case denied
    case restricted
    case unknown

    var displayName: String {
        switch self {
        case .notDetermined:
            "Not requested"
        case .granted:
            "Granted"
        case .writeOnly:
            "Write only"
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

    var recoveryCopy: String? {
        switch state {
        case .denied, .restricted, .unknown:
            kind.recoveryCopy
        case .notDetermined, .granted, .writeOnly:
            nil
        }
    }
}

@MainActor
protocol PermissionChecking: AnyObject {
    func currentSnapshots() -> [PermissionSnapshot]
    func request(_ kind: SystemPermission) async -> PermissionSnapshot
}

@MainActor
final class PermissionCenter: PermissionChecking {
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

    private func requestAccessibility() -> PermissionState {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary

        return AXIsProcessTrustedWithOptions(options) ? .granted : currentState(for: .accessibility)
    }

    private func requestInputMonitoring() -> PermissionState {
        let granted = CGRequestListenEventAccess()
        if !granted, let settingsURL = SystemPermission.inputMonitoring.systemSettingsURL {
            NSWorkspace.shared.open(settingsURL)
        }
        return granted ? .granted : currentState(for: .inputMonitoring)
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

}
