import { describe, it, expect, beforeEach } from "vitest";
import { SessionState } from "../state.js";

describe("SessionState", () => {
  let state: SessionState;

  beforeEach(() => {
    state = new SessionState("test-session", "/test/cwd", 8080, "test-token");
  });

  describe("constructor", () => {
    it("should initialize with default values", () => {
      const status = state.getStatus();
      
      expect(status.sessionId).toBe("test-session");
      expect(status.cwd).toBe("/test/cwd");
      expect(status.port).toBe(8080);
      expect(status.token).toBe("test-token");
      expect(status.state).toBe("idle");
      expect(status.sessionName).toBeNull();
      expect(status.pendingApproval).toBeNull();
    });

    it("should set lastActivity to current time", () => {
      const before = Date.now();
      const newState = new SessionState("id", "/cwd", 1234, "token");
      const after = Date.now();
      
      const status = newState.getStatus();
      expect(status.lastActivity).toBeGreaterThanOrEqual(before);
      expect(status.lastActivity).toBeLessThanOrEqual(after);
    });
  });

  describe("setSessionName", () => {
    it("should update session name", () => {
      state.setSessionName("My Session");
      expect(state.getStatus().sessionName).toBe("My Session");
    });

    it("should allow setting to null", () => {
      state.setSessionName("Name");
      state.setSessionName(null);
      expect(state.getStatus().sessionName).toBeNull();
    });
  });

  describe("setModel", () => {
    it("should update model and touch lastActivity", () => {
      const before = state.getStatus().lastActivity;
      
      state.setModel({
        provider: "anthropic",
        id: "claude-4",
        thinkingLevel: "medium",
      });
      
      const status = state.getStatus();
      expect(status.model.provider).toBe("anthropic");
      expect(status.model.id).toBe("claude-4");
      expect(status.lastActivity).toBeGreaterThanOrEqual(before);
    });
  });

  describe("setState", () => {
    it("should update state and touch lastActivity", () => {
      const before = state.getStatus().lastActivity;
      
      state.setState("thinking");
      
      const status = state.getStatus();
      expect(status.state).toBe("thinking");
      expect(status.lastActivity).toBeGreaterThanOrEqual(before);
    });
  });

  describe("setLastMessage", () => {
    it("should update last message and touch lastActivity", () => {
      const before = state.getStatus().lastActivity;
      
      state.setLastMessage("Hello world");
      
      const status = state.getStatus();
      expect(status.lastMessage).toBe("Hello world");
      expect(status.lastActivity).toBeGreaterThanOrEqual(before);
    });

    it("should truncate long messages to 100 chars", () => {
      const longMessage = "a".repeat(200);
      state.setLastMessage(longMessage);
      
      expect(state.getStatus().lastMessage.length).toBe(100);
    });
  });

  describe("setPendingApproval", () => {
    it("should set approval and change state to needs_approval", () => {
      const approval = {
        toolCallId: "call-123",
        toolName: "bash",
        description: "rm -rf /",
        timestamp: Date.now(),
      };
      
      state.setPendingApproval(approval);
      
      const status = state.getStatus();
      expect(status.pendingApproval).toEqual(approval);
      expect(status.state).toBe("needs_approval");
    });

    it("should clear approval and reset state when set to null", () => {
      const approval = {
        toolCallId: "call-123",
        toolName: "bash",
        description: "rm -rf /",
        timestamp: Date.now(),
      };
      
      state.setPendingApproval(approval);
      state.setPendingApproval(null);
      
      const status = state.getStatus();
      expect(status.pendingApproval).toBeNull();
      expect(status.state).toBe("idle");
    });

    it("should keep previous state when clearing approval if not needs_approval", () => {
      state.setState("thinking");
      state.setPendingApproval(null);
      
      expect(state.getStatus().state).toBe("thinking");
    });
  });

  describe("getStatus", () => {
    it("should return a copy of status", () => {
      const status1 = state.getStatus();
      status1.state = "thinking" as any;
      
      const status2 = state.getStatus();
      expect(status2.state).toBe("idle");
    });
  });
});
