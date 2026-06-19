import SwiftUI

// 创建任务视图
struct CreateTaskView: View {
    @StateObject private var viewModel = CreateTaskViewModel()

    var body: some View {
        NavigationView {
            Form {
                // 任务信息
                Section("任务信息") {
                    TextField("任务标题", text: $viewModel.title)

                    VStack(alignment: .leading) {
                        Text("提示词 (Prompt)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $viewModel.prompt)
                            .frame(minHeight: 140)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(.systemGray4), lineWidth: 1)
                            )
                    }
                }

                // 目标设备
                Section("目标设备") {
                    if viewModel.isLoadingDevices {
                        ProgressView("加载设备...")
                    } else if viewModel.availableDevices.isEmpty {
                        Text("暂无可用设备，请先注册设备")
                            .foregroundColor(.secondary)
                    } else {
                        Picker("选择设备", selection: $viewModel.selectedDeviceID) {
                            Text("请选择").tag("")
                            ForEach(viewModel.availableDevices) { device in
                                HStack {
                                    Image(systemName: device.platform.iconName)
                                    Text(device.name)
                                    Circle()
                                        .fill(device.status == .online ? Color.green : Color.gray)
                                        .frame(width: 8, height: 8)
                                }
                                .tag(device.id)
                            }
                        }
                    }
                }

                // 执行选项
                Section("执行选项") {
                    TextField("工作目录", text: $viewModel.workingDirectory)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    Picker("权限模式", selection: $viewModel.permissionMode) {
                        ForEach(PermissionMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // 提交按钮
                Section {
                    Button {
                        Task { await viewModel.submitTask() }
                    } label: {
                        HStack {
                            Spacer()
                            if viewModel.isSubmitting {
                                ProgressView()
                            } else {
                                Text("提交任务")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(!viewModel.isFormValid || viewModel.isSubmitting)
                }

                // 错误提示
                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("创建任务")
            .alert("任务已创建", isPresented: $viewModel.taskCreatedSuccessfully) {
                Button("确定", role: .cancel) {}
            } message: {
                Text("任务已成功创建，请在任务列表中查看状态。")
            }
        }
        .task {
            await viewModel.loadDevices()
        }
    }
}
