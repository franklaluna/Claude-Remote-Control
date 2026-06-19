import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @StateObject private var wsService = WebSocketService.shared
    @AppStorage("auth_token") private var token = ""

    var body: some View {
        if token.isEmpty {
            LoginView()
        } else {
            mainView
                .onAppear { connectWebSocket() }
        }
    }

    private var mainView: some View {
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
        }
    }

    private func connectWebSocket() {
        let serverHost = UserDefaults.standard.string(forKey: "server_host") ?? "192.168.11.210:3000"
        let baseURL = URL(string: "http://\(serverHost)/api") ?? URL(string: "http://192.168.11.210:3000/api")!

        APIService.shared.configure(baseURL: baseURL, token: token)

        let host = serverHost.components(separatedBy: ":").first ?? "192.168.11.210"
        let port = Int(serverHost.components(separatedBy: ":").last ?? "3000") ?? 3000
        var wsComponents = URLComponents()
        wsComponents.scheme = "ws"
        wsComponents.host = host
        wsComponents.port = port
        wsComponents.path = "/ws"

        if let wsURL = wsComponents.url {
            WebSocketService.shared.connect(url: wsURL, token: token)
        }
    }
}
