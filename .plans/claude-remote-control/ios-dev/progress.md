# iOS Dev Progress

## 2026-06-20

### Task 2: App Icon -- complete
- Created `/ios/Claude-Remote-Control/Assets.xcassets/AppIcon.appiconset/` with `Contents.json`
- Generated 11 PNG icon sizes from 20pt to 1024pt using Python Pillow (gradient background + desktop/arrow motif)
- Covers iPhone (20/29/40/60pt @2x,@3x), iPad (20/29/40/76/83.5pt @2x), App Store (1024pt)

### Task 3: Logout Button -- complete
- Created `Views/SettingsView.swift` with user email display, server address, "退出登录" button with confirmation alert
- Updated `ContentView.swift` -- added 4th tab "设置" (gearshape) with `onLogout` callback
- Logout: clears `auth_token` from UserDefaults, calls `APIService.shared.setToken(nil)`, resets token state to show LoginView

### Task 4 (iOS): Cancel Running Task -- complete
- `TaskListView.swift`: swipe cancel now shown for `.queued` AND `.running`
- `TaskDetailView.swift`: "取消任务" button in header when task is queued/running
- `TaskDetailViewModel.swift`: added `cancelTask()` method

### Task 5 (iOS): Timeout Config -- complete
- `CreateTaskView.swift`: timeout Picker below permission picker (15/30/60/120 min)
- `CreateTaskViewModel.swift`: `timeoutMinutes` field (default 30), passed to request, reset on form clear
- `Models/APIResponses.swift`: `timeout_minutes: Int?` added to `CreateTaskRequest`

### Task 6 (iOS): Continue in Same Task -- complete
- `TaskDetailViewModel.swift`: `sendContinue()` inserts cycle separator marker, resets status to `.running`, clears result. Removed `newTaskCreated` flag. Added `isCycleSeparator(at:)` and `cancelTask()`
- `TaskDetailView.swift`: renders "新的追问" separator between execution cycles

### Task 7 (iOS): Delete Task -- complete
- `TaskListView.swift`: delete swipe action for completed/failed/cancelled tasks
- `APIService.swift`: `deleteTask(id:)` sending DELETE to `tasks/{id}`
- `TaskListViewModel.swift`: `deleteTask()` removes from local array on success
- `Models/APIResponses.swift`: `DeleteTaskResponse` struct
