//
//  AuthScreen.swift
//  Struc
//

import SwiftUI

struct AuthScreen: View {
    @EnvironmentObject private var authManager: AuthManager

    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false

    var body: some View {
        ZStack {
            DS.screenBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: DS.Spacing.largeSection) {

                    // MARK: Header
                    VStack(spacing: DS.Spacing.micro) {
                        Image(systemName: "graduationcap.fill")
                            .font(.system(size: 60, weight: .light))
                            .foregroundStyle(DS.Colors.accent)
                            .padding(.top, 48)

                        Text("Struc")
                            .font(.largeTitle.weight(.bold))

                        Text(isSignUp ? "Create your account" : "Welcome back")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, DS.Spacing.xs)

                    // MARK: Social sign-in
                    VStack(spacing: DS.Spacing.micro) {
                        Button {
                            Task {
                                isLoading = true
                                let result = await authManager.signInWithApple()
                                if case .failure = result { isLoading = false }
                            }
                        } label: {
                            HStack(spacing: DS.Spacing.micro) {
                                Image(systemName: "apple.logo")
                                    .font(.body.weight(.semibold))
                                Text("Continue with Apple")
                                    .font(.body.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(DS.Colors.primaryButtonFg)
                            .background(
                                DS.Colors.primaryButtonBg,
                                in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                            )
                        }
                        .buttonStyle(PressScaleButtonStyle())
                        .disabled(isLoading)

                        Button {
                            Task {
                                isLoading = true
                                let result = await authManager.signInWithGoogle()
                                if case .failure = result { isLoading = false }
                            }
                        } label: {
                            HStack(spacing: DS.Spacing.micro) {
                                Image(systemName: "g.circle.fill")
                                    .font(.body.weight(.semibold))
                                Text("Continue with Google")
                                    .font(.body.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(.primary)
                            .background(
                                DS.Colors.secondaryButtonBg,
                                in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                            )
                        }
                        .buttonStyle(PressScaleButtonStyle())
                        .disabled(isLoading)
                    }

                    // MARK: Divider
                    HStack(spacing: DS.Spacing.xs) {
                        Rectangle()
                            .fill(DS.Border.color)
                            .frame(height: 1)
                        Text("or")
                            .font(.caption)
                            .foregroundStyle(DS.Colors.secondaryText)
                        Rectangle()
                            .fill(DS.Border.color)
                            .frame(height: 1)
                    }

                    // MARK: Email / password
                    VStack(spacing: DS.Spacing.micro) {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                DS.cardBackground,
                                in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                                    .stroke(DS.Border.color, lineWidth: DS.Border.width)
                            )

                        SecureField("Password", text: $password)
                            .textContentType(isSignUp ? .newPassword : .password)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                DS.cardBackground,
                                in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                                    .stroke(DS.Border.color, lineWidth: DS.Border.width)
                            )

                        Button {
                            Task { await submitEmail() }
                        } label: {
                            Group {
                                if isLoading {
                                    ProgressView()
                                        .tint(DS.Colors.primaryButtonFg)
                                } else {
                                    Text(isSignUp ? "Create Account" : "Sign In")
                                        .font(.body.weight(.semibold))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(DS.Colors.primaryButtonFg)
                            .background(
                                (email.isEmpty || password.isEmpty)
                                    ? DS.Colors.primaryButtonBg.opacity(0.4)
                                    : DS.Colors.primaryButtonBg,
                                in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                            )
                        }
                        .buttonStyle(PressScaleButtonStyle())
                        .disabled(email.isEmpty || password.isEmpty || isLoading)
                    }
                    .padding(DS.Spacing.standard)
                    .elevatedCard()

                    // MARK: Error
                    if let errorMessage = authManager.lastAuthErrorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(DS.Colors.destructive)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, DS.Spacing.standard)
                    }

                    // MARK: Toggle sign-in / sign-up
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSignUp.toggle()
                        }
                    } label: {
                        Text(isSignUp ? "Already have an account? Sign In" : "No account yet? Create one")
                            .font(.subheadline)
                            .foregroundStyle(DS.Colors.accent)
                    }

                    // MARK: Skip
                    Button {
                        UserDefaults.standard.set(true, forKey: "studyos.auth.skipped")
                    } label: {
                        Text("Continue without an account")
                            .font(.footnote)
                            .foregroundStyle(DS.Colors.secondaryText)
                    }
                    .padding(.bottom, DS.Spacing.largeSection)
                }
                .padding(.horizontal, DS.Spacing.standard)
            }
        }
    }

    private func submitEmail() async {
        isLoading = true
        let result: Result<Void, AuthManager.AuthError>
        if isSignUp {
            result = await authManager.signUpWithEmail(email: email, password: password)
        } else {
            result = await authManager.signInWithEmail(email: email, password: password)
        }
        if case .failure = result { isLoading = false }
    }
}
