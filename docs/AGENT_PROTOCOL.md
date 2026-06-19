# AGENT_PROTOCOL.md
# Agent Communication Protocol
Version: 1.0
Transport:
WebSocket Secure (WSS)
Encoding:
JSON

# Message Envelope
Every message must follow:
```
{
  "type": "message_type",
  "timestamp": "2026-06-19T12:00:00Z",
  "payload": {}
}
```

# Device Registration
## Client → Server
```
{
  "type": "register_device",
  "payload": {
    "device_id": "device-001",
    "name": "MacBook Pro",
    "platform": "macos",
    "agent_version": "1.0.0"
  }
}
```

## Server → Client
```
{
  "type": "register_success",
  "payload": {
    "status": "ok"
  }
}
```

# Heartbeat
## Agent → Server
```
{
  "type": "heartbeat",
  "payload": {
    "cpu": 15,
    "memory": 42,
    "active_task": false
  }
}
```

# Task Creation
## Server → Agent
```
{
  "type": "task_create",
  "payload": {
    "task_id": "task-001",
    "title": "Refactor Auth",
    "prompt": "Refactor authentication module",
    "working_directory": "/repo"
  }
}
```

# Task Accepted
## Agent → Server
```
{
  "type": "task_accepted",
  "payload": {
    "task_id": "task-001"
  }
}
```

# Task Started
```
{
  "type": "task_started",
  "payload": {
    "task_id": "task-001"
  }
}
```

# Log Event
```
{
  "type": "task_log",
  "payload": {
    "task_id": "task-001",
    "message": "Analyzing repository..."
  }
}
```

# Progress Event
```
{
  "type": "task_progress",
  "payload": {
    "task_id": "task-001",
    "percent": 45
  }
}
```

# File Change Event
```
{
  "type": "file_changed",
  "payload": {
    "task_id": "task-001",
    "file": "src/auth.ts"
  }
}
```

# Task Completed
```
{
  "type": "task_completed",
  "payload": {
    "task_id": "task-001",
    "summary": "Authentication module updated",
    "files_changed": 5,
    "duration_seconds": 140
  }
}
```

# Task Failed
```
{
  "type": "task_failed",
  "payload": {
    "task_id": "task-001",
    "error": "npm test failed"
  }
}
```

# Task Cancel
## iOS → Server
```
{
  "type": "cancel_task",
  "payload": {
    "task_id": "task-001"
  }
}
```

# Agent Capabilities
Agent reports capabilities on startup.
```
{
  "shell": true,
  "git": true,
  "claude_code": true,
  "docker": true,
  "node": true
}
```

# Security Requirements
## JWT Authentication
All requests require:
Authorization: Bearer <token>

## Message Validation
Every payload must validate:
schema
required fields
payload size

## Rate Limits
Device Registration:
10/minute
Heartbeat:
1/30 seconds
Task Events:
unlimited

# Error Codes
1001 Unauthorized
1002 Device Not Found
1003 Task Not Found
1004 Invalid Payload
1005 Agent Offline
1006 Task Already Running
1007 Execution Failed
1008 Permission Denied

# Protocol Compatibility
Major version changes:
1.x -> incompatible
Minor version changes:
1.0 -> 1.1 compatible
Agent and Server must reject incompatible versions.