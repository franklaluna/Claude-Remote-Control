import Foundation

// API 服务 — 封装所有 HTTP 请求
final class APIService {
    static let shared = APIService()

    private var baseURL: URL = URL(string: "http://localhost:3000/api")!
    private var token: String?

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = fmt.date(from: str) { return date }
            // fallback: without fractional seconds
            let fmt2 = ISO8601DateFormatter()
            if let date = fmt2.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(str)")
        }
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        e.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(fmt.string(from: date))
        }
        return e
    }()

    private init() {}

    // 设置基础 URL 和 token
    func configure(baseURL: URL, token: String? = nil) {
        self.baseURL = baseURL
        if let token { self.token = token }
    }

    func setToken(_ token: String?) {
        self.token = token
    }

    // MARK: - 通用请求

    private func request<T: Decodable>(
        method: String,
        path: String,
        body: (any Encodable)? = nil,
        authenticated: Bool = true
    ) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if authenticated, let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            req.httpBody = try encoder.encode(AnyEncodable(body))
        }

        let (data, response) = try await URLSession.shared.data(for: req)

        guard let http = response as? HTTPURLResponse else {
            throw AppError.network("无效响应")
        }

        if http.statusCode == 401 {
            throw AppError.unauthorized
        }

        if http.statusCode >= 400 {
            if let apiErr = try? decoder.decode(ApiError.self, from: data) {
                throw AppError.server(apiErr)
            }
            throw AppError.network("HTTP \(http.statusCode)")
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AppError.decoding(error)
        }
    }

    // MARK: - 认证

    func login(email: String, password: String) async throws -> LoginResponse {
        let body = LoginRequest(email: email, password: password)
        return try await request(method: "POST", path: "auth/login", body: body, authenticated: false)
    }

        func registerUser(email: String, password: String) async throws -> LoginResponse {
        let body = LoginRequest(email: email, password: password)
        return try await request(method: "POST", path: "auth/register", body: body, authenticated: false)
    }

    // MARK: - 设备

    func listDevices() async throws -> DeviceListResponse {
        try await request(method: "GET", path: "devices")
    }

    func createDevice(name: String, platform: Platform, version: String) async throws -> CreateDeviceResponse {
        let body = CreateDeviceRequest(name: name, platform: platform, version: version)
        return try await request(method: "POST", path: "devices", body: body)
    }

    // MARK: - 任务

    func listTasks() async throws -> TaskListResponse {
        try await request(method: "GET", path: "tasks")
    }

    func createTask(_ task: CreateTaskRequest) async throws -> CreateTaskResponse {
        try await request(method: "POST", path: "tasks", body: task)
    }

    func getTask(id: String) async throws -> GetTaskResponse {
        try await request(method: "GET", path: "tasks/\(id)")
    }

    func cancelTask(id: String) async throws -> CancelTaskResponse {
        try await request(method: "POST", path: "tasks/\(id)/cancel")
    }
    func continueTask(id: String, prompt: String) async throws -> CreateTaskResponse {
        let body = ContinueTaskRequest(prompt: prompt)
        return try await request(method: "POST", path: "tasks/\(id)/continue", body: body)
    }

    func deleteTask(id: String) async throws -> DeleteTaskResponse {
        try await request(method: "DELETE", path: "tasks/\(id)")
    }
}
struct ContinueTaskRequest: Codable {
    let prompt: String
}

private struct AnyEncodable: Encodable {
    let value: any Encodable

    init(_ value: any Encodable) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}
