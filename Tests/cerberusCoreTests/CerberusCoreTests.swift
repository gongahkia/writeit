import Foundation
import Testing
@testable import cerberusCore

@Test func appMetadataIsStable() {
    #expect(CerberusCore.appName == "cerberus")
    #expect(CerberusCore.bundleIdentifier == "dev.gongahkia.cerberus")
}

@Test func stateMachineFollowsHappyPath() {
    var machine = AssistantStateMachine()

    #expect(machine.handle(.wakeDetected(.manual))?.to == .listening)
    #expect(machine.handle(.silenceDetected)?.to == .reasoning)
    #expect(machine.handle(.responseReady("done"))?.to == .speaking)
    #expect(machine.handle(.speechFinished)?.to == .idle)
}

@Test func stateMachineRejectsInvalidTransitions() {
    var machine = AssistantStateMachine()

    #expect(machine.handle(.silenceDetected) == nil)
    #expect(machine.state == .idle)
}

@Test func systemPromptDocumentsUntrustedToolOutput() {
    let prompt = SystemPrompt.render(toolSummaries: [
        ToolSummary(name: "calendar.read", capability: "Read upcoming events.", mutatesState: false)
    ])

    #expect(prompt.contains("untrusted data"))
    #expect(prompt.contains("calendar.read"))
    #expect(prompt.contains("read-only"))
}

@Test func headGestureClassifierUsesCalibratedNeutralPose() {
    var classifier = HeadGestureClassifier(pitchThreshold: 0.3, yawThreshold: 0.4, cooldown: 1.0)
    let start = Date(timeIntervalSince1970: 1_000)

    classifier.calibrate(pitch: 0.1, yaw: -0.1)

    #expect(classifier.classify(pitch: 0.2, yaw: -0.2, at: start) == nil)
    #expect(classifier.classify(pitch: 0.5, yaw: -0.1, at: start.addingTimeInterval(1.1)) == .nod)
}

@Test func headGestureClassifierAppliesCooldown() {
    var classifier = HeadGestureClassifier(pitchThreshold: 0.3, yawThreshold: 0.4, cooldown: 2.0)
    let start = Date(timeIntervalSince1970: 2_000)

    classifier.calibrate(pitch: 0, yaw: 0)

    #expect(classifier.classify(pitch: 0.4, yaw: 0, at: start) == .nod)
    #expect(classifier.classify(pitch: 0.8, yaw: 0, at: start.addingTimeInterval(1.0)) == nil)
}

@Test func wakeWordDetectorMatchesNormalizedPhrase() {
    let detector = WakeWordDetector()

    #expect(detector.detectsWakeWord(in: "Hey, Cerberus."))
    #expect(!detector.detectsWakeWord(in: "hello service"))
}
