import SwiftUI

struct ContentView: View {
    @State private var token: String = UserDefaults.standard.string(forKey: "auth_token") ?? ""
    @State private var selectedTab = 0

    var body: some View {
        if token.isEmpty {
            LoginView(onLogin: { t in token = t })
        } else {
            TabView(selection: $selectedTab) {
                DeviceListView()
                    .tabItem {
                        Image(systemName: "desktopcomputer")
                        Text("设备")
                    }
                    .tag(0)

                TaskListView()
                    .tabItem {
                        Image(systemName: "list.bullet.rectangle")
                        Text("任务")
                    }
                    .tag(1)

                CreateTaskView()
                    .tabItem {
                        Image(systemName: "plus.circle")
                        Text("创建")
                    }
                    .tag(2)

                SettingsView(onLogout: {
                    token = ""
                })
                    .tabItem {
                        Image(systemName: "gearshape")
                        Text("设置")
                    }
                    .tag(3)
            }
            .onAppear {
                configureAPI()
            }
        }
    }

    func configureAPI() {
        let host = UserDefaults.standard.string(forKey: "server_host") ?? "192.168.11.210:8080"
        let baseURL = URL(string: "http://\(host)/api")!
        APIService.shared.configure(baseURL: baseURL, token: token)
    }
}
