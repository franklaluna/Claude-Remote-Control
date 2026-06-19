import Foundation

// MARK: - 认证

struct LoginRequest: Codable {
    let email: String
    let password: String
}

struct LoginResponse: Codable {
    let token: String
    let user: UserInfo
}

struct UserInfo: Codable {
    let id: String
    let email: String
    let created_at: Date
}

// MARK: - 设备

struct DeviceListResponse: Codable {
    let devices: [Device]
}

struct CreateDeviceRequest: Codable {
    let name: String
    let platform: Platform
    let version: String
}

struct CreateDeviceResponse: Codable {
    let device: Device
}

// MARK: - 任务

struct CreateTaskRequest: Codable {
    let title: String
    let prompt: String
    let device_id: String
    let working_directory: String
    let permission_mode: PermissionMode
}

struct CreateTaskResponse: Codable {
    let task: Task
}

struct GetTaskResponse: Codable {
    let task: Task
    let logs: [TaskLog]
    let result: TaskResult?
}

struct TaskListResponse: Codable {
    let tasks: [Task]
}

struct CancelTaskResponse: Codable {
    let task: Task
}

// MARK: - 通用错误

struct ApiError: Codable, Error {
    let statusCode: Int
    let message: String
    let error: String
}

// MARK: - 应用状态

enum AppError: LocalizedError {
    case network(String)
    case server(ApiError)
    case unauthorized
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .network(let msg): return "网络错误: \(msg)"
        case .server(let api): return api.message
        case .unauthorized: return "认证已过期，请重新登录"
        case .decoding(let err): return "数据解析错误: \(err.localizedDescription)"
        }
    }
}
