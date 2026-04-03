# Pi Session Monitor - Design Specification

## Overview

A macOS menu bar application that monitors and controls multiple pi coding agent terminal sessions, providing real-time visibility into session states, model usage, and pending approvals across different projects.

## Goals

- Track multiple pi terminal sessions grouped by project
- View real-time session status (idle, thinking, executing, needs_approval)
- See model configuration and last activity for each session
- Approve/reject tool calls remotely from the menu bar
- Send messages and abort operations on specific sessions
- Receive native macOS notifications when approval is needed

## Non-Goals

- Cross-machine session monitoring (local only)
- Historical session analytics or persistence
- Complex multi-step workflows from the menu bar
- Support for non-macOS platforms (initially)

## Architecture

### System Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    macOS Menu Bar App (SwiftUI)                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  • Proyecto A (~/docs/GitHub/proyecto-a)                 │  │
│  │    ├─ 🔴 Terminal 1 - "Refactor auth"                    │  │
│  │    │   Modelo: Claude-4, Thinking: medium               │  │
│  │    │   "Revisando código..." → [Aprobar] [Cancelar]     │  │
│  │    └─ 🟢 Terminal 2 - "Tests"                           │  │
│  │        Modelo: GPT-4o, Idle                             │  │
│  │  • Proyecto B (~/docs/GitHub/proyecto-b)                 │  │
│  │    └─ 🟡 Terminal 1 - "Bug fix"                         │  │
│  │        Esperando aprobación: rm -rf ...                 │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ HTTP/WebSocket
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
   ┌──────────┐         ┌──────────┐         ┌──────────┐
   │ Terminal │         │ Terminal │         │ Terminal │
   │  :8081   │         │  :8082   │         │  :8083   │
   └────┬─────┘         └────┬─────┘         └────┬─────┘
        │                     │                     │
        └─────────────────────┴─────────────────────┘
                              │
                    ┌─────────┴─────────┐
                    │ session-servers.json│
                    │ (port registry)     │
                    └───────────────────┘
```

### Components

#### 1. Pi Extension (`pi-session-monitor.ts`)

**Location:** `~/.pi/agent/extensions/pi-session-monitor.ts`

**Responsibilities:**
- Start HTTP/WebSocket server on random available port when session starts
- Register server port in `~/.pi/agent/.session-servers.json`
- Capture session events (model_select, turn_start, turn_end, tool_call, message_update)
- Intercept tool calls requiring approval and pause them
- Expose REST API and WebSocket endpoint for external control
- Clean up registry entry on session shutdown

**Server Endpoints:**

| Method | Path | Description | Request Body | Response |
|--------|------|-------------|--------------|----------|
| GET | `/status` | Get current session status | - | `SessionStatus` |
| POST | `/message` | Send message to session | `{ "content": string }` | `{ "success": boolean }` |
| POST | `/abort` | Abort current operation | - | `{ "success": boolean }` |
| POST | `/approve` | Approve pending tool call | `{ "toolCallId": string }` | `{ "success": boolean }` |
| POST | `/reject` | Reject pending tool call | `{ "toolCallId": string, "reason": string }` | `{ "success": boolean }` |
| WS | `/events` | Real-time event stream | - | `ServerEvent` (streaming) |

**SessionStatus Schema:**

```typescript
interface SessionStatus {
  sessionId: string;
  sessionName: string | null;
  cwd: string;
  port: number;
  token: string;  // Auth token for this session
  model: {
    provider: string;
    id: string;
    thinkingLevel: string;
  };
  state: "idle" | "thinking" | "executing" | "needs_approval";
  lastActivity: number;  // Unix timestamp (ms)
  lastMessage: string;   // First 100 chars of last message
  pendingApproval: {
    toolCallId: string;
    toolName: string;
    description: string;  // Human-readable description
    timestamp: number;
  } | null;
}
```

**ServerEvent Schema:**

```typescript
type ServerEvent =
  | { type: "status_update"; status: SessionStatus }
  | { type: "model_changed"; model: SessionStatus["model"] }
  | { type: "state_changed"; state: SessionStatus["state"] }
  | { type: "approval_needed"; toolCall: SessionStatus["pendingApproval"] }
  | { type: "approval_resolved"; toolCallId: string; approved: boolean }
  | { type: "message_received"; preview: string }
  | { type: "heartbeat" };  // Every 30s to keep connection alive
```

**Approval Flow:**

1. Extension intercepts `tool_call` event via `pi.on("tool_call", ...)`
2. If tool requires approval (destructive operations, or flagged by model):
   - Store tool call details in `pendingApproval`
   - Return `{ block: true }` to pause execution
   - Emit `approval_needed` event via WebSocket
3. Wait for POST /approve or /reject
4. On approve: execute original tool call and return result
5. On reject: return error result to LLM
6. Clear `pendingApproval` and emit `approval_resolved` event

**Registry Format (`~/.pi/agent/.session-servers.json`):**

```json
{
  "version": 1,
  "servers": [
    {
      "sessionId": "uuid-v4-string",
      "port": 8081,
      "cwd": "/Users/nacho/docs/GitHub/proyecto-a",
      "token": "random-32-char-token",
      "startedAt": 1712345678901
    }
  ]
}
```

#### 2. macOS Menu Bar App (Swift/SwiftUI)

**Project Structure:**

```
PiSessionMonitor/
├── PiSessionMonitor/
│   ├── PiSessionMonitorApp.swift
│   ├── MenuBarController.swift
│   ├── SessionStore.swift
│   ├── SessionMonitor.swift
│   ├── Network/
│   │   ├── APIClient.swift
│   │   └── WebSocketClient.swift
│   ├── Models/
│   │   └── SessionModels.swift
│   └── Views/
│       ├── MenuContentView.swift
│       ├── ProjectGroupView.swift
│       ├── TerminalRowView.swift
│       └── ActionPanelView.swift
└── PiSessionMonitor.xcodeproj
```

**Key Classes:**

- `MenuBarController`: Manages NSStatusItem, menu popup, badge updates
- `SessionStore`: Observable object holding all session data, groups by project
- `SessionMonitor`: Manages WebSocket connections to individual sessions
- `APIClient`: HTTP client for REST endpoints

**UI Components:**

1. **Menu Bar Icon:**
   - Default: pi logo or terminal icon
   - Badge: Red circle with count of sessions needing approval
   - Animation: Subtle pulse when new approval needed

2. **Menu Content:**
   - Scrollable list of projects (grouped by cwd)
   - Each project expandable/collapsible
   - Terminal rows show: status indicator, name, model, state
   - Quick action buttons appear on hover/select

3. **Action Panel (appears when session selected):**
   - Text field to send message
   - [Abort] button (when thinking/executing)
   - [Approve] / [Reject] buttons (when needs_approval)
   - [Focus Terminal] button (brings terminal to front)

**State Indicators:**

| State | Icon | Color | Description |
|-------|------|-------|-------------|
| idle | ● | Green (#10B981) | Ready for input |
| thinking | ◐ | Yellow (#F59E0B) | LLM generating response |
| executing | ◑ | Blue (#3B82F6) | Executing tools |
| needs_approval | ⏸ | Red (#EF4444) | Waiting for user approval |

**Notifications:**

- Trigger: Session enters `needs_approval` state
- Title: "Pi Approval Needed"
- Body: "{toolName} in {sessionName} ({project})"
- Actions: [Approve], [Reject], [View]

### Discovery Protocol

1. App reads `~/.pi/agent/.session-servers.json` every 2 seconds
2. For each server entry not currently connected:
   - Attempt HTTP GET /status with auth token
   - If successful, establish WebSocket connection
   - Add to `SessionStore.sessions`
3. For each connected server not in registry:
   - Close WebSocket connection
   - Remove from `SessionStore.sessions`
4. Group sessions by `cwd` for project hierarchy

### Security Considerations

- All communication is localhost-only (127.0.0.1)
- Each session generates random 32-character auth token
- Token must be provided in `Authorization: Bearer {token}` header
- Registry file has permissions 0600 (owner read/write only)
- No CORS headers needed (localhost-only)

### Error Handling

**Extension side:**
- Port binding failure: Retry with different port (max 10 attempts)
- Registry write failure: Log error, continue without registration
- WebSocket disconnection: Clean up client, continue accepting new connections

**App side:**
- Server unreachable: Mark session as "disconnected", retry every 5s
- Invalid auth: Remove from registry (stale entry)
- Network timeout: Show "reconnecting..." indicator

### Cleanup

**On session shutdown:**
1. Close all WebSocket connections
2. Stop HTTP server
3. Remove entry from `session-servers.json`
4. Cancel any pending approvals with error

**On app quit:**
1. Close all WebSocket connections gracefully
2. Clear notification badges

## Implementation Phases

### Phase 1: Extension Core
- HTTP server with /status endpoint
- Registry read/write
- Basic event capture (model, state)

### Phase 2: Extension Approval Flow
- Tool call interception
- Approval pause/resume logic
- WebSocket event streaming

### Phase 3: macOS App Core
- Menu bar UI shell
- Registry polling
- HTTP client for /status

### Phase 4: macOS App Full Feature
- WebSocket real-time updates
- Action panel (message, abort, approve)
- Notifications

### Phase 5: Polish
- Error handling edge cases
- UI animations
- Code signing for distribution

## Open Questions

None - all requirements confirmed with user.

## Appendix

### Session File Location

Sessions are stored at `~/.pi/agent/sessions/` by default. The extension does not interact directly with session files; it uses pi's ExtensionAPI to get session information.

### Port Range

Server ports are selected randomly from range 10000-65535 to avoid conflicts with well-known services.

### Rate Limiting

No rate limiting needed for localhost communication.

### WebSocket Protocol

- Text frames with JSON payloads
- Ping/pong every 30 seconds
- Automatic reconnection with exponential backoff (max 30s)
