import Foundation
import Combine

// 任务详情 ViewModel
final class TaskDetailViewModel: ObservableObject {
    @Published var task: AppTask?
    @Published var logs: [TaskLog] = []
    @Published var result: TaskResult?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api = APIService.shared
    private let ws = WebSocketService.shared
    private var cancellables = Set<AnyCancellable>()
    private var taskID: String?

    // 加载任务详情
    func loadTask(id: String) async {
        taskID = id
        await MainActor.run { isLoading = true; errorMessage = nil }

        do {
            let response = try await api.getTask(id: id)
            await MainActor.run {
                self.task = response.task
                self.logs = response.logs.sorted { $0.timestamp < $1.timestamp }
                self.result = response.result
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    // 开始订阅 WebSocket 实时更新
    func subscribeToRealtimeUpdates() {
        cancellables.removeAll()

        // 日志
        ws.logPublisher
            .filter { [weak self] in $0.task_id == self?.taskID }
            .sink { [weak self] payload in
                guard let self else { return }
                let entry = TaskLog(
                    id: UUID().uuidString,
                    task_id: payload.task_id,
                    timestamp: Date(),
                    message: payload.message
                )
                self.logs.append(entry)
            }
            .store(in: &cancellables)

        // 状态
        ws.statusPublisher
            .filter { [weak self] in $0.task_id == self?.taskID }
            .sink { [weak self] payload in
                if let status = TaskStatus(rawValue: payload.status) { self?.task?.status = status }
            }
            .store(in: &cancellables)

        // 结果
        ws.resultPublisher
            .filter { [weak self] in $0.task_id == self?.taskID }
            .sink { [weak self] payload in
                self?.result = TaskResult(
                    status: payload.status,
                    summary: payload.summary ?? "",
                    files_changed: 0,
                    files: [],
                    error: payload.error
                )
            }
            .store(in: &cancellables)
    }

    func unsubscribe() {
        cancellables.removeAll()
    }
}
