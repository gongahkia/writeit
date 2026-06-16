import CryptoKit
import Foundation
import Network

public enum MCPOAuthKeychainAccount {
    public static func accessToken(serverName: String) -> String {
        "mcp.oauth.access.\(serverName)"
    }

    public static func clientRegistration(serverName: String) -> String {
        "mcp.oauth.client.\(serverName)"
    }

    public static func flow(serverName: String, state: String) -> String {
        "mcp.oauth.flow.\(serverName).\(state)"
    }

    public static func tokenRecord(serverName: String) -> String {
        "mcp.oauth.token.\(serverName)"
    }
}

public struct MCPOAuthProtectedResourceMetadata: Codable, Equatable, Sendable {
    public let resource: String?
    public let authorizationServers: [URL]
    public let scopesSupported: [String]
    public let rawJSON: String

    public init(resource: String?, authorizationServers: [URL], scopesSupported: [String], rawJSON: String) {
        self.resource = resource
        self.authorizationServers = authorizationServers
        self.scopesSupported = scopesSupported
        self.rawJSON = rawJSON
    }
}

public struct MCPOAuthAuthorizationServerMetadata: Codable, Equatable, Sendable {
    public let issuer: URL?
    public let authorizationEndpoint: URL
    public let tokenEndpoint: URL
    public let registrationEndpoint: URL?
    public let scopesSupported: [String]
    public let codeChallengeMethodsSupported: [String]
    public let rawJSON: String

    public init(
        issuer: URL?,
        authorizationEndpoint: URL,
        tokenEndpoint: URL,
        registrationEndpoint: URL?,
        scopesSupported: [String],
        codeChallengeMethodsSupported: [String],
        rawJSON: String
    ) {
        self.issuer = issuer
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.registrationEndpoint = registrationEndpoint
        self.scopesSupported = scopesSupported
        self.codeChallengeMethodsSupported = codeChallengeMethodsSupported
        self.rawJSON = rawJSON
    }
}

public struct MCPOAuthDiscoveryResult: Equatable, Sendable {
    public let resourceMetadataURL: URL
    public let protectedResource: MCPOAuthProtectedResourceMetadata
    public let authorizationServer: MCPOAuthAuthorizationServerMetadata

    public init(
        resourceMetadataURL: URL,
        protectedResource: MCPOAuthProtectedResourceMetadata,
        authorizationServer: MCPOAuthAuthorizationServerMetadata
    ) {
        self.resourceMetadataURL = resourceMetadataURL
        self.protectedResource = protectedResource
        self.authorizationServer = authorizationServer
    }
}

public struct MCPOAuthClientRegistration: Codable, Equatable, Sendable {
    public let clientID: String

    public init(clientID: String) {
        self.clientID = clientID
    }
}

public struct MCPOAuthFlowRecord: Codable, Equatable, Sendable {
    public let serverName: String
    public let state: String
    public let codeVerifier: String
    public let clientID: String
    public let redirectURI: String
    public let resource: String
    public let tokenEndpoint: URL
    public let createdAt: Date

    public init(
        serverName: String,
        state: String,
        codeVerifier: String,
        clientID: String,
        redirectURI: String,
        resource: String,
        tokenEndpoint: URL,
        createdAt: Date = Date()
    ) {
        self.serverName = serverName
        self.state = state
        self.codeVerifier = codeVerifier
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.resource = resource
        self.tokenEndpoint = tokenEndpoint
        self.createdAt = createdAt
    }
}

public struct MCPOAuthStartResult: Equatable, Sendable {
    public let authorizationURL: URL
    public let state: String
    public let clientID: String

    public init(authorizationURL: URL, state: String, clientID: String) {
        self.authorizationURL = authorizationURL
        self.state = state
        self.clientID = clientID
    }
}

public struct MCPOAuthLoopbackCallback: Equatable, Sendable {
    public let code: String
    public let state: String
    public let requestURL: URL

    public init(code: String, state: String, requestURL: URL) {
        self.code = code
        self.state = state
        self.requestURL = requestURL
    }
}

public struct MCPOAuthTokenResult: Equatable, Sendable {
    public let tokenType: String
    public let expiresIn: Int?
    public let scope: String?
    public let hasRefreshToken: Bool

    public init(tokenType: String, expiresIn: Int?, scope: String?, hasRefreshToken: Bool = false) {
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.scope = scope
        self.hasRefreshToken = hasRefreshToken
    }
}

public struct MCPOAuthTokenRecord: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let tokenType: String
    public let expiresAt: Date?
    public let scope: String?
    public let clientID: String
    public let tokenEndpoint: URL
    public let resource: String

    public init(
        accessToken: String,
        refreshToken: String?,
        tokenType: String,
        expiresAt: Date?,
        scope: String?,
        clientID: String,
        tokenEndpoint: URL,
        resource: String
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.expiresAt = expiresAt
        self.scope = scope
        self.clientID = clientID
        self.tokenEndpoint = tokenEndpoint
        self.resource = resource
    }
}

public struct MCPOAuthClient: Sendable {
    public let urlSession: URLSession
    public let keychainService: String

    public init(urlSession: URLSession = .shared, keychainService: String = CerberusCore.bundleIdentifier) {
        self.urlSession = urlSession
        self.keychainService = keychainService
    }

    public func discover(configuration: MCPServerConfiguration) async throws -> MCPOAuthDiscoveryResult {
        let resourceMetadataURL = try await resourceMetadataURL(for: configuration)
        let protectedResource = try await protectedResourceMetadata(from: resourceMetadataURL)
        guard let authorizationServerURL = protectedResource.authorizationServers.first else {
            throw ToolExecutionError.denied("MCP OAuth resource metadata did not include authorization_servers.")
        }

        let authorizationMetadataURL = Self.authorizationServerMetadataURL(for: authorizationServerURL)
        let authorizationServer = try await authorizationServerMetadata(from: authorizationMetadataURL)
        return MCPOAuthDiscoveryResult(
            resourceMetadataURL: resourceMetadataURL,
            protectedResource: protectedResource,
            authorizationServer: authorizationServer
        )
    }

    public func start(configuration: MCPServerConfiguration, scopes: [String]) async throws -> MCPOAuthStartResult {
        let discovery = try await discover(configuration: configuration)
        let clientID = try await configuredOrRegisteredClientID(
            configuration: configuration,
            metadata: discovery.authorizationServer
        )
        let redirectURI = configuration.oauthRedirectURI ?? "http://127.0.0.1:8765/callback"
        let resource = configuration.endpointURL?.absoluteString ?? discovery.protectedResource.resource ?? ""
        guard !resource.isEmpty else {
            throw ToolExecutionError.invalidArguments("MCP OAuth requires an endpointURL or resource identifier.")
        }

        let verifier = Self.codeVerifier()
        let state = Self.state()
        let authorizationURL = try Self.authorizationURL(
            endpoint: discovery.authorizationServer.authorizationEndpoint,
            clientID: clientID,
            redirectURI: redirectURI,
            resource: resource,
            scopes: scopes.isEmpty ? configuration.oauthScopes : scopes,
            codeChallenge: Self.codeChallenge(for: verifier),
            state: state
        )
        let flow = MCPOAuthFlowRecord(
            serverName: configuration.name,
            state: state,
            codeVerifier: verifier,
            clientID: clientID,
            redirectURI: redirectURI,
            resource: resource,
            tokenEndpoint: discovery.authorizationServer.tokenEndpoint
        )
        try saveJSON(flow, account: MCPOAuthKeychainAccount.flow(serverName: configuration.name, state: state))
        return MCPOAuthStartResult(authorizationURL: authorizationURL, state: state, clientID: clientID)
    }

    public func exchangeCode(configuration: MCPServerConfiguration, state: String, code: String) async throws -> MCPOAuthTokenResult {
        let flow: MCPOAuthFlowRecord = try readJSON(
            account: MCPOAuthKeychainAccount.flow(serverName: configuration.name, state: state)
        )
        guard flow.serverName == configuration.name else {
            throw ToolExecutionError.denied("MCP OAuth flow state does not match server.")
        }

        let tokenObject = try await postForm(
            to: flow.tokenEndpoint,
            fields: [
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": flow.redirectURI,
                "client_id": flow.clientID,
                "code_verifier": flow.codeVerifier,
                "resource": flow.resource
            ]
        )
        guard let accessToken = tokenObject["access_token"] as? String, !accessToken.isEmpty else {
            throw ToolExecutionError.denied("MCP OAuth token response did not include access_token.")
        }

        let record = Self.tokenRecord(
            from: tokenObject,
            accessToken: accessToken,
            fallbackRefreshToken: nil,
            clientID: flow.clientID,
            tokenEndpoint: flow.tokenEndpoint,
            resource: flow.resource
        )
        try saveTokenRecord(record, configuration: configuration)
        return Self.tokenResult(from: record, expiresIn: tokenObject["expires_in"] as? Int)
    }

    public func authorizeWithLoopback(
        configuration: MCPServerConfiguration,
        scopes: [String],
        openAuthorizationURL: @Sendable (URL) async throws -> Void
    ) async throws -> MCPOAuthTokenResult {
        let discovery = try await discover(configuration: configuration)
        let receiver = MCPOAuthLoopbackReceiver(
            preferredRedirectURI: configuration.oauthRedirectURI,
            timeoutNanoseconds: 120_000_000_000
        )
        let session = try await receiver.start()
        let clientID = try await configuredOrRegisteredClientID(
            configuration: configuration,
            metadata: discovery.authorizationServer,
            redirectURI: session.redirectURI
        )
        let resource = configuration.endpointURL?.absoluteString ?? discovery.protectedResource.resource ?? ""
        guard !resource.isEmpty else {
            throw ToolExecutionError.invalidArguments("MCP OAuth requires an endpointURL or resource identifier.")
        }

        let verifier = Self.codeVerifier()
        let state = Self.state()
        let authorizationURL = try Self.authorizationURL(
            endpoint: discovery.authorizationServer.authorizationEndpoint,
            clientID: clientID,
            redirectURI: session.redirectURI,
            resource: resource,
            scopes: scopes.isEmpty ? configuration.oauthScopes : scopes,
            codeChallenge: Self.codeChallenge(for: verifier),
            state: state
        )
        let flow = MCPOAuthFlowRecord(
            serverName: configuration.name,
            state: state,
            codeVerifier: verifier,
            clientID: clientID,
            redirectURI: session.redirectURI,
            resource: resource,
            tokenEndpoint: discovery.authorizationServer.tokenEndpoint
        )
        try saveJSON(flow, account: MCPOAuthKeychainAccount.flow(serverName: configuration.name, state: state))

        try await openAuthorizationURL(authorizationURL)
        let callback = try await session.waitForCallback()
        guard callback.state == state else {
            throw ToolExecutionError.denied("MCP OAuth callback state did not match.")
        }
        return try await exchangeCode(configuration: configuration, state: state, code: callback.code)
    }

    public func refreshToken(configuration: MCPServerConfiguration) async throws -> MCPOAuthTokenResult {
        let record: MCPOAuthTokenRecord = try readJSON(
            account: MCPOAuthKeychainAccount.tokenRecord(serverName: configuration.name)
        )
        guard let refreshToken = record.refreshToken, !refreshToken.isEmpty else {
            throw ToolExecutionError.denied("MCP OAuth token record does not include a refresh_token.")
        }

        let tokenObject = try await postForm(
            to: record.tokenEndpoint,
            fields: [
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": record.clientID,
                "resource": record.resource
            ]
        )
        guard let accessToken = tokenObject["access_token"] as? String, !accessToken.isEmpty else {
            throw ToolExecutionError.denied("MCP OAuth refresh response did not include access_token.")
        }

        let refreshedRecord = Self.tokenRecord(
            from: tokenObject,
            accessToken: accessToken,
            fallbackRefreshToken: refreshToken,
            clientID: record.clientID,
            tokenEndpoint: record.tokenEndpoint,
            resource: record.resource
        )
        try saveTokenRecord(refreshedRecord, configuration: configuration)
        return Self.tokenResult(from: refreshedRecord, expiresIn: tokenObject["expires_in"] as? Int)
    }

    private func resourceMetadataURL(for configuration: MCPServerConfiguration) async throws -> URL {
        if let url = configuration.protectedResourceMetadataURL {
            return url
        }
        guard let endpointURL = configuration.endpointURL else {
            throw ToolExecutionError.invalidArguments("MCP OAuth requires a Streamable HTTP endpointURL.")
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": [
                "protocolVersion": "2025-06-18",
                "capabilities": [:],
                "clientInfo": [
                    "name": "cerberus",
                    "version": "0.1.0"
                ]
            ]
        ], options: [.sortedKeys])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("2025-06-18", forHTTPHeaderField: "MCP-Protocol-Version")
        for (header, value) in configuration.headers where header.lowercased() != "authorization" {
            request.setValue(value, forHTTPHeaderField: header)
        }

        let (_, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ToolExecutionError.denied("MCP OAuth probe returned a non-HTTP response.")
        }
        guard httpResponse.statusCode == 401 else {
            throw ToolExecutionError.denied("MCP server did not return OAuth resource metadata; set protectedResourceMetadataURL in config.")
        }
        guard let authenticate = httpResponse.value(forHTTPHeaderField: "WWW-Authenticate"),
              let url = Self.resourceMetadataURL(fromWWWAuthenticate: authenticate) else {
            throw ToolExecutionError.denied("MCP 401 response did not include WWW-Authenticate resource_metadata.")
        }
        return url
    }

    private func protectedResourceMetadata(from url: URL) async throws -> MCPOAuthProtectedResourceMetadata {
        let object = try await getJSONObject(from: url)
        let servers = (object["authorization_servers"] as? [String] ?? []).compactMap(URL.init(string:))
        return MCPOAuthProtectedResourceMetadata(
            resource: object["resource"] as? String,
            authorizationServers: servers,
            scopesSupported: object["scopes_supported"] as? [String] ?? [],
            rawJSON: Self.stableJSONString(object)
        )
    }

    private func authorizationServerMetadata(from url: URL) async throws -> MCPOAuthAuthorizationServerMetadata {
        let object = try await getJSONObject(from: url)
        guard let authorizationEndpoint = (object["authorization_endpoint"] as? String).flatMap(URL.init(string:)),
              let tokenEndpoint = (object["token_endpoint"] as? String).flatMap(URL.init(string:)) else {
            throw ToolExecutionError.denied("MCP OAuth authorization server metadata is missing endpoints.")
        }

        return MCPOAuthAuthorizationServerMetadata(
            issuer: (object["issuer"] as? String).flatMap(URL.init(string:)),
            authorizationEndpoint: authorizationEndpoint,
            tokenEndpoint: tokenEndpoint,
            registrationEndpoint: (object["registration_endpoint"] as? String).flatMap(URL.init(string:)),
            scopesSupported: object["scopes_supported"] as? [String] ?? [],
            codeChallengeMethodsSupported: object["code_challenge_methods_supported"] as? [String] ?? [],
            rawJSON: Self.stableJSONString(object)
        )
    }

    private func configuredOrRegisteredClientID(
        configuration: MCPServerConfiguration,
        metadata: MCPOAuthAuthorizationServerMetadata,
        redirectURI: String? = nil
    ) async throws -> String {
        if let clientID = configuration.oauthClientID, !clientID.isEmpty {
            return clientID
        }

        let account = MCPOAuthKeychainAccount.clientRegistration(serverName: configuration.name)
        if let registration: MCPOAuthClientRegistration = try? readJSON(account: account) {
            return registration.clientID
        }

        guard let registrationEndpoint = metadata.registrationEndpoint else {
            throw ToolExecutionError.invalidArguments("MCP OAuth requires oauthClientID when dynamic registration is unavailable.")
        }

        let redirectURI = redirectURI ?? configuration.oauthRedirectURI ?? "http://127.0.0.1:8765/callback"
        var request = URLRequest(url: registrationEndpoint)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_name": "cerberus",
            "redirect_uris": [redirectURI],
            "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"],
            "token_endpoint_auth_method": "none"
        ], options: [.sortedKeys])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw ToolExecutionError.denied("MCP OAuth dynamic client registration failed.")
        }
        let object = try Self.jsonObject(from: data)
        guard let clientID = object["client_id"] as? String, !clientID.isEmpty else {
            throw ToolExecutionError.denied("MCP OAuth registration response did not include client_id.")
        }

        let registration = MCPOAuthClientRegistration(clientID: clientID)
        try saveJSON(registration, account: account)
        return clientID
    }

    private func getJSONObject(from url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw ToolExecutionError.denied("MCP OAuth metadata request failed.")
        }
        return try Self.jsonObject(from: data)
    }

    private func postForm(to url: URL, fields: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Self.formEncoded(fields)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw ToolExecutionError.denied("MCP OAuth token exchange failed.")
        }
        return try Self.jsonObject(from: data)
    }

    private func saveJSON<Value: Encodable>(_ value: Value, account: String) throws {
        let data = try JSONEncoder().encode(value)
        try KeychainSecretStore(service: keychainService, account: account).save(data)
    }

    private func saveTokenRecord(_ record: MCPOAuthTokenRecord, configuration: MCPServerConfiguration) throws {
        let accessTokenAccount = configuration.accessTokenKeychainAccount
            ?? MCPOAuthKeychainAccount.accessToken(serverName: configuration.name)
        try KeychainSecretStore(service: keychainService, account: accessTokenAccount).save(Data(record.accessToken.utf8))
        try saveJSON(record, account: MCPOAuthKeychainAccount.tokenRecord(serverName: configuration.name))
    }

    private func readJSON<Value: Decodable>(account: String) throws -> Value {
        guard let data = try KeychainSecretStore(service: keychainService, account: account).data() else {
            throw ToolExecutionError.denied("MCP OAuth flow was not found in Keychain.")
        }
        return try JSONDecoder().decode(Value.self, from: data)
    }

    public static func authorizationServerMetadataURL(for issuer: URL) -> URL {
        var components = URLComponents(url: issuer, resolvingAgainstBaseURL: false)!
        let issuerPath = components.percentEncodedPath
        components.percentEncodedPath = issuerPath.isEmpty || issuerPath == "/"
            ? "/.well-known/oauth-authorization-server"
            : "/.well-known/oauth-authorization-server\(issuerPath)"
        components.query = nil
        components.fragment = nil
        return components.url!
    }

    private static func tokenRecord(
        from object: [String: Any],
        accessToken: String,
        fallbackRefreshToken: String?,
        clientID: String,
        tokenEndpoint: URL,
        resource: String
    ) -> MCPOAuthTokenRecord {
        let expiresIn = object["expires_in"] as? Int
        return MCPOAuthTokenRecord(
            accessToken: accessToken,
            refreshToken: object["refresh_token"] as? String ?? fallbackRefreshToken,
            tokenType: object["token_type"] as? String ?? "Bearer",
            expiresAt: expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) },
            scope: object["scope"] as? String,
            clientID: clientID,
            tokenEndpoint: tokenEndpoint,
            resource: resource
        )
    }

    private static func tokenResult(from record: MCPOAuthTokenRecord, expiresIn: Int?) -> MCPOAuthTokenResult {
        MCPOAuthTokenResult(
            tokenType: record.tokenType,
            expiresIn: expiresIn,
            scope: record.scope,
            hasRefreshToken: record.refreshToken != nil
        )
    }

    public static func authorizationURL(
        endpoint: URL,
        clientID: String,
        redirectURI: String,
        resource: String,
        scopes: [String],
        codeChallenge: String,
        state: String
    ) throws -> URL {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw ToolExecutionError.invalidArguments("Invalid MCP OAuth authorization endpoint.")
        }

        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "resource", value: resource),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        if !scopes.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "scope", value: scopes.joined(separator: " ")))
        }

        guard let url = components.url else {
            throw ToolExecutionError.invalidArguments("Could not build MCP OAuth authorization URL.")
        }
        return url
    }

    public static func codeVerifier(byteCount: Int = 32) -> String {
        base64URLEncoded(randomData(byteCount: byteCount))
    }

    public static func codeChallenge(for verifier: String) -> String {
        base64URLEncoded(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    public static func state(byteCount: Int = 16) -> String {
        base64URLEncoded(randomData(byteCount: byteCount))
    }

    public static func resourceMetadataURL(fromWWWAuthenticate header: String) -> URL? {
        for part in header.split(separator: ",") {
            let text = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let range = text.range(of: "resource_metadata=", options: [.caseInsensitive]) else {
                continue
            }

            var value = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("\""), value.hasSuffix("\"") {
                value.removeFirst()
                value.removeLast()
            }
            return URL(string: value)
        }
        return nil
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let object = object as? [String: Any] else {
            throw ToolExecutionError.invalidArguments("MCP OAuth server returned non-object JSON.")
        }
        return object
    }

    private static func formEncoded(_ fields: [String: String]) -> Data {
        let text = fields
            .map { key, value in
                "\(formEscape(key))=\(formEscape(value))"
            }
            .sorted()
            .joined(separator: "&")
        return Data(text.utf8)
    }

    private static func formEscape(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func randomData(byteCount: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<byteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return Data(bytes)
    }

    private static func stableJSONString(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }
}

public final class MCPOAuthLoopbackReceiver: @unchecked Sendable {
    private let preferredRedirectURI: String?
    private let timeoutNanoseconds: UInt64

    public init(preferredRedirectURI: String?, timeoutNanoseconds: UInt64 = 120_000_000_000) {
        self.preferredRedirectURI = preferredRedirectURI
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    public func start() async throws -> MCPOAuthLoopbackSession {
        let template = Self.redirectTemplate(from: preferredRedirectURI)
        let listener = try NWListener(using: .tcp, on: template.port ?? .any)
        let session = MCPOAuthLoopbackSession(
            listener: listener,
            callbackPath: template.path,
            timeoutNanoseconds: timeoutNanoseconds
        )
        try await session.start()
        return session
    }

    private static func redirectTemplate(from redirectURI: String?) -> (path: String, port: NWEndpoint.Port?) {
        guard let redirectURI,
              let components = URLComponents(string: redirectURI),
              components.scheme == "http",
              components.host == "127.0.0.1" || components.host == "localhost" else {
            return ("/callback", nil)
        }

        let path = components.path.isEmpty ? "/callback" : components.path
        let port = components.port.flatMap { NWEndpoint.Port(rawValue: UInt16($0)) }
        return (path, port)
    }
}

public final class MCPOAuthLoopbackSession: @unchecked Sendable {
    public private(set) var redirectURI: String

    private let listener: NWListener
    private let callbackPath: String
    private let timeoutNanoseconds: UInt64
    private let queue = DispatchQueue(label: "cerberus.mcp.oauth.loopback")
    private let lock = NSLock()
    private var callbackContinuation: CheckedContinuation<MCPOAuthLoopbackCallback, any Error>?
    private var resolvedCallback: Result<MCPOAuthLoopbackCallback, any Error>?

    init(listener: NWListener, callbackPath: String, timeoutNanoseconds: UInt64) {
        self.listener = listener
        self.callbackPath = callbackPath
        self.timeoutNanoseconds = timeoutNanoseconds
        redirectURI = "http://127.0.0.1:0\(callbackPath)"
    }

    public func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else {
                    return
                }

                switch state {
                case .ready:
                    self.redirectURI = "http://127.0.0.1:\(self.listener.port?.rawValue ?? 0)\(self.callbackPath)"
                    self.listener.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    self.listener.stateUpdateHandler = nil
                    continuation.resume(throwing: ToolExecutionError.denied("MCP OAuth loopback listener failed: \(error)"))
                case .cancelled:
                    break
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
        }
    }

    public func waitForCallback() async throws -> MCPOAuthLoopbackCallback {
        try await withThrowingTaskGroup(of: MCPOAuthLoopbackCallback.self) { group in
            group.addTask {
                try await self.awaitCallback()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: self.timeoutNanoseconds)
                self.cancel()
                throw ToolExecutionError.denied("MCP OAuth loopback callback timed out.")
            }

            let callback = try await group.next() ?? MCPOAuthLoopbackCallback(
                code: "",
                state: "",
                requestURL: URL(string: redirectURI)!
            )
            group.cancelAll()
            cancel()
            return callback
        }
    }

    public func cancel() {
        listener.cancel()
    }

    private func awaitCallback() async throws -> MCPOAuthLoopbackCallback {
        return try await withCheckedThrowingContinuation { continuation in
            installCallbackContinuation(continuation)
        }
    }

    private func installCallbackContinuation(_ continuation: CheckedContinuation<MCPOAuthLoopbackCallback, any Error>) {
        lock.lock()
        if let resolvedCallback {
            lock.unlock()
            continuation.resume(with: resolvedCallback)
            return
        }
        callbackContinuation = continuation
        lock.unlock()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        guard Self.isLoopback(connection.endpoint) else {
            respond(connection, status: "403 Forbidden", body: "OAuth callback must arrive on loopback.")
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, error in
            guard let self else {
                connection.cancel()
                return
            }

            if let error {
                self.respond(connection, status: "400 Bad Request", body: "OAuth callback read failed.")
                self.resolve(.failure(ToolExecutionError.denied("MCP OAuth callback read failed: \(error)")))
                return
            }

            let result = self.parse(data ?? Data())
            switch result {
            case .success(let callback):
                self.respond(connection, status: "200 OK", body: "cerberus captured the OAuth callback. You can close this tab.")
                self.resolve(.success(callback))
            case .failure(let error):
                self.respond(connection, status: "400 Bad Request", body: error.localizedDescription)
                self.resolve(.failure(error))
            }
        }
    }

    private func parse(_ data: Data) -> Result<MCPOAuthLoopbackCallback, any Error> {
        guard let text = String(data: data, encoding: .utf8),
              let requestLine = text.components(separatedBy: "\r\n").first else {
            return .failure(ToolExecutionError.invalidArguments("MCP OAuth callback was not valid HTTP."))
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else {
            return .failure(ToolExecutionError.invalidArguments("MCP OAuth callback must use GET."))
        }

        guard let url = URL(string: "http://127.0.0.1\(parts[1])"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.path == callbackPath else {
            return .failure(ToolExecutionError.invalidArguments("MCP OAuth callback path did not match redirect URI."))
        }

        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        if let error = query["error"], !error.isEmpty {
            return .failure(ToolExecutionError.denied("MCP OAuth authorization failed: \(error)"))
        }
        guard let code = query["code"], !code.isEmpty,
              let state = query["state"], !state.isEmpty else {
            return .failure(ToolExecutionError.invalidArguments("MCP OAuth callback is missing code or state."))
        }

        return .success(MCPOAuthLoopbackCallback(code: code, state: state, requestURL: url))
    }

    private func respond(_ connection: NWConnection, status: String, body: String) {
        let payload = Data(body.utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(payload)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func resolve(_ result: Result<MCPOAuthLoopbackCallback, any Error>) {
        lock.lock()
        guard resolvedCallback == nil else {
            lock.unlock()
            return
        }
        resolvedCallback = result
        let continuation = callbackContinuation
        callbackContinuation = nil
        lock.unlock()

        continuation?.resume(with: result)
    }

    private static func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else {
            return false
        }

        let text = "\(host)"
        return text == "127.0.0.1" || text == "::1" || text == "localhost"
    }
}
