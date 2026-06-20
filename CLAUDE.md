# CLAUDE.md

## Git 提交规范

每当功能验证通过后，立即提交代码。提交信息使用中文，格式：`<类型>: <简短描述>`。

类型包括：feat（新功能）、fix（修复）、refactor（重构）、docs（文档）、chore（杂项）。

## 工作状态

始终保持工作状态，持续推动项目直到完成。不等待用户确认，遇到阻塞主动排查并推进。每个任务完成后立即检查下一个任务，不主动暂停。

使用 /loop 功能进行持续工作循环，自动监控团队进度、解决阻塞、推动任务完成。项目完成前不休眠。

## 部署基础设施

### Nginx 网关 (192.168.11.157)
所有外部流量通过此 nginx 代理到内网 192.168.2.x 网段。

### 可用服务
| 服务 | 内部地址 | 代理端口 |
|------|---------|---------|
| MySQL | 192.168.2.200:3306, .201:3306 | :3306 |
| Redis | 192.168.2.138:6379 | :6379 |
| Elasticsearch | 192.168.2.138:9200 | :9200 |
| Kafka | 192.168.2.200-202:9092 | :9092 |
| Nacos | 192.168.2.200:8845, .201:8846, .202:8847 | :8848 |

### K8s 集群 (二进制 v1.20.0)
- master: .17, .18, .19 | worker: .22, .23
- 跳板访问: `ssh -p 2217 root@192.168.11.157` → k8s-master01

### Relay Server 部署策略
- 数据库: MySQL (192.168.2.200:3306, 通过 nginx :3306 代理)。pg 和达梦不可用
- Redis: 192.168.2.138:6379
- 部署位置: k8s 集群 (Deployment + Service + Nginx stream 代理)
- WebSocket: Nginx 已支持 WebSocket 代理 (参考 5601 端口配置)

## 团队协作

### 团队控制面
- team-lead = 主会话，负责任务分解、进度追踪、用户对齐
- 全部开发工作通过队友 (Agent with team_name) 进行

### 团队名册

| 名称 | 角色 | 技术栈 |
|------|------|--------|
| ios-dev | iOS 开发者 | SwiftUI + Combine |
| server-dev | 服务端开发者 | NestJS + Prisma + MySQL |
| agent-dev | Agent 开发者 | Go |
| reviewer | 代码审查者 | 安全 + 质量审查 |

### 任务分配协议
- 大任务: 发送到对应队友，附带完整上下文（范围、验收标准、依赖文件）
- 跨组件任务: server-dev 为 primary，定义合同，ios-dev/agent-dev 实现各自部分
- 审查: 全部开发完成后由 reviewer 统一审查

### 状态检查
| 检查内容 | 方式 |
|----------|------|
| 总览 | TaskList |
| 个人进度 | .plans/claude-remote-control/{name}/progress.md |
| 详细调查 | .plans/claude-remote-control/{name}/findings.md |

### 文档索引
| 文档 | 路径 |
|------|------|
| 任务计划 | .plans/claude-remote-control/task_plan.md |
| 进度日志 | .plans/claude-remote-control/progress.md |
| 测试计划 | .plans/claude-remote-control/reviewer/test-plan.md |
