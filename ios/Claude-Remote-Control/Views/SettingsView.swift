import SwiftUI

// 设置页面
struct SettingsView: View {
    @State private var showLogoutAlert = false
    @State private var isLoggingOut = false
    var onLogout: () -> Void

    var body: some View {
        NavigationView {
            Form {
                Section("用户信息") {
                    HStack {
                        Text("邮箱")
                        Spacer()
                        Text(UserDefaults.standard.string(forKey: "saved_email") ?? "未知")
                            .foregroundColor(.secondary)
                    }
                }

                Section("服务器") {
                    HStack {
                        Text("地址")
                        Spacer()
                        Text(UserDefaults.standard.string(forKey: "server_host") ?? "192.168.11.210:8080")
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    Button {
                        showLogoutAlert = true
                    } label: {
                        HStack {
                            Spacer()
                            if isLoggingOut {
                                ProgressView()
                            } else {
                                Text("退出登录")
                                    .foregroundColor(.red)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isLoggingOut)
                }
            }
            .navigationTitle("设置")
            .alert("确认退出", isPresented: $showLogoutAlert) {
                Button("取消", role: .cancel) {}
                Button("退出", role: .destructive) { performLogout() }
            } message: {
                Text("退出后需要重新登录")
            }
        }
    }

    private func performLogout() {
        isLoggingOut = true
        UserDefaults.standard.removeObject(forKey: "auth_token")
        APIService.shared.setToken(nil)
        onLogout()
    }
}
