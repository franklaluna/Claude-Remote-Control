# 集成测试计划 — Claude Remote Control

版本: 1.0
日期: 2026-06-19
测试范围: E2E 流程、WebSocket 可靠性、任务队列、边界条件

---

## 1. 端到端流程测试

### TC-1.1: 完整 Happy Path — 用户发送任务到查看结果

**前提**: Server 运行，1 个 Agent 在线，iOS App 连接

| 步骤 | 操作 | 预期结果 |
|------|------|----------|
| 1 | iOS App 启动，登录（email + password） | 返回 token，进入设备列表 |
| 2 | 设备列表显示 Agent 在线 | Device card 有绿色 online 指示灯 |
| 3 | 点击创建设备，输入名称和平台 | 设备列表新增一条记录 |
| 4 | 进入创建任务页面 | 自动加载可用设备列表 |
| 5 | 输入 title="测试任务"，prompt="列出当前目录文件"，选择在线设备 | 表单验证通过 |
| 6 | 提交任务 | 返回 task status=queued，跳转到任务列表 |
| 7 | 任务列表显示该任务状态变为 running | 实时状态更新 |
| 8 | 点击进入任务详情 | 实时日志逐行滚动显示 |
| 9 | 任务完成 | 状态变为 completed，显示 summary 和 files_changed |
| 10 | 查看 completion notification | iOS 收到推送/本地通知 |

**验证规则**:
- token 存储在 iOS 内存中，后续请求自动携带
- WebSocket 日志流无丢行（对比 DB task_logs 记录数）
- 任务从 queued → running → completed 状态转换正确

### TC-1.2: 任务失败流程

| 步骤 | 操作 | 预期结果 |
|------|------|----------|
| 1 | 发送 prompt 指向不存在的目录 | Agent 返回 status=failed |
| 2 | 发送 prompt 执行不存在的命令 | Agent 返回 error 信息 |
| 3 | 查看任务详情 | 日志显示错误输出（stderr），状态为 failed |
| 4 | 查看 failure 通知 | iOS 收到失败通知 |

### TC-1.3: Agent 离线时创建任务

| 步骤 | 操作 | 预期结果 |
|------|------|----------|
| 1 | 停止 Agent 进程 | 设备列表状态变为 offline |
| 2 | 向该设备创建任务 | 任务创建成功 (status=queued) |
| 3 | 启动 Agent 重连 | Agent 收到排队任务并开始执行 |
| 4 | 任务完成 | 正常返回结果 |

---

## 2. WebSocket 断线重连测试

### TC-2.1: Agent 网络中断恢复

| 步骤 | 操作 | 预期结果 |
|------|------|----------|
| 1 | Agent 正常运行中 | WebSocket 连接稳定 |
| 2 | 断开 Agent 网络 (iptables / 拔网线) | Agent WS 连接断开 |
| 3 | 等待 10 秒 | Agent 开始指数退避重连（log 应显示） |
| 4 | 恢复网络 | Agent 在退避周期后重连成功 |
| 5 | 重连后发送认证消息 | 认证成功，设备状态恢复为 online |
| 6 | 发送新任务 | 任务正常接收和执行 |

**验证规则**:
- 退避序列: ~1s, ~2s, ~4s, ~8s, ~16s... 上限 2min
- 每次重连有 ±25% 随机抖动
- 重连期间心跳停止，重连后恢复
- 重连成功后 service 端 device status 更新为 online

### TC-2.2: iOS 客户端网络切换

| 步骤 | 操作 | 预期结果 |
|------|------|----------|
| 1 | iOS App 连接 WebSocket | 正在查看任务详情日志 |
| 2 | 切换 Wi-Fi → 蜂窝数据 | WebSocket 连接断开 |
| 3 | 等待 5 秒 | App 应自动重连 |
| 4 | 重连后日志继续显示 | 无日志丢失（gap-less） |

**验证规则**:
- 重连后 WebSocket 认证自动完成
- 断线期间的日志应在重连后补拉（或标记缺失）

### TC-2.3: Server 重启时的行为

| 步骤 | 操作 | 预期结果 |
|------|------|----------|
| 1 | Agent 和 iOS 均连接 | 正常运行 |
| 2 | 重启 Relay Server | 所有 WebSocket 连接断开 |
| 3 | Server 启动完成 | Agent 和 iOS 均重连成功 |
| 4 | 发送任务 | 正常执行 |
| 5 | 检查正在执行的任务 | 状态不变（Agent 端继续执行，结果在重连后发送） |

---

## 3. 任务队列 FIFO 和取消测试

### TC-3.1: FIFO 顺序执行

| 步骤 | 操作 | 预期结果 |
|------|------|----------|
| 1 | 向同一设备快速创建 3 个任务 (A, B, C) | 3 个任务状态均为 queued |
| 2 | 等待 Agent 处理 | A 先变为 running，B/C 保持 queued |
| 3 | A 完成 | A → completed，B → running |
| 4 | B 完成 | B → completed，C → running |
| 5 | C 完成 | C → completed |

**验证规则**:
- 同一设备同时只有 1 个 running 任务
- 完成顺序 = 创建顺序

### TC-3.2: 取消排队任务

| 步骤 | 操作 | 预期结果 |
|------|------|----------|
| 1 | 创建任务 A 并在 running | — |
| 2 | 创建任务 B (queued) | — |
| 3 | 取消任务 B | POST /api/tasks/b-id/cancel 返回 status=cancelled |
| 4 | A 完成后 | 下一个如果有 C 则执行 C，跳过 B |
| 5 | 尝试取消 running 任务 A | 返回 400 "只能取消排队中的任务" |

**验证规则**:
- queued 任务可以取消
- running/completed/failed 任务不可取消
- 取消的任务不计入队列执行

### TC-3.3: 多设备独立队列

| 步骤 | 操作 | 预期结果 |
|------|------|----------|
| 1 | Device-1 有 2 个任务，Device-2 有 1 个任务 | — |
| 2 | 启动两个 Agent 分别连接 | Device-1 和 Device-2 并行执行各自任务 |
| 3 | 等待完成 | 两个设备互不影响，各自按 FIFO 顺序 |

---

## 4. 边界条件测试

### TC-4.1: 空 prompt

| 输入 | prompt="" |
|------|-----------|
| 预期 | API 返回 400 Bad Request，错误消息明确指示 prompt 不能为空 |
| 验证层 | Server DTO validation + Agent security.Check |

### TC-4.2: 超长 prompt

| 输入 | prompt = 100,000 字符的随机文本 |
|------|-----------|
| 预期 | API 返回 400 或数据库截断 warning |
| 验证层 | Server DTO @MaxLength(10000) 或 DB prompt 字段限制 |

### TC-4.3: 无效设备 ID

| 输入 | POST /api/tasks 使用不存在的 device_id |
|------|-----------|
| 预期 | API 返回 404 或 400 "设备不存在" + 明确错误消息 |
| 验证层 | tasks.service.ts create() 中校验 device_id 存在性 |

### TC-4.4: 无 Authorization header

| 输入 | 不携带 Authorization header 访问受保护端点 |
|------|-----------|
| 预期 | 返回 401 "未提供认证 Token" |
| 验证层 | JwtAuthGuard |

### TC-4.5: 过期/无效 JWT

| 输入 | Authorization: Bearer <expired_or_fake_token> |
|------|-----------|
| 预期 | 返回 401 "Token 无效或已过期" |
| 验证层 | JwtAuthGuard（需 JWT 实现后） |

### TC-4.6: 特殊字符 prompt

| 输入 | prompt 包含: `<script>alert(1)</script>`, 空字节 `\0`, emoji, 全角字符 |
|------|-----------|
| 预期 | 正常执行或安全拒绝，无 crash，无 XSS 在 iOS 日志页面渲染 |
| 验证层 | 日志显示转义后的内容，非执行的 HTML |

### TC-4.7: 并发任务创建

| 输入 | 同时发送 10 个 POST /api/tasks 请求 |
|------|-----------|
| 预期 | 10 个任务均创建成功，status=queued，无数据库锁死超时 |
| 验证层 | Prisma 连接池 + 数据库事务隔离 |

### TC-4.8: Agent 执行危险命令请求

| 输入 | prompt="请帮我执行 rm -rf /" 或 "format C:" |
|------|-----------|
| 预期 | Agent 的 security.Check() 拒绝执行，返回 status=rejected，reason 包含拒绝原因 |
| 验证层 | agent/internal/security/filter.go |

### TC-4.9: Server 数据库不可用

| 输入 | Agent 正常连接，Server PostgreSQL 停止 |
|------|-----------|
| 预期 | API 返回 500 error，Agent WebSocket 保持连接（无数据库操作时不中断） |
| 验证层 | PrismaService 错误处理 |

### TC-4.10: 空日志流

| 输入 | Claude Code 执行但无 stdout 输出（例如简单命令） |
|------|-----------|
| 预期 | 任务正常标记 completed，logs 数组为空，summary 为默认文本 |

---

## 测试环境要求

| 组件 | 配置 |
|------|------|
| Relay Server | localhost:3000, PostgreSQL + Redis |
| Agent (macOS) | agent-config.json 指向 localhost:3000 |
| Agent (Windows) | 另一台机器，同上 |
| iOS | 模拟器 (Xcode) 或真机，API baseURL 指向 localhost |

## 自动化建议

| 测试类别 | 工具 | 优先级 |
|----------|------|--------|
| API 端点测试 | Jest + supertest (NestJS 内置) | P0 |
| WebSocket 测试 | Jest + ws 库 | P0 |
| Agent 单元测试 | Go testing | P1 |
| E2E 流程 | Playwright 或自定义脚本 | P1 |
| iOS UI 测试 | XCUITest | P2 |
