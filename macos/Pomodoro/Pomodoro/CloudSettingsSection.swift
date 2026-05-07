import AppKit
import FirebaseAuth
import SwiftUI

enum AuthProvider: CaseIterable, Identifiable {
    case google
    case apple
    case email

    var id: Self { self }

    func title(using localizationManager: LocalizationManager) -> String {
        switch self {
        case .google:
            return localizationManager.text("auth.continue_google")
        case .apple:
            return localizationManager.text("auth.continue_apple")
        case .email:
            return localizationManager.text("auth.continue_email")
        }
    }
}

struct CloudSettingsSection: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var localizationManager: LocalizationManager
    @State private var supportId: String?
    @State private var supportIdErrorMessage: String?
    @State private var isLoadingSupportId = false
    @State private var supportIdLoadFailed = false

    private let userProfileClient = UserProfileAPIClient()
    private let supportIdRetryDelayNanoseconds: UInt64 = 750_000_000

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if authViewModel.isLoggedIn {
                loggedInSection
            } else {
                accountOverviewPanel {
                    LoginView()
                }
            }
        }
        .task(id: authViewModel.currentUser?.uid) {
            await loadSupportId()
        }
    }

    private var loggedInSection: some View {
        accountOverviewPanel {
            HStack(spacing: 12) {
                avatarView(url: authViewModel.user?.photoURL)
                VStack(alignment: .leading, spacing: 2) {
                    Text(accountDisplayName)
                        .font(.headline)
                    Text(accountSubtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusChip(isLoggedIn: true, isAnonymous: authViewModel.isAnonymousUser)
            }

            supportIdRow

            if authViewModel.isAnonymousUser {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sign in or create an account to make account recovery easier for support.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    LoginView()
                }
            }

            if !authViewModel.isAnonymousUser {
                Button(localizationManager.text("settings.account.logout")) {
                    Task { @MainActor in
                        await authViewModel.signOut()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(authViewModel.isAuthenticating || authViewModel.isDeletingAccount)
            }
        }
    }

    private func accountOverviewPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localizationManager.text("settings.account.title"))
                .font(.title3.bold())

            content()
        }
        .padding(16)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(12)
    }

    private var accountDisplayName: String {
        if authViewModel.isAnonymousUser {
            return "Continue without account"
        }
        return authViewModel.user?.displayName ?? localizationManager.text("settings.account.signed_in")
    }

    private var accountSubtitle: String {
        if authViewModel.isAnonymousUser {
            return "Subscription and quota are tied to this private purchase session."
        }
        return authViewModel.currentUserEmail.isEmpty ? localizationManager.text("settings.account.no_email") : authViewModel.currentUserEmail
    }

    private var supportIdRow: some View {
        HStack(spacing: 10) {
            Text(localizationManager.text("settings.account.support_id"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            if isLoadingSupportId {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text(supportIdDisplayValue)
                    .font(supportId == nil ? .footnote : .system(.footnote, design: .monospaced))
                    .foregroundStyle(supportId == nil ? .secondary : .primary)
                    .textSelection(.enabled)
            }

            Spacer()

            Button(localizationManager.text("settings.account.copy_support_id")) {
                copySupportId()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(supportId == nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.035))
        .cornerRadius(8)
        .accessibilityIdentifier("settings.account.support_id")
    }

    private var supportIdDisplayValue: String {
        if let supportId, !supportId.isEmpty {
            return supportId
        }
        if let supportIdErrorMessage, supportIdLoadFailed {
            return supportIdErrorMessage
        }
        if supportIdLoadFailed {
            return localizationManager.text("settings.account.support_id_unavailable")
        }
        return localizationManager.text("settings.account.support_id_loading")
    }

    private func statusChip(isLoggedIn: Bool, isAnonymous: Bool = false) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isLoggedIn ? Color.green : Color.orange.opacity(0.65))
                .frame(width: 10, height: 10)
            Text(statusChipTitle(isLoggedIn: isLoggedIn, isAnonymous: isAnonymous))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(8)
    }

    private func statusChipTitle(isLoggedIn: Bool, isAnonymous: Bool) -> String {
        if isAnonymous {
            return "No account"
        }
        return isLoggedIn ? localizationManager.text("settings.account.logged_in") : localizationManager.text("settings.account.optional_login")
    }

    @ViewBuilder
    private func avatarView(url: URL?) -> some View {
        let fallback = Circle()
            .fill(Color.primary.opacity(0.1))
            .overlay {
                if let initial = userInitial {
                    Text(initial)
                        .font(.headline.weight(.semibold))
                } else {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                }
            }

        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    fallback
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .clipShape(Circle())
                case .failure:
                    fallback
                @unknown default:
                    fallback
                }
            }
            .frame(width: 40, height: 40)
        } else {
            fallback
                .frame(width: 40, height: 40)
        }
    }

    private var userInitial: String? {
        if let name = authViewModel.user?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           let first = name.first {
            return String(first).uppercased()
        }
        if let first = authViewModel.currentUserEmail.first {
            return String(first).uppercased()
        }
        return nil
    }

    @MainActor
    private func loadSupportId() async {
        authViewModel.startListeningIfNeeded()
        guard authViewModel.isLoggedIn else {
            supportId = nil
            supportIdErrorMessage = nil
            supportIdLoadFailed = false
            isLoadingSupportId = false
            return
        }

        isLoadingSupportId = true
        supportIdLoadFailed = false
        supportIdErrorMessage = nil
        defer { isLoadingSupportId = false }

        for attempt in 1...2 {
            do {
                let profile = try await userProfileClient.fetchCurrentUserProfile()
                let normalizedSupportId = profile.supportId?.trimmingCharacters(in: .whitespacesAndNewlines)
                supportId = normalizedSupportId?.isEmpty == false ? normalizedSupportId : nil
                supportIdErrorMessage = nil
                supportIdLoadFailed = supportId == nil
                if supportId != nil {
                    return
                }
            } catch {
                supportId = nil
                supportIdErrorMessage = error.localizedDescription
                supportIdLoadFailed = attempt == 2
            }

            if attempt == 1 {
                try? await Task.sleep(nanoseconds: supportIdRetryDelayNanoseconds)
            }
        }
    }

    private func copySupportId() {
        guard let supportId, !supportId.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(supportId, forType: .string)
    }
}

struct AccountSecuritySettingsSection: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var localizationManager: LocalizationManager
    @State private var deleteConfirmationStep: DeleteAccountConfirmationStep?
    @State private var emailChangeAddress = ""
    @State private var emailChangeMessage: String?
    @State private var emailChangeErrorMessage: String?
    @State private var isSendingEmailChangeVerification = false
    @State private var passwordResetMessage: String?
    @State private var passwordResetErrorMessage: String?
    @State private var isSendingPasswordReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if authViewModel.isAnonymousUser {
                Text("You can purchase and restore subscriptions without creating an account. Use any sign-in method from the account panel only if you want an easier account-recovery path for support.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if authViewModel.isLoggedIn {
                passwordResetRow

                Divider()

                emailChangeRow

                Divider()

                deleteAccountRow

                if let message = authViewModel.authError, !message.isEmpty {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } else {
                Text(localizationManager.text("auth.error.authentication_required"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .alert(item: $deleteConfirmationStep) { step in
            switch step {
            case .deletePurchases:
                return Alert(
                    title: Text(localizationManager.text("settings.account.delete_purchases_title")),
                    message: Text(localizationManager.text("settings.account.delete_purchases_message")),
                    primaryButton: .destructive(Text(localizationManager.text("settings.account.delete_purchases_continue"))) {
                        deleteConfirmationStep = .areYouSure
                    },
                    secondaryButton: .cancel(Text(localizationManager.text("common.cancel")))
                )
            case .areYouSure:
                return Alert(
                    title: Text(localizationManager.text("settings.account.delete_confirm_title")),
                    message: Text(localizationManager.text("settings.account.delete_confirm_message")),
                    primaryButton: .destructive(Text(localizationManager.text("settings.account.delete_confirm_button"))) {
                        Task { @MainActor in
                            await authViewModel.deleteAccount()
                        }
                    },
                    secondaryButton: .cancel(Text(localizationManager.text("common.cancel")))
                )
            }
        }
    }

    private var passwordResetRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localizationManager.text("settings.account.password_reset_title"))
                .font(.footnote.weight(.semibold))
            Text(
                localizationManager.format(
                    "settings.account.password_reset_body",
                    authViewModel.currentUserEmail.isEmpty ? localizationManager.text("settings.account.no_email") : authViewModel.currentUserEmail
                )
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    Task { @MainActor in
                        await sendPasswordResetForCurrentUser()
                    }
                } label: {
                    if isSendingPasswordReset {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(localizationManager.text("settings.account.password_reset_button"))
                    }
                }
                .buttonStyle(.bordered)
                .disabled(authViewModel.isAuthenticating || isSendingPasswordReset || authViewModel.currentUserEmail.isEmpty)

                statusText(message: passwordResetMessage, errorMessage: passwordResetErrorMessage)
            }
        }
    }

    private var emailChangeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localizationManager.text("settings.account.email_change_title"))
                .font(.footnote.weight(.semibold))
            Text(localizationManager.text("settings.account.email_change_body"))
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                TextField(localizationManager.text("settings.account.email_change_placeholder"), text: $emailChangeAddress)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                    .disabled(authViewModel.isAuthenticating || isSendingEmailChangeVerification)

                Button {
                    Task { @MainActor in
                        await sendEmailChangeVerification()
                    }
                } label: {
                    if isSendingEmailChangeVerification {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(localizationManager.text("settings.account.email_change_button"))
                    }
                }
                .buttonStyle(.bordered)
                .disabled(
                    authViewModel.isAuthenticating
                    || isSendingEmailChangeVerification
                    || emailChangeAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }

            statusText(message: emailChangeMessage, errorMessage: emailChangeErrorMessage)
        }
    }

    private var deleteAccountRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localizationManager.text("settings.account.delete_account_title"))
                .font(.footnote.weight(.semibold))
            Text(localizationManager.text("settings.account.delete_account_body"))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button(role: .destructive) {
                deleteConfirmationStep = .deletePurchases
            } label: {
                if authViewModel.isDeletingAccount {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(localizationManager.text("settings.account.delete_account_button"))
                }
            }
            .buttonStyle(.bordered)
            .disabled(authViewModel.isAuthenticating || authViewModel.isDeletingAccount)
        }
    }

    @ViewBuilder
    private func statusText(message: String?, errorMessage: String?) -> some View {
        if let message, !message.isEmpty {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.green)
        }
        if let errorMessage, !errorMessage.isEmpty {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    @MainActor
    private func sendPasswordResetForCurrentUser() async {
        let email = authViewModel.currentUserEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else { return }

        isSendingPasswordReset = true
        passwordResetMessage = nil
        passwordResetErrorMessage = nil
        authViewModel.clearError()
        defer { isSendingPasswordReset = false }

        do {
            try await authViewModel.sendPasswordReset(email: email)
            passwordResetMessage = localizationManager.text("settings.account.password_reset_success")
        } catch {
            passwordResetErrorMessage = (error as NSError).localizedDescription
        }
    }

    @MainActor
    private func sendEmailChangeVerification() async {
        let newEmail = emailChangeAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newEmail.isEmpty else { return }

        isSendingEmailChangeVerification = true
        emailChangeMessage = nil
        emailChangeErrorMessage = nil
        authViewModel.clearError()
        defer { isSendingEmailChangeVerification = false }

        do {
            try await authViewModel.sendEmailChangeVerification(newEmail: newEmail)
            emailChangeMessage = localizationManager.text("settings.account.email_change_success")
        } catch {
            emailChangeErrorMessage = (error as NSError).localizedDescription
        }
    }
}

private enum DeleteAccountConfirmationStep: Identifiable {
    case deletePurchases
    case areYouSure

    var id: String {
        switch self {
        case .deletePurchases:
            return "deletePurchases"
        case .areYouSure:
            return "areYouSure"
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var localizationManager: LocalizationManager
    @State private var showEmailLogin = false
    @State private var activeProvider: AuthProvider?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AuthProviderButton(
                provider: .apple,
                title: AuthProvider.apple.title(using: localizationManager),
                isLoading: activeProvider == .apple && authViewModel.isAuthenticating,
                isDisabled: authViewModel.isAuthenticating
            ) {
                Task { @MainActor in
                    authViewModel.clearError()
                    await performProviderSignIn(provider: .apple) {
                        try await authViewModel.signInWithApple()
                    }
                }
            }

            AuthProviderButton(
                provider: .google,
                title: AuthProvider.google.title(using: localizationManager),
                isLoading: activeProvider == .google && authViewModel.isAuthenticating,
                isDisabled: authViewModel.isAuthenticating
            ) {
                Task { @MainActor in
                    authViewModel.clearError()
                    await performProviderSignIn(provider: .google) {
                        try await authViewModel.signInWithGoogle()
                    }
                }
            }

            AuthProviderButton(
                provider: .email,
                title: AuthProvider.email.title(using: localizationManager),
                isLoading: false,
                isDisabled: authViewModel.isAuthenticating
            ) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    authViewModel.clearError()
                    showEmailLogin.toggle()
                }
            }

            if showEmailLogin {
                EmailLoginView()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if !showEmailLogin, let message = authViewModel.authError, !message.isEmpty {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    @MainActor
    private func performProviderSignIn(
        provider: AuthProvider,
        _ operation: @escaping @MainActor () async throws -> Void
    ) async {
        activeProvider = provider
        defer { activeProvider = nil }
        do {
            try await operation()
        } catch {}
    }
}

struct AuthProviderButton: View {
    let provider: AuthProvider
    let title: String
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AuthProviderButtonChrome(
                provider: provider,
                title: title,
                isLoading: isLoading
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

private struct AuthProviderButtonChrome: View {
    let provider: AuthProvider
    let title: String
    var isLoading: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            AuthProviderIcon(provider: provider)

            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)

            Spacer()

            if isLoading, provider == .google || provider == .apple {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }
}

struct EmailLoginView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var localizationManager: LocalizationManager
    @State private var email = ""
    @State private var password = ""
    @State private var emailErrorMessage: String?
    @State private var showingCreateAccountPrompt = false
    @State private var showingPasswordResetSheet = false
    @State private var passwordResetEmail = ""
    @State private var passwordResetMessage: String?
    @State private var passwordResetErrorMessage: String?
    @State private var isSendingPasswordReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(emailHintText)
                .font(.footnote)
                .foregroundStyle(.secondary)

            TextField(localizationManager.text("auth.email.placeholder"), text: $email)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                .autocorrectionDisabled()
                .disabled(authViewModel.isAuthenticating)

            SecureField(localizationManager.text("auth.password.placeholder"), text: $password)
                .textFieldStyle(.roundedBorder)
                .textContentType(.password)
                .disabled(authViewModel.isAuthenticating)

            if let emailErrorMessage, !emailErrorMessage.isEmpty {
                Text(emailErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button(localizationManager.text("auth.signin_email")) {
                Task { @MainActor in
                    emailErrorMessage = nil
                    authViewModel.clearError()
                    do {
                        try await authViewModel.signInWithEmail(
                            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                            password: password
                        )
                        password = ""
                    } catch {
                        if !authViewModel.isAnonymousUser, isAccountNotFound(error) {
                            showingCreateAccountPrompt = true
                        } else {
                            emailErrorMessage = (error as NSError).localizedDescription
                        }
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(authViewModel.isAuthenticating || !canSubmit)

            if !authViewModel.isAnonymousUser {
                Button(localizationManager.text("auth.create_account")) {
                    Task { @MainActor in
                        emailErrorMessage = nil
                        authViewModel.clearError()
                        do {
                            try await authViewModel.signUpWithEmail(
                                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                                password: password
                            )
                            password = ""
                        } catch {
                            emailErrorMessage = (error as NSError).localizedDescription
                        }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(authViewModel.isAuthenticating || !canSubmit)
            }

            HStack {
                Spacer()

                Button(localizationManager.text("auth.forgot_password")) {
                    passwordResetEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
                    passwordResetMessage = nil
                    passwordResetErrorMessage = nil
                    showingPasswordResetSheet = true
                }
                .buttonStyle(.link)
                .disabled(authViewModel.isAuthenticating)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onAppear {
            emailErrorMessage = nil
            authViewModel.clearError()
        }
        .alert(localizationManager.text("auth.create_account_prompt.title"), isPresented: $showingCreateAccountPrompt) {
            Button(localizationManager.text("common.cancel"), role: .cancel) {}
            Button(localizationManager.text("auth.create_account")) {
                Task { @MainActor in
                    emailErrorMessage = nil
                    authViewModel.clearError()
                    do {
                        try await authViewModel.signUpWithEmail(
                            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                            password: password
                        )
                        password = ""
                    } catch {
                        emailErrorMessage = (error as NSError).localizedDescription
                    }
                }
            }
        } message: {
            Text(
                localizationManager.format(
                    "auth.create_account_prompt.message",
                    email.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
        }
        .sheet(isPresented: $showingPasswordResetSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text(localizationManager.text("auth.password_reset.title"))
                    .font(.title3.weight(.semibold))

                Text(localizationManager.text("auth.password_reset.subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField(localizationManager.text("auth.email.placeholder"), text: $passwordResetEmail)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                    .disabled(isSendingPasswordReset)

                if let passwordResetMessage, !passwordResetMessage.isEmpty {
                    Text(passwordResetMessage)
                        .font(.footnote)
                        .foregroundStyle(.green)
                }

                if let passwordResetErrorMessage, !passwordResetErrorMessage.isEmpty {
                    Text(passwordResetErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                HStack {
                    Spacer()

                    Button(localizationManager.text("common.cancel")) {
                        showingPasswordResetSheet = false
                    }
                    .buttonStyle(.bordered)

                    Button(localizationManager.text("auth.password_reset.send")) {
                        Task { @MainActor in
                            isSendingPasswordReset = true
                            passwordResetMessage = nil
                            passwordResetErrorMessage = nil
                            authViewModel.clearError()
                            do {
                                try await authViewModel.sendPasswordReset(email: passwordResetEmail)
                                passwordResetMessage = localizationManager.text("auth.password_reset.success")
                            } catch {
                                passwordResetErrorMessage = (error as NSError).localizedDescription
                            }
                            isSendingPasswordReset = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                        .disabled(isSendingPasswordReset || passwordResetEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(24)
            .frame(minWidth: 420)
        }
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    private var emailHintText: String {
        if authViewModel.isAnonymousUser {
            return "Add an email and password to transfer this temporary account into a regular account."
        }
        return localizationManager.text("auth.email_auto_create_hint")
    }

    private func isAccountNotFound(_ error: Error) -> Bool {
        guard let authError = error as? AuthViewModel.AuthViewModelError else {
            return false
        }
        return authError == .accountNotFound
    }
}

private struct AuthProviderIcon: View {
    let provider: AuthProvider

    var body: some View {
        Group {
            switch provider {
            case .google:
                Image("GoogleLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            case .apple:
                Image(systemName: "applelogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.primary)
            case .email:
                Image(systemName: "envelope")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: 18, height: 18)
    }
}

struct LoginSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localizationManager: LocalizationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CloudSettingsSection()
            HStack {
                Spacer()
                Button(localizationManager.text("common.close")) {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(minWidth: 460, idealWidth: 520)
    }
}

#Preview {
    CloudSettingsSection()
        .frame(width: 520)
        .environmentObject(AuthViewModel.shared)
        .environmentObject(LocalizationManager.shared)
}
