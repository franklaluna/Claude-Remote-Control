# Database Schema — Claude Remote Control

> 数据库: PostgreSQL | ORM: Prisma | 版本: 1.0.0

---

## ER 图

```
┌──────────────────┐       ┌──────────────────┐       ┌──────────────────┐
│     users         │       │     devices       │       │     tasks         │
├──────────────────┤       ├──────────────────┤       ├──────────────────┤
│ id (PK, UUID)    │──┐    │ id (PK, UUID)    │──┐    │ id (PK, UUID)    │
│ email (UNIQUE)   │  │    │ user_id (FK)     │  │    │ user_id (FK)     │
│ password_hash    │  │    │ name             │  │    │ device_id (FK)   │
│ created_at       │  │    │ platform         │  │    │ title            │
└──────────────────┘  │    │ status           │  │    │ prompt           │
                      │    │ version          │  │    │ working_directory│
                      ├───►│ last_seen        │  │    │ permission_mode  │
                      │    │ created_at       │  │    │ status           │
                      │    └──────────────────┘  │    │ created_at       │
                      │                          │    │ updated_at       │
                      │                          │    └──────────────────┘
                      │                          │              │
                      │                          │              │ 1:N
                      │                          │              ▼
                      │                          │    ┌──────────────────┐
                      │                          │    │   task_logs       │
                      │                          │    ├──────────────────┤
                      │                          │    │ id (PK, UUID)    │
                      │                          │    │ task_id (FK)     │
                      │                          └───►│ timestamp        │
                      │                               │ message          │
                      │                               └──────────────────┘
                      │
                      └──────────────────────────────┐
                                                     ▼
                                           (user owns both devices and tasks)
```

---

## 表定义

### users — 用户账号

| 列名          | 类型      | 约束              | 说明           |
|---------------|-----------|-------------------|----------------|
| id            | UUID      | PK, DEFAULT uuid()| 主键           |
| email         | VARCHAR   | UNIQUE, NOT NULL  | 登录邮箱       |
| password_hash | VARCHAR   | NOT NULL          | bcrypt 哈希    |
| created_at    | TIMESTAMP | DEFAULT now()     | 注册时间       |

### devices — 注册设备

| 列名       | 类型      | 约束              | 说明                          |
|------------|-----------|-------------------|-------------------------------|
| id         | UUID      | PK, DEFAULT uuid()| 主键                          |
| user_id    | UUID      | FK → users.id, NOT NULL | 所属用户                 |
| name       | VARCHAR   | NOT NULL          | 设备名称 (e.g. "MacBook Pro") |
| platform   | VARCHAR   | NOT NULL          | "macos" 或 "windows"          |
| status     | VARCHAR   | DEFAULT 'offline' | "online" 或 "offline"         |
| version    | VARCHAR   | DEFAULT '1.0.0'   | Agent 版本                    |
| last_seen  | TIMESTAMP | DEFAULT now()     | 最后在线时间                  |
| created_at | TIMESTAMP | DEFAULT now()     | 注册时间                      |

**索引:** user_id (隐式，Prisma FK 自动创建)
**Cascade:** 删除用户时级联删除其所有设备

### tasks — 执行任务

| 列名              | 类型      | 约束                          | 说明                                        |
|-------------------|-----------|-------------------------------|---------------------------------------------|
| id                | UUID      | PK, DEFAULT uuid()            | 主键                                        |
| user_id           | UUID      | FK → users.id, NOT NULL       | 创建者                                      |
| device_id         | UUID      | FK → devices.id, NOT NULL     | 目标设备                                    |
| title             | VARCHAR   | NOT NULL                      | 任务标题                                    |
| prompt            | TEXT      | NOT NULL                      | Claude Code 提示词                          |
| working_directory | VARCHAR   | DEFAULT ''                    | 工作目录路径                                |
| permission_mode   | VARCHAR   | DEFAULT 'default'             | default / acceptEdits / bypassPermissions / plan |
| status            | VARCHAR   | DEFAULT 'queued'              | queued / running / completed / failed / cancelled |
| created_at        | TIMESTAMP | DEFAULT now()                 | 创建时间                                    |
| updated_at        | TIMESTAMP | auto-update                   | 最后更新时间                                |

**索引:** user_id, device_id (隐式 FK), status
**Cascade:** 删除用户或设备时级联删除关联任务

### task_logs — 任务执行日志

| 列名      | 类型      | 约束                      | 说明           |
|-----------|-----------|---------------------------|----------------|
| id        | UUID      | PK, DEFAULT uuid()        | 主键           |
| task_id   | UUID      | FK → tasks.id, NOT NULL   | 关联任务       |
| timestamp | TIMESTAMP | DEFAULT now()             | 日志时间       |
| message   | TEXT      | NOT NULL                  | 日志内容       |

**索引:** task_id, timestamp
**Cascade:** 删除任务时级联删除所有日志

---

## 迁移命令

```bash
# 初始化数据库（首次）
cd server
npx prisma migrate dev --name init

# 后续迁移
npx prisma migrate dev --name <描述>

# 生产环境
npx prisma migrate deploy

# 查看数据库
npx prisma studio
```

## 状态流转

```
queued ──► running ──► completed
  │                     │
  └──► cancelled        └──► failed
```

- 只有 `queued` 状态的任务可以被取消
- 每个设备同时最多执行 1 个 `running` 任务
- `running` → `completed`/`failed` 由 Agent 回报状态驱动
