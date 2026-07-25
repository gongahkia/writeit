@preconcurrency import ApplicationServices
import AppKit
import CoreGraphics
import Foundation
import FoundationModels

public struct ScreenUIElementsTool: AssistantTool {
    @Generable
    public struct Arguments: Codable, Sendable {
        public let limit: Int
        public let applicationName: String?
        public let bundleIdentifier: String?

        public init(limit: Int = 30, applicationName: String? = nil, bundleIdentifier: String? = nil) {
            self.limit = limit
            self.applicationName = applicationName
            self.bundleIdentifier = bundleIdentifier
        }
    }

    public let name = "screen.ui_elements"
    public let capability = "Read Accessibility roles, labels, and screen coordinates for visible UI elements in the active or named macOS app."
    public let mutatesState = false
    public let argumentSchema = #"{"limit":30,"applicationName":"optional app name","bundleIdentifier":"optional.bundle.id"}"#

    private let hasAccessibilityAccess: @Sendable () -> Bool

    public init(hasAccessibilityAccess: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() }) {
        self.hasAccessibilityAccess = hasAccessibilityAccess
    }

    public func run(arguments: Arguments) async throws -> ToolResult {
        guard hasAccessibilityAccess() else {
            throw ToolExecutionError.denied("Accessibility access is not granted.")
        }

        let limit = ToolArgumentSupport.clampLimit(arguments.limit, default: 30, maximum: 100)
        let snapshot = try await MainActor.run {
            try Self.snapshot(arguments: arguments, limit: limit)
        }

        return ToolResult(
            toolName: name,
            succeeded: true,
            spokenSummary: snapshot.elements.count == 1 ? "Found 1 UI element in \(snapshot.applicationName)." : "Found \(snapshot.elements.count) UI elements in \(snapshot.applicationName).",
            untrustedPayload: Self.payload(for: snapshot),
            metadata: [
                "count": "\(snapshot.elements.count)",
                "applicationName": snapshot.applicationName,
                "bundleIdentifier": snapshot.bundleIdentifier ?? ""
            ]
        )
    }

    @MainActor
    static func snapshot(arguments: Arguments, limit: Int) throws -> ScreenUIElementSnapshot {
        guard let app = runningApplication(named: arguments.applicationName, bundleIdentifier: arguments.bundleIdentifier) else {
            throw ToolExecutionError.denied("Could not find the requested application.")
        }

        let root = AXUIElementCreateApplication(app.processIdentifier)
        let windows = focusedWindow(from: root).map { [$0] } ?? attributeArray(kAXWindowsAttribute, from: root)
        var collector = ScreenUIElementCollector(limit: limit)

        if windows.isEmpty {
            collector.visit(root, depth: 0)
        } else {
            for window in windows {
                collector.visit(window, depth: 0)
            }
        }

        return ScreenUIElementSnapshot(
            applicationName: app.localizedName ?? arguments.applicationName ?? app.bundleIdentifier ?? "application",
            bundleIdentifier: app.bundleIdentifier,
            elements: collector.elements
        )
    }

    static func payload(for snapshot: ScreenUIElementSnapshot) -> String {
        let header = "application: \(snapshot.applicationName); bundleIdentifier: \(snapshot.bundleIdentifier ?? "unknown"); coordinates use global screen pixels with origin top-left."
        guard !snapshot.elements.isEmpty else {
            return "\(header)\nNo UI elements found."
        }

        return ([header] + snapshot.elements.map { element in
            "- \(element.summary)"
        }).joined(separator: "\n")
    }

    @MainActor
    private static func runningApplication(named applicationName: String?, bundleIdentifier: String?) -> NSRunningApplication? {
        let trimmedName = applicationName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBundleID = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName?.isEmpty != false && trimmedBundleID?.isEmpty != false {
            return NSWorkspace.shared.frontmostApplication
        }

        return NSWorkspace.shared.runningApplications.first { app in
            if let trimmedBundleID, !trimmedBundleID.isEmpty, app.bundleIdentifier == trimmedBundleID {
                return true
            }
            if let trimmedName, !trimmedName.isEmpty {
                return app.localizedName?.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
            }
            return false
        }
    }

    private static func focusedWindow(from element: AXUIElement) -> AXUIElement? {
        attribute(kAXFocusedWindowAttribute, from: element, as: AXUIElement.self)
    }

    fileprivate static func attributeArray(_ name: String, from element: AXUIElement) -> [AXUIElement] {
        attribute(name, from: element, as: [AXUIElement].self) ?? []
    }

    fileprivate static func attribute<T>(_ name: String, from element: AXUIElement, as type: T.Type) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as? T
    }

    fileprivate static func stringAttribute(_ name: String, from element: AXUIElement) -> String? {
        if let value = attribute(name, from: element, as: String.self), !value.isEmpty {
            return value
        }
        if let value = attribute(name, from: element, as: NSNumber.self) {
            return value.stringValue
        }
        return nil
    }

    fileprivate static func boolAttribute(_ name: String, from element: AXUIElement) -> Bool? {
        attribute(name, from: element, as: NSNumber.self)?.boolValue
    }

    fileprivate static func rect(from element: AXUIElement) -> CGRect? {
        guard let positionValue = attribute(kAXPositionAttribute, from: element, as: AXValue.self),
              let sizeValue = attribute(kAXSizeAttribute, from: element, as: AXValue.self) else {
            return nil
        }

        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &point),
              AXValueGetValue(sizeValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: point, size: size)
    }
}

private struct ScreenUIElementCollector {
    private static let maximumDepth = 5
    private var visited = Set<ObjectIdentifier>()
    private(set) var elements: [ScreenUIElementObservation] = []
    let limit: Int

    init(limit: Int) {
        self.limit = limit
    }

    mutating func visit(_ element: AXUIElement, depth: Int) {
        guard elements.count < limit, depth <= Self.maximumDepth else {
            return
        }

        let identifier = ObjectIdentifier(element)
        guard visited.insert(identifier).inserted else {
            return
        }

        if let observation = ScreenUIElementObservation(element: element) {
            elements.append(observation)
        }

        for child in ScreenUIElementsTool.attributeArray(kAXChildrenAttribute, from: element) {
            visit(child, depth: depth + 1)
            if elements.count >= limit {
                return
            }
        }
    }
}

struct ScreenUIElementSnapshot: Sendable {
    let applicationName: String
    let bundleIdentifier: String?
    let elements: [ScreenUIElementObservation]
}

struct ScreenUIElementObservation: Sendable {
    let role: String
    let subrole: String?
    let title: String?
    let value: String?
    let description: String?
    let help: String?
    let identifier: String?
    let enabled: Bool?
    let frame: CGRect?

    init(
        role: String,
        subrole: String? = nil,
        title: String? = nil,
        value: String? = nil,
        description: String? = nil,
        help: String? = nil,
        identifier: String? = nil,
        enabled: Bool? = nil,
        frame: CGRect? = nil
    ) {
        self.role = role
        self.subrole = subrole
        self.title = title
        self.value = value
        self.description = description
        self.help = help
        self.identifier = identifier
        self.enabled = enabled
        self.frame = frame
    }

    init?(element: AXUIElement) {
        guard let role = ScreenUIElementsTool.stringAttribute(kAXRoleAttribute, from: element) else {
            return nil
        }

        self.role = role
        subrole = ScreenUIElementsTool.stringAttribute(kAXSubroleAttribute, from: element)
        title = ScreenUIElementsTool.stringAttribute(kAXTitleAttribute, from: element)
        value = ScreenUIElementsTool.stringAttribute(kAXValueAttribute, from: element)
        description = ScreenUIElementsTool.stringAttribute(kAXDescriptionAttribute, from: element)
        help = ScreenUIElementsTool.stringAttribute(kAXHelpAttribute, from: element)
        identifier = ScreenUIElementsTool.stringAttribute(kAXIdentifierAttribute, from: element)
        enabled = ScreenUIElementsTool.boolAttribute(kAXEnabledAttribute, from: element)
        frame = ScreenUIElementsTool.rect(from: element)
    }

    var summary: String {
        var fields = ["role: \(role)"]
        append("subrole", subrole, to: &fields)
        append("title", title.map(ScreenTextRedactor.redact), to: &fields)
        append("value", value.map(ScreenTextRedactor.redact), to: &fields)
        append("description", description.map(ScreenTextRedactor.redact), to: &fields)
        append("help", help.map(ScreenTextRedactor.redact), to: &fields)
        append("identifier", identifier, to: &fields)
        if let enabled {
            fields.append("enabled: \(enabled)")
        }
        if let frame {
            fields.append("frame: \(Self.format(frame))")
        }
        return fields.joined(separator: ", ")
    }

    private func append(_ name: String, _ value: String?, to fields: inout [String]) {
        guard let value, !value.isEmpty else {
            return
        }
        fields.append("\(name): \(value)")
    }

    private static func format(_ rect: CGRect) -> String {
        "x=\(String(format: "%.0f", rect.minX)) y=\(String(format: "%.0f", rect.minY)) w=\(String(format: "%.0f", rect.width)) h=\(String(format: "%.0f", rect.height))"
    }
}
