import Foundation

// 设备平台
enum Platform: String, Codable, CaseIterable {
    case macos
    case windows

    var displayName: String {
        switch self {
        case .macos: return "macOS"
        case .windows: return "Windows"
        }
    }

    var iconName: String {
        switch self {
        case .macos: return "desktopcomputer"
        case .windows: return "display"
        }
    }
}

// 设备状态
enum DeviceStatus: String, Codable {
    case online
    case offline
}

// 注册设备
struct Device: Codable, Identifiable, Equatable {
    let id: String
    let user_id: String
    let name: String
    let platform: Platform
    var status: DeviceStatus
    let version: String
    let last_seen: Date
    let created_at: Date
}
