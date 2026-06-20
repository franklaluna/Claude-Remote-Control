# Claude Remote Control — 6 Fixes Task Plan

版本: 1.1
日期: 2026-06-20
父项目: /Users/gyfan/claude/Claude-Remote-Control

## 问题列表

| # | 问题 | 涉及组件 | 优先级 |
|---|------|---------|--------|
| 1 | App 没有图标 | iOS | P1 |
| 2 | 没有退出登录按钮 | iOS | P1 |
| 3 | 无法手动中止运行中任务 | iOS + Server + Agent | P0 |
| 4 | 任务超时无限制 | iOS + Server + Agent | P0 |
| 5 | 追问应在本任务继续 | iOS + Server + Agent | P1 |
| 6 | 任务列表无法删除 | iOS + Server | P2 |

## 团队

| 角色 | 名称 | 负责 |
|------|------|------|
| Team Lead | team-lead | 协调、进度追踪、用户对齐 |
| iOS Developer | ios-dev | SwiftUI 所有变更 |
| Server Developer | server-dev | NestJS API + WebSocket |
| Agent Developer | agent-dev | Go Agent 变更 |
| Reviewer | reviewer | 代码审查 + 安全审计 |

## 任务依赖

```
Task-2 (App图标)     ─┐
Task-3 (退出登录)     ─┤
Task-4 (中止任务)     ─┼─→ Task-8 (Review)
Task-5 (超时限制)     ─┤
Task-6 (追问继续)     ─┤
Task-7 (删除任务)     ─┘
```

## 验收标准

1. 代码编译通过（iOS: Xcode build, Server: tsc, Agent: go build）
2. 功能行为符合描述
3. 不引入回归
4. 全部修复完成后由 reviewer 统一审查
