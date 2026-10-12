// Owner-private connection store. Bearer tokens live only here and in daemon memory.
import { closeSync, constants, fstatSync, fsyncSync, lstatSync, mkdirSync, openSync, readSync, renameSync, unlinkSync, writeSync } from "node:fs";
import { randomBytes } from "node:crypto";
import { homedir } from "node:os";
import { join } from "node:path";
import { Failure, isObject } from "./util.ts";

export interface Environment {
  /** Pinned server identity; the stable key for everything else. */
  environmentId: string;
  label: string;
  url: string;
  token: string;
  /** Epoch seconds. */
  expiresAt: number;
  /** When set, the URL is rediscovered from an existing `ssh -L` forward to this host. */
  sshHost?: string;
}

export interface Config {
  version: 1;
  environments: Environment[];
}

export const MAX_ENVIRONMENTS = 12;
const MAX_CONFIG_BYTES = 64 * 1024;

export function configDir(): string {
  return process.env.T3_LOUPE_CONFIG_DIR || join(homedir(), ".config/t3-loupe");
}

/** Reject anything but an owner-only directory reached without symlinks. */
function checkPrivateDir(dir: string) {
  const info = lstatSync(dir);
  if (!info.isDirectory() || info.uid !== process.getuid!() || info.mode & 0o077) throw new Failure("private_config_required");
}

export function loadConfig(dir = configDir()): Config {
  try {
    checkPrivateDir(dir);
  } catch (error: any) {
    if (error?.code === "ENOENT") return { version: 1, environments: [] };
    throw error;
  }
  let fd: number;
  try {
    fd = openSync(join(dir, "connections.json"), constants.O_RDONLY | constants.O_NOFOLLOW);
  } catch (error: any) {
    if (error?.code === "ENOENT") return { version: 1, environments: [] };
    if (error?.code === "ELOOP") throw new Failure("private_config_required");
    throw error;
  }
  try {
    const info = fstatSync(fd);
    if (!info.isFile() || info.uid !== process.getuid!() || info.mode & 0o077) throw new Failure("private_config_required");
    const buffer = Buffer.alloc(MAX_CONFIG_BYTES + 1);
    let length = 0;
    for (;;) {
      const n = readSync(fd, buffer, length, buffer.length - length, null);
      if (n === 0) break;
      length += n;
      if (length > MAX_CONFIG_BYTES) throw new Failure("config_too_large");
    }
    return validate(JSON.parse(buffer.subarray(0, length).toString("utf8")));
  } catch (error) {
    if (error instanceof Failure) throw error;
    throw new Failure("config_invalid");
  } finally {
    closeSync(fd);
  }
}

function validate(data: unknown): Config {
  if (!isObject(data) || data.version !== 1 || !Array.isArray(data.environments) || data.environments.length > MAX_ENVIRONMENTS) {
    throw new Failure("config_invalid");
  }
  const seen = new Set<string>();
  const environments: Environment[] = [];
  for (const e of data.environments) {
    if (!isObject(e) || typeof e.environmentId !== "string" || typeof e.url !== "string" || typeof e.token !== "string") {
      throw new Failure("config_invalid");
    }
    if (seen.has(e.environmentId)) throw new Failure("config_invalid");
    seen.add(e.environmentId);
    environments.push({
      environmentId: e.environmentId,
      label: typeof e.label === "string" && e.label.trim() ? e.label.trim().slice(0, 40) : e.environmentId.slice(0, 8),
      url: e.url,
      token: e.token,
      expiresAt: typeof e.expiresAt === "number" ? e.expiresAt : 0,
      ...(typeof e.sshHost === "string" && e.sshHost ? { sshHost: e.sshHost } : {}),
    });
  }
  return { version: 1, environments };
}

export function saveConfig(config: Config, dir = configDir()) {
  validate(config);
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  checkPrivateDir(dir);
  const temp = join(dir, `.connections-${randomBytes(8).toString("hex")}`);
  const fd = openSync(temp, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600);
  try {
    writeSync(fd, JSON.stringify(config, null, 2) + "\n");
    fsyncSync(fd);
  } finally {
    closeSync(fd);
  }
  try {
    renameSync(temp, join(dir, "connections.json"));
    const dirFd = openSync(dir, constants.O_RDONLY | constants.O_DIRECTORY);
    try { fsyncSync(dirFd); } finally { closeSync(dirFd); }
  } finally {
    try { unlinkSync(temp); } catch {}
  }
}

/** Insert or replace by environmentId; a label change follows the identity. */
export function upsertEnvironment(config: Config, env: Environment): Config {
  const others = config.environments.filter((e) => e.environmentId !== env.environmentId);
  if (others.length >= MAX_ENVIRONMENTS) throw new Failure("too_many_environments");
  return { version: 1, environments: [...others, env] };
}
