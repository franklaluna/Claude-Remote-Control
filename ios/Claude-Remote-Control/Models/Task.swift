import Foundation

// 任务状态
enum TaskStatus: String, Codable, CaseIterable {
    case queued
    case running
    case completed
    case failed
    case cancelled

    var displayName: String {
        switch self {
        case .queued: return "排队中"
        case .running: return "运行中"
        case .completed: return "已完成"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }
}

// 权限模式
enum PermissionMode: String, Codable, CaseIterable {
    case `default`
    case acceptEdits
    case bypassPermissions
    case plan

    var displayName: String {
        switch self {
        case .default: return "默认"
        case .acceptEdits: return "接受编辑"
        case .bypassPermissions: return "跳过权限"
        case .plan: return "计划"
        }
    }
}

// 任务
struct Task: Codable, Identifiable, Equatable {
    let id: String
    let user_id: String
    let device_id: String
    let title: String
    let prompt: String
    let working_directory: String
    let permission_mode: PermissionMode
    var status: TaskStatus
    let created_at: Date
    let updated_at: Date
}
