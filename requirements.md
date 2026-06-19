# Mobile Claude Controller
## Project Overview
Build an iOS application that can remotely control Claude Code instances running on macOS and Windows machines.
The user should be able to:
View all registered computers
Send tasks to Claude Code
Monitor execution progress in real time
Review logs and code changes
Receive completion notifications
Manage multiple devices
The system consists of three components:
iOS Client
Agent Service (Mac/Windows)
Relay Server

# Architecture
iPhone App
    │
    │ HTTPS/WebSocket
    ▼
Relay Server
    │
    │ WebSocket
    ▼
Agent Service
    │
    ▼
Claude Code CLI

# Functional Requirements
## FR-001 Device Management
### Description
Users can register and manage multiple computers.
### Features
Device registration
Device rename
Device removal
Online/offline status
Last seen timestamp
### Device Object
{
  "id": "device-001",
  "name": "MacBook Pro",
  "platform": "macos",
  "status": "online",
  "version": "1.0.0",
  "last_seen": "2026-06-19T10:00:00Z"
}

## FR-002 Task Creation
### Description
Users can create Claude Code tasks from iPhone.
### Input Fields
Task Title
Prompt
Target Device
Working Directory
Permission Mode
### Example
Refactor authentication module.

Requirements:
- Add JWT middleware
- Improve error handling
- Run tests after completion
### Task Object
{
  "id": "task-001",
  "title": "Refactor Auth",
  "prompt": "...",
  "device_id": "device-001",
  "working_directory": "/Users/dev/project",
  "status": "queued"
}

## FR-003 Task Queue
### Description
Each device maintains a task queue.
### States
queued
running
completed
failed
cancelled
### Rules
One active task per device
FIFO execution
User can cancel queued tasks

## FR-004 Real-Time Logs
### Description
Display Claude execution logs in real time.
### Example
Analyzing repository...
Reading auth.ts
Updating middleware...
Running tests...
### Requirements
Stream logs through WebSocket
Auto-scroll enabled
Store logs in database

## FR-005 Task Results
### Description
Display final execution results.
### Result Types
#### Success
{
  "status": "completed",
  "summary": "Authentication module updated",
  "files_changed": 5
}
#### Failure
{
  "status": "failed",
  "error": "npm test failed"
}

## FR-006 File Change Summary
### Description
Show changed files after task completion.
### Example
{
  "files": [
    "src/auth.ts",
    "src/middleware.ts",
    "src/routes.ts"
  ]
}

## FR-007 Push Notifications
### Description
Notify user when task completes.
### Events
Task completed
Task failed
Device offline
Device online

# Agent Service Requirements
## Overview
Agent runs continuously on macOS or Windows.
Responsibilities:
Receive tasks
Launch Claude Code
Stream logs
Return results

## Agent Modules
### Task Receiver
Receives tasks from Relay Server.
### Claude Executor
Executes Claude Code.
Example:
claude
or
claude --print
depending on installed version.
### Log Streamer
Streams stdout and stderr.
### Result Collector
Collects:
logs
file changes
exit code
summary

# Security Requirements
## SR-001 Authentication
All requests require JWT token.

## SR-002 Device Ownership
A device belongs to exactly one account.

## SR-003 Encrypted Transport
Use HTTPS and WSS only.

## SR-004 Dangerous Commands
Agent must reject:
rm -rf /
format disk
shutdown system
Maintain blacklist configuration.

# Relay Server Requirements
## Responsibilities
Authentication
Device registry
Task routing
WebSocket relay
Notification dispatch

## API Endpoints
### Login
POST /api/auth/login
### List Devices
GET /api/devices
### Create Task
POST /api/tasks
### Get Task
GET /api/tasks/{id}
### Cancel Task
POST /api/tasks/{id}/cancel

# Database Schema
## Users
users
Fields:
id
email
password_hash
created_at

## Devices
devices
Fields:
id
user_id
name
platform
status
last_seen
created_at

## Tasks
tasks
Fields:
id
user_id
device_id
title
prompt
status
created_at
updated_at

## Task Logs
task_logs
Fields:
id
task_id
timestamp
message

# iOS Screens
## Screen 1
Device List
Features:
Device cards
Online indicator
Add device button

## Screen 2
Create Task
Fields:
Prompt
Device selector
Submit button

## Screen 3
Task List
Tabs:
Running
Completed
Failed

## Screen 4
Task Detail
Sections:
Status
Logs
File Changes
Summary

# MVP Scope
Version 1.0
Included:
Authentication
Device registration
Task creation
Claude execution
Real-time logs
Task results
Excluded:
Voice input
Team collaboration
Multi-user projects
GitHub integration
AI-generated task templates

# Recommended Technology Stack
## iOS
SwiftUI
Combine
WebSocket
## Relay Server
Node.js
NestJS
PostgreSQL
Redis
## Agent
Go
WebSocket Client
## Deployment
Docker
VPS
Cloudflare Tunnel

# Success Criteria
A user can:
Open iPhone app
Select a registered computer
Send a Claude Code task
Watch logs in real time
Receive completion notification
Review generated code changes
Project is considered successful when this workflow works reliably on both macOS and Windows.