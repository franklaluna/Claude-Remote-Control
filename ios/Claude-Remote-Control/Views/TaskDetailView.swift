import SwiftUI

// 任务详情视图
struct TaskDetailView: View {
    let taskID: String
    @StateObject private var viewModel = TaskDetailViewModel()
    @State private var autoScroll = true

    var body: some View {
        ScrollViewReader { scrollProxy in
            List {
                // 状态区域
                if let task = viewModel.task {
                    statusSection(task)
                }

                // 实时日志区域
                logSection(scrollProxy: scrollProxy)

                // 文件变更列表
                if let result = viewModel.result, !result.files.isEmpty {
                    fileChangesSection(result)
                }

                // 结果摘要
                if let result = viewModel.result {
                    resultSummarySection(result)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(viewModel.task?.title ?? "任务详情")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await viewModel.loadTask(id: taskID)
            viewModel.subscribeToRealtimeUpdates()
        }
        .onDisappear {
            viewModel.unsubscribe()
        }
    }

    // MARK: - 状态区域

    private func statusSection(_ task: AppTask) -> some View {
        Section("状态") {
            HStack {
                Text("任务状态")
                    .foregroundColor(.secondary)
                Spacer()
                HStack(spacing: 6) {
                    statusBadge(task.status)
                    Text(task.status.displayName)
                        .font(.subheadline)
                        .foregroundColor(statusColor(task.status))
                }
            }

            HStack {
                Text("目标设备")
                    .foregroundColor(.secondary)
                Spacer()
                Text(task.device_id)
                    .font(.subheadline)
                    .lineLimit(1)
            }

            HStack {
                Text("工作目录")
                    .foregroundColor(.secondary)
                Spacer()
                Text(task.working_directory)
                    .font(.subheadline)
                    .lineLimit(1)
            }

            HStack {
                Text("权限模式")
                    .foregroundColor(.secondary)
                Spacer()
                Text(task.permission_mode.displayName)
                    .font(.subheadline)
            }

            HStack {
                Text("创建时间")
                    .foregroundColor(.secondary)
                Spacer()
                Text(task.created_at.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
            }
        }
    }

    private func statusBadge(_ status: TaskStatus) -> some View {
        Group {
            switch status {
            case .queued:   Image(systemName: "hourglass").foregroundColor(.orange)
            case .running:  ProgressView().scaleEffect(0.6)
            case .completed: Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            case .failed:   Image(systemName: "xmark.circle.fill").foregroundColor(.red)
            case .cancelled: Image(systemName: "slash.circle.fill").foregroundColor(.gray)
            }
        }
    }

    private func statusColor(_ status: TaskStatus) -> Color {
        switch status {
        case .queued: return .orange
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        }
    }

    // MARK: - 日志区域

    private func logSection(scrollProxy: ScrollViewProxy) -> some View {
        Section {
            HStack {
                Text("实时日志")
                    .font(.headline)
                Spacer()
                Toggle("自动滚动", isOn: $autoScroll)
                    .labelsHidden()
                    .scaleEffect(0.8)
                Text("自动滚动")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if viewModel.logs.isEmpty {
                if viewModel.task?.status == .queued {
                    HStack {
                        Spacer()
                        ProgressView("等待执行...")
                        Spacer()
                    }
                } else if viewModel.task?.status == .running {
                    HStack {
                        Spacer()
                        ProgressView("等待日志...")
                        Spacer()
                    }
                }
            }

            ForEach(viewModel.logs) { log in
                VStack(alignment: .leading, spacing: 2) {
                    Text(log.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(log.message)
                        .font(.subheadline.monospaced())
                        .textSelection(.enabled)
                }
                .id(log.id)
                .padding(.vertical, 1)
            }
        } header: {
            EmptyView()
        } footer: {
            if let task = viewModel.task, task.status == .running {
                HStack {
                    Spacer()
                    ProgressView("任务执行中...")
                    Spacer()
                }
                .padding(.top, 8)
            }
        }
        .onChange(of: viewModel.logs.count) { _ in
            guard autoScroll, let lastLog = viewModel.logs.last else { return }
            withAnimation {
                scrollProxy.scrollTo(lastLog.id, anchor: .bottom)
            }
        }
    }

    // MARK: - 文件变更

    private func fileChangesSection(_ result: TaskResult) -> some View {
        Section("文件变更 (\(result.files_changed))") {
            ForEach(result.files) { file in
                HStack {
                    Image(systemName: "doc.text")
                        .foregroundColor(.accentColor)
                    Text(file.path)
                        .font(.subheadline.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - 结果摘要

    private func resultSummarySection(_ result: TaskResult) -> some View {
        Section("结果摘要") {
            HStack {
                Image(systemName: result.status == "completed" ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .foregroundColor(result.status == "completed" ? .green : .red)
                    .font(.title2)
                Text(result.summary)
                    .font(.subheadline)
            }

            if let error = result.error {
                VStack(alignment: .leading, spacing: 4) {
                    Text("错误信息")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(error)
                        .font(.subheadline.monospaced())
                        .foregroundColor(.red)
                        .textSelection(.enabled)
                }
            }
        }
    }
}
