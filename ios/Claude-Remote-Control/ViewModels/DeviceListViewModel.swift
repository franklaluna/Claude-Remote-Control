import Foundation
import Combine

// 设备列表 ViewModel
final class DeviceListViewModel: ObservableObject {
    @Published var devices: [Device] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // 添加设备表单
    @Published var showAddSheet = false
    @Published var newDeviceName = ""
    @Published var newDevicePlatform: Platform = .macos
    @Published var newDeviceVersion = "1.0.0"
    @Published var isAdding = false

    private let api = APIService.shared
    private let ws = WebSocketService.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        // 监听 WebSocket 设备状态变化，更新列表中对应设备
        ws.deviceStatusPublisher
            .sink { [weak self] payload in
                guard let self, let index = self.devices.firstIndex(where: { $0.id == payload.device_id }) else { return }
                self.devices[index].status = payload.status
            }
            .store(in: &cancellables)
    }

    // 加载设备列表
    func loadDevices() async {
        await MainActor.run { isLoading = true; errorMessage = nil }
        do {
            let response = try await api.listDevices()
            await MainActor.run {
                self.devices = response.devices
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    // 添加设备
    func addDevice() async {
        guard !newDeviceName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        await MainActor.run { isAdding = true }
        do {
            let response = try await api.createDevice(
                name: newDeviceName.trimmingCharacters(in: .whitespaces),
                platform: newDevicePlatform,
                version: newDeviceVersion
            )
            await MainActor.run {
                self.devices.append(response.device)
                self.isAdding = false
                self.showAddSheet = false
                self.newDeviceName = ""
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isAdding = false
            }
        }
    }

    // 删除设备（左滑）
    func deleteDevice(_ device: Device) async {
        // API 暂无 DELETE /api/devices/:id 端点，先本地移除
        // TODO: 服务端提供删除端点后调用
        await MainActor.run {
            self.devices.removeAll { $0.id == device.id }
        }
    }
}
