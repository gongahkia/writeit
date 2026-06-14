import Testing
@testable import cerberusCore

@Test func appMetadataIsStable() {
    #expect(CerberusCore.appName == "cerberus")
    #expect(CerberusCore.bundleIdentifier == "dev.gongahkia.cerberus")
}
