# ARCHITECTURE.md
# System Architecture
## Overview
The system consists of three independently deployable services.
┌─────────────────┐
│    iOS Client   │
└────────┬────────┘
         │
         │ HTTPS / WSS
         ▼
┌─────────────────┐
│   Relay Server  │
└────────┬────────┘
         │
         │ WSS
         ▼
┌─────────────────┐
│  Desktop Agent  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Claude Code    │
└─────────────────┘

# Design Principles
## Agent First
All code execution happens on the desktop machine.
The server never:
Reads source code
Executes shell commands
Stores repository files
The server only routes messages.

## Stateless Server
Relay Server should remain stateless whenever possible.
Store only:
Users
Devices
Tasks
Logs metadata
Never store:
Source code
Repository snapshots
Secrets

## Real-Time Communication
Primary protocol:
WebSocket
Fallback:
HTTPS Polling

# Component Responsibilities
## iOS Client
Responsibilities:
Authentication
Device management
Task creation
Log viewing
Push notifications
Must not:
Execute tasks
Store repository data

## Relay Server
Responsibilities:
Authentication
Device registry
Task routing
Event broadcasting
Notification dispatch
Must not:
Execute shell commands
Access repositories

## Desktop Agent
Responsibilities:
Maintain persistent connection
Receive tasks
Execute Claude Code
Capture logs
Report progress

# Agent Lifecycle
## Startup
Agent starts
Reads config
Loads authentication token
Opens WebSocket
Registers device
Starts heartbeat

## Heartbeat
Interval:
30 seconds
Payload:
{
  "device_id": "device-001",
  "cpu": 25,
  "memory": 48,
  "active_task": true
}

## Shutdown
Agent sends:
{
  "event": "agent_offline"
}
before exit.

# Task Execution Pipeline
## Step 1
Task received
## Step 2
Validate permissions
## Step 3
Create execution session
## Step 4
Launch Claude Code
## Step 5
Stream logs
## Step 6
Collect result
## Step 7
Upload summary
## Step 8
Close session

# Permission Model
## Read Only
Allowed:
Read files
Search code
Analyze repository
Denied:
File write
Shell execution

## Safe Edit
Allowed:
Modify files
Run tests
Denied:
Dangerous shell commands

## Full Access
Allowed:
Read files
Modify files
Execute shell commands
Requires explicit user approval.

# Failure Handling
## Agent Offline
Task remains queued.

## Network Lost
Agent continues execution.
Results are uploaded after reconnect.

## Claude Crash
Task status:
failed
Error report generated.

# Future Architecture
Version 2.0
Add:
Multiple agents
Team workspaces
Shared task queues
GitHub integration
GitLab integration
Self-hosted mode
Local network mode