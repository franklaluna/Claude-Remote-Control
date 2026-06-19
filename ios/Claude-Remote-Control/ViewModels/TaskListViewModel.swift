import Foundation
import Combine

final class TaskListViewModel: ObservableObject {
    @Published var tasks: [AppTask] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedTab: TaskListTab = .running

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

    var filteredTasks: [AppTask] {
        switch selectedTab {
        case .running: return tasks.filter { $0.status == .queued || $0.status == .running }
        case .completed: return tasks.filter { $0.status == .completed }
        case .failed: return tasks.filter { $0.status == .failed || $0.status == .cancelled }
        }
    }

    private let api = APIService.shared
    private let ws = WebSocketService.shared
    private var cancellables = Set<AnyCancellable>()

    func subscribe() {
        guard cancellables.isEmpty else { return }
        ws.statusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] payload in
                guard let self, let index = self.tasks.firstIndex(where: { $0.id == payload.task_id }) else { return }
                if let status = TaskStatus(rawValue: payload.status) { self.tasks[index].status = status }
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
            subscribe()
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func cancelTask(_ task: AppTask) async {
        do {
            _ = try await api.cancelTask(id: task.id)
            await loadTasks()
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
}
