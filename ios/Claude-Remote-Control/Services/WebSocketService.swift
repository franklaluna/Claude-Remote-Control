import Foundation
import Combine

// MARK: - 消息负载类型（与服务端 WsMessage 对齐）

struct WsTaskLogPayload: Codable {
    let task_id: String
    let message: String
}

struct WsTaskStatusPayload: Codable {
    let task_id: String
    let status: String
}

struct WsTaskResultPayload: Codable {
    let task_id: String
    let summary: String?
    let error: String?
    let status: String
}

struct WsDeviceStatusPayload: Codable {
    let device_id: String
    let status: String
    let name: String?
    let platform: String?
    let last_seen: String?
}

// 服务端消息信封
struct WsMessage: Codable {
    let type: String
    // payload 为 Any，用 JSONSerialization 手动解析
}

// MARK: - WebSocket 服务（原生 URLSessionWebSocketTask）

final class WebSocketService: NSObject, ObservableObject {
    static let shared = WebSocketService()

    private var wsTask: URLSessionWebSocketTask?
    private var session: URLSession!
    private var shouldReconnect = false
    private var wsURL: URL?
    private var authToken: String?

    private let decoder = JSONDecoder()

    @Published var isConnected = false

    // Combine 发布者（ViewModel 订阅）
    let logPublisher = PassthroughSubject<WsTaskLogPayload, Never>()
    let statusPublisher = PassthroughSubject<WsTaskStatusPayload, Never>()
    let resultPublisher = PassthroughSubject<WsTaskResultPayload, Never>()
    let deviceStatusPublisher = PassthroughSubject<WsDeviceStatusPayload, Never>()

    private override init() {
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    func connect(url: URL, token: String?) {
        disconnect()
        self.wsURL = url
        self.authToken = token
        shouldReconnect = true

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        wsTask = session.webSocketTask(with: request)
        wsTask?.resume()
        isConnected = true

        // 连接后立即发送认证消息
        if let token {
            sendAuth(token: token)
        }

        receive()
    }

    func disconnect() {
        shouldReconnect = false
        wsTask?.cancel(with: .normalClosure, reason: nil)
        wsTask = nil
        isConnected = false
    }

    // MARK: - 发送

    func send(type: String, payload: [String: Any]) {
        guard let task = wsTask else { return }
        let msg: [String: Any] = [
            "type": type,
            "payload": payload,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: msg),
              let text = String(data: data, encoding: .utf8) else { return }

        task.send(.string(text)) { error in
            if let error { print("[WS] send error: \(error.localizedDescription)") }
        }
    }

    // MARK: - 认证

    private func sendAuth(token: String) {
        send(type: "auth", payload: ["token": token])
    }

    // MARK: - 接收

    private func receive() {
        wsTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handle(message)
                self?.receive()
            case .failure(let error):
                print("[WS] receive error: \(error.localizedDescription)")
                DispatchQueue.main.async { self?.isConnected = false }
                self?.tryReconnect()
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            guard let data = text.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = dict["type"] as? String else { return }
            DispatchQueue.main.async { [weak self] in
                self?.dispatch(type: type, dict: dict)
            }
        case .data(let data):
            guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = dict["type"] as? String else { return }
            DispatchQueue.main.async { [weak self] in
                self?.dispatch(type: type, dict: dict)
            }
        @unknown default: break
        }
    }

    private func dispatch(type: String, dict: [String: Any]) {
        switch type {
        case "auth_ok":
            isConnected = true
            print("[WS] 认证成功")

        case "auth_error":
            isConnected = false
            print("[WS] 认证失败: \(dict["payload"] ?? "")")

        case "task_log":
            if let payload = extractPayload(dict) as WsTaskLogPayload? {
                logPublisher.send(payload)
            }

        case "task_started":
            if let payload = rawPayload(dict),
               let taskId = payload["task_id"] as? String {
                statusPublisher.send(WsTaskStatusPayload(task_id: taskId, status: "running"))
            }

        case "task_completed":
            if let payload = rawPayload(dict),
               let taskId = payload["task_id"] as? String {
                resultPublisher.send(WsTaskResultPayload(
                    task_id: taskId,
                    summary: payload["summary"] as? String,
                    error: nil,
                    status: "completed"
                ))
                statusPublisher.send(WsTaskStatusPayload(task_id: taskId, status: "completed"))
            }

        case "task_failed":
            if let payload = rawPayload(dict),
               let taskId = payload["task_id"] as? String {
                resultPublisher.send(WsTaskResultPayload(
                    task_id: taskId,
                    summary: nil,
                    error: payload["error"] as? String,
                    status: "failed"
                ))
                statusPublisher.send(WsTaskStatusPayload(task_id: taskId, status: "failed"))
            }

        case "device:status", "device:online", "device:offline":
            if let payload = extractPayload(dict) as WsDeviceStatusPayload? {
                deviceStatusPublisher.send(payload)
            }

        default: break
        }
    }

    // 从消息信封中提取 payload 字典（不解码）
    private func rawPayload(_ dict: [String: Any]) -> [String: Any]? {
        return dict["payload"] as? [String: Any]
    }

    // 从消息信封中提取 payload 并解码为目标类型
    private func extractPayload<T: Decodable>(_ dict: [String: Any]) -> T? {
        guard let payload = dict["payload"] else { return nil }
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload)
            return try decoder.decode(T.self, from: jsonData)
        } catch {
            print("[WS] decode error: \(error)")
            return nil
        }
    }

    // MARK: - 重连

    private func tryReconnect() {
        guard shouldReconnect, let url = wsURL else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.shouldReconnect else { return }
            print("[WS] 尝试重连...")
            self.connect(url: url, token: self.authToken)
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension WebSocketService: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async { [weak self] in self?.isConnected = false }
        tryReconnect()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DispatchQueue.main.async { [weak self] in self?.isConnected = false }
        if let error { print("[WS] disconnected: \(error.localizedDescription)") }
        tryReconnect()
    }
}
