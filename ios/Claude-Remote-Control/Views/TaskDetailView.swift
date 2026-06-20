import SwiftUI

struct TaskDetailView: View {
    @StateObject private var viewModel = TaskDetailViewModel()
    let taskId: String

    var body: some View {
        VStack(spacing: 0) {
            // Header
            if let t = viewModel.task {
                VStack(spacing: 4) {
                    Text(t.title).font(.headline)
                    Text(t.status.displayName).font(.caption)
                        .foregroundColor(t.status == .completed ? .green : t.status == .failed ? .red : .orange)
                    if t.status == .queued || t.status == .running {
                        Button("取消任务") {
                            Task { await viewModel.cancelTask() }
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, 4)
                    }
                }
                .padding(.vertical, 8)
            }

            // Logs / conversation
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if viewModel.task != nil {
                            Text("Prompt: \(viewModel.task!.prompt)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                                .padding(.bottom, 8)
                        }

                        ForEach(Array(viewModel.logs.enumerated()), id: \.element.id) { index, log in
                            if viewModel.isCycleSeparator(at: index) {
                                HStack {
                                    Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                                    Text("新的追问").font(.caption2).foregroundColor(.secondary)
                                    Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 4)
                            }
                            Text(log.message)
                                .font(.caption)
                                .padding(8)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 4)

                        if viewModel.result != nil {
                            Text("完成: \(viewModel.result!.summary)")
                                .font(.caption)
                                .foregroundColor(.green)
                                .padding(.horizontal)
                                .padding(.top, 8)
                        }
                    }
                    .id("bottom")
                }
                .onChange(of: viewModel.logs.count) { _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }

            // Input bar for continue
            if viewModel.task?.status == .completed || viewModel.task?.status == .failed {
                HStack(spacing: 8) {
                    TextField("输入追问...", text: $viewModel.continueText)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)

                    Button("发送") {
                        Task { await viewModel.sendContinue() }
                    }
                    .font(.caption)
                    .disabled(viewModel.continueText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isSending)
                }
                .padding(8)
                .background(Color(.systemBackground))
            }
        }
        .task { await viewModel.loadTask(id: taskId) }
    }
}
