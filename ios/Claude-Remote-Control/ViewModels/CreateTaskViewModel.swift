import Foundation
import Combine

// 创建任务 ViewModel
final class CreateTaskViewModel: ObservableObject {
    // 表单字段
    @Published var title = ""
    @Published var prompt = ""
    @Published var selectedDeviceID: String = ""
    @Published var workingDirectory = "/Users/gyfan/claude"
    @Published var permissionMode: PermissionMode = .default

    // 可用设备列表（从 DeviceListViewModel 传入或单独加载）
    @Published var availableDevices: [Device] = []

    // 状态
    @Published var isLoadingDevices = false
    @Published var isSubmitting = false
    @Published var errorMessage: String?
    @Published var taskCreatedSuccessfully = false

    private let api = APIService.shared
    private var cancellables = Set<AnyCancellable>()

    // 表单是否有效
    var isFormValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !prompt.trimmingCharacters(in: .whitespaces).isEmpty &&
        !selectedDeviceID.isEmpty
    }

    // 加载可用设备
    func loadDevices() async {
        await MainActor.run { isLoadingDevices = true }
        do {
            let response = try await api.listDevices()
            await MainActor.run {
                self.availableDevices = response.devices
                if self.selectedDeviceID.isEmpty, let first = response.devices.first {
                    self.selectedDeviceID = first.id
                }
                self.isLoadingDevices = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoadingDevices = false
            }
        }
    }

    // 提交任务
    func submitTask() async {
        guard isFormValid else { return }

        await MainActor.run { isSubmitting = true; errorMessage = nil }

        let request = CreateTaskRequest(
            title: title.trimmingCharacters(in: .whitespaces),
            prompt: prompt.trimmingCharacters(in: .whitespaces),
            device_id: selectedDeviceID,
            working_directory: workingDirectory,
            permission_mode: permissionMode
        )

        do {
            _ = try await api.createTask(request)
            await MainActor.run {
                self.isSubmitting = false
                self.taskCreatedSuccessfully = true
                // 重置表单
                self.title = ""
                self.prompt = ""
                self.workingDirectory = "/Users/gyfan/claude"
                self.permissionMode = .default
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isSubmitting = false
            }
        }
    }
}
