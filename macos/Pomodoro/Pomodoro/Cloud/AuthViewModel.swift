import AuthenticationServices
import Combine
import FirebaseAuth
import FirebaseCore
import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    static let shared = AuthViewModel()

    @Published private(set) var currentUser: User?
    @Published private(set) var isLoading = false
    @Published private(set) var isAuthenticating = false
    @Published private(set) var isDeletingAccount = false
    @Published private(set) var isPreparingPurchase = false
    @Published private(set) var hasValidPurchaseToken = false
    @Published var isPurchaseLoginPromptPresented = false
    @Published private(set) var authError: String?

    private var authStateListener: AuthStateDidChangeListenerHandle?
    private var auth: Auth?
    private let authManager: AuthManager
    private let accountDeletionClient: AccountDeletionAPIClient
    private var purchaseTokenWarmupTask: Task<Void, Never>?

    private init() {
        authManager = .shared
        accountDeletionClient = AccountDeletionAPIClient()
        if FirebaseApp.app() != nil {
            let auth = Auth.auth()
            self.auth = auth
            currentUser = auth.currentUser
        } else {
            currentUser = nil
        }
        hasValidPurchaseToken = false
    }

    deinit {
        purchaseTokenWarmupTask?.cancel()
        if let authStateListener, let auth {
            auth.removeStateDidChangeListener(authStateListener)
        }
    }

    var isLoggedIn: Bool {
        currentUser != nil
    }

    var isAuthenticated: Bool {
        isLoggedIn
    }

    var isSignedIn: Bool {
        isLoggedIn
    }

    var user: User? {
        currentUser
    }

    var currentUserEmail: String {
        currentUser?.email ?? ""
    }

    var canStartPurchase: Bool {
        isAuthenticated && !isAuthenticating && !isPreparingPurchase && hasValidPurchaseToken
    }

    var errorMessage: String? {
        authError
    }

    func startListeningIfNeeded() {
        guard authStateListener == nil else { return }
        guard FirebaseApp.app() != nil else { return }
        guard let auth = try? currentAuth() else { return }
        currentUser = auth.currentUser
        listen(using: auth)
    }

    func signInWithGoogle() async throws {
        try await performAuthenticationFlow {
            _ = try await authManager.signInWithGoogle()
        }
    }

    func signInWithGitHub() async throws {
        try await performAuthenticationFlow {
            _ = try await authManager.signInWithGitHub()
        }
    }

    func signInWithApple() async throws {
        try await performAuthenticationFlow {
            _ = try await authManager.signInWithApple()
        }
    }

    func recordAuthenticationError(_ error: Error) {
        let mappedError = mapAuthError(error)
        authError = (mappedError as NSError).localizedDescription
    }

    func signUpWithEmail(email: String, password: String) async throws {
        let credentials = try sanitizeEmailCredentials(email: email, password: password)
        try await performAuthenticationFlow {
            _ = try await createUser(email: credentials.email, password: credentials.password)
        }
    }

    func signInWithEmail(email: String, password: String) async throws {
        let credentials = try sanitizeEmailCredentials(email: email, password: password)
        try await performAuthenticationFlow {
            do {
                _ = try await signIn(email: credentials.email, password: credentials.password)
            } catch {
                throw mapEmailSignInError(error)
            }
        }
    }

    func sendPasswordReset(email: String) async throws {
        startListeningIfNeeded()
        let auth = try currentAuth()
        let sanitizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedEmail.isEmpty else {
            throw AuthViewModelError.invalidEmail
        }

        let _: Void = try await performExclusiveAuthOperation {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                auth.sendPasswordReset(withEmail: sanitizedEmail) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
        }
    }

    func getValidIDToken() async throws -> String {
        startListeningIfNeeded()
        let auth = try currentAuth()
        guard let user = auth.currentUser else {
            throw AuthViewModelError.notAuthenticated
        }

        do {
            let tokenResult = try await getIDTokenResult(for: user, forceRefresh: false)
            let expirationDate = tokenResult.expirationDate
            if expirationDate.timeIntervalSinceNow > 60 {
                return tokenResult.token
            }

            return try await getIDToken(for: user, forceRefresh: true)
        } catch {
            let nsError = error as NSError
            if nsError.domain == AuthErrorDomain,
               nsError.code == AuthErrorCode.userTokenExpired.rawValue {
                return try await getIDToken(for: user, forceRefresh: true)
            }
            throw mapAuthError(error)
        }
    }

    func signOut() async {
        startListeningIfNeeded()

        do {
            let _: Void = try await performExclusiveAuthOperation {
                try authManager.signOut()
            }
            handleAuthStateChange(authManager.currentUser())
        } catch {
            // performExclusiveAuthOperation already updates authError.
        }
    }

    func deleteAccount() async {
        startListeningIfNeeded()
        guard currentUser != nil else {
            authError = AuthViewModelError.notAuthenticated.localizedDescription
            return
        }
        guard !isAuthenticating, !isDeletingAccount else {
            authError = AuthViewModelError.authenticationInProgress.localizedDescription
            return
        }

        isDeletingAccount = true
        isLoading = true
        authError = nil
        defer {
            isDeletingAccount = false
            isLoading = false
        }

        do {
            try await accountDeletionClient.deleteAccount()
            try? authManager.signOut()
            handleAuthStateChange(nil)
        } catch {
            let mappedError = mapAuthError(error)
            authError = (mappedError as NSError).localizedDescription
        }
    }

    func clearError() {
        authError = nil
    }

    func preparePurchaseReadiness() async {
        startListeningIfNeeded()
        purchaseTokenWarmupTask?.cancel()

        guard currentUser != nil else {
            hasValidPurchaseToken = false
            isPreparingPurchase = false
            return
        }

        purchaseTokenWarmupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            _ = try? await self.refreshPurchaseToken(forceRefresh: false)
        }
    }

    func prepareForPurchase() async throws -> String {
        startListeningIfNeeded()

        guard isAuthenticated else {
            isPurchaseLoginPromptPresented = true
            throw AuthViewModelError.purchaseAuthenticationRequired
        }

        guard !isAuthenticating else {
            throw AuthViewModelError.authenticationInProgress
        }

        return try await refreshPurchaseToken(forceRefresh: true)
    }

    func dismissPurchaseLoginPrompt() {
        isPurchaseLoginPromptPresented = false
    }

    private func listen(using auth: Auth) {
        authStateListener = auth.addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor [weak self] in
                self?.handleAuthStateChange(user)
            }
        }
    }

    private func performAuthenticationFlow(_ operation: () async throws -> Void) async throws {
        startListeningIfNeeded()
        let auth = try currentAuth()

        do {
            let _: Void = try await performExclusiveAuthOperation {
                try await operation()
            }
            handleAuthStateChange(auth.currentUser)
        } catch {
            throw error
        }
    }

    private func performExclusiveAuthOperation<T>(_ operation: () async throws -> T) async throws -> T {
        guard !isAuthenticating else {
            throw AuthViewModelError.authenticationInProgress
        }

        isAuthenticating = true
        isLoading = true
        authError = nil
        defer {
            isAuthenticating = false
            isLoading = false
        }

        do {
            let result = try await operation()
            authError = nil
            return result
        } catch {
            let mappedError = mapAuthError(error)
            authError = (mappedError as NSError).localizedDescription
            throw mappedError
        }
    }

    private func handleAuthStateChange(_ user: User?) {
        currentUser = user
        isPurchaseLoginPromptPresented = false
        purchaseTokenWarmupTask?.cancel()

        if user == nil {
            hasValidPurchaseToken = false
            isPreparingPurchase = false
            return
        }

        authError = nil
        hasValidPurchaseToken = false
        purchaseTokenWarmupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            _ = try? await self.refreshPurchaseToken(forceRefresh: false)
        }
    }

    private func refreshPurchaseToken(forceRefresh: Bool) async throws -> String {
        isPreparingPurchase = true
        defer { isPreparingPurchase = false }

        do {
            let token: String
            if forceRefresh {
                guard let user = currentUser else {
                    throw AuthViewModelError.purchaseAuthenticationRequired
                }
                token = try await getIDToken(for: user, forceRefresh: true)
            } else {
                token = try await getValidIDToken()
            }
            hasValidPurchaseToken = !token.isEmpty
            return token
        } catch {
            hasValidPurchaseToken = false
            throw mapAuthError(error)
        }
    }

    private func sanitizeEmailCredentials(email: String, password: String) throws -> (email: String, password: String) {
        let sanitizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedEmail.isEmpty else {
            throw AuthViewModelError.invalidEmail
        }
        guard !password.isEmpty else {
            throw AuthViewModelError.invalidPassword
        }
        return (sanitizedEmail, password)
    }

    private func createUser(email: String, password: String) async throws -> AuthDataResult {
        let auth = try currentAuth()
        return try await withCheckedThrowingContinuation { continuation in
            auth.createUser(withEmail: email, password: password) { result, error in
                if let error {
                    ClientLog.debugError("[Auth] Email registration error", error)
                    continuation.resume(throwing: error)
                    return
                }
                guard let result else {
                    continuation.resume(throwing: AuthViewModelError.missingResult)
                    return
                }
                continuation.resume(returning: result)
            }
        }
    }

    private func signIn(email: String, password: String) async throws -> AuthDataResult {
        let auth = try currentAuth()
        return try await withCheckedThrowingContinuation { continuation in
            auth.signIn(withEmail: email, password: password) { result, error in
                if let error {
                    ClientLog.debugError("[Auth] Email sign-in error", error)
                    continuation.resume(throwing: error)
                    return
                }
                guard let result else {
                    continuation.resume(throwing: AuthViewModelError.missingResult)
                    return
                }
                continuation.resume(returning: result)
            }
        }
    }

    private func currentAuth() throws -> Auth {
        guard FirebaseApp.app() != nil else {
            throw AuthViewModelError.firebaseNotConfigured
        }
        if let auth {
            return auth
        }
        let initializedAuth = Auth.auth()
        auth = initializedAuth
        return initializedAuth
    }

    private func getIDToken(for user: User, forceRefresh: Bool) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            user.getIDTokenForcingRefresh(forceRefresh) { token, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let token, !token.isEmpty else {
                    continuation.resume(throwing: AuthViewModelError.missingToken)
                    return
                }
                continuation.resume(returning: token)
            }
        }
    }

    private func getIDTokenResult(for user: User, forceRefresh: Bool) async throws -> AuthTokenResult {
        try await withCheckedThrowingContinuation { continuation in
            user.getIDTokenResult(forcingRefresh: forceRefresh) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let result else {
                    continuation.resume(throwing: AuthViewModelError.missingToken)
                    return
                }
                continuation.resume(returning: result)
            }
        }
    }

    private func mapEmailSignInError(_ error: Error) -> Error {
        let nsError = error as NSError
        guard nsError.domain == AuthErrorDomain,
              let code = AuthErrorCode(rawValue: nsError.code) else {
            return mapAuthError(error)
        }

        switch code {
        case .userNotFound:
            return AuthViewModelError.accountNotFound
        case .invalidCredential:
            return AuthViewModelError.invalidEmailOrPassword
        default:
            return mapAuthError(error)
        }
    }

    private func mapAuthError(_ error: Error) -> Error {
        if let authError = error as? AuthViewModelError {
            return authError
        }

        if let authManagerError = error as? AuthManagerError {
            return authManagerError
        }

        let nsError = error as NSError
        if nsError.domain == ASAuthorizationError.errorDomain,
           nsError.code == ASAuthorizationError.canceled.rawValue {
            return AuthViewModelError.signInCancelled
        }

        guard nsError.domain == AuthErrorDomain,
              let code = AuthErrorCode(rawValue: nsError.code) else {
            return error
        }

        switch code {
        case .wrongPassword:
            return AuthViewModelError.incorrectPassword
        case .invalidCredential:
            return AuthViewModelError.invalidEmailOrPassword
        case .weakPassword:
            return AuthViewModelError.weakPassword
        case .invalidEmail:
            return AuthViewModelError.invalidEmailAddress
        case .userNotFound:
            return AuthViewModelError.accountNotFound
        case .networkError, .webNetworkRequestFailed:
            return AuthViewModelError.networkError
        case .tooManyRequests:
            return AuthViewModelError.tooManyRequests
        case .webContextCancelled:
            return AuthViewModelError.signInCancelled
        case .userDisabled:
            return AuthViewModelError.accountDisabled
        case .accountExistsWithDifferentCredential:
            return AuthViewModelError.accountExistsWithDifferentCredential
        default:
            return error
        }
    }

    enum AuthViewModelError: @preconcurrency LocalizedError, Equatable {
        case firebaseNotConfigured
        case missingResult
        case invalidEmail
        case invalidPassword
        case incorrectPassword
        case invalidEmailOrPassword
        case weakPassword
        case invalidEmailAddress
        case notAuthenticated
        case missingToken
        case purchaseAuthenticationRequired
        case authenticationInProgress
        case accountNotFound
        case networkError
        case tooManyRequests
        case signInCancelled
        case accountDisabled
        case accountExistsWithDifferentCredential

        @MainActor
        var errorDescription: String? {
            switch self {
            case .firebaseNotConfigured:
                return LocalizationManager.shared.text("auth.error.firebase_not_configured")
            case .missingResult:
                return LocalizationManager.shared.text("auth.error.sign_in_failed")
            case .invalidEmail:
                return LocalizationManager.shared.text("auth.error.invalid_email")
            case .invalidPassword:
                return LocalizationManager.shared.text("auth.error.invalid_password")
            case .incorrectPassword:
                return LocalizationManager.shared.text("auth.error.incorrect_password")
            case .invalidEmailOrPassword:
                return LocalizationManager.shared.text("auth.error.invalid_email_or_password")
            case .weakPassword:
                return LocalizationManager.shared.text("auth.error.weak_password")
            case .invalidEmailAddress:
                return LocalizationManager.shared.text("auth.error.invalid_email_address")
            case .notAuthenticated:
                return LocalizationManager.shared.text("auth.error.authentication_required")
            case .missingToken:
                return LocalizationManager.shared.text("auth.error.missing_firebase_id_token")
            case .purchaseAuthenticationRequired:
                return LocalizationManager.shared.text("auth.error.purchase_sign_in_required")
            case .authenticationInProgress:
                return LocalizationManager.shared.text("auth.error.authentication_in_progress")
            case .accountNotFound:
                return LocalizationManager.shared.text("auth.error.account_not_found")
            case .networkError:
                return LocalizationManager.shared.text("auth.error.network")
            case .tooManyRequests:
                return LocalizationManager.shared.text("auth.error.too_many_requests")
            case .signInCancelled:
                return LocalizationManager.shared.text("auth.error.cancelled")
            case .accountDisabled:
                return LocalizationManager.shared.text("auth.error.account_disabled")
            case .accountExistsWithDifferentCredential:
                return LocalizationManager.shared.text("auth.error.account_exists_different_provider")
            }
        }
    }
}
