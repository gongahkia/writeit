import Foundation
import cerberusCore

final class ShellExecServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: (any ShellExecServiceProtocol).self)
        connection.exportedObject = ShellExecService()
        connection.resume()
        return true
    }
}

let delegate = ShellExecServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
