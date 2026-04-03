import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { isToolCallEventType } from "@mariozechner/pi-coding-agent";
import { randomBytes } from "node:crypto";
import { SessionState } from "./state.js";
import { SessionServer } from "./server.js";
import { registerServer, unregisterServer } from "./registry.js";
import { ApprovalQueue } from "./approval.js";
import type { PendingApproval } from "./types.js";

export default function piSessionMonitor(pi: ExtensionAPI) {
  let state: SessionState | null = null;
  let server: SessionServer | null = null;
  let sessionId: string = randomBytes(16).toString("hex");
  let token: string = randomBytes(32).toString("hex");
  let port: number = 0;
  const approvalQueue = new ApprovalQueue();
  let pendingTool: { toolCallId: string; toolName: string; input: unknown } | null = null;

  // Dangerous commands that require approval
  const dangerousPatterns = [
    /rm\s+-rf/i,
    /sudo/i,
    />\s*\/etc/i,
    />\s*\/usr/i,
    /:\(\){ :|:& };:/, // fork bomb
    /curl.*\|.*sh/i, // pipe curl to shell
  ];

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
        approvalQueue.approve(toolCallId);
      },
      onReject: async (toolCallId, reason) => {
        approvalQueue.reject(toolCallId, reason);
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

  // Tool call interception for dangerous commands
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
