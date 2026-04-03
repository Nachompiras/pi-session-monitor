import { describe, it, expect } from "vitest";
import { ApprovalQueue } from "../approval.js";

describe("ApprovalQueue", () => {
  describe("add", () => {
    it("should return a promise that resolves on approve", async () => {
      const queue = new ApprovalQueue();
      const promise = queue.add("tool-1");
      
      queue.approve("tool-1");
      
      const result = await promise;
      expect(result).toBe(true);
    });

    it("should return a promise that rejects on reject", async () => {
      const queue = new ApprovalQueue();
      const promise = queue.add("tool-2").catch((e) => e);
      
      queue.reject("tool-2", "User cancelled");
      
      const result = await promise;
      expect(result).toBe("User cancelled");
    });
  });

  describe("approve", () => {
    it("should return true when tool exists", async () => {
      const queue = new ApprovalQueue();
      queue.add("tool-3").catch(() => {});
      
      const result = queue.approve("tool-3");
      expect(result).toBe(true);
    });

    it("should return false when tool does not exist", () => {
      const queue = new ApprovalQueue();
      
      const result = queue.approve("non-existent");
      expect(result).toBe(false);
    });

    it("should remove tool after approval", async () => {
      const queue = new ApprovalQueue();
      queue.add("tool-4").catch(() => {});
      queue.approve("tool-4");
      
      expect(queue.has("tool-4")).toBe(false);
    });
  });

  describe("reject", () => {
    it("should return true when tool exists", async () => {
      const queue = new ApprovalQueue();
      queue.add("tool-5").catch(() => {});
      
      const result = queue.reject("tool-5", "Rejected");
      expect(result).toBe(true);
    });

    it("should return false when tool does not exist", () => {
      const queue = new ApprovalQueue();
      
      const result = queue.reject("non-existent", "Rejected");
      expect(result).toBe(false);
    });

    it("should remove tool after rejection", async () => {
      const queue = new ApprovalQueue();
      queue.add("tool-6").catch(() => {});
      queue.reject("tool-6", "No");
      
      expect(queue.has("tool-6")).toBe(false);
    });
  });

  describe("has", () => {
    it("should return true for pending tool", () => {
      const queue = new ApprovalQueue();
      queue.add("tool-7").catch(() => {});
      
      expect(queue.has("tool-7")).toBe(true);
    });

    it("should return false for non-pending tool", () => {
      const queue = new ApprovalQueue();
      
      expect(queue.has("not-added")).toBe(false);
    });

    it("should return false after tool is resolved", async () => {
      const queue = new ApprovalQueue();
      queue.add("tool-8").catch(() => {});
      queue.approve("tool-8");
      
      expect(queue.has("tool-8")).toBe(false);
    });
  });

  describe("getAll", () => {
    it("should return all pending tool IDs", () => {
      const queue = new ApprovalQueue();
      queue.add("tool-a").catch(() => {});
      queue.add("tool-b").catch(() => {});
      queue.add("tool-c").catch(() => {});
      
      const all = queue.getAll();
      expect(all).toContain("tool-a");
      expect(all).toContain("tool-b");
      expect(all).toContain("tool-c");
      expect(all).toHaveLength(3);
    });

    it("should not include resolved tools", async () => {
      const queue = new ApprovalQueue();
      queue.add("tool-x").catch(() => {});
      queue.add("tool-y").catch(() => {});
      queue.approve("tool-x");
      
      const all = queue.getAll();
      expect(all).not.toContain("tool-x");
      expect(all).toContain("tool-y");
    });
  });

  describe("multiple concurrent approvals", () => {
    it("should handle multiple tools independently", async () => {
      const queue = new ApprovalQueue();
      
      const promise1 = queue.add("tool-1");
      const promise2 = queue.add("tool-2").catch(() => "rejected");
      
      queue.approve("tool-1");
      queue.reject("tool-2", "No");
      
      const result1 = await promise1;
      const result2 = await promise2;
      
      expect(result1).toBe(true);
      expect(result2).toBe("rejected");
    });
  });
});
