import Foundation

public enum UploadError: Error {
    case disabled
    case invalidResponse
    case httpStatus(Int)
}

public protocol UploadService {
    func createSession(_ fields: [String: Any]) async throws -> String
    func createTrials(sessionRecordId: String, trials: [[String: Any]]) async throws
    func createResults(sessionRecordId: String, fields: [String: Any]) async throws
}

#if UPLOAD_ENABLED
public final class AirtableClient: UploadService {
    private let cfg: AirtableConfig
    private let session: URLSession
    private let encoder = JSONEncoder()

    public init(cfg: AirtableConfig, session: URLSession = .shared) {
        self.cfg = cfg
        self.session = session
    }

    public func createSession(_ fields: [String: Any]) async throws -> String {
        let url = endpoint(path: cfg.useProxy ? "session" : cfg.tableSessions)
        var request = baseRequest(url: url)
        let body = try JSONSerialization.data(withJSONObject: ["fields": fields], options: [])
        request.httpBody = body
        let data = try await perform(request: request)
        let payload = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        guard let id = payload?["id"] as? String else {
            throw UploadError.invalidResponse
        }
        return id
    }

    public func createTrials(sessionRecordId: String, trials: [[String: Any]]) async throws {
        let url = endpoint(path: cfg.useProxy ? "trials" : cfg.tableTrials)
        var request = baseRequest(url: url)
        let records = trials.map { trial -> [String: Any] in
            var fields = trial
            fields["Session"] = [sessionRecordId]
            return ["fields": fields]
        }
        let payload = cfg.useProxy ? ["records": trials, "sessionId": sessionRecordId] : ["records": records]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        _ = try await perform(request: request)
    }

    public func createResults(sessionRecordId: String, fields: [String: Any]) async throws {
        let url = endpoint(path: cfg.useProxy ? "results" : cfg.tableResults)
        var request = baseRequest(url: url)
        var payloadFields = fields
        payloadFields["Session"] = [sessionRecordId]
        let payload = cfg.useProxy ? ["fields": payloadFields, "sessionId": sessionRecordId] : ["fields": payloadFields]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        _ = try await perform(request: request)
    }

    private func endpoint(path: String) -> URL {
        if cfg.useProxy {
            return cfg.baseURL.appendingPathComponent(path)
        } else {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "api.airtable.com"
            components.path = "/v0/\(cfg.baseID)/\(path)"
            return components.url ?? cfg.baseURL
        }
    }

    private func baseRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !cfg.useProxy, let apiKey = cfg.apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func perform(request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UploadError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UploadError.httpStatus(http.statusCode)
        }
        return data
    }
}
#else
public final class AirtableClient: UploadService {
    public init(cfg: AirtableConfig) { }
    public func createSession(_ fields: [String : Any]) async throws -> String {
        throw UploadError.disabled
    }
    public func createTrials(sessionRecordId: String, trials: [[String : Any]]) async throws {
        throw UploadError.disabled
    }
    public func createResults(sessionRecordId: String, fields: [String : Any]) async throws {
        throw UploadError.disabled
    }
}
#endif
