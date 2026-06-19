@preconcurrency import Contacts
import Foundation
import FoundationModels

public struct ContactSearchRecord: Equatable, Sendable {
    public let displayName: String
    public let organizationName: String?
    public let emailAddresses: [String]
    public let phoneNumbers: [String]

    public init(
        displayName: String,
        organizationName: String? = nil,
        emailAddresses: [String] = [],
        phoneNumbers: [String] = []
    ) {
        self.displayName = displayName
        self.organizationName = organizationName
        self.emailAddresses = emailAddresses
        self.phoneNumbers = phoneNumbers
    }
}

public struct ContactsTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let query: String
        public let includeEmails: Bool
        public let includePhones: Bool
        public let limit: Int

        public init(query: String, includeEmails: Bool = true, includePhones: Bool = false, limit: Int = 10) {
            self.query = query
            self.includeEmails = includeEmails
            self.includePhones = includePhones
            self.limit = limit
        }
    }

    public let name = "contacts.search"
    public let capability = "Search local Contacts by name, organization, email, or phone number. Read-only."
    public let mutatesState = false
    public let argumentSchema = #"{"query":"name organization email or phone","includeEmails":true,"includePhones":false,"limit":10}"#

    private let recordsProvider: @Sendable () async throws -> [ContactSearchRecord]

    public init() {
        recordsProvider = {
            try Self.requireAccess()
            return try Self.loadContacts()
        }
    }

    public init(records: [ContactSearchRecord]) {
        recordsProvider = { records }
    }

    public func validate(_ arguments: Arguments) throws {
        guard !arguments.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolExecutionError.invalidArguments("query is required")
        }
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        try validate(arguments)
        let limit = ToolArgumentSupport.clampLimit(arguments.limit)
        let query = arguments.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let records = try await recordsProvider()
            .filter { $0.matches(query) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            .prefix(limit)
        let payload = records
            .map { Self.format($0, includeEmails: arguments.includeEmails, includePhones: arguments.includePhones) }
            .joined(separator: "\n")
        let count = records.count

        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: count == 1 ? "Found 1 contact." : "Found \(count) contacts.",
            untrustedPayload: payload,
            metadata: ["count": "\(count)"]
        )
    }

    static func format(_ record: ContactSearchRecord, includeEmails: Bool, includePhones: Bool) -> String {
        var parts = ["- \(record.displayName)"]
        if let organization = record.organizationName, !organization.isEmpty {
            parts.append("[\(organization)]")
        }
        if includeEmails, !record.emailAddresses.isEmpty {
            parts.append("emails: \(record.emailAddresses.joined(separator: ", "))")
        }
        if includePhones, !record.phoneNumbers.isEmpty {
            parts.append("phones: \(record.phoneNumbers.joined(separator: ", "))")
        }
        return parts.joined(separator: " ")
    }

    private static func requireAccess() throws {
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
            throw ToolExecutionError.denied("Contacts access is not granted.")
        }
    }

    private static func loadContacts() throws -> [ContactSearchRecord] {
        let store = CNContactStore()
        let keys: [any CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactOrganizationNameKey as any CNKeyDescriptor,
            CNContactEmailAddressesKey as any CNKeyDescriptor,
            CNContactPhoneNumbersKey as any CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var records: [ContactSearchRecord] = []
        try store.enumerateContacts(with: request) { contact, _ in
            let name = CNContactFormatter.string(from: contact, style: .fullName)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let organization = contact.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = name?.isEmpty == false ? name! : organization
            guard !displayName.isEmpty else {
                return
            }
            records.append(ContactSearchRecord(
                displayName: displayName,
                organizationName: organization.isEmpty ? nil : organization,
                emailAddresses: contact.emailAddresses.map { String($0.value) },
                phoneNumbers: contact.phoneNumbers.map { $0.value.stringValue }
            ))
        }
        return records
    }
}

private extension ContactSearchRecord {
    func matches(_ query: String) -> Bool {
        let normalized = query.lowercased()
        return displayName.lowercased().contains(normalized)
            || (organizationName?.lowercased().contains(normalized) ?? false)
            || emailAddresses.contains { $0.lowercased().contains(normalized) }
            || phoneNumbers.contains { $0.lowercased().contains(normalized) }
    }
}
