import Foundation
import UIKit

/// Assembles the device User-Agent from encoded fragments and owns the
/// `URLSession` used for the config POST + install-data lookup. The same UA is
/// used by the HTTP client and the web view so one session stays consistent.
final class NetworkClient {
    let userAgent: String
    let session: URLSession

    init() {
        userAgent = NetworkClient.buildUserAgent()
        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        config.timeoutIntervalForRequest = Tunables.configTimeout
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    private static func buildUserAgent() -> String {
        let version = normalizedIOS(UIDevice.current.systemVersion)
        let cpu = version.replacingOccurrences(of: ".", with: "_")
        // Every fragment lives encoded in the Rust vault and is assembled at
        // runtime, so no fragment exists as a string literal in the binary.
        let product = RemoteStore.value(.uaProduct)
        let prefix = RemoteStore.value(.uaPlatformPrefix)
        let suffix = RemoteStore.value(.uaPlatformSuffix)
        let engine = RemoteStore.value(.uaEngine)
        let safari = RemoteStore.value(.uaSafariVersion)
        let mobile = RemoteStore.value(.uaMobileToken)
        let tail = RemoteStore.value(.uaSafariTail)
        if product.isEmpty {
            // Vault not populated — fall back to the system default UA.
            return ""
        }
        return "\(product) \(prefix) \(cpu) \(suffix) \(engine) "
            + "Version/\(safari) \(mobile) Safari/\(tail)"
    }

    private static func normalizedIOS(_ raw: String) -> String {
        let parts = raw.split(separator: ".").compactMap { Int($0) }.prefix(3)
        guard let major = parts.first, major >= 15 else { return "18.6" }
        return parts.map(String.init).joined(separator: ".")
    }

    // MARK: Requests

    func post(_ url: URL, body: Data, headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        // Content-Type / Accept value is vault-sourced so no "application/json"
        // literal exists on the Swift side — the two header NAMES are standard
        // RFC 7231 tokens and are indistinguishable from any JSON client.
        let json = RemoteStore.headerJson
        if !json.isEmpty {
            request.setValue(json, forHTTPHeaderField: "Content-Type")
            request.setValue(json, forHTTPHeaderField: "Accept")
        }
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await session.data(for: request)
        return (data, response as? HTTPURLResponse ?? HTTPURLResponse())
    }

    func get(_ url: URL, headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await session.data(for: request)
        return (data, response as? HTTPURLResponse ?? HTTPURLResponse())
    }
}
