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
