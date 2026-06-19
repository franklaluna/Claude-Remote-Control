import SwiftUI

struct CreateTaskView: View {
    @StateObject private var viewModel = CreateTaskViewModel()
    @FocusState private var focusedField: Field?

    enum Field { case title, prompt, dir }

    var body: some View {
        NavigationView {
            Form {
                Section("任务信息") {
                    TextField("任务标题", text: $viewModel.title)
                        .focused($focusedField, equals: .title)
                    TextField("Prompt", text: $viewModel.prompt, axis: .vertical)
                        .focused($focusedField, equals: .prompt)
                        .lineLimit(3...10)
                    Picker("设备", selection: $viewModel.selectedDeviceID) {
                        if viewModel.availableDevices.isEmpty {
                            Text("无可用设备").tag("")
                        }
                        ForEach(viewModel.availableDevices) { device in
                            Text("\(device.name) (\(device.status == .online ? "在线" : "离线"))")
                                .tag(device.id)
                        }
                    }
                    TextField("工作目录", text: $viewModel.workingDirectory)
                        .focused($focusedField, equals: .dir)
                    Picker("权限", selection: $viewModel.permissionMode) {
                        ForEach(PermissionMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                }

                if let error = viewModel.errorMessage {
                    Text(error).foregroundColor(.red).font(.caption)
                }

                Section {
                    Button {
                        focusedField = nil  // dismiss keyboard
                        Task { await viewModel.submitTask() }
                    } label: {
                        HStack {
                            Spacer()
                            if viewModel.isSubmitting {
                                ProgressView()
                            } else {
                                Text("提交任务")
                            }
                            Spacer()
                        }
                    }
                    .disabled(!viewModel.isFormValid || viewModel.isSubmitting)
                }

                if viewModel.taskCreatedSuccessfully {
                    Section {
                        Text("任务已创建").foregroundColor(.green)
                    }
                }
            }
            .navigationTitle("创建任务")
            .task { await viewModel.loadDevices() }
        }
    }
}
