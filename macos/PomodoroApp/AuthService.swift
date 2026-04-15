import Foundation

/// Simple authentication service that posts provider credentials and returns a JWT.
final class AuthService {
    enum Error: LocalizedError {
        case invalidEndpoint
        case invalidResponse
        case serverStatus(Int)
        case missingJWT
        case decoding(DecodingError)
        case transport(Swift.Error)

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint:
                return "Could not form login URL."
            case .invalidResponse:
                return "Unexpected server response."
            case .serverStatus(let code):
                return "Server returned status code \(code)."
            case .missingJWT:
                return "Login succeeded but no JWT was returned."
            case .decoding:
                return "Failed to decode server response."
            case .transport(let underlying):
                return underlying.localizedDescription
            }
        }
    }

    static let shared = AuthService()

    /// Base URL for the backend API. Update this to point at your server.
    private let baseURL: URL
    private let session: URLSession

    init(
        baseURL: URL = URL(string: "https://us-central1-pomodoro-app1.cloudfunctions.net")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Sends a POST request to `/auth/login` with the provider and token.
    /// - Parameters:
    ///   - provider: Authentication provider identifier (e.g. "apple", "google").
    ///   - token: Provider-issued token.
    /// - Returns: JWT string from the server response.
    @discardableResult
    func login(provider: String, token: String) async throws -> String {
        guard let url = URL(string: "/auth/login", relativeTo: baseURL) else {
            throw Error.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(LoginRequest(provider: provider, token: token))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Error.transport(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw Error.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw Error.serverStatus(httpResponse.statusCode)
        }

        do {
            let loginResponse = try JSONDecoder().decode(LoginResponse.self, from: data)
            guard !loginResponse.jwt.isEmpty else { throw Error.missingJWT }
            TokenStorage.shared.saveToken(jwt: loginResponse.jwt)
            return loginResponse.jwt
        } catch let decodingError as DecodingError {
            throw Error.decoding(decodingError)
        }
    }
}

private struct LoginRequest: Encodable {
    let provider: String
    let token: String
}

private struct LoginResponse: Decodable {
    let jwt: String
}
