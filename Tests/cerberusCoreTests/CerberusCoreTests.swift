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
