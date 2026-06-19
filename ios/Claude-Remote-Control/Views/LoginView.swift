import SwiftUI

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @AppStorage("auth_token") private var token = ""
    @State private var isRegistering = false
    @State private var registered = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "desktopcomputer.and.arrow.down")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("Claude Remote")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("远程控制 Claude Code")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer().frame(height: 24)

            VStack(spacing: 16) {
                TextField("邮箱", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)

                SecureField("密码", text: $password)
                    .textContentType(.password)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
            }
            .padding(.horizontal)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button {
                Task { await performAction() }
            } label: {
                HStack {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(isRegistering ? "注册" : "登录")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(formValid ? Color.accentColor : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(!formValid || isLoading)
            .padding(.horizontal)

            Button(isRegistering ? "已有账号？登录" : "没有账号？注册") {
                isRegistering.toggle()
                errorMessage = nil
            }
            .font(.footnote)

            Spacer()
        }
        .padding()
    }

    private var formValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && password.count >= 6
    }

    private func performAction() async {
        isLoading = true
        errorMessage = nil

        do {
            let response: LoginResponse
            if isRegistering {
                response = try await APIService.shared.registerUser(
                    email: email.trimmingCharacters(in: .whitespaces),
                    password: password
                )
            } else {
                response = try await APIService.shared.login(
                    email: email.trimmingCharacters(in: .whitespaces),
                    password: password
                )
            }

            await MainActor.run {
                APIService.shared.setToken(response.token)
                self.token = response.token
                registered = true
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}
