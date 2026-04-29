import AppKit
import FirebaseAuth
import SwiftUI

enum AuthProvider: CaseIterable, Identifiable {
    case google
    case github
    case apple
    case email

    var id: Self { self }

    func title(using localizationManager: LocalizationManager) -> String {
        switch self {
        case .google:
            return localizationManager.text("auth.continue_google")
        case .github:
            return localizationManager.text("auth.continue_github")
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
    @State private var deleteConfirmationStep: DeleteAccountConfirmationStep?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localizationManager.text("settings.account.title"))
                .font(.title3.bold())

            if authViewModel.isLoggedIn {
                loggedInSection
            } else {
                LoginView()
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(12)
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

    private var loggedInSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                avatarView(url: authViewModel.user?.photoURL)
                VStack(alignment: .leading, spacing: 2) {
                    Text(authViewModel.user?.displayName ?? localizationManager.text("settings.account.signed_in"))
                        .font(.headline)
                    Text(authViewModel.currentUserEmail.isEmpty ? localizationManager.text("settings.account.no_email") : authViewModel.currentUserEmail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusChip(isLoggedIn: true)
            }

            Button(localizationManager.text("settings.account.logout")) {
                Task { @MainActor in
                    await authViewModel.signOut()
                }
            }
            .orchestranaButton(.secondary)
            .disabled(authViewModel.isAuthenticating || authViewModel.isDeletingAccount)

            Divider()
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 8) {
                Text(localizationManager.text("settings.account.delete_account_title"))
                    .font(.subheadline.weight(.semibold))
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
                .orchestranaButton(.destructive)
                .disabled(authViewModel.isAuthenticating || authViewModel.isDeletingAccount)
            }

            if let message = authViewModel.authError, !message.isEmpty {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private func statusChip(isLoggedIn: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isLoggedIn ? Color.green : Color.orange.opacity(0.65))
                .frame(width: 10, height: 10)
            Text(isLoggedIn ? localizationManager.text("settings.account.logged_in") : localizationManager.text("settings.account.optional_login"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(8)
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

            if isLoading, provider == .google || provider == .github || provider == .apple {
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
            Text(localizationManager.text("auth.email_auto_create_hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)

            TextField(localizationManager.text("auth.email.placeholder"), text: $email)
                .orchestranaTextField()
                .textContentType(.emailAddress)
                .autocorrectionDisabled()
                .disabled(authViewModel.isAuthenticating)

            SecureField(localizationManager.text("auth.password.placeholder"), text: $password)
                .orchestranaTextField()
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
                        if isAccountNotFound(error) {
                            showingCreateAccountPrompt = true
                        } else {
                            emailErrorMessage = (error as NSError).localizedDescription
                        }
                    }
                }
            }
            .orchestranaButton(.primary)
            .disabled(authViewModel.isAuthenticating || !canSubmit)

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
            .orchestranaButton(.secondary)
            .disabled(authViewModel.isAuthenticating || !canSubmit)

            HStack {
                Spacer()

                Button(localizationManager.text("auth.forgot_password")) {
                    passwordResetEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
                    passwordResetMessage = nil
                    passwordResetErrorMessage = nil
                    showingPasswordResetSheet = true
                }
                .orchestranaButton(.subtle)
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
                    .orchestranaTextField()
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
                    .orchestranaButton(.secondary)

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
                    .orchestranaButton(.primary)
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
            case .github:
                Image("GitHubLogo")
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
                .orchestranaButton(.secondary)
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
