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
