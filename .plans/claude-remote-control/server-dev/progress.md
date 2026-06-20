# server-dev Progress Log

## 2026-06-20 — Tasks 4-7 (Server) COMPLETE

### Task 4: Cancel Running Tasks
- `tasks.service.ts:103-124` — cancel() accepts both `queued` and `running`. For running: sends cancel_task WS message to device, then updates status to cancelled.
- `ws.gateway.ts:191-201` — handleCancelTask() accepts both `queued` and `running`. Forwards cancel_task to Agent. Ownership check preserved.
- API contract: iOS still calls `POST /api/tasks/:id/cancel`. Server now rejects only completed/failed/cancelled (not running).

### Task 5: Task Timeout
- `create-task.dto.ts:27-31` — timeout_minutes: optional, @IsInt, @Min(5), @Max(120).
- `types/index.ts:143` — WsTaskCreatePayload includes timeout_minutes?: number.
- `ws.gateway.ts:215-219` — sendTaskCreate() accepts optional timeoutMinutes, conditionally includes in task_create payload.
- `tasks.service.ts:218` — tryDispatchNext() passes timeout_minutes through to sendTaskCreate().
- API contract: task_create WS message now carries `timeout_minutes` (number, optional). Agent defaults to 30 if absent. No DB storage needed.

### Task 6: Continue in Same Task
- `types/index.ts:87` — 'task_continue' added to WsMessageType union.
- `types/index.ts:148-152` — WsTaskContinuePayload { task_id, prompt, working_directory }.
- `ws.gateway.ts:221-223` — sendTaskContinue(deviceId, taskId, prompt, workingDirectory) method.
- `tasks.service.ts:154-178` — continueTask() reworked entirely:
  - Blocks queued/cancelled status.
  - Appends log entry: `追问: ${followUpPrompt}`.
  - Resets status to running.
  - Sends task_continue WS message to Agent (same task_id, same working_directory).
  - No new task row created.
- API contract: `POST /api/tasks/:id/continue { prompt }` still works. Server sends `task_continue` WS message. Agent should parse type 'task_continue' and launch new Claude process in same working_directory.

### Task 7: Delete Task
- `types/index.ts:276-279` — DeleteTaskResponse { ok: boolean }.
- `tasks.controller.ts:65-71` — DELETE /api/tasks/:id (JWT auth guard).
- `tasks.service.ts:180-192` — delete():
  - Only allows completed/failed/cancelled tasks.
  - Verifies ownership.
  - Prisma cascade handles log deletion.
  - Returns { ok: true }.
- API contract: `DELETE /api/tasks/:id` — 404 if not owner, 400 if active, 200 { ok: true } on success.

### Files Modified
| File | Tasks |
|------|-------|
| server/src/modules/tasks/tasks.service.ts | 4, 5, 6, 7 |
| server/src/common/ws.gateway.ts | 4, 5, 6 |
| server/src/types/index.ts | 5, 6, 7 |
| server/src/modules/tasks/tasks.controller.ts | 7 |
| server/src/modules/tasks/dto/create-task.dto.ts | 5 |

### TypeScript Compilation
Zero new errors. Pre-existing `continue-task.dto.ts` strict mode warning (unrelated).
