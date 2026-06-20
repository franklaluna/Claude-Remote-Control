import SwiftUI

struct TaskListView: View {
    @StateObject private var viewModel = TaskListViewModel()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("", selection: $viewModel.selectedTab) {
                    ForEach(TaskListViewModel.TaskListTab.allCases, id: \.self) { tab in
                        Text(tab.displayName).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                if viewModel.isLoading {
                    ProgressView().padding()
                }

                if let error = viewModel.errorMessage {
                    Text(error).foregroundColor(.red).font(.caption).padding(.horizontal)
                }

                List {
                    ForEach(viewModel.filteredTasks) { task in
                        NavigationLink(destination: TaskDetailView(taskId: task.id)) {
                            TaskCardView(task: task)
                        }
                        .swipeActions(edge: .trailing) {
                            if task.status == .queued || task.status == .running {
                                Button("取消") {
                                    Task { await viewModel.cancelTask(task) }
                                }
                                .tint(.red)
                            }
                            if task.status == .completed || task.status == .failed || task.status == .cancelled {
                                Button("删除", role: .destructive) {
                                    Task { await viewModel.deleteTask(task) }
                                }
                                .tint(.red)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable { await viewModel.loadTasks() }
            }
            .navigationTitle("任务列表")
            .task { await viewModel.loadTasks() }
        }
    }
}

struct TaskCardView: View {
    let task: AppTask

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.title).font(.headline)
            Text(task.prompt).font(.caption).foregroundColor(.secondary).lineLimit(2)
            HStack {
                statusBadge
                Spacer()
                Text(task.created_at, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    var statusBadge: some View {
        Text(task.status.displayName)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.2))
            .foregroundColor(statusColor)
            .cornerRadius(4)
    }

    var statusColor: Color {
        switch task.status {
        case .queued: return .orange
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        }
    }
}
