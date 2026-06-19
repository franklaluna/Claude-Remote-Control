import SwiftUI

struct LoginView: View {
    @AppStorage("saved_email") private var savedEmail = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMsg = ""
    @State private var isReg = false
    var onLogin: (String) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "desktopcomputer.and.arrow.down")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
            Text("Claude Remote").font(.largeTitle).bold()
            Spacer().frame(height: 20)

            TextField("邮箱", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)

            SecureField("密码", text: $password)
                .textContentType(.password)
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)

            if !errorMsg.isEmpty {
                Text(errorMsg).foregroundColor(.red).font(.caption)
            }

            Button {
                Task { await doAction() }
            } label: {
                HStack {
                    if isLoading { ProgressView().tint(.white) }
                    else { Text(isReg ? "注册" : "登录") }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(email.isEmpty || password.count < 6 ? Color.gray : Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(email.isEmpty || password.count < 6 || isLoading)
            .padding(.horizontal)

            Button(isReg ? "已有账号？登录" : "没有账号？注册") {
                isReg.toggle()
                errorMsg = ""
            }
            .font(.footnote)
            Spacer()
        }
        .onAppear { email = savedEmail }
    }

    func doAction() async {
        isLoading = true
        errorMsg = ""
        let host = UserDefaults.standard.string(forKey: "server_host") ?? "192.168.11.210:8080"
        APIService.shared.configure(baseURL: URL(string: "http://\(host)/api")!, token: nil)

        do {
            let rsp: LoginResponse
            if isReg {
                rsp = try await APIService.shared.registerUser(email: email, password: password)
            } else {
                rsp = try await APIService.shared.login(email: email, password: password)
            }
            // Save email for next time
            savedEmail = email
            UserDefaults.standard.set(rsp.token, forKey: "auth_token")
            await MainActor.run {
                onLogin(rsp.token)
            }
        } catch {
            await MainActor.run {
                errorMsg = error.localizedDescription
                isLoading = false
            }
        }
    }
}
