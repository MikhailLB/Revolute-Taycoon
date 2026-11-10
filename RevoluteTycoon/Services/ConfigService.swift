import Foundation

/// POSTs the flat attribution body to the config endpoint and parses the reply.
/// A successful destination is cached (URL + expiry) for returning launches.
final class ConfigService {
    private let agent: NetworkClient
    private let session: SessionCache

    init(agent: NetworkClient, session: SessionCache) {
        self.agent = agent
        self.session = session
    }

    func request(_ payload: [String: Any]) async -> ConfigResult {
        guard RemoteStore.ready else { return .rejected("credentials_unavailable") }
        guard let url = URL(string: RemoteStore.endpoint) else {
            return .rejected("bad_endpoint")
        }
        do {
            let body = try JSONSerialization.data(withJSONObject: payload)
            debugTrace("exchange request \(String(data: body, encoding: .utf8) ?? "")")
            let (data, response) = try await agent.post(url, body: body)
            debugTrace("exchange response \(response.statusCode)")
            guard response.statusCode == 200 else {
                return .rejected("http_\(response.statusCode)")
            }
            let reply = ConfigResult.parse(data)
            if reply.hasDestination, let dest = reply.url {
                session.cacheUrl(dest, expiresAt: reply.expiresAt)
            }
            return reply
        } catch {
            debugTrace("exchange failed \(error.localizedDescription)")
            return .rejected("network_failure")
        }
    }
}
