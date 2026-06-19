import Foundation

// 任务执行日志条目
struct TaskLog: Codable, Identifiable, Equatable {
    let id: String
    let task_id: String
    let timestamp: Date
    let message: String
}
