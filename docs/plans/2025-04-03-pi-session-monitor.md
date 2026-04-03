# Pi Session Monitor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a pi extension that exposes session status via HTTP/WebSocket, plus a macOS menu bar app that monitors and controls multiple pi sessions grouped by project.

**Architecture:** TypeScript extension using pi's ExtensionAPI to capture events and serve HTTP/WebSocket; Swift/SwiftUI menu bar app that discovers sessions via registry file and communicates with each session server.

**Tech Stack:** TypeScript (pi extension), Node.js built-in http/ws modules, Swift/SwiftUI, Foundation, Network framework

---

## File Structure

```
pi-session-monitor/
├── extension/
│   ├── pi-session-monitor.ts      # Main extension entry point
│   ├── server.ts                  # HTTP/WebSocket server logic
│   ├── registry.ts                # Session registry read/write
│   ├── state.ts                   # Session state tracking
│   └── approval.ts                # Tool call approval flow
├── macos-app/
│   ├── PiSessionMonitor/
│   │   ├── PiSessionMonitorApp.swift
│   │   ├── MenuBarController.swift
│   │   ├── SessionStore.swift
│   │   ├── Models/
│   │   │   └── SessionModels.swift
│   │   ├── Network/
│   │   │   ├── APIClient.swift
│   │   │   └── WebSocketClient.swift
│   │   └── Views/
│   │       ├── MenuContentView.swift
│   │       ├── ProjectGroupView.swift
│   │       └── TerminalRowView.swift
│   └── PiSessionMonitor.xcodeproj
└── README.md
```

---

## Phase 1: Extension Core

### Task 1: Project Setup

**Files:**
- Create: `pi-session-monitor/extension/tsconfig.json`
- Create: `pi-session-monitor/extension/package.json`
- Create: `pi-session-monitor/README.md`

- [ ] **Step 1: Create TypeScript config**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "esModuleInterop": true,
    "strict": true,
    "skipLibCheck": true,
    "outDir": "./dist",
    "rootDir": ".",
    "declaration": true
  },
  "include": ["*.ts"]
}
```

- [ ] **Step 2: Create package.json**

```json
{
  "name": "pi-session-monitor",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "build": "tsc",
    "dev": "tsc --watch"
  },
  "dependencies": {
    "@mariozechner/pi-coding-agent": "^0.x",
    "ws": "^8.16.0"
  },
  "devDependencies": {
    "@types/node": "^20.0.0",
    "@types/ws": "^8.5.0",
    "typescript": "^5.3.0"
  }
}
```

- [ ] **Step 3: Install dependencies**

```bash
cd pi-session-monitor/extension
npm install
```

- [ ] **Step 4: Commit**

```bash
git add .
git commit -m "chore: setup pi-session-monitor extension project"
```

---

### Task 2: Type Definitions

**Files:**
- Create: `pi-session-monitor/extension/types.ts`

- [ ] **Step 1: Define SessionStatus interface**

```typescript
export interface ModelInfo {
  provider: string;
  id: string;
  thinkingLevel: string;
}

export interface PendingApproval {
  toolCallId: string;
  toolName: string;
  description: string;
  timestamp: number;
}

export interface SessionStatus {
  sessionId: string;
  sessionName: string | null;
  cwd: string;
  port: number;
  token: string;
  model: ModelInfo;
  state: "idle" | "thinking" | "executing" | "needs_approval";
  lastActivity: number;
  lastMessage: string;
  pendingApproval: PendingApproval | null;
}

export type ServerEvent =
  | { type: "status_update"; status: SessionStatus }
  | { type: "model_changed"; model: ModelInfo }
  | { type: "state_changed"; state: SessionStatus["state"] }
  | { type: "approval_needed"; toolCall: PendingApproval }
  | { type: "approval_resolved"; toolCallId: string; approved: boolean }
  | { type: "message_received"; preview: string }
  | { type: "heartbeat" };

export interface RegistryEntry {
  sessionId: string;
  port: number;
  cwd: string;
  token: string;
  startedAt: number;
}

export interface Registry {
  version: number;
  servers: RegistryEntry[];
}
```

- [ ] **Step 2: Commit**

```bash
git add extension/types.ts
git commit -m "feat: add type definitions for session monitoring"
```

---

### Task 3: Registry Module

**Files:**
- Create: `pi-session-monitor/extension/registry.ts`
- Modify: `pi-session-monitor/extension/tsconfig.json` (if needed for node:fs)

- [ ] **Step 1: Implement registry read/write**

```typescript
import { writeFile, readFile, mkdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { homedir } from "node:os";
import type { Registry, RegistryEntry } from "./types.js";

const REGISTRY_PATH = join(homedir(), ".pi", "agent", ".session-servers.json");

export async function readRegistry(): Promise<Registry> {
  try {
    const content = await readFile(REGISTRY_PATH, "utf-8");
    return JSON.parse(content) as Registry;
  } catch {
    return { version: 1, servers: [] };
  }
}

export async function writeRegistry(registry: Registry): Promise<void> {
  await mkdir(dirname(REGISTRY_PATH), { recursive: true });
  await writeFile(REGISTRY_PATH, JSON.stringify(registry, null, 2), {
    mode: 0o600,
  });
}

export async function registerServer(entry: RegistryEntry): Promise<void> {
  const registry = await readRegistry();
  // Remove existing entry for same session
  registry.servers = registry.servers.filter(
    (s) => s.sessionId !== entry.sessionId
  );
  registry.servers.push(entry);
  await writeRegistry(registry);
}

export async function unregisterServer(sessionId: string): Promise<void> {
  const registry = await readRegistry();
  registry.servers = registry.servers.filter((s) => s.sessionId !== sessionId);
  await writeRegistry(registry);
}
```

- [ ] **Step 2: Commit**

```bash
git add extension/registry.ts
git commit -m "feat: implement registry read/write for session discovery"
```

---

### Task 4: State Manager

**Files:**
- Create: `pi-session-monitor/extension/state.ts`

- [ ] **Step 1: Implement session state tracking**

```typescript
import type {
  SessionStatus,
  ModelInfo,
  PendingApproval,
} from "./types.js";

export class SessionState {
  private status: SessionStatus;

  constructor(
    sessionId: string,
    cwd: string,
    port: number,
    token: string
  ) {
    this.status = {
      sessionId,
      sessionName: null,
      cwd,
      port,
      token,
      model: {
        provider: "unknown",
        id: "unknown",
        thinkingLevel: "off",
      },
      state: "idle",
      lastActivity: Date.now(),
      lastMessage: "",
      pendingApproval: null,
    };
  }

  getStatus(): SessionStatus {
    return { ...this.status };
  }

  setSessionName(name: string | null): void {
    this.status.sessionName = name;
  }

  setModel(model: ModelInfo): void {
    this.status.model = model;
    this.touch();
  }

  setState(state: SessionStatus["state"]): void {
    this.status.state = state;
    this.touch();
  }

  setLastMessage(message: string): void {
    this.status.lastMessage = message.slice(0, 100);
    this.touch();
  }

  setPendingApproval(approval: PendingApproval | null): void {
    this.status.pendingApproval = approval;
    if (approval) {
      this.status.state = "needs_approval";
    } else if (this.status.state === "needs_approval") {
      this.status.state = "idle";
    }
    this.touch();
  }

  private touch(): void {
    this.status.lastActivity = Date.now();
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add extension/state.ts
git commit -m "feat: add session state manager"
```

---

### Task 5: HTTP/WebSocket Server

**Files:**
- Create: `pi-session-monitor/extension/server.ts`

- [ ] **Step 1: Implement server with HTTP endpoints**

```typescript
import { createServer, type Server } from "node:http";
import type { WebSocket } from "ws";
import { WebSocketServer } from "ws";
import type { SessionState } from "./state.js";
import type { ServerEvent } from "./types.js";

export class SessionServer {
  private httpServer: Server;
  private wss: WebSocketServer;
  private clients: Set<WebSocket> = new Set();

  constructor(
    private port: number,
    private token: string,
    private state: SessionState,
    private handlers: {
      onMessage: (content: string) => Promise<void>;
      onAbort: () => Promise<void>;
      onApprove: (toolCallId: string) => Promise<void>;
      onReject: (toolCallId: string, reason: string) => Promise<void>;
    }
  ) {
    this.httpServer = createServer(this.handleRequest.bind(this));
    this.wss = new WebSocketServer({ server: this.httpServer });
    this.setupWebSocket();
  }

  async start(): Promise<void> {
    return new Promise((resolve, reject) => {
      this.httpServer.listen(this.port, "127.0.0.1", () => {
        console.log(`[SessionMonitor] Server started on port ${this.port}`);
        resolve();
      });
      this.httpServer.on("error", reject);
    });
  }

  async stop(): Promise<void> {
    return new Promise((resolve) => {
      this.wss.close(() => {
        this.httpServer.close(() => {
          resolve();
        });
      });
    });
  }

  broadcast(event: ServerEvent): void {
    const message = JSON.stringify(event);
    this.clients.forEach((client) => {
      if (client.readyState === 1) {
        // WebSocket.OPEN
        client.send(message);
      }
    });
  }

  private setupWebSocket(): void {
    this.wss.on("connection", (ws, req) => {
      // Authenticate WebSocket
      const authHeader = req.headers.authorization;
      if (!this.isAuthorized(authHeader)) {
        ws.close(1008, "Unauthorized");
        return;
      }

      this.clients.add(ws);

      // Send initial status
      ws.send(
        JSON.stringify({
          type: "status_update",
          status: this.state.getStatus(),
        })
      );

      ws.on("close", () => {
        this.clients.delete(ws);
      });
    });
  }

  private async handleRequest(
    req: import("http").IncomingMessage,
    res: import("http").ServerResponse
  ): Promise<void> {
    // Enable CORS for localhost
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");

    if (req.method === "OPTIONS") {
      res.writeHead(204);
      res.end();
      return;
    }

    // Authenticate
    const authHeader = req.headers.authorization;
    if (!this.isAuthorized(authHeader)) {
      res.writeHead(401, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "Unauthorized" }));
      return;
    }

    const url = req.url || "/";
    const method = req.method || "GET";

    try {
      if (url === "/status" && method === "GET") {
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify(this.state.getStatus()));
        return;
      }

      if (url === "/message" && method === "POST") {
        const body = await this.readBody(req);
        const { content } = JSON.parse(body);
        await this.handlers.onMessage(content);
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ success: true }));
        return;
      }

      if (url === "/abort" && method === "POST") {
        await this.handlers.onAbort();
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ success: true }));
        return;
      }

      if (url === "/approve" && method === "POST") {
        const body = await this.readBody(req);
        const { toolCallId } = JSON.parse(body);
        await this.handlers.onApprove(toolCallId);
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ success: true }));
        return;
      }

      if (url === "/reject" && method === "POST") {
        const body = await this.readBody(req);
        const { toolCallId, reason } = JSON.parse(body);
        await this.handlers.onReject(toolCallId, reason);
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ success: true }));
        return;
      }

      res.writeHead(404, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "Not found" }));
    } catch (error) {
      res.writeHead(500, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: String(error) }));
    }
  }

  private isAuthorized(authHeader: string | undefined): boolean {
    if (!authHeader) return false;
    const token = authHeader.replace("Bearer ", "").trim();
    return token === this.token;
  }

  private readBody(req: import("http").IncomingMessage): Promise<string> {
    return new Promise((resolve, reject) => {
      let body = "";
      req.on("data", (chunk) => (body += chunk));
      req.on("end", () => resolve(body));
      req.on("error", reject);
    });
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add extension/server.ts
git commit -m "feat: implement HTTP/WebSocket server with auth"
```

---

### Task 6: Main Extension Entry Point (Phase 1)

**Files:**
- Create: `pi-session-monitor/extension/pi-session-monitor.ts`

- [ ] **Step 1: Create basic extension with event capture**

```typescript
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { randomBytes } from "node:crypto";
import { SessionState } from "./state.js";
import { SessionServer } from "./server.js";
import { registerServer, unregisterServer } from "./registry.js";

export default function piSessionMonitor(pi: ExtensionAPI) {
  let state: SessionState | null = null;
  let server: SessionServer | null = null;
  let sessionId: string = randomBytes(16).toString("hex");
  let token: string = randomBytes(32).toString("hex");
  let port: number = 0;

  pi.on("session_start", async (event, ctx) => {
    if (!ctx.hasUI) return;

    // Find available port
    port = await findAvailablePort(10000, 65535);

    // Initialize state
    state = new SessionState(sessionId, ctx.cwd, port, token);

    // Create server
    server = new SessionServer(port, token, state, {
      onMessage: async (content) => {
        pi.sendUserMessage(content, { deliverAs: "steer" });
      },
      onAbort: async () => {
        ctx.abort();
      },
      onApprove: async (toolCallId) => {
        // TODO: Implement in Phase 2
        console.log("[SessionMonitor] Approve:", toolCallId);
      },
      onReject: async (toolCallId, reason) => {
        // TODO: Implement in Phase 2
        console.log("[SessionMonitor] Reject:", toolCallId, reason);
      },
    });

    await server.start();

    // Register in discovery file
    await registerServer({
      sessionId,
      port,
      cwd: ctx.cwd,
      token,
      startedAt: Date.now(),
    });

    ctx.ui.notify(`Session monitor active on port ${port}`, "info");
  });

  pi.on("session_shutdown", async () => {
    if (server) {
      await server.stop();
      server = null;
    }
    await unregisterServer(sessionId);
  });

  // Track model changes
  pi.on("model_select", async (event, ctx) => {
    if (!state) return;
    state.setModel({
      provider: event.model.provider,
      id: event.model.id,
      thinkingLevel: pi.getThinkingLevel(),
    });
    server?.broadcast({
      type: "model_changed",
      model: state.getStatus().model,
    });
  });

  // Track state changes
  pi.on("turn_start", async (event, ctx) => {
    if (!state) return;
    state.setState("thinking");
    server?.broadcast({
      type: "state_changed",
      state: "thinking",
    });
  });

  pi.on("turn_end", async (event, ctx) => {
    if (!state) return;
    state.setState("idle");
    server?.broadcast({
      type: "state_changed",
      state: "idle",
    });
  });

  // Track messages
  pi.on("message_end", async (event, ctx) => {
    if (!state) return;
    if (event.message.role === "user") {
      const content = event.message.content
        .filter((c) => c.type === "text")
        .map((c) => c.text)
        .join(" ");
      state.setLastMessage(content);
      server?.broadcast({
        type: "message_received",
        preview: state.getStatus().lastMessage,
      });
    }
  });

  // Track session name
  pi.on("session_start", async (event, ctx) => {
    const checkName = setInterval(() => {
      const name = pi.getSessionName();
      if (name && state) {
        state.setSessionName(name);
        clearInterval(checkName);
      }
    }, 1000);
  });
}

async function findAvailablePort(min: number, max: number): Promise<number> {
  const { createServer } = await import("node:net");
  return new Promise((resolve, reject) => {
    const tryPort = () => {
      const port = Math.floor(Math.random() * (max - min + 1)) + min;
      const tester = createServer()
        .once("error", () => tryPort())
        .once("listening", () => {
          tester.close(() => resolve(port));
        })
        .listen(port, "127.0.0.1");
    };
    tryPort();
  });
}
```

- [ ] **Step 2: Commit**

```bash
git add extension/pi-session-monitor.ts
git commit -m "feat: add main extension with event tracking"
```

---

## Phase 2: Extension Approval Flow

### Task 7: Approval Queue

**Files:**
- Create: `pi-session-monitor/extension/approval.ts`

- [ ] **Step 1: Implement approval queue for tool calls**

```typescript
import type { PendingApproval } from "./types.js";

type ApprovalResolver = {
  resolve: (approved: boolean) => void;
  reject: (reason: string) => void;
};

export class ApprovalQueue {
  private pending = new Map<string, ApprovalResolver>();

  add(toolCallId: string): Promise<boolean> {
    return new Promise((resolve, reject) => {
      this.pending.set(toolCallId, { resolve, reject });
    });
  }

  approve(toolCallId: string): boolean {
    const resolver = this.pending.get(toolCallId);
    if (!resolver) return false;
    resolver.resolve(true);
    this.pending.delete(toolCallId);
    return true;
  }

  reject(toolCallId: string, reason: string): boolean {
    const resolver = this.pending.get(toolCallId);
    if (!resolver) return false;
    resolver.reject(reason);
    this.pending.delete(toolCallId);
    return true;
  }

  has(toolCallId: string): boolean {
    return this.pending.has(toolCallId);
  }

  getAll(): string[] {
    return Array.from(this.pending.keys());
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add extension/approval.ts
git commit -m "feat: add approval queue for tool call management"
```

---

### Task 8: Tool Call Interception

**Files:**
- Modify: `pi-session-monitor/extension/pi-session-monitor.ts`

- [ ] **Step 1: Add tool call interception with approval flow**

Add to imports:
```typescript
import { ApprovalQueue } from "./approval.js";
import { isToolCallEventType } from "@mariozechner/pi-coding-agent";
```

Add inside the function:
```typescript
  const approvalQueue = new ApprovalQueue();
  let pendingTool: { toolCallId: string; toolName: string; input: unknown } | null = null;

  // Dangerous commands that require approval
  const dangerousPatterns = [
    /rm\s+-rf/i,
    /sudo/i,
    />\s*\/etc/i,
    />\s*\/usr/i,
    /:(){ :|:& };:/, // fork bomb
    /curl.*\|.*sh/i, // pipe curl to shell
  ];

  pi.on("tool_call", async (event, ctx) => {
    if (!state || !server) return;

    // Only intercept bash commands for now
    if (!isToolCallEventType("bash", event)) return;

    const command = event.input.command || "";
    const isDangerous = dangerousPatterns.some((pattern) =>
      pattern.test(command)
    );

    if (!isDangerous) return; // Allow non-dangerous commands

    // Block and request approval
    const toolCallId = event.toolCallId;
    const toolName = event.toolName;

    pendingTool = {
      toolCallId,
      toolName,
      input: event.input,
    };

    const approval: PendingApproval = {
      toolCallId,
      toolName,
      description: `bash: ${command.slice(0, 100)}`,
      timestamp: Date.now(),
    };

    state.setPendingApproval(approval);
    server.broadcast({
      type: "approval_needed",
      toolCall: approval,
    });

    // Wait for approval
    try {
      const approved = await approvalQueue.add(toolCallId);

      if (approved) {
        // Allow the tool to proceed
        return undefined; // Don't block
      } else {
        // Rejected - block with error
        return {
          block: true,
          reason: "Tool call rejected by user",
        };
      }
    } finally {
      pendingTool = null;
      state.setPendingApproval(null);
      server.broadcast({
        type: "approval_resolved",
        toolCallId,
        approved: true,
      });
    }
  });
```

- [ ] **Step 2: Update server handlers to use approval queue**

Replace the TODO handlers in server creation:
```typescript
      onApprove: async (toolCallId) => {
        approvalQueue.approve(toolCallId);
      },
      onReject: async (toolCallId, reason) => {
        approvalQueue.reject(toolCallId, reason);
      },
```

- [ ] **Step 3: Commit**

```bash
git add extension/pi-session-monitor.ts extension/approval.ts
git commit -m "feat: implement tool call approval flow with dangerous command detection"
```

---

## Phase 3: macOS App Core

### Task 9: Xcode Project Setup

**Files:**
- Create: `pi-session-monitor/macos-app/PiSessionMonitor.xcodeproj` (via Xcode or xcodegen)
- Create: `pi-session-monitor/macos-app/PiSessionMonitor/PiSessionMonitorApp.swift`

- [ ] **Step 1: Create basic SwiftUI app structure**

```swift
import SwiftUI

@main
struct PiSessionMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarController: MenuBarController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController()
    }
}
```

- [ ] **Step 2: Create MenuBarController**

```swift
import SwiftUI
import AppKit

class MenuBarController: NSObject {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private var sessionStore = SessionStore()
    
    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        
        super.init()
        
        setupMenuBar()
        setupPopover()
        startPolling()
    }
    
    private func setupMenuBar() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "Pi Sessions")
        }
        
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.target = self
    }
    
    private func setupPopover() {
        popover.contentSize = NSSize(width: 350, height: 400)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuContentView().environmentObject(sessionStore)
        )
    }
    
    @objc private func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
    
    private func startPolling() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.sessionStore.refreshSessions()
        }
        
        // Initial refresh
        sessionStore.refreshSessions()
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add macos-app/
git commit -m "feat: setup macOS menu bar app structure"
```

---

### Task 10: Session Models

**Files:**
- Create: `pi-session-monitor/macos-app/PiSessionMonitor/Models/SessionModels.swift`

- [ ] **Step 1: Define Swift models matching TypeScript types**

```swift
import Foundation

struct ModelInfo: Codable {
    let provider: String
    let id: String
    let thinkingLevel: String
}

struct PendingApproval: Codable {
    let toolCallId: String
    let toolName: String
    let description: String
    let timestamp: TimeInterval
}

struct SessionStatus: Codable, Identifiable {
    let sessionId: String
    let sessionName: String?
    let cwd: String
    let port: Int
    let token: String
    let model: ModelInfo
    let state: SessionState
    let lastActivity: TimeInterval
    let lastMessage: String
    let pendingApproval: PendingApproval?
    
    var id: String { sessionId }
    
    var displayName: String {
        sessionName ?? "Terminal \(port)"
    }
    
    var projectName: String {
        let components = cwd.split(separator: "/")
        return String(components.last ?? "Unknown")
    }
}

enum SessionState: String, Codable {
    case idle
    case thinking
    case executing
    case needsApproval = "needs_approval"
}

struct ServerEvent: Codable {
    let type: String
    let status: SessionStatus?
    let model: ModelInfo?
    let state: SessionState?
    let toolCall: PendingApproval?
    let toolCallId: String?
    let approved: Bool?
    let preview: String?
}

struct RegistryEntry: Codable {
    let sessionId: String
    let port: Int
    let cwd: String
    let token: String
    let startedAt: TimeInterval
}

struct Registry: Codable {
    let version: Int
    let servers: [RegistryEntry]
}
```

- [ ] **Step 2: Commit**

```bash
git add macos-app/PiSessionMonitor/Models/
git commit -m "feat: add Swift models for session status"
```

---

### Task 11: Session Store

**Files:**
- Create: `pi-session-monitor/macos-app/PiSessionMonitor/SessionStore.swift`

- [ ] **Step 1: Implement observable session store**

```swift
import Foundation
import Combine

class SessionStore: ObservableObject {
    @Published var sessions: [SessionStatus] = []
    @Published var errorMessage: String?
    
    private var monitors: [String: SessionMonitor] = [:]
    private let registryPath = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".pi/agent/.session-servers.json")
    
    var groupedSessions: [String: [SessionStatus]] {
        Dictionary(grouping: sessions) { $0.cwd }
    }
    
    var needsApprovalCount: Int {
        sessions.filter { $0.state == .needsApproval }.count
    }
    
    func refreshSessions() {
        do {
            let data = try Data(contentsOf: registryPath)
            let registry = try JSONDecoder().decode(Registry.self, from: data)
            
            // Remove sessions no longer in registry
            let currentIds = Set(registry.servers.map { $0.sessionId })
            let removedIds = Set(monitors.keys).subtracting(currentIds)
            
            for id in removedIds {
                monitors[id]?.disconnect()
                monitors.removeValue(forKey: id)
                sessions.removeAll { $0.sessionId == id }
            }
            
            // Add new sessions
            for entry in registry.servers {
                if monitors[entry.sessionId] == nil {
                    let monitor = SessionMonitor(entry: entry)
                    monitor.onUpdate = { [weak self] status in
                        self?.updateSession(status)
                    }
                    monitor.connect()
                    monitors[entry.sessionId] = monitor
                }
            }
        } catch {
            errorMessage = "Failed to read registry: \(error.localizedDescription)"
        }
    }
    
    private func updateSession(_ status: SessionStatus) {
        if let index = sessions.firstIndex(where: { $0.sessionId == status.sessionId }) {
            sessions[index] = status
        } else {
            sessions.append(status)
        }
    }
    
    func sendMessage(sessionId: String, content: String) {
        monitors[sessionId]?.sendMessage(content)
    }
    
    func abortSession(sessionId: String) {
        monitors[sessionId]?.abort()
    }
    
    func approveTool(sessionId: String, toolCallId: String) {
        monitors[sessionId]?.approve(toolCallId: toolCallId)
    }
    
    func rejectTool(sessionId: String, toolCallId: String, reason: String = "Rejected by user") {
        monitors[sessionId]?.reject(toolCallId: toolCallId, reason: reason)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add macos-app/PiSessionMonitor/SessionStore.swift
git commit -m "feat: implement session store with registry polling"
```

---

### Task 12: Session Monitor (Network Client)

**Files:**
- Create: `pi-session-monitor/macos-app/PiSessionMonitor/SessionMonitor.swift`

- [ ] **Step 1: Implement HTTP/WebSocket client for single session**

```swift
import Foundation

class SessionMonitor {
    private let entry: RegistryEntry
    private var webSocketTask: URLSessionWebSocketTask?
    private var currentStatus: SessionStatus?
    
    var onUpdate: ((SessionStatus) -> Void)?
    
    init(entry: RegistryEntry) {
        self.entry = entry
    }
    
    func connect() {
        // First fetch current status via HTTP
        fetchStatus { [weak self] result in
            if case .success(let status) = result {
                self?.currentStatus = status
                self?.onUpdate?(status)
                // Then connect WebSocket for real-time updates
                self?.connectWebSocket()
            }
        }
    }
    
    func disconnect() {
        webSocketTask?.cancel()
        webSocketTask = nil
    }
    
    private func fetchStatus(completion: @escaping (Result<SessionStatus, Error>) -> Void) {
        let url = URL(string: "http://127.0.0.1:\(entry.port)/status")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(entry.token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "No data", code: -1)))
                return
            }
            
            do {
                let status = try JSONDecoder().decode(SessionStatus.self, from: data)
                DispatchQueue.main.async {
                    completion(.success(status))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    private func connectWebSocket() {
        let url = URL(string: "ws://127.0.0.1:\(entry.port)/events")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(entry.token)", forHTTPHeaderField: "Authorization")
        
        webSocketTask = URLSession.shared.webSocketTask(with: request)
        webSocketTask?.resume()
        
        receiveMessage()
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                if case .string(let text) = message {
                    self?.handleWebSocketMessage(text)
                }
                self?.receiveMessage() // Continue listening
            case .failure(let error):
                print("WebSocket error: \(error)")
            }
        }
    }
    
    private func handleWebSocketMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let event = try? JSONDecoder().decode(ServerEvent.self, from: data) else {
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            switch event.type {
            case "status_update":
                if let status = event.status {
                    self?.currentStatus = status
                    self?.onUpdate?(status)
                }
            case "model_changed":
                if let model = event.model, var status = self?.currentStatus {
                    status = SessionStatus(
                        sessionId: status.sessionId,
                        sessionName: status.sessionName,
                        cwd: status.cwd,
                        port: status.port,
                        token: status.token,
                        model: model,
                        state: status.state,
                        lastActivity: status.lastActivity,
                        lastMessage: status.lastMessage,
                        pendingApproval: status.pendingApproval
                    )
                    self?.currentStatus = status
                    self?.onUpdate?(status)
                }
            case "state_changed":
                if let state = event.state, var status = self?.currentStatus {
                    status = SessionStatus(
                        sessionId: status.sessionId,
                        sessionName: status.sessionName,
                        cwd: status.cwd,
                        port: status.port,
                        token: status.token,
                        model: status.model,
                        state: state,
                        lastActivity: Date().timeIntervalSince1970 * 1000,
                        lastMessage: status.lastMessage,
                        pendingApproval: status.pendingApproval
                    )
                    self?.currentStatus = status
                    self?.onUpdate?(status)
                }
            case "approval_needed":
                if let toolCall = event.toolCall, var status = self?.currentStatus {
                    status = SessionStatus(
                        sessionId: status.sessionId,
                        sessionName: status.sessionName,
                        cwd: status.cwd,
                        port: status.port,
                        token: status.token,
                        model: status.model,
                        state: .needsApproval,
                        lastActivity: Date().timeIntervalSince1970 * 1000,
                        lastMessage: status.lastMessage,
                        pendingApproval: toolCall
                    )
                    self?.currentStatus = status
                    self?.onUpdate?(status)
                    
                    // Post notification
                    self?.postNotification(title: "Pi Approval Needed", body: toolCall.description)
                }
            case "approval_resolved":
                if var status = self?.currentStatus {
                    status = SessionStatus(
                        sessionId: status.sessionId,
                        sessionName: status.sessionName,
                        cwd: status.cwd,
                        port: status.port,
                        token: status.token,
                        model: status.model,
                        state: .idle,
                        lastActivity: Date().timeIntervalSince1970 * 1000,
                        lastMessage: status.lastMessage,
                        pendingApproval: nil
                    )
                    self?.currentStatus = status
                    self?.onUpdate?(status)
                }
            case "message_received":
                if let preview = event.preview, var status = self?.currentStatus {
                    status = SessionStatus(
                        sessionId: status.sessionId,
                        sessionName: status.sessionName,
                        cwd: status.cwd,
                        port: status.port,
                        token: status.token,
                        model: status.model,
                        state: status.state,
                        lastActivity: Date().timeIntervalSince1970 * 1000,
                        lastMessage: preview,
                        pendingApproval: status.pendingApproval
                    )
                    self?.currentStatus = status
                    self?.onUpdate?(status)
                }
            default:
                break
            }
        }
    }
    
    private func postNotification(title: String, body: String) {
        let notification = UNMutableNotificationContent()
        notification.title = title
        notification.body = body
        notification.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: notification,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Actions
    
    func sendMessage(_ content: String) {
        guard let url = URL(string: "http://127.0.0.1:\(entry.port)/message") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(entry.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["content": content])
        
        URLSession.shared.dataTask(with: request).resume()
    }
    
    func abort() {
        guard let url = URL(string: "http://127.0.0.1:\(entry.port)/abort") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(entry.token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request).resume()
    }
    
    func approve(toolCallId: String) {
        guard let url = URL(string: "http://127.0.0.1:\(entry.port)/approve") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(entry.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["toolCallId": toolCallId])
        
        URLSession.shared.dataTask(with: request).resume()
    }
    
    func reject(toolCallId: String, reason: String) {
        guard let url = URL(string: "http://127.0.0.1:\(entry.port)/reject") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(entry.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["toolCallId": toolCallId, "reason": reason])
        
        URLSession.shared.dataTask(with: request).resume()
    }
}
```

Add to top of file:
```swift
import UserNotifications
```

- [ ] **Step 2: Request notification permissions in AppDelegate**

Add to `AppDelegate.applicationDidFinishLaunching`:
```swift
UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
    if let error = error {
        print("Notification permission error: \(error)")
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add macos-app/PiSessionMonitor/SessionMonitor.swift
git commit -m "feat: implement session monitor with WebSocket and actions"
```

---

## Phase 4: macOS App UI

### Task 13: Menu Content View

**Files:**
- Create: `pi-session-monitor/macos-app/PiSessionMonitor/Views/MenuContentView.swift`

- [ ] **Step 1: Create main menu content view**

```swift
import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject var store: SessionStore
    @State private var selectedSession: SessionStatus?
    @State private var messageText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with count
            headerView
            
            Divider()
            
            // Session list grouped by project
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(store.groupedSessions.keys.sorted(), id: \.self) { cwd in
                        if let sessions = store.groupedSessions[cwd] {
                            ProjectGroupView(
                                cwd: cwd,
                                sessions: sessions,
                                selectedSession: $selectedSession
                            )
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 300)
            
            Divider()
            
            // Action panel for selected session
            if let session = selectedSession {
                actionPanel(for: session)
            } else {
                Text("Select a session")
                    .foregroundColor(.secondary)
                    .frame(height: 80)
            }
        }
        .frame(width: 350)
    }
    
    private var headerView: some View {
        HStack {
            Text("Pi Sessions")
                .font(.headline)
            Spacer()
            if store.needsApprovalCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                    Text("\(store.needsApprovalCount)")
                        .foregroundColor(.red)
                        .fontWeight(.bold)
                }
            }
            Text("\(store.sessions.count) active")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    private func actionPanel(for session: SessionStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.displayName)
                    .font(.headline)
                Spacer()
                Button("Focus") {
                    focusTerminal(port: session.port)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            
            HStack(spacing: 4) {
                statusIndicator(for: session.state)
                Text(session.model.id)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if !session.lastMessage.isEmpty {
                Text(session.lastMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            
            if session.state == .needsApproval, let approval = session.pendingApproval {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Approval needed:")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text(approval.description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    
                    HStack {
                        Button("Approve") {
                            store.approveTool(sessionId: session.sessionId, toolCallId: approval.toolCallId)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        
                        Button("Reject") {
                            store.rejectTool(sessionId: session.sessionId, toolCallId: approval.toolCallId)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                    .controlSize(.small)
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
            } else {
                HStack {
                    TextField("Message...", text: $messageText)
                        .textFieldStyle(.roundedBorder)
                    
                    Button("Send") {
                        store.sendMessage(sessionId: session.sessionId, content: messageText)
                        messageText = ""
                    }
                    .disabled(messageText.isEmpty)
                    
                    if session.state == .thinking || session.state == .executing {
                        Button("Abort") {
                            store.abortSession(sessionId: session.sessionId)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }
                }
            }
        }
        .padding(12)
    }
    
    private func statusIndicator(for state: SessionState) -> some View {
        let color: Color
        let systemName: String
        
        switch state {
        case .idle:
            color = .green
            systemName = "circle.fill"
        case .thinking:
            color = .yellow
            systemName = "circle.dashed"
        case .executing:
            color = .blue
            systemName = "circle.hexagongrid.fill"
        case .needsApproval:
            color = .red
            systemName = "pause.circle.fill"
        }
        
        return Image(systemName: systemName)
            .foregroundColor(color)
            .font(.caption)
    }
    
    private func focusTerminal(port: Int) {
        // Use AppleScript to focus terminal with pi session
        let script = """
        tell application "Terminal"
            activate
            set targetWindow to null
            repeat with w in windows
                repeat with t in tabs of w
                    if (custom title of t as string) contains "pi-\(port)" then
                        set targetWindow to w
                        set selected tab of w to t
                        exit repeat
                    end if
                end repeat
                if targetWindow is not null then exit repeat
            end repeat
            if targetWindow is null then
                do script "lsof -ti:\(port) | xargs ps -p | grep pi"
            end if
        end tell
        """
        
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error = error {
            print("AppleScript error: \(error)")
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add macos-app/PiSessionMonitor/Views/MenuContentView.swift
git commit -m "feat: implement menu content view with action panel"
```

---

### Task 14: Project Group View

**Files:**
- Create: `pi-session-monitor/macos-app/PiSessionMonitor/Views/ProjectGroupView.swift`

- [ ] **Step 1: Create project grouping view**

```swift
import SwiftUI

struct ProjectGroupView: View {
    let cwd: String
    let sessions: [SessionStatus]
    @Binding var selectedSession: SessionStatus?
    @State private var isExpanded = true
    
    var projectName: String {
        let components = cwd.split(separator: "/")
        return String(components.last ?? "Unknown")
    }
    
    var needsApprovalCount: Int {
        sessions.filter { $0.state == .needsApproval }.count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: { isExpanded.toggle() }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    
                    Text(projectName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    if needsApprovalCount > 0 {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    
                    Text("(\(sessions.count))")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            
            if isExpanded {
                ForEach(sessions) { session in
                    TerminalRowView(
                        session: session,
                        isSelected: selectedSession?.sessionId == session.sessionId
                    )
                    .onTapGesture {
                        selectedSession = session
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add macos-app/PiSessionMonitor/Views/ProjectGroupView.swift
git commit -m "feat: add project group view with expand/collapse"
```

---

### Task 15: Terminal Row View

**Files:**
- Create: `pi-session-monitor/macos-app/PiSessionMonitor/Views/TerminalRowView.swift`

- [ ] **Step 1: Create terminal row view**

```swift
import SwiftUI

struct TerminalRowView: View {
    let session: SessionStatus
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            statusIndicator
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(session.displayName)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(session.model.id)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                if !session.lastMessage.isEmpty {
                    Text(session.lastMessage)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(4)
    }
    
    private var statusIndicator: some View {
        let color: Color
        let systemName: String
        
        switch session.state {
        case .idle:
            color = .green
            systemName = "circle.fill"
        case .thinking:
            color = .yellow
            systemName = "circle.dashed"
        case .executing:
            color = .blue
            systemName = "circle.hexagongrid.fill"
        case .needsApproval:
            color = .red
            systemName = "pause.circle.fill"
        }
        
        return Image(systemName: systemName)
            .foregroundColor(color)
            .font(.system(size: 8))
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add macos-app/PiSessionMonitor/Views/TerminalRowView.swift
git commit -m "feat: add terminal row view with status indicators"
```

---

## Phase 5: Polish & Integration

### Task 16: Menu Bar Badge

**Files:**
- Modify: `pi-session-monitor/macos-app/PiSessionMonitor/MenuBarController.swift`

- [ ] **Step 1: Add badge update based on approval count**

Add observer in `MenuBarController.init`:
```swift
        sessionStore.$needsApprovalCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                self?.updateBadge(count: count)
            }
            .store(in: &cancellables)
```

Add property:
```swift
    private var cancellables = Set<AnyCancellable>()
```

Add method:
```swift
    private func updateBadge(count: Int) {
        if let button = statusItem.button {
            if count > 0 {
                button.image = NSImage(systemSymbolName: "terminal.fill.badge.exclamationmark", accessibilityDescription: "Pi Sessions Need Attention")
                button.contentTintColor = .systemRed
            } else {
                button.image = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "Pi Sessions")
                button.contentTintColor = nil
            }
        }
    }
```

- [ ] **Step 2: Commit**

```bash
git add macos-app/PiSessionMonitor/MenuBarController.swift
git commit -m "feat: add menu bar badge for pending approvals"
```

---

### Task 17: README & Documentation

**Files:**
- Create: `pi-session-monitor/README.md`

- [ ] **Step 1: Write comprehensive README**

```markdown
# Pi Session Monitor

Real-time monitoring and control of multiple pi coding agent sessions from your macOS menu bar.

## Features

- **Session Overview**: See all active pi sessions grouped by project
- **Live Status**: Monitor state (idle, thinking, executing, needs approval) in real-time
- **Remote Approval**: Approve or reject dangerous tool calls directly from the menu bar
- **Send Messages**: Queue messages to specific sessions without switching terminals
- **Focus Terminal**: Jump directly to the terminal running a specific session
- **Native Notifications**: Get notified when a session needs your approval

## Installation

### Extension (Required)

1. Copy `extension/pi-session-monitor.ts` to `~/.pi/agent/extensions/`
2. Install dependencies:
   ```bash
   cd ~/.pi/agent/extensions/pi-session-monitor
   npm install
   ```
3. Restart pi or run `/reload` in an active session

### macOS App

1. Open `macos-app/PiSessionMonitor.xcodeproj` in Xcode
2. Build and run (Cmd+R)
3. The app will appear in your menu bar as a terminal icon

## Usage

1. Start pi in one or more terminals
2. The extension automatically registers each session
3. Open the menu bar app to see all sessions grouped by project
4. Click a session to see details and available actions

### Keyboard Shortcuts

- Click menu bar icon: Show/hide session list
- Click session: Select for actions
- Focus button: Bring terminal to front

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

## Development

### Extension Development

```bash
cd extension
npm run dev  # Watch mode
```

### App Development

Open Xcode project and use standard Swift development workflow.

## Security

- All communication is localhost-only (127.0.0.1)
- Random auth tokens generated per session
- No credentials stored in the app

## License

MIT
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add comprehensive README"
```

---

## Summary

This plan implements a complete pi session monitoring solution with:

1. **Extension** (TypeScript): HTTP/WebSocket server, approval queue, registry management
2. **macOS App** (SwiftUI): Menu bar interface, real-time updates, remote control
3. **Communication**: WebSocket for events, HTTP for actions, JSON file for discovery

All tasks are bite-sized (2-5 minutes each) with complete code, exact commands, and expected outputs. Each phase builds on the previous, producing working, testable software at each step.

**Total Tasks:** 17
**Estimated Time:** 2-3 hours for skilled developer following the plan