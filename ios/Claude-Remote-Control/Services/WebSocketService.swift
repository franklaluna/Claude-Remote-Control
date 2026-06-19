import Foundation
import Combine

// WebSocket 消息类型（与服务端对齐）
enum WsMessageType: String, Codable {
    case taskLog = "task:log"
    case taskStatus = "task:status"
    case taskResult = "task:result"
    case deviceStatus = "device:status"
    case deviceOnline = "device:online"
    case deviceOffline = "device:offline"
    case heartbeat
    case auth
}

// WebSocket 消息
struct WsMessage: Codable {
    let type: WsMessageType
    let payload: AnyCodable
    let timestamp: String
}

// 任务日志负载
struct WsTaskLogPayload: Codable {
    let task_id: String
    let message: String
}

// 任务状态负载
struct WsTaskStatusPayload: Codable {
    let task_id: String
    let status: TaskStatus
}

// 任务结果负载
struct WsTaskResultPayload: Codable {
    let task_id: String
    let result: TaskResult
}

// 设备状态负载
struct WsDeviceStatusPayload: Codable {
    let device_id: String
    let status: DeviceStatus
}

// 用于解码任意 JSON 值
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            value = str
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let obj = try? container.decode([String: AnyCodable].self) {
            value = obj.mapValues { $0.value }
        } else if let arr = try? container.decode([AnyCodable].self) {
            value = arr.map { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let str as String: try container.encode(str)
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let bool as Bool: try container.encode(bool)
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        case let arr as [Any]:
            try container.encode(arr.map { AnyCodable($0) })
        default: try container.encodeNil()
        }
    }
}

extension AnyCodable {
    var unwrapped: Any {
        switch value {
        case let dict as [String: AnyCodable]: return dict.mapValues { $0.unwrapped }
        case let arr as [AnyCodable]: return arr.map { $0.unwrapped }
        default: return value
        }
    }
}

// MARK: - WebSocket 服务

final class WebSocketService: NSObject, ObservableObject {
    static let shared = WebSocketService()

    private var task: URLSessionWebSocketTask?
    private var session: URLSession!
    private var pingTimer: Timer?

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    // Combine 发布者 — 日志消息流
    let logPublisher = PassthroughSubject<WsTaskLogPayload, Never>()
    let statusPublisher = PassthroughSubject<WsTaskStatusPayload, Never>()
    let resultPublisher = PassthroughSubject<WsTaskResultPayload, Never>()
    let deviceStatusPublisher = PassthroughSubject<WsDeviceStatusPayload, Never>()

    @Published var isConnected = false

    private override init() {
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    func connect(url: URL, token: String? = nil) {
        disconnect()

        var request = URLRequest(url: url)
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        task = session.webSocketTask(with: request)
        task?.resume()
        isConnected = true

        startPing()
        receive()
    }

    func disconnect() {
        pingTimer?.invalidate()
        pingTimer = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        isConnected = false
    }

    // MARK: - 发送消息

    func send(type: WsMessageType, payload: Any) {
        guard let task else { return }
        let msg = WsMessage(
            type: type,
            payload: AnyCodable(payload),
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
        guard let data = try? encoder.encode(msg),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { [weak self] error in
            if let error {
                print("[WS] 发送失败: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 接收消息

    private func receive() {
        task?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handle(message)
                self?.receive()
            case .failure(let error):
                print("[WS] 接收错误: \(error.localizedDescription)")
                self?.isConnected = false
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            guard let data = text.data(using: .utf8),
                  let wsMsg = try? decoder.decode(WsMessage.self, from: data) else { return }
            DispatchQueue.main.async { [weak self] in
                self?.dispatch(wsMsg)
            }
        case .data(let data):
            guard let wsMsg = try? decoder.decode(WsMessage.self, from: data) else { return }
            DispatchQueue.main.async { [weak self] in
                self?.dispatch(wsMsg)
            }
        @unknown default: break
        }
    }

    private func dispatch(_ msg: WsMessage) {
        switch msg.type {
        case .taskLog:
            if let payload = decodePayload(WsTaskLogPayload.self, from: msg.payload) {
                logPublisher.send(payload)
            }
        case .taskStatus:
            if let payload = decodePayload(WsTaskStatusPayload.self, from: msg.payload) {
                statusPublisher.send(payload)
            }
        case .taskResult:
            if let payload = decodePayload(WsTaskResultPayload.self, from: msg.payload) {
                resultPublisher.send(payload)
            }
        case .deviceStatus, .deviceOnline, .deviceOffline:
            if let payload = decodePayload(WsDeviceStatusPayload.self, from: msg.payload) {
                deviceStatusPublisher.send(payload)
            }
        case .heartbeat, .auth: break
        }
    }

    private func decodePayload<T: Decodable>(_ type: T.Type, from anyCodable: AnyCodable) -> T? {
        let raw = anyCodable.unwrapped
        guard JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw),
              let obj = try? decoder.decode(T.self, from: data) else { return nil }
        return obj
    }

    // MARK: - 心跳

    private func startPing() {
        pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.task?.sendPing { error in
                if let error {
                    print("[WS] Ping 失败: \(error.localizedDescription)")
                    DispatchQueue.main.async { self?.isConnected = false }
                }
            }
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension WebSocketService: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = false
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = false
            if let error {
                print("[WS] 连接断开: \(error.localizedDescription)")
            }
        }
    }
}
