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
