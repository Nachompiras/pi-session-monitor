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
