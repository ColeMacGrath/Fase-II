import Foundation

/// Cliente REST de la Capa Nube.
nonisolated struct AgentAPIClient: Sendable {
    enum ClientError: LocalizedError {
        case invalidBaseURL
        case unreachable(String)
        case server(status: Int, detail: String)
        case decoding(String)

        var errorDescription: String? {
            switch self {
            case .invalidBaseURL: "La URL del backend no es válida."
            case .unreachable(let base): "No hay conexión con la Capa Nube en \(base). Levanta el contenedor con docker compose up -d."
            case .server(let status, let detail): "La Capa Nube respondió \(status): \(detail)"
            case .decoding(let message): "Respuesta inesperada del backend: \(message)"
            }
        }
    }

    var baseURL: String
    var token: String

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 90
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }

    func health() async throws -> HealthResponse {
        try await send(path: "/health", method: "GET", body: Optional<AnalyzeRequest>.none)
    }

    func analyze(_ request: AnalyzeRequest) async throws -> AnalyzeResponse {
        try await send(path: "/v1/analyze", method: "POST", body: request)
    }

    private func send<Body: Encodable, Response: Decodable>(path: String, method: String, body: Body?) async throws -> Response {
        let trimmed = baseURL.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed + path) else { throw ClientError.invalidBaseURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !token.isEmpty { request.setValue(token, forHTTPHeaderField: "X-Agent-Token") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: request)
        } catch {
            throw ClientError.unreachable(trimmed)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let detail = (try? Self.decoder.decode(APIErrorBody.self, from: data).detail) ?? HTTPURLResponse.localizedString(forStatusCode: status)
            throw ClientError.server(status: status, detail: detail)
        }
        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw ClientError.decoding(error.localizedDescription)
        }
    }
}
