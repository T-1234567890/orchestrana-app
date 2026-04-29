import Foundation
import Combine
import CryptoKit
import FirebaseAppCheck
import FirebaseAuth
import FirebaseCore
import StoreKit

enum AppCheckRequestAuthorizer {
    static let headerName = "X-Firebase-AppCheck"

    enum AppCheckError: LocalizedError {
        case missingToken

        var errorDescription: String? {
            switch self {
            case .missingToken:
                return "App Check token is unavailable."
            }
        }
    }

    static func fetchToken(forceRefresh: Bool = false) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            AppCheck.appCheck().token(forcingRefresh: forceRefresh) { token, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let value = token?.token, !value.isEmpty else {
                    continuation.resume(throwing: AppCheckError.missingToken)
                    return
                }

                continuation.resume(returning: value)
            }
        }
    }

    static func authorize(_ request: inout URLRequest) async {
        do {
            let token = try await fetchToken()
            request.setValue(token, forHTTPHeaderField: headerName)
        } catch {
            ClientLog.debugError("[AppCheck] Token unavailable. Continuing without App Check header", error)
        }
    }
}

private enum CloudEndpointResolver {
    static func explicitURL(for key: String) -> URL? {
        guard let value = Bundle.main.infoDictionary?[key] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: value),
              isAllowed(url) else {
            return nil
        }
        return url
    }

    static func functionsURL(path: String, region: String = cloudFunctionsRegion()) -> URL? {
        guard let projectID = FirebaseApp.app()?.options.projectID,
              !projectID.isEmpty else {
            return nil
        }
        return URL(string: "https://\(region)-\(projectID).cloudfunctions.net/\(path)")
    }

    static func cloudFunctionsRegion() -> String {
        if let configured = Bundle.main.infoDictionary?["POMODORO_CLOUD_FUNCTION_REGION"] as? String,
           !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return configured
        }
        return "us-central1"
    }

    private static func isAllowed(_ url: URL) -> Bool {
#if DEBUG
        return true
#else
        guard url.scheme?.lowercased() == "https" else {
            return false
        }
        let host = url.host?.lowercased() ?? ""
        return host != "localhost"
            && host != "127.0.0.1"
            && host != "::1"
            && !host.hasSuffix(".localhost")
#endif
    }
}

final class APIClient {
    enum APIError: LocalizedError {
        case invalidEndpoint
        case authRequired
        case missingToken

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint: return LocalizationManager.shared.text("api.error.invalid_endpoint")
            case .authRequired: return LocalizationManager.shared.text("api.error.auth_required")
            case .missingToken: return LocalizationManager.shared.text("api.error.missing_token")
            }
        }
    }

    enum HTTPMethod: String {
        case get = "GET"
        case post = "POST"
    }

    static let shared = APIClient()

    private let auth: Auth

    private init(auth: Auth = Auth.auth()) {
        self.auth = auth
    }

    func makeRequest(
        path: String,
        method: HTTPMethod = .get,
        body: Data? = nil
    ) async throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: Self.baseURL) else {
            throw APIError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let token = try await fetchIDToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        await AppCheckRequestAuthorizer.authorize(&request)

        return request
    }

    private func fetchIDToken(forceRefresh: Bool = false) async throws -> String {
        guard let user = auth.currentUser else {
            throw APIError.authRequired
        }

        return try await withCheckedThrowingContinuation { continuation in
            user.getIDTokenForcingRefresh(forceRefresh) { token, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let token, !token.isEmpty else {
                    continuation.resume(throwing: APIError.missingToken)
                    return
                }
                continuation.resume(returning: token)
            }
        }
    }

    private static var baseURL: URL {
        if let url = CloudEndpointResolver.explicitURL(for: "POMODORO_CLOUD_BASE_URL") {
            return url
        }
        return CloudEndpointResolver.functionsURL(path: "")!
    }
}

final class AccountDeletionAPIClient {
    enum AccountDeletionError: LocalizedError {
        case invalidEndpoint
        case invalidResponse
        case network(Swift.Error)
        case http(statusCode: Int, message: String?)

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint:
                return LocalizationManager.shared.text("api.error.invalid_endpoint")
            case .invalidResponse:
                return LocalizationManager.shared.text("api.error.aiproxy_invalid_response")
            case .network(let error):
                return error.localizedDescription
            case .http(_, let message):
                return message ?? LocalizationManager.shared.text("api.error.aiproxy_invalid_response")
            }
        }
    }

    private struct DeleteResponse: Decodable {
        let ok: Bool
    }

    private struct ErrorEnvelope: Decodable {
        struct InnerError: Decodable {
            let message: String?
        }

        let error: InnerError?
        let message: String?
    }

    private let session: URLSession
    private let region: String

    init(session: URLSession = .shared, region: String? = nil) {
        self.session = session
        if let region {
            self.region = region
        } else {
            self.region = CloudEndpointResolver.cloudFunctionsRegion()
        }
    }

    func deleteAccount() async throws {
        let token = try await AuthViewModel.shared.getValidIDToken()
        let endpoint = try resolveEndpointURL()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        await AppCheckRequestAuthorizer.authorize(&request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AccountDeletionError.network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AccountDeletionError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            guard (try? JSONDecoder().decode(DeleteResponse.self, from: data).ok) == true else {
                throw AccountDeletionError.invalidResponse
            }
        default:
            throw AccountDeletionError.http(
                statusCode: httpResponse.statusCode,
                message: extractErrorMessage(from: data)
            )
        }
    }

    private func resolveEndpointURL() throws -> URL {
        if let url = CloudEndpointResolver.explicitURL(for: "POMODORO_DELETE_ACCOUNT_URL") {
            return url
        }

        guard let url = CloudEndpointResolver.functionsURL(path: "deleteAccount", region: region) else {
            throw AccountDeletionError.invalidEndpoint
        }

        return url
    }

    private func extractErrorMessage(from data: Data) -> String? {
        if let decoded = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
            return decoded.error?.message ?? decoded.message
        }
        if let raw = String(data: data, encoding: .utf8),
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return raw
        }
        return nil
    }
}

struct CloudUserProfile: Decodable {
    let uid: String
    let email: String?
    let supportId: String?
    let displayName: String?
}

final class UserProfileAPIClient {
    enum UserProfileError: LocalizedError {
        case invalidEndpoint
        case invalidResponse
        case network(Swift.Error)
        case http(statusCode: Int, message: String?)

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint:
                return LocalizationManager.shared.text("api.error.invalid_endpoint")
            case .invalidResponse:
                return LocalizationManager.shared.text("api.error.aiproxy_invalid_response")
            case .network(let error):
                return error.localizedDescription
            case .http(_, let message):
                return message ?? LocalizationManager.shared.text("api.error.aiproxy_invalid_response")
            }
        }
    }

    private struct ErrorEnvelope: Decodable {
        struct InnerError: Decodable {
            let message: String?
        }

        let error: InnerError?
        let message: String?
    }

    private let session: URLSession
    private let region: String

    init(session: URLSession = .shared, region: String? = nil) {
        self.session = session
        if let region {
            self.region = region
        } else {
            self.region = CloudEndpointResolver.cloudFunctionsRegion()
        }
    }

    func fetchCurrentUserProfile() async throws -> CloudUserProfile {
        let token = try await AuthViewModel.shared.getValidIDToken()
        let endpoint = try resolveEndpointURL()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        await AppCheckRequestAuthorizer.authorize(&request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UserProfileError.network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UserProfileError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            do {
                return try JSONDecoder().decode(CloudUserProfile.self, from: data)
            } catch {
                throw UserProfileError.invalidResponse
            }
        default:
            throw UserProfileError.http(
                statusCode: httpResponse.statusCode,
                message: extractErrorMessage(from: data)
            )
        }
    }

    private func resolveEndpointURL() throws -> URL {
        if let url = CloudEndpointResolver.explicitURL(for: "POMODORO_GET_ME_URL") {
            return url
        }

        guard let url = CloudEndpointResolver.functionsURL(path: "getMe", region: region) else {
            throw UserProfileError.invalidEndpoint
        }

        return url
    }

    private func extractErrorMessage(from data: Data) -> String? {
        if let decoded = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
            return decoded.error?.message ?? decoded.message
        }
        if let raw = String(data: data, encoding: .utf8),
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return raw
        }
        return nil
    }
}

/// Typed client for calling the Firebase HTTPS function `aiProxy`.
///
/// Example usage:
/// ```swift
/// let client = AIProxyClient()
/// let payload = AIProxyClient.PromptRequest(
///     prompt: "Summarize my focus sessions for today."
/// )
/// let response: AIProxyClient.ProxyResponse = try await client.sendPrompt(payload)
/// ```
final class AIProxyClient {
    private static let maxRetryAttempts = 3

    struct PromptRequest: Encodable {
        let prompt: String
        let model: String?
        let modelFamily: String?
        let featureType: String?
        let temperature: Double?
        let maxOutputTokens: Int?
        let metadata: [String: String]?

        init(
            prompt: String,
            model: String? = nil,
            modelFamily: String? = nil,
            featureType: String? = nil,
            temperature: Double? = nil,
            maxOutputTokens: Int? = nil,
            metadata: [String: String]? = nil
        ) {
            self.prompt = prompt
            self.model = model
            self.modelFamily = modelFamily
            self.featureType = featureType
            self.temperature = temperature
            self.maxOutputTokens = maxOutputTokens
            self.metadata = metadata
        }

        enum CodingKeys: String, CodingKey {
            case prompt
            case model
            case modelFamily
            case featureType
            case temperature
            case maxOutputTokens = "max_output_tokens"
            case metadata
        }
    }

    /// Default response type for common aiProxy JSON payloads.
    struct ProxyResponse: Decodable {
        let text: String?
        let output: String?
        let result: String?
        let model: String?
        let modelFamily: String?

        var outputText: String? {
            text ?? output ?? result
        }
    }

    enum AIProxyError: LocalizedError {
        case invalidEndpoint
        case unauthorized
        case forbidden(message: String?)
        case quotaExceeded(message: String?)
        case decodingFailed(Swift.Error)
        case invalidResponse
        case network(Swift.Error)
        case http(statusCode: Int, message: String?)

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint:
                return LocalizationManager.shared.text("api.error.aiproxy_invalid_endpoint")
            case .unauthorized:
                return LocalizationManager.shared.text("api.error.aiproxy_unauthorized")
            case .forbidden(let message):
                return message ?? LocalizationManager.shared.text("api.error.aiproxy_forbidden")
            case .quotaExceeded(let message):
                return message ?? LocalizationManager.shared.text("api.error.aiproxy_quota_exceeded")
            case .decodingFailed:
                return LocalizationManager.shared.text("api.error.aiproxy_decoding_failed")
            case .invalidResponse:
                return LocalizationManager.shared.text("api.error.aiproxy_invalid_response")
            case .network(let error):
                return error.localizedDescription
            case .http(let statusCode, let message):
                return message ?? LocalizationManager.shared.format("api.error.aiproxy_http_status", statusCode)
            }
        }
    }

    private struct ErrorEnvelope: Decodable {
        struct InnerError: Decodable {
            let message: String?
            let status: String?
            let code: Int?
        }

        let error: InnerError?
        let message: String?
    }

    private let session: URLSession
    private let region: String

    init(
        session: URLSession = .shared,
        region: String? = nil
    ) {
        self.session = session
        if let region {
            self.region = region
        } else {
            self.region = CloudEndpointResolver.cloudFunctionsRegion()
        }
    }

    func sendPrompt<Response: Decodable>(_ requestBody: PromptRequest, decodeAs: Response.Type = Response.self) async throws -> Response {
        try await send(requestBody, decodeAs: decodeAs)
    }

    func send<Body: Encodable, Response: Decodable>(_ body: Body, decodeAs: Response.Type = Response.self) async throws -> Response {
        let requestBody = try JSONEncoder().encode(body)
        var lastError: AIProxyError?

        for attempt in 1...Self.maxRetryAttempts {
            do {
                return try await performSend(bodyData: requestBody, decodeAs: decodeAs)
            } catch let error as AIProxyError {
                lastError = error
                guard shouldRetry(error), attempt < Self.maxRetryAttempts else {
                    throw error
                }
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 500_000_000)
            }
        }

        if let lastError {
            throw lastError
        }
        throw AIProxyError.invalidResponse
    }

    private func performSend<Response: Decodable>(bodyData: Data, decodeAs: Response.Type) async throws -> Response {
        let token = try await AuthViewModel.shared.getValidIDToken()
        let endpoint = try resolveEndpointURL()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        await AppCheckRequestAuthorizer.authorize(&request)
        request.httpBody = bodyData

        let data: Data
        let urlResponse: URLResponse
        do {
            (data, urlResponse) = try await session.data(for: request)
        } catch {
            throw AIProxyError.network(error)
        }

        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            throw AIProxyError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            do {
                return try JSONDecoder().decode(Response.self, from: data)
            } catch {
                throw AIProxyError.decodingFailed(error)
            }
        case 401:
            throw AIProxyError.unauthorized
        case 403:
            throw AIProxyError.forbidden(message: extractErrorMessage(from: data))
        case 429:
            throw AIProxyError.quotaExceeded(message: extractErrorMessage(from: data))
        default:
            throw AIProxyError.http(
                statusCode: httpResponse.statusCode,
                message: extractErrorMessage(from: data)
            )
        }
    }

    private func shouldRetry(_ error: AIProxyError) -> Bool {
        switch error {
        case .network, .invalidResponse, .decodingFailed:
            return true
        case .http(let statusCode, _):
            return statusCode >= 500
        case .invalidEndpoint, .unauthorized, .forbidden, .quotaExceeded:
            return false
        }
    }

    private func resolveEndpointURL() throws -> URL {
        if let url = CloudEndpointResolver.explicitURL(for: "POMODORO_AI_PROXY_URL") {
            return url
        }

        guard let url = CloudEndpointResolver.functionsURL(path: "aiProxy", region: region) else {
            throw AIProxyError.invalidEndpoint
        }
        return url
    }

    private func extractErrorMessage(from data: Data) -> String? {
        if let decoded = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
            return decoded.error?.message ?? decoded.message
        }
        if let raw = String(data: data, encoding: .utf8),
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return raw
        }
        return nil
    }

}

final class EventTasksAPIClient {
    struct EventTaskPayload: Decodable {
        let id: UUID
        let title: String
        let isCompleted: Bool
        let createdAt: Date
        let source: PlanningItem.EventTask.Source
    }

    struct EventStatePayload: Decodable {
        let eventId: UUID
        let eventTitle: String?
        let eventDescription: String?
        let startTime: Date?
        let endTime: Date?
        let hasTaskMode: Bool
        let eventTasks: [EventTaskPayload]
    }

    private struct GenerateRequest: Encodable {
        let eventId: UUID
        let eventTitle: String
        let eventDescription: String?
        let startTime: Date?
        let endTime: Date?
    }

    enum EventTasksError: LocalizedError {
        case invalidEndpoint
        case invalidResponse
        case unauthorized
        case forbidden(message: String?)
        case network(Swift.Error)
        case http(statusCode: Int, message: String?)

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint:
                return LocalizationManager.shared.text("api.error.invalid_endpoint")
            case .invalidResponse:
                return LocalizationManager.shared.text("api.error.aiproxy_invalid_response")
            case .unauthorized:
                return LocalizationManager.shared.text("api.error.auth_required")
            case .forbidden(let message):
                return message ?? LocalizationManager.shared.text("api.error.aiproxy_forbidden")
            case .network(let error):
                return error.localizedDescription
            case .http(_, let message):
                return message ?? LocalizationManager.shared.text("api.error.aiproxy_invalid_response")
            }
        }
    }

    private struct ErrorEnvelope: Decodable {
        struct InnerError: Decodable {
            let message: String?
        }

        let error: InnerError?
        let message: String?
    }

    private let session: URLSession
    private let region: String

    init(session: URLSession = .shared, region: String? = nil) {
        self.session = session
        if let region {
            self.region = region
        } else {
            self.region = CloudEndpointResolver.cloudFunctionsRegion()
        }
    }

    func fetchState(eventID: UUID) async throws -> EventStatePayload {
        EventStatePayload(
            eventId: eventID,
            eventTitle: nil,
            eventDescription: nil,
            startTime: nil,
            endTime: nil,
            hasTaskMode: false,
            eventTasks: []
        )
    }

    func sync(event: PlanningItem) async throws -> EventStatePayload {
        localEventState(for: event)
    }

    func generateTasks(for event: PlanningItem) async throws -> EventStatePayload {
        let endpoint = try resolveEndpointURL(functionName: "generateEventTasks")
        var request = try await authorizedRequest(url: endpoint, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(
            GenerateRequest(
                eventId: event.id,
                eventTitle: event.title,
                eventDescription: event.notes,
                startTime: event.startDate,
                endTime: event.endDate
            )
        )
        return try await send(request, decodeAs: EventStatePayload.self)
    }

    private func localEventState(for event: PlanningItem) -> EventStatePayload {
        EventStatePayload(
            eventId: event.id,
            eventTitle: event.title,
            eventDescription: event.notes,
            startTime: event.startDate,
            endTime: event.endDate,
            hasTaskMode: event.hasTaskMode,
            eventTasks: event.eventTasks.map {
                EventTaskPayload(
                    id: $0.id,
                    title: $0.title,
                    isCompleted: $0.isCompleted,
                    createdAt: $0.createdAt,
                    source: $0.source
                )
            }
        )
    }

    private func authorizedRequest(url: URL, method: String) async throws -> URLRequest {
        let token = try await AuthViewModel.shared.getValidIDToken()
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        await AppCheckRequestAuthorizer.authorize(&request)
        return request
    }

    private func send<Response: Decodable>(_ request: URLRequest, decodeAs: Response.Type) async throws -> Response {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw EventTasksError.network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EventTasksError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try decoder.decode(Response.self, from: data)
            } catch {
                throw EventTasksError.invalidResponse
            }
        case 401:
            throw EventTasksError.unauthorized
        case 403:
            throw EventTasksError.forbidden(message: extractErrorMessage(from: data))
        default:
            throw EventTasksError.http(statusCode: httpResponse.statusCode, message: extractErrorMessage(from: data))
        }
    }

    private func resolveEndpointURL(functionName: String, queryItems: [URLQueryItem] = []) throws -> URL {
        guard let baseURL = CloudEndpointResolver.functionsURL(path: functionName, region: region),
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw EventTasksError.invalidEndpoint
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw EventTasksError.invalidEndpoint
        }
        return url
    }

    private func extractErrorMessage(from data: Data) -> String? {
        if let decoded = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
            return decoded.error?.message ?? decoded.message
        }
        if let raw = String(data: data, encoding: .utf8),
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return raw
        }
        return nil
    }
}

struct SubscriptionEntitlement: Decodable {
    let effectiveProductId: String?
    let tier: String
    let expires: String?
    let nextProductId: String?
    let nextTier: String?
    let productId: String?
    let status: String?
}

final class SubscriptionAPIClient {
    enum SubscriptionAPIError: LocalizedError {
        case invalidEndpoint
        case invalidResponse
        case network(Swift.Error)
        case http(statusCode: Int, message: String?)

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint:
                return LocalizationManager.shared.text("api.error.invalid_endpoint")
            case .invalidResponse:
                return LocalizationManager.shared.text("api.error.aiproxy_invalid_response")
            case .network(let error):
                return error.localizedDescription
            case .http(_, let message):
                return message ?? LocalizationManager.shared.text("api.error.aiproxy_invalid_response")
            }
        }
    }

    private struct VerifyRequest: Encodable {
        let transactionId: String
        let originalTransactionId: String?
        let productId: String?
        let signedTransactionInfo: String?
        let userId: String?
        let syncReason: String?
    }

    private struct ErrorEnvelope: Decodable {
        struct InnerError: Decodable {
            let message: String?
        }

        let error: InnerError?
        let message: String?
    }

    private let session: URLSession
    private let region: String

    init(
        session: URLSession = .shared,
        region: String? = nil
    ) {
        self.session = session
        if let region {
            self.region = region
        } else {
            self.region = CloudEndpointResolver.cloudFunctionsRegion()
        }
    }

    func verify(
        transactionId: String,
        originalTransactionId: String? = nil,
        productId: String? = nil,
        signedTransactionInfo: String? = nil,
        userId: String? = nil,
        syncReason: String? = nil
    ) async throws -> SubscriptionEntitlement {
        let token = try await AuthViewModel.shared.getValidIDToken()
        let endpoint = try resolveEndpointURL()
        ClientLog.debug("[SubscriptionAPI] Verifying transaction")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        await AppCheckRequestAuthorizer.authorize(&request)
        request.httpBody = try JSONEncoder().encode(VerifyRequest(
            transactionId: transactionId,
            originalTransactionId: originalTransactionId,
            productId: productId,
            signedTransactionInfo: signedTransactionInfo,
            userId: userId,
            syncReason: syncReason
        ))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SubscriptionAPIError.network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SubscriptionAPIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            do {
                let entitlement = try JSONDecoder().decode(SubscriptionEntitlement.self, from: data)
                ClientLog.debug("[SubscriptionAPI] Transaction verified")
                return entitlement
            } catch {
                throw SubscriptionAPIError.invalidResponse
            }
        default:
            ClientLog.debug("[SubscriptionAPI] Verification failed with HTTP \(httpResponse.statusCode)")
            throw SubscriptionAPIError.http(
                statusCode: httpResponse.statusCode,
                message: extractErrorMessage(from: data)
            )
        }
    }

    private func resolveEndpointURL() throws -> URL {
        if let url = CloudEndpointResolver.explicitURL(for: "POMODORO_SUBSCRIPTION_VERIFY_URL") {
            return url
        }

        guard let url = CloudEndpointResolver.functionsURL(path: "subscriptionVerify", region: region) else {
            throw SubscriptionAPIError.invalidEndpoint
        }

        return url
    }

    private func extractErrorMessage(from data: Data) -> String? {
        if let decoded = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
            return decoded.error?.message ?? decoded.message
        }
        if let raw = String(data: data, encoding: .utf8),
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return raw
        }
        return nil
    }

}

@MainActor
final class SubscriptionStore: ObservableObject {
    private struct EmptyStoreProductsError: LocalizedError {
        var errorDescription: String? {
            "No subscription products were returned by StoreKit."
        }
    }

    enum SubscriptionChangeKind: String {
        case newPurchase = "new_purchase"
        case upgrade
        case downgrade
        case sameTierChange = "same_tier_change"
        case noChange = "no_change"
    }

    private struct ActiveSubscriptionContext {
        let transaction: Transaction
        let renewalInfo: Product.SubscriptionInfo.RenewalInfo?
        let renewalInfoJWS: String?
        let productID: String
        let tier: String
        let expirationDate: Date?
    }

    static let shared = SubscriptionStore()

    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isRestoring = false
    @Published private(set) var activePurchaseProductID: String?
    @Published private(set) var lastEntitlement: SubscriptionEntitlement?
    @Published private(set) var isSubscribed = false
    @Published private(set) var activeProductIDs: Set<String> = []
    @Published private(set) var localSubscriptionTier: FeatureGate.Tier = .free
    @Published private(set) var localSubscriptionEndAt: Date?
    @Published private(set) var productLoadErrorMessage: String?
    @Published var errorMessage: String?

    private let productIDs = [
        "pomodoro.pro.monthly",
        "pomodoro.pro.yearly",
        "pomodoro.plus.monthly",
        "pomodoro.plus.yearly",
    ]

    private let apiClient: SubscriptionAPIClient
    private var updatesTask: Task<Void, Never>?
    private var hasStarted = false

    private init(apiClient: SubscriptionAPIClient? = nil) {
        self.apiClient = apiClient ?? SubscriptionAPIClient()
    }

    deinit {
        updatesTask?.cancel()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        updatesTask = Task { [weak self] in
            await self?.observeTransactionUpdates()
        }

        Task { [weak self] in
            guard let self else { return }
            await self.loadProducts()
            await self.syncCurrentEntitlements()
        }
    }

    func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        productLoadErrorMessage = nil

        let maxAttempts = 3
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                let loadedProducts = try await Product.products(for: productIDs)
                guard !loadedProducts.isEmpty else {
                    throw EmptyStoreProductsError()
                }
                products = loadedProducts.sorted { lhs, rhs in
                    let lhsRank = Self.productSortRank(for: lhs.id)
                    let rhsRank = Self.productSortRank(for: rhs.id)
                    if lhsRank == rhsRank {
                        return lhs.displayPrice < rhs.displayPrice
                    }
                    return lhsRank < rhsRank
                }
                productLoadErrorMessage = nil
                return
            } catch {
                lastError = error
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 500_000_000)
                }
            }
        }

        if let lastError {
            productLoadErrorMessage = Self.productLoadFailureMessage(for: lastError)
        }
    }

    func ensureProductsLoaded() async {
        guard products.isEmpty else { return }
        await loadProducts()
    }

    func purchase(_ product: Product) async {
        activePurchaseProductID = product.id
        errorMessage = nil
        defer { activePurchaseProductID = nil }

        do {
            _ = try await AuthViewModel.shared.prepareForPurchase()
            let activeContext = try await activeSubscriptionContext(preferredProduct: product)
            let changeKind = determineChangeKind(from: activeContext, to: product.id)
            if changeKind == .noChange {
                errorMessage = "This subscription is already active."
                return
            }

            var purchaseOptions: Set<Product.PurchaseOption> = []
            if let appAccountToken = appAccountToken() {
                purchaseOptions.insert(.appAccountToken(appAccountToken))
            }

            let result = try await product.purchase(options: purchaseOptions)
            switch result {
            case .success(let verification):
                let transaction = try verified(verification)
                guard productIDs.contains(transaction.productID) else {
                    errorMessage = "Failed to verify transaction."
                    return
                }
                applyLocalEntitlements(from: [transaction])
                await transaction.finish()
                syncBackendInBackground(
                    for: transaction,
                    signedTransactionInfo: verification.jwsRepresentation,
                    reason: "purchase"
                )
            case .pending:
                errorMessage = "Purchase is pending approval."
            case .userCancelled:
                errorMessage = nil
            @unknown default:
                errorMessage = "Purchase status is temporarily unavailable."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        isRestoring = true
        errorMessage = nil
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
        } catch {
            ClientLog.debugError("[StoreKit] AppStore.sync failed during restore", error)
        }

        await syncCurrentEntitlements(reason: "restore")
    }

    func syncCurrentEntitlements(reason: String = "current_entitlements") async {
        errorMessage = nil
        var activeTransactions: [Transaction] = []
        var backendSyncFailed = false

        for await verification in Transaction.currentEntitlements {
            let transaction: Transaction
            do {
                transaction = try verified(verification)
            } catch {
                ClientLog.debugError("[StoreKit] Skipping unverified current entitlement", error)
                continue
            }

            guard isActiveSubscriptionTransaction(transaction) else {
                continue
            }

            let signedTransactionInfo = verification.jwsRepresentation
            activeTransactions.append(transaction)
            do {
                lastEntitlement = try await syncBackend(
                    for: transaction,
                    signedTransactionInfo: signedTransactionInfo,
                    reason: reason
                )
            } catch {
                backendSyncFailed = true
                ClientLog.debugError("[SubscriptionAPI] Backend sync failed", error)
            }
        }

        applyLocalEntitlements(from: activeTransactions)
        if backendSyncFailed && isSubscribed {
            errorMessage = "Server subscription verification failed. AI features unlock after the server verifies your purchase."
        }
        await FeatureGate.shared.refreshAllowance()
    }

    private func observeTransactionUpdates() async {
        for await verification in Transaction.updates {
            do {
                let signedTransactionInfo = verification.jwsRepresentation
                let transaction = try await MainActor.run {
                    try self.verified(verification)
                }

                guard await MainActor.run(body: { self.isActiveSubscriptionTransaction(transaction) }) else {
                    await transaction.finish()
                    await syncCurrentEntitlements(reason: "transaction_update")
                    continue
                }

                await MainActor.run {
                    self.applyLocalEntitlements(from: [transaction])
                }
                await transaction.finish()
                await MainActor.run {
                    self.syncBackendInBackground(
                        for: transaction,
                        signedTransactionInfo: signedTransactionInfo,
                        reason: "transaction_update"
                    )
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to verify transaction."
                }
            }
        }
    }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified(_, let error):
            throw error
        }
    }

    private func activeSubscriptionContext(preferredProduct: Product? = nil) async throws -> ActiveSubscriptionContext? {
        if let preferredProduct,
           let subscription = preferredProduct.subscription {
            do {
                let statuses = try await subscription.status
                if let context = try verifiedActiveSubscriptionContext(from: statuses) {
                    return context
                }
            } catch {
                ClientLog.debugError("[StoreKit] Could not load subscription status before purchase", error)
            }
        }

        var fallbackTransaction: Transaction?
        for await verification in Transaction.currentEntitlements {
            let transaction: Transaction
            do {
                transaction = try verified(verification)
            } catch {
                ClientLog.debugError("[StoreKit] Skipping unverified entitlement during purchase preflight", error)
                continue
            }
            if productIDs.contains(transaction.productID) {
                fallbackTransaction = transaction
                break
            }
        }

        guard let fallbackTransaction,
              let tier = subscriptionTier(for: fallbackTransaction.productID) else {
            return nil
        }

        return ActiveSubscriptionContext(
            transaction: fallbackTransaction,
            renewalInfo: nil,
            renewalInfoJWS: nil,
            productID: fallbackTransaction.productID,
            tier: tier,
            expirationDate: fallbackTransaction.expirationDate
        )
    }

    private func verifiedActiveSubscriptionContext(
        from statuses: [Product.SubscriptionInfo.Status]
    ) throws -> ActiveSubscriptionContext? {
        let activeStates: Set<Product.SubscriptionInfo.RenewalState> = [
            .subscribed,
            .inGracePeriod,
            .inBillingRetryPeriod,
        ]

        let sortedStatuses = statuses
            .filter { activeStates.contains($0.state) }
            .sorted {
                let lhsExpiration = (try? verified($0.transaction).expirationDate) ?? .distantPast
                let rhsExpiration = (try? verified($1.transaction).expirationDate) ?? .distantPast
                return lhsExpiration > rhsExpiration
            }

        for status in sortedStatuses {
            let transaction = try verified(status.transaction)
            guard let tier = subscriptionTier(for: transaction.productID) else {
                continue
            }
            let renewalInfo = try? verified(status.renewalInfo)
            return ActiveSubscriptionContext(
                transaction: transaction,
                renewalInfo: renewalInfo,
                renewalInfoJWS: renewalInfo == nil ? nil : status.renewalInfo.jwsRepresentation,
                productID: transaction.productID,
                tier: tier,
                expirationDate: transaction.expirationDate
            )
        }

        return nil
    }

    private func determineChangeKind(
        from activeContext: ActiveSubscriptionContext?,
        to newProductID: String
    ) -> SubscriptionChangeKind {
        guard let newTier = subscriptionTier(for: newProductID) else {
            return .newPurchase
        }
        guard let activeContext else {
            return .newPurchase
        }
        if activeContext.productID == newProductID {
            return .noChange
        }
        let currentRank = tierRank(for: activeContext.tier)
        let newRank = tierRank(for: newTier)
        if newRank > currentRank {
            return .upgrade
        }
        if newRank < currentRank {
            return .downgrade
        }
        return .sameTierChange
    }

    private func subscriptionTier(for productID: String) -> String? {
        if productID.contains("pomodoro.pro.") {
            return "pro"
        }
        if productID.contains("pomodoro.plus.") {
            return "plus"
        }
        return nil
    }

    private func featureTier(for productID: String) -> FeatureGate.Tier? {
        switch subscriptionTier(for: productID) {
        case "plus":
            return .plus
        case "pro":
            return .pro
        default:
            return nil
        }
    }

    private func isActiveSubscriptionTransaction(_ transaction: Transaction) -> Bool {
        guard productIDs.contains(transaction.productID), transaction.revocationDate == nil else {
            return false
        }
        if let expirationDate = transaction.expirationDate {
            return expirationDate > Date()
        }
        return true
    }

    private func applyLocalEntitlements(from transactions: [Transaction]) {
        let activeTransactions = transactions.filter(isActiveSubscriptionTransaction)
        let productIDs = Set(activeTransactions.map(\.productID))
        activeProductIDs = productIDs
        isSubscribed = !productIDs.isEmpty

        guard let bestTransaction = activeTransactions.sorted(by: { lhs, rhs in
            let lhsRank = tierRank(for: subscriptionTier(for: lhs.productID) ?? "free")
            let rhsRank = tierRank(for: subscriptionTier(for: rhs.productID) ?? "free")
            if lhsRank != rhsRank {
                return lhsRank > rhsRank
            }
            return (lhs.expirationDate ?? .distantFuture) > (rhs.expirationDate ?? .distantFuture)
        }).first,
              let tier = featureTier(for: bestTransaction.productID) else {
            localSubscriptionTier = .free
            localSubscriptionEndAt = nil
            FeatureGate.shared.clearLocalStoreKitEntitlement()
            return
        }

        localSubscriptionTier = tier
        localSubscriptionEndAt = bestTransaction.expirationDate
        FeatureGate.shared.applyLocalStoreKitEntitlement(
            tier: tier,
            subscriptionEndAt: bestTransaction.expirationDate
        )
    }

    private func syncBackendInBackground(
        for transaction: Transaction,
        signedTransactionInfo: String?,
        reason: String
    ) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let entitlement = try await self.syncBackend(
                    for: transaction,
                    signedTransactionInfo: signedTransactionInfo,
                    reason: reason
                )
                await MainActor.run {
                    self.lastEntitlement = entitlement
                }
                await FeatureGate.shared.refreshAllowance()
                await MainActor.run {
                    if self.isSubscribed {
                        FeatureGate.shared.applyLocalStoreKitEntitlement(
                            tier: self.localSubscriptionTier,
                            subscriptionEndAt: self.localSubscriptionEndAt
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Server subscription verification failed. AI features unlock after the server verifies your purchase."
                }
                ClientLog.debugError("[SubscriptionAPI] Backend sync failed", error)
            }
        }
    }

    private func syncBackend(
        for transaction: Transaction,
        signedTransactionInfo: String?,
        reason: String = "current_entitlements"
    ) async throws -> SubscriptionEntitlement {
        try await apiClient.verify(
            transactionId: String(transaction.id),
            originalTransactionId: String(transaction.originalID),
            productId: transaction.productID,
            signedTransactionInfo: signedTransactionInfo,
            userId: AuthViewModel.shared.currentUser?.uid,
            syncReason: reason
        )
    }

    private func tierRank(for tier: String) -> Int {
        switch tier {
        case "plus":
            return 1
        case "pro":
            return 2
        default:
            return 0
        }
    }

    private func appAccountToken() -> UUID? {
        guard let uid = AuthViewModel.shared.currentUser?.uid,
              let data = uid.data(using: .utf8) else {
            return nil
        }
        let digest = SHA256.hash(data: data)
        let bytes = Array(digest.prefix(16))
        let formatted = bytes.enumerated().map { index, byte -> String in
            let separator: String
            switch index {
            case 4, 6, 8, 10:
                separator = "-"
            default:
                separator = ""
            }
            return separator + String(format: "%02x", byte)
        }.joined()
        return UUID(uuidString: formatted)
    }

    private static func productSortRank(for productID: String) -> Int {
        switch productID {
        case "pomodoro.plus.monthly":
            return 0
        case "pomodoro.plus.yearly":
            return 1
        case "pomodoro.pro.monthly":
            return 2
        case "pomodoro.pro.yearly":
            return 3
        default:
            return Int.max
        }
    }

    private static func productLoadFailureMessage(for error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.isEmpty {
            return "Could not load subscription prices from the App Store."
        }
        return "Could not load subscription prices: \(message)"
    }

    func product(for productID: String) -> Product? {
        products.first { $0.id == productID }
    }

    var currentProductID: String? {
        guard FeatureGate.shared.tier == .plus || FeatureGate.shared.tier == .pro else {
            return nil
        }
        return lastEntitlement?.effectiveProductId ?? lastEntitlement?.productId
    }

    var currentTier: FeatureGate.Tier {
        FeatureGate.shared.tier
    }

    var isServerVerificationPending: Bool {
        guard isSubscribed else { return false }
        switch FeatureGate.shared.tier {
        case .plus, .pro, .developer:
            return false
        case .free, .beta, .expired:
            return true
        }
    }
}

typealias SubscriptionManager = SubscriptionStore
