import AppKit
import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import Foundation
import GoogleSignIn
import Security

@objc
private protocol OAuthProviderCredentialBridge {
    @objc(getCredentialWithUIDelegate:completion:)
    func getCredential(withUIDelegate uiDelegate: AnyObject?, completion: @escaping (AuthCredential?, Error?) -> Void)
}

@objc
private protocol AuthRedirectHandlingBridge {
    @objc(canHandleURL:)
    func canHandleURL(_ url: URL) -> Bool
}

@MainActor
final class AuthManager {
    static let shared = AuthManager()
    private var activeOAuthProvider: OAuthProvider?
    private var activeAppleSignInCoordinator: AppleSignInCoordinator?
    private var currentAuthorizationController: ASAuthorizationController?

    private init() {}

    func signInWithGoogle() async throws -> String {
        guard FirebaseApp.app() != nil else {
            throw AuthManagerError.firebaseNotConfigured
        }
        guard let clientID = FirebaseApp.app()?.options.clientID, !clientID.isEmpty else {
            throw AuthManagerError.missingGoogleClientID
        }
        guard let presentingWindow = presentingWindow() else {
            throw AuthManagerError.missingPresentingWindow
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        print("[Auth] Starting Google sign-in")

        do {
            let googleResult: GIDSignInResult = try await withCheckedThrowingContinuation { continuation in
                GIDSignIn.sharedInstance.signIn(withPresenting: presentingWindow) { result, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let result else {
                        continuation.resume(throwing: AuthManagerError.missingResult)
                        return
                    }
                    continuation.resume(returning: result)
                }
            }
            guard
                let idToken = googleResult.user.idToken?.tokenString,
                !idToken.isEmpty
            else {
                throw AuthManagerError.missingGoogleIDToken
            }

            let accessToken = googleResult.user.accessToken.tokenString
            guard !accessToken.isEmpty else {
                throw AuthManagerError.missingGoogleAccessToken
            }

            print("[Auth] Google token retrieval succeeded")
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
            let authResult = try await signIn(with: credential)
            print("[Auth] Google sign-in succeeded for uid: \(authResult.user.uid)")
            return authResult.user.uid
        } catch {
            log(error, prefix: "[Auth] Google sign-in failed")
            throw error
        }
    }

    func signInWithGitHub() async throws -> String {
        guard FirebaseApp.app() != nil else {
            throw AuthManagerError.firebaseNotConfigured
        }
        guard let window = presentingWindow() else {
            throw AuthManagerError.missingPresentingWindow
        }

        let provider = OAuthProvider(providerID: "github.com")
        provider.scopes = ["user:email"]
        activeOAuthProvider = provider
        activate(window: window)
        print("[Auth] Starting GitHub OAuth")
        print("[Auth] Configured provider: \(provider.providerID)")
        print("[Auth] Requested scopes: \(provider.scopes?.joined(separator: ", ") ?? "none")")
        print("[Auth] GitHub window available: \(window)")
        print("[Auth] GitHub browser handler: \(defaultBrowserDescription())")
        print("[Auth] Expected GitHub callback: \(expectedFirebaseAuthCallbackURL())")

        do {
            print("[Auth] Requesting GitHub Firebase credential")
            let credential = try await gitHubCredential(with: provider)
            print("[Auth] Firebase credential created for GitHub")
            let authResult = try await signIn(with: credential)
            let uid = authResult.user.uid
            print("[Auth] GitHub OAuth returned result")
            print("[Auth] GitHub sign-in succeeded for uid: \(uid)")
            activeOAuthProvider = nil
            return uid
        } catch {
            activeOAuthProvider = nil
            log(error, prefix: "[Auth] GitHub sign-in failed")
            throw error
        }
    }

    func signInWithGithub() async throws -> String {
        try await signInWithGitHub()
    }

    func signInWithApple() async throws -> String {
        guard FirebaseApp.app() != nil else {
            throw AuthManagerError.firebaseNotConfigured
        }
        guard let window = presentingWindow() else {
            throw AuthManagerError.missingPresentingWindow
        }

        print("[Auth] Starting Apple sign-in on main thread: true")
        print("[Auth] Apple presentation window before activation: \(window)")
        activate(window: window)

        let nonce = try randomNonceString()
        let coordinator = AppleSignInCoordinator(
            window: window,
            controllerDidChange: { [weak self] controller in
                self?.currentAuthorizationController = controller
            }
        )
        activeAppleSignInCoordinator = coordinator

        do {
            print("[Auth] Apple nonce generated")
            let authorization = try await coordinator.beginSignIn(nonce: nonce)
            defer {
                activeAppleSignInCoordinator = nil
                currentAuthorizationController = nil
            }

            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                throw AuthManagerError.missingResult
            }

            print("[Auth] Apple authorization completed")

            guard let identityTokenData = appleIDCredential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8),
                  !identityToken.isEmpty else {
                throw AuthManagerError.missingAppleIdentityToken
            }

            print("[Auth] Apple Firebase credential created")
            let credential = OAuthProvider.appleCredential(
                withIDToken: identityToken,
                rawNonce: nonce,
                fullName: appleIDCredential.fullName
            )
            let authResult = try await signIn(with: credential)
            print("[Auth] Apple sign-in succeeded for uid: \(authResult.user.uid)")
            return authResult.user.uid
        } catch {
            activeAppleSignInCoordinator = nil
            currentAuthorizationController = nil
            log(error, prefix: "[Auth] Apple sign-in failed")
            throw error
        }
    }

    func signOut() throws {
        guard FirebaseApp.app() != nil else {
            throw AuthManagerError.firebaseNotConfigured
        }

        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            print("[Auth] Signed out")
        } catch {
            log(error, prefix: "[Auth] Sign-out failed")
            throw error
        }
    }

    func currentUser() -> User? {
        Auth.auth().currentUser
    }

    func handleOpenURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }

        for url in urls {
            print("[Auth] Redirect received: \(url.absoluteString)")
            let handled = (Auth.auth() as? AuthRedirectHandlingBridge)?.canHandleURL(url) ?? false
            print("[Auth] Firebase redirect handled: \(handled)")
        }
    }

    func logAuthConfiguration() {
        let urlSchemes = bundleURLSchemes()
        let hasURLSchemes = !urlSchemes.isEmpty
        print("[Auth] Registered URL schemes: \(hasURLSchemes ? urlSchemes.joined(separator: ", ") : "none")")
        print("[Auth] Expected Firebase auth handler: \(expectedFirebaseAuthCallbackURL())")
        if !hasURLSchemes {
            print("[Auth] WARNING: No URL schemes were found in Info.plist. GitHub OAuth redirect handling will fail.")
        }
    }

    private func signIn(with credential: AuthCredential) async throws -> AuthDataResult {
        try await withCheckedThrowingContinuation { continuation in
            Auth.auth().signIn(with: credential) { result, error in
                if let error {
                    print("[Auth] Firebase sign-in error: \((error as NSError).localizedDescription)")
                    continuation.resume(throwing: error)
                    return
                }
                guard let result else {
                    continuation.resume(throwing: AuthManagerError.missingResult)
                    return
                }
                continuation.resume(returning: result)
            }
        }
    }

    private func gitHubCredential(with provider: OAuthProvider) async throws -> AuthCredential {
        guard let providerBridge = provider as? OAuthProviderCredentialBridge else {
            throw AuthManagerError.missingResult
        }

        return try await withCheckedThrowingContinuation { continuation in
            providerBridge.getCredential(withUIDelegate: nil) { credential, error in
                if let error {
                    let nsError = error as NSError
                    print("[Auth] GitHub credential error: \(nsError.localizedDescription) [\(nsError.domain):\(nsError.code)]")
                    continuation.resume(throwing: error)
                    return
                }
                guard let credential else {
                    continuation.resume(throwing: AuthManagerError.missingResult)
                    return
                }
                continuation.resume(returning: credential)
            }
        }
    }

    private func presentingWindow() -> NSWindow? {
        if let keyWindow = NSApplication.shared.keyWindow {
            return keyWindow
        }
        if let mainWindow = NSApplication.shared.mainWindow {
            return mainWindow
        }
        return NSApplication.shared.windows.first(where: { $0.canBecomeMain })
    }

    private func log(_ error: Error, prefix: String) {
        let nsError = error as NSError
        print("\(prefix): \(nsError.localizedDescription) [\(nsError.domain):\(nsError.code)]")
    }

    private func bundleURLSchemes() -> [String] {
        guard
            let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        else {
            return []
        }

        return urlTypes
            .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
            .filter { !$0.isEmpty }
    }

    private func defaultBrowserDescription() -> String {
        guard let url = URL(string: "https://github.com") else {
            return "unavailable"
        }

        if let browserURL = NSWorkspace.shared.urlForApplication(toOpen: url) {
            return browserURL.path
        }

        return "not found"
    }

    private func activate(window: NSWindow) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func expectedFirebaseAuthCallbackURL() -> String {
        if let projectID = FirebaseApp.app()?.options.projectID, !projectID.isEmpty {
            return "https://\(projectID).firebaseapp.com/__/auth/handler"
        }

        return "https://<project>.firebaseapp.com/__/auth/handler"
    }

    private func randomNonceString(length: Int = 32) throws -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let errorCode = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if errorCode != errSecSuccess {
                throw AuthManagerError.nonceGenerationFailed
            }

            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }

                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.map { String(format: "%02x", $0) }.joined()
    }

    @MainActor
    private final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        private let window: NSWindow
        private let controllerDidChange: (ASAuthorizationController?) -> Void
        private var controller: ASAuthorizationController?
        private var continuation: CheckedContinuation<ASAuthorization, Error>?

        init(window: NSWindow, controllerDidChange: @escaping (ASAuthorizationController?) -> Void) {
            self.window = window
            self.controllerDidChange = controllerDidChange
        }

        func beginSignIn(nonce: String) async throws -> ASAuthorization {
            print("[Auth] Apple beginSignIn on main thread: true")
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation

                let provider = ASAuthorizationAppleIDProvider()
                let request = provider.createRequest()
                request.requestedScopes = [.fullName, .email]
                request.nonce = AuthManager.shared.sha256(nonce)

                let controller = ASAuthorizationController(authorizationRequests: [request])
                controller.delegate = self
                controller.presentationContextProvider = self
                self.controller = controller
                controllerDidChange(controller)
                print("[Auth] Apple controller configured with delegate and presentation context provider")
                print("[Auth] Apple controller retained: \(String(describing: self.controller))")
                print("[Auth] Performing Apple authorization request")
                controller.performRequests()
            }
        }

        @MainActor
        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            print("[Auth] Apple authorization delegate success")
            self.controller = nil
            controllerDidChange(nil)
            continuation?.resume(returning: authorization)
            continuation = nil
        }

        @MainActor
        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            let nsError = error as NSError
            print("[Auth] Apple authorization delegate error: \(nsError.localizedDescription) [\(nsError.domain):\(nsError.code)]")
            print("[Auth] Apple authorization error userInfo: \(nsError.userInfo)")
            print("[Auth] Apple authorization callback on main thread: \(Thread.isMainThread)")
            self.controller = nil
            controllerDidChange(nil)
            continuation?.resume(throwing: error)
            continuation = nil
        }

        @MainActor
        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            let anchor = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? window
            print("[Auth] Apple presentation anchor: \(anchor)")
            print("[Auth] Apple presentation anchor on main thread: \(Thread.isMainThread)")
            return anchor
        }
    }
}

enum AuthManagerError: LocalizedError {
    case firebaseNotConfigured
    case missingGoogleClientID
    case missingGoogleIDToken
    case missingGoogleAccessToken
    case missingPresentingWindow
    case missingResult
    case missingAppleIdentityToken
    case nonceGenerationFailed

    var errorDescription: String? {
        switch self {
        case .firebaseNotConfigured:
            return "Firebase is not configured."
        case .missingGoogleClientID:
            return "Missing Google OAuth client ID in Firebase configuration."
        case .missingGoogleIDToken:
            return "Google Sign-In did not return an ID token."
        case .missingGoogleAccessToken:
            return "Google Sign-In did not return an access token."
        case .missingPresentingWindow:
            return "No active macOS window is available to present the login flow."
        case .missingResult:
            return "Authentication did not return a result."
        case .missingAppleIdentityToken:
            return "Sign in with Apple did not return an identity token."
        case .nonceGenerationFailed:
            return "Unable to generate a secure sign-in nonce."
        }
    }
}
