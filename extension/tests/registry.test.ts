import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { readRegistry, writeRegistry, registerServer, unregisterServer } from "../registry.js";
import type { Registry, RegistryEntry } from "../types.js";
import { writeFile, unlink, mkdir, rm } from "node:fs/promises";
import { homedir } from "node:os";
import { join, dirname } from "node:path";

const REGISTRY_PATH = join(homedir(), ".pi", "agent", ".session-servers.json");

async function cleanup() {
  try {
    await unlink(REGISTRY_PATH);
  } catch {
    // File might not exist
  }
}

describe("Registry", () => {
  beforeEach(async () => {
    await cleanup();
    // Ensure directory exists
    await mkdir(dirname(REGISTRY_PATH), { recursive: true });
  });

  afterEach(async () => {
    await cleanup();
  });

  describe("readRegistry", () => {
    it("should return empty registry when file does not exist", async () => {
      const registry = await readRegistry();
      expect(registry).toEqual({ version: 1, servers: [] });
    });

    it("should return parsed registry when file exists", async () => {
      const testRegistry: Registry = {
        version: 1,
        servers: [
          {
            sessionId: "test-123",
            port: 8080,
            cwd: "/test/project",
            token: "test-token",
            startedAt: Date.now(),
          },
        ],
      };
      
      await writeFile(REGISTRY_PATH, JSON.stringify(testRegistry));
      
      const registry = await readRegistry();
      expect(registry.servers).toHaveLength(1);
      expect(registry.servers[0].sessionId).toBe("test-123");
    });
  });

  describe("writeRegistry", () => {
    it("should write registry to file", async () => {
      const registry: Registry = {
        version: 1,
        servers: [
          {
            sessionId: "test-456",
            port: 9090,
            cwd: "/another/project",
            token: "another-token",
            startedAt: 1234567890,
          },
        ],
      };

      await writeRegistry(registry);
      const read = await readRegistry();
      expect(read).toEqual(registry);
    });
  });

  describe("registerServer", () => {
    it("should add new server to registry", async () => {
      const entry: RegistryEntry = {
        sessionId: "new-session",
        port: 1111,
        cwd: "/new/project",
        token: "new-token",
        startedAt: Date.now(),
      };

      await registerServer(entry);
      const registry = await readRegistry();
      
      expect(registry.servers).toHaveLength(1);
      expect(registry.servers[0].sessionId).toBe("new-session");
    });

    it("should replace existing server with same sessionId", async () => {
      const entry1: RegistryEntry = {
        sessionId: "same-session",
        port: 2222,
        cwd: "/project/1",
        token: "token1",
        startedAt: Date.now(),
      };

      const entry2: RegistryEntry = {
        sessionId: "same-session",
        port: 3333,
        cwd: "/project/2",
        token: "token2",
        startedAt: Date.now(),
      };

      await registerServer(entry1);
      await registerServer(entry2);
      
      const registry = await readRegistry();
      expect(registry.servers).toHaveLength(1);
      expect(registry.servers[0].port).toBe(3333);
    });
  });

  describe("unregisterServer", () => {
    it("should remove server from registry", async () => {
      const entry: RegistryEntry = {
        sessionId: "to-remove",
        port: 4444,
        cwd: "/remove/me",
        token: "remove-token",
        startedAt: Date.now(),
      };

      await registerServer(entry);
      await unregisterServer("to-remove");
      
      const registry = await readRegistry();
      expect(registry.servers).toHaveLength(0);
    });

    it("should not fail when removing non-existent server", async () => {
      await expect(unregisterServer("non-existent")).resolves.not.toThrow();
    });
  });
});
