import Foundation
import Combine

// 任务列表 ViewModel
final class TaskListViewModel: ObservableObject {
    @Published var tasks: [Task] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedTab: TaskListTab = .running

    // 三个 Tab
    enum TaskListTab: String, CaseIterable {
        case running, completed, failed
        var displayName: String {
            switch self {
            case .running: return "运行中"
            case .completed: return "已完成"
            case .failed: return "失败"
            }
        }
    }

    // 根据 Tab 筛选
    var filteredTasks: [Task] {
        switch selectedTab {
        case .running: return tasks.filter { $0.status == .queued || $0.status == .running }
        case .completed: return tasks.filter { $0.status == .completed }
        case .failed: return tasks.filter { $0.status == .failed || $0.status == .cancelled }
        }
    }

    private let api = APIService.shared
    private let ws = WebSocketService.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        // 监听 WebSocket 任务状态更新
        ws.statusPublisher
            .sink { [weak self] payload in
                guard let self, let index = self.tasks.firstIndex(where: { $0.id == payload.task_id }) else { return }
                self.tasks[index].status = payload.status
            }
            .store(in: &cancellables)
    }

    func loadTasks() async {
        await MainActor.run { isLoading = true; errorMessage = nil }
        do {
            let response = try await api.listTasks()
            await MainActor.run {
                self.tasks = response.tasks.sorted { $0.created_at > $1.created_at }
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    // 取消排队中的任务
    func cancelTask(_ task: Task) async {
        do {
            _ = try await api.cancelTask(id: task.id)
            await loadTasks()
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
}
