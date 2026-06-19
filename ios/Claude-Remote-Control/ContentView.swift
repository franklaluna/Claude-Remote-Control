import SwiftUI

// 主内容视图 — Tab 导航
struct ContentView: View {
    @State private var selectedTab = 0
    @StateObject private var wsService = WebSocketService.shared

    var body: some View {
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
        .onAppear { connectWebSocket() }
    }

    private func connectWebSocket() {
        let serverHost = UserDefaults.standard.string(forKey: "server_host") ?? "localhost:3000"
        let token = UserDefaults.standard.string(forKey: "auth_token") ?? ""
        let baseURL = URL(string: "http://\(serverHost)/api") ?? URL(string: "http://localhost:3000/api")!

        APIService.shared.configure(baseURL: baseURL, token: token)

        // 原生 WebSocket: ws:// 方案，path=/ws
        let host = serverHost.components(separatedBy: ":").first ?? "localhost"
        let port = Int(serverHost.components(separatedBy: ":").last ?? "3000") ?? 3000
        var wsComponents = URLComponents()
        wsComponents.scheme = "ws"
        wsComponents.host = host
        wsComponents.port = port
        wsComponents.path = "/ws"

        if let wsURL = wsComponents.url {
            WebSocketService.shared.connect(url: wsURL, token: token.isEmpty ? nil : token)
        }
    }
}
