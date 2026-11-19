// Finds an existing `ssh -L <port>:127.0.0.1:3773 <host>` forward. Never starts one.
import { readdirSync, readFileSync, statSync } from "node:fs";
import { isLoopbackHost } from "./listener.ts";
import { Failure } from "./util.ts";

const LOOPBACK = new Set(["127.0.0.1", "localhost"]);

// ssh(1) options that take an argument, which may be joined (`-p22`) or the next word (`-p 22`).
const SSH_ARG_OPTIONS = new Set("BbcDEeFIiJLlmOoPpQRSWw");

/**
 * The destination and `-L` specs of an ssh command line, read the way ssh parses options, so
 * `-L13773:...`, `-NfL ...` and option values such as `-J jump` are told apart from the destination.
 * Options may also follow the destination; the next plain word starts the remote command.
 */
function parseSsh(args: string[]): { destination: string | null; forwards: string[] } {
  let destination: string | null = null;
  const forwards: string[] = [];
  for (let i = 1; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--") {
      destination ??= args[i + 1] ?? null;
      break;
    }
    if (!arg.startsWith("-") || arg.length < 2) {
      if (destination !== null) break;
      destination = arg;
      continue;
    }
    for (let j = 1; j < arg.length; j++) {
      if (!SSH_ARG_OPTIONS.has(arg[j])) continue;
      const value = j + 1 < arg.length ? arg.slice(j + 1) : args[++i];
      if (arg[j] === "L" && value !== undefined) forwards.push(value);
      break;
    }
  }
  return { destination, forwards };
}

/** Select only a forward that belongs to the configured SSH target. */
export function tunnelUrl(args: string[], host: string, remotePort = 3773): string | null {
  const { destination, forwards } = parseSsh(args);
  if (destination !== host && !destination?.endsWith("@" + host)) return null;
  for (const spec of forwards) {
    const parts = spec.split(":");
    let localPort: string, remoteHost: string, port: string;
    if (parts.length === 3) {
      [localPort, remoteHost, port] = parts;
    } else if (parts.length === 4) {
      if (!LOOPBACK.has(parts[0])) continue;
      [, localPort, remoteHost, port] = parts;
    } else {
      continue;
    }
    const local = Number(localPort);
    if (LOOPBACK.has(remoteHost) && port === String(remotePort) && /^\d+$/.test(localPort) && local > 0 && local < 65536) {
      return `http://127.0.0.1:${local}`;
    }
  }
  return null;
}

export function existingTunnel(host: string, procRoot = "/proc"): string {
  const uid = process.getuid!();
  for (const pid of readdirSync(procRoot)) {
    if (!/^\d+$/.test(pid)) continue;
    try {
      if (statSync(`${procRoot}/${pid}`).uid !== uid) continue;
      if (readFileSync(`${procRoot}/${pid}/comm`, "utf8").trim() !== "ssh") continue;
      const args = readFileSync(`${procRoot}/${pid}/cmdline`, "utf8").split("\0").filter(Boolean);
      const url = tunnelUrl(args, host);
      if (url) return url;
    } catch {}
  }
  throw new Failure("tunnel_missing");
}

/** A machine paired over SSH is reached through its forward, unless it was paired at a direct (HTTPS) URL. */
export function usesTunnel(env: { url: string; sshHost?: string }): boolean {
  if (!env.sshHost) return false;
  try { return !env.url || isLoopbackHost(new URL(env.url).hostname); } catch { return true; }
}

/** Where to reach a paired machine right now. */
export function environmentBase(env: { url: string; sshHost?: string }, procRoot = "/proc"): string {
  return usesTunnel(env) ? existingTunnel(env.sshHost!, procRoot) : env.url;
}
