import Foundation
import Combine

final class TaskDetailViewModel: ObservableObject {
    @Published var task: AppTask?
    @Published var logs: [TaskLog] = []
    @Published var result: TaskResult?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var continueText = ""
    @Published var isSending = false
    @Published var newTaskCreated = false

    private let api = APIService.shared
    private let ws = WebSocketService.shared
    private var cancellables = Set<AnyCancellable>()
    private var taskID: String?

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
            subscribeToRealtimeUpdates()
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func sendContinue() async {
        guard let id = taskID, !continueText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        await MainActor.run { isSending = true }

        do {
            let response = try await api.continueTask(id: id, prompt: continueText.trimmingCharacters(in: .whitespaces))
            await MainActor.run {
                self.isSending = false
                self.continueText = ""
                self.newTaskCreated = true
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isSending = false
            }
        }
    }

    private func subscribeToRealtimeUpdates() {
        cancellables.removeAll()

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

        ws.statusPublisher
            .filter { [weak self] in $0.task_id == self?.taskID }
            .sink { [weak self] payload in
                if let status = TaskStatus(rawValue: payload.status) { self?.task?.status = status }
            }
            .store(in: &cancellables)

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
}
