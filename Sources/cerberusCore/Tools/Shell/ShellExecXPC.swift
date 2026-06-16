import Foundation

@objc public protocol ShellExecServiceProtocol {
    func run(_ request: ShellExecRequest, withReply reply: @escaping @Sendable (ShellExecResponse) -> Void)
}

@objc(CerberusShellExecRequest)
public final class ShellExecRequest: NSObject, NSSecureCoding, @unchecked Sendable {
    public static let supportsSecureCoding = true

    public let executable: String
    public let arguments: [String]
    public let workingDirectory: String?

    public init(executable: String, arguments: [String], workingDirectory: String?) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        super.init()
    }

    public convenience init(command: ValidatedCommand) {
        self.init(
            executable: command.executableURL.lastPathComponent,
            arguments: command.arguments,
            workingDirectory: command.workingDirectoryURL?.path
        )
    }

    public convenience init?(coder: NSCoder) {
        guard let executable = coder.decodeObject(of: NSString.self, forKey: "executable") as String? else {
            return nil
        }

        let arguments = coder.decodeObject(of: [NSArray.self, NSString.self], forKey: "arguments") as? [String] ?? []
        let workingDirectory = coder.decodeObject(of: NSString.self, forKey: "workingDirectory") as String?
        self.init(executable: executable, arguments: arguments, workingDirectory: workingDirectory)
    }

    public func encode(with coder: NSCoder) {
        coder.encode(executable, forKey: "executable")
        coder.encode(arguments, forKey: "arguments")
        coder.encode(workingDirectory, forKey: "workingDirectory")
    }

    var shellCommand: ShellCommand {
        ShellCommand(executable: executable, arguments: arguments, workingDirectory: workingDirectory)
    }
}

@objc(CerberusShellExecResponse)
public final class ShellExecResponse: NSObject, NSSecureCoding, @unchecked Sendable {
    public static let supportsSecureCoding = true

    public let succeeded: Bool
    public let output: String
    public let errorMessage: String?

    public init(succeeded: Bool, output: String = "", errorMessage: String? = nil) {
        self.succeeded = succeeded
        self.output = output
        self.errorMessage = errorMessage
        super.init()
    }

    public convenience init?(coder: NSCoder) {
        let succeeded = coder.decodeBool(forKey: "succeeded")
        let output = coder.decodeObject(of: NSString.self, forKey: "output") as String? ?? ""
        let errorMessage = coder.decodeObject(of: NSString.self, forKey: "errorMessage") as String?
        self.init(succeeded: succeeded, output: output, errorMessage: errorMessage)
    }

    public func encode(with coder: NSCoder) {
        coder.encode(succeeded, forKey: "succeeded")
        coder.encode(output, forKey: "output")
        coder.encode(errorMessage, forKey: "errorMessage")
    }
}

public final class ShellExecService: NSObject, ShellExecServiceProtocol {
    private let allowlist: CommandAllowlist
    private let executor: any ShellCommandExecutor

    public init(
        allowlist: CommandAllowlist = CommandAllowlist(),
        executor: any ShellCommandExecutor = DirectShellCommandExecutor()
    ) {
        self.allowlist = allowlist
        self.executor = executor
        super.init()
    }

    public func run(_ request: ShellExecRequest, withReply reply: @escaping @Sendable (ShellExecResponse) -> Void) {
        let command: ValidatedCommand
        do {
            command = try allowlist.validate(request.shellCommand)
        } catch {
            reply(ShellExecResponse(succeeded: false, errorMessage: error.localizedDescription))
            return
        }

        let commandExecutor = executor
        Task {
            do {
                let output = try await commandExecutor.run(command)
                reply(ShellExecResponse(succeeded: true, output: output))
            } catch {
                reply(ShellExecResponse(succeeded: false, errorMessage: error.localizedDescription))
            }
        }
    }
}

public struct ShellXPCCommandExecutor: ShellCommandExecutor {
    public let serviceName: String

    public init(serviceName: String = "dev.gongahkia.cerberus.ShellExecService") {
        self.serviceName = serviceName
    }

    public func run(_ command: ValidatedCommand) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let connection = NSXPCConnection(serviceName: serviceName)
            let connectionBox = XPCConnectionBox(connection)
            connection.remoteObjectInterface = NSXPCInterface(with: (any ShellExecServiceProtocol).self)
            connection.resume()

            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
                connectionBox.invalidate()
            } as? any ShellExecServiceProtocol

            guard let proxy else {
                connectionBox.invalidate()
                continuation.resume(throwing: ToolExecutionError.denied("Could not connect to shell XPC service."))
                return
            }

            proxy.run(ShellExecRequest(command: command)) { response in
                connectionBox.invalidate()
                if response.succeeded {
                    continuation.resume(returning: response.output)
                } else {
                    continuation.resume(
                        throwing: ToolExecutionError.denied(response.errorMessage ?? "Shell XPC service failed.")
                    )
                }
            }
        }
    }
}

private final class XPCConnectionBox: @unchecked Sendable {
    private let connection: NSXPCConnection

    init(_ connection: NSXPCConnection) {
        self.connection = connection
    }

    func invalidate() {
        connection.invalidate()
    }
}
