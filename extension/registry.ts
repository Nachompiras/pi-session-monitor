import { writeFile, readFile, mkdir } from "node:fs/promises";
import { dirname } from "node:path";
import { homedir } from "node:os";
import type { Registry, RegistryEntry } from "./types.js";

const REGISTRY_PATH = `${homedir()}/.pi/agent/.session-servers.json`;

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
