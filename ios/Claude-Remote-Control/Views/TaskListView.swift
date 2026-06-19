import SwiftUI

// 任务列表视图
struct TaskListView: View {
    @StateObject private var viewModel = TaskListViewModel()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Tab 栏
                Picker("", selection: $viewModel.selectedTab) {
                    ForEach(TaskListViewModel.TaskListTab.allCases, id: \.self) { tab in
                        Text(tab.displayName).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                // 任务列表
                List {
                    if viewModel.isLoading {
                        ProgressView("加载任务列表...")
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.subheadline)
                            .listRowBackground(Color.clear)
                    }

                    if !viewModel.isLoading && viewModel.filteredTasks.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "tray")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("暂无\(viewModel.selectedTab.displayName)任务")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .listRowBackground(Color.clear)
                    }

                    ForEach(viewModel.filteredTasks) { task in
                        NavigationLink {
                            TaskDetailView(taskID: task.id)
                        } label: {
                            TaskCardView(task: task)
                        }
                        .swipeActions(edge: .trailing) {
                            if task.status == .queued {
                                Button("取消") {
                                    Task { await viewModel.cancelTask(task) }
                                }
                                .tint(.orange)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    await viewModel.loadTasks()
                }
            }
            .navigationTitle("任务列表")
        }
        .task {
            await viewModel.loadTasks()
        }
    }
}

// 任务卡片视图
struct TaskCardView: View {
    let task: Task

    var body: some View {
        HStack(spacing: 12) {
            // 状态图标
            statusIcon
                .font(.system(size: 28))
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Image(systemName: "desktopcomputer")
                        .font(.caption2)
                    Text(task.device_id)
                        .font(.caption)
                        .lineLimit(1)

                    Spacer()

                    Text(task.created_at, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var statusIcon: some View {
        Group {
            switch task.status {
            case .queued:   Image(systemName: "hourglass").foregroundColor(.orange)
            case .running:  ProgressView()
            case .completed: Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            case .failed:   Image(systemName: "xmark.circle.fill").foregroundColor(.red)
            case .cancelled: Image(systemName: "slash.circle.fill").foregroundColor(.gray)
            }
        }
    }
}
