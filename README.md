# Pi Session Monitor

Real-time monitoring and control of pi coding agent sessions from your macOS menu bar.

## Features

- **Session Overview**: See all active pi sessions grouped by project
- **Live Status**: Monitor state (idle, thinking, executing, needs approval) in real-time via WebSocket
- **Remote Control**:
  - Approve or reject dangerous tool calls directly from the menu bar
  - Send messages to specific sessions without switching terminals
  - Abort running operations
  - Focus terminal window with one click
- **Native Notifications**: Get notified when a session needs your approval
- **Menu Bar Badge**: Visual indicator shows count of pending approvals

## Installation

### Quick Install (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/yourusername/pi-session-monitor/main/install.sh | bash
```

### Manual Install

#### 1. Extension

```bash
# Copy extension to pi's extensions directory
cp -r extension ~/.pi/agent/extensions/pi-session-monitor

# Install dependencies
cd ~/.pi/agent/extensions/pi-session-monitor
npm install
```

#### 2. macOS App

1. Open Xcode
2. Create new macOS App project named "PiSessionMonitor"
3. Replace the generated files with the contents from `macos-app/PiSessionMonitor/`
4. Build and run (Cmd+R)
5. The app will appear in your menu bar as a terminal icon

## Usage

1. Start pi in one or more terminals
2. The extension automatically registers each session in `~/.pi/agent/.session-servers.json`
3. Open the menu bar app to see all sessions grouped by project
4. Click a session to:
   - View its current state and model
   - Send messages (queues as steering message)
   - Abort running operations
   - Approve/reject pending tool calls
   - Focus the terminal window

## Architecture

```
┌─────────────────┐      WebSocket       ┌──────────────────┐
│  macOS Menu Bar │◄────────────────────►│  Pi Extension    │
│     App         │   (per session)      │  (per terminal)  │
└─────────────────┘                      └──────────────────┘
         │                                          │
         └──────────────┬───────────────────────────┘
                        │
         ~/.pi/agent/.session-servers.json
              (session registry)
```

### How It Works

1. When pi starts with the extension loaded, it:
   - Starts an HTTP/WebSocket server on a random port
   - Registers the session in `~/.pi/agent/.session-servers.json`
   - Captures events (model changes, turn start/end, messages, tool calls)

2. The macOS app:
   - Polls the registry file every 2 seconds
   - Connects to each session via WebSocket for real-time updates
   - Displays sessions grouped by project directory
   - Sends actions via HTTP POST to control sessions

3. When a dangerous command is detected (e.g., `rm -rf`, `sudo`):
   - The extension pauses execution
   - Sends notification via WebSocket
   - The app shows a badge and native notification
   - User can approve/reject from the menu bar

## Development

### Extension

```bash
cd extension
npm run dev  # Watch mode
npm test     # Run tests
```

### macOS App

Standard Swift/Xcode development workflow.

## Security

- All communication is localhost-only (127.0.0.1)
- Random auth tokens generated per session (32 bytes)
- Registry file has restricted permissions (0600)
- No credentials stored in the app

## Requirements

- macOS 13.0+
- pi coding agent (with ExtensionAPI support)
- Node.js 18+ (for extension)

## License

MIT
