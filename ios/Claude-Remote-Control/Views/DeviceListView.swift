import SwiftUI

// 设备列表视图
struct DeviceListView: View {
    @StateObject private var viewModel = DeviceListViewModel()

    var body: some View {
        NavigationView {
            List {
                if viewModel.isLoading {
                    ProgressView("加载设备列表...")
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.subheadline)
                        .listRowBackground(Color.clear)
                }

                if !viewModel.isLoading && viewModel.devices.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "desktopcomputer.trianglebadge.exclamationmark")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("暂无设备")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("点击右上角 + 添加设备")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                    .listRowBackground(Color.clear)
                }

                ForEach(viewModel.devices) { device in
                    DeviceCardView(device: device)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task { await viewModel.deleteDevice(device) }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable {
                await viewModel.loadDevices()
            }
            .navigationTitle("设备列表")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $viewModel.showAddSheet) {
                addDeviceSheet
            }
        }
        .task {
            await viewModel.loadDevices()
        }
    }

    // 添加设备表单
    private var addDeviceSheet: some View {
        NavigationView {
            Form {
                Section("设备信息") {
                    TextField("设备名称", text: $viewModel.newDeviceName)
                        .autocapitalization(.none)

                    Picker("平台", selection: $viewModel.newDevicePlatform) {
                        ForEach(Platform.allCases, id: \.self) { platform in
                            Text(platform.displayName).tag(platform)
                        }
                    }

                    TextField("版本", text: $viewModel.newDeviceVersion)
                }

                Section {
                    Button {
                        Task { await viewModel.addDevice() }
                    } label: {
                        HStack {
                            Spacer()
                            if viewModel.isAdding {
                                ProgressView()
                            } else {
                                Text("注册设备")
                            }
                            Spacer()
                        }
                    }
                    .disabled(viewModel.isAdding || viewModel.newDeviceName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("添加设备")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("取消") { viewModel.showAddSheet = false }
                }
            }
        }
    }
}

// 设备卡片视图
struct DeviceCardView: View {
    let device: Device

    var body: some View {
        HStack(spacing: 12) {
            // 平台图标 + 状态指示
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: device.platform.iconName)
                    .font(.system(size: 32))
                    .foregroundColor(.accentColor)

                Circle()
                    .fill(device.status == .online ? Color.green : Color.gray)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.headline)

                HStack(spacing: 6) {
                    Text(device.platform.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("v\(device.version)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(device.status == .online ? "在线" : "离线 — \(device.last_seen, style: .relative)前")
                    .font(.caption)
                    .foregroundColor(device.status == .online ? .green : .secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
