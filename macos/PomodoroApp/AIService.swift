import Foundation

/// Handles AI proxy requests that require authenticated access.
final class AIService {
    enum ServiceError: LocalizedError {
        case missingToken
        case invalidEndpoint
        case encodingFailed
        case invalidResponse
        case serverStatus(Int)
        case emptyBody

        var errorDescription: String? {
            switch self {
            case .missingToken: return "No JWT available. Please sign in first."
            case .invalidEndpoint: return "Unable to form AI proxy endpoint."
            case .encodingFailed: return "Failed to encode request body."
            case .invalidResponse: return "Unexpected server response."
            case .serverStatus(let code): return "Server returned status code \(code)."
            case .emptyBody: return "Response body was empty."
            }
        }
    }

    static let shared = AIService()

    private let baseURL: URL
    private let session: URLSession

    init(
        baseURL: URL = URL(string: "https://us-central1-pomodoro-app1.cloudfunctions.net")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Sends an authenticated AI proxy request.
    /// - Parameters:
    ///   - body: JSON body to forward to the AI service.
    ///   - completion: Result containing response string or an error.
    func sendAIRequest(
        body: [String: Any],
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let jwt = TokenStorage.shared.getToken() else {
            completion(.failure(ServiceError.missingToken))
            return
        }

        guard let url = URL(string: "/aiProxy", relativeTo: baseURL) else {
            completion(.failure(ServiceError.invalidEndpoint))
            return
        }

        let jsonData: Data
        do {
            jsonData = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            completion(.failure(ServiceError.encodingFailed))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData

        let task = session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(ServiceError.invalidResponse))
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                completion(.failure(ServiceError.serverStatus(httpResponse.statusCode)))
                return
            }

            guard let data, !data.isEmpty else {
                completion(.failure(ServiceError.emptyBody))
                return
            }

            if let string = String(data: data, encoding: .utf8) {
                completion(.success(string))
            } else {
                completion(.failure(ServiceError.invalidResponse))
            }
        }

        task.resume()
    }
}
