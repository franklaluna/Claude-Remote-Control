import Foundation
import Combine

final class DeviceListViewModel: ObservableObject {
    @Published var devices: [Device] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published var showAddSheet = false
    @Published var newDeviceName = ""
    @Published var newDevicePlatform: Platform = .macos
    @Published var newDeviceVersion = "1.0.0"
    @Published var isAdding = false

    private let api = APIService.shared
    private let ws = WebSocketService.shared
    private var cancellables = Set<AnyCancellable>()

    func subscribe() {
        guard cancellables.isEmpty else { return }
        ws.deviceStatusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] payload in
                guard let self, let index = self.devices.firstIndex(where: { $0.id == payload.device_id }) else { return }
                if let status = DeviceStatus(rawValue: payload.status) { self.devices[index].status = status }
            }
            .store(in: &cancellables)
    }

    func loadDevices() async {
        await MainActor.run { isLoading = true; errorMessage = nil }
        do {
            let response = try await api.listDevices()
            await MainActor.run {
                self.devices = response.devices
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

    func addDeviceTapped() { Task { await addDevice() } }

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

    func deleteDeviceTapped(_ device: Device) { Task { await deleteDevice(device) } }

    func deleteDevice(_ device: Device) async {
        await MainActor.run {
            self.devices.removeAll { $0.id == device.id }
        }
    }
}
