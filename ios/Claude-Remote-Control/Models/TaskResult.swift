import Foundation

// 文件变更条目
struct FileChangeEntry: Codable, Identifiable, Equatable {
    var id: String { path }
    let path: String
}

// 任务完成后的结果摘要
struct TaskResult: Codable, Equatable {
    let status: String          // "completed" 或 "failed"
    let summary: String
    let files_changed: Int
    let files: [FileChangeEntry]
    let error: String?
}
