// Finds an existing `ssh -L <port>:127.0.0.1:3773 <host>` forward. Never starts one.
import { readdirSync, readFileSync, statSync } from "node:fs";
import { Failure } from "./util.ts";

const LOOPBACK = new Set(["127.0.0.1", "localhost"]);

/** Select only a forward that belongs to the configured SSH target. */
export function tunnelUrl(args: string[], host: string, remotePort = 3773): string | null {
  if (!args.some((a) => a === host || a.endsWith("@" + host))) return null;
  for (let i = 0; i < args.length - 1; i++) {
    if (args[i] !== "-L") continue;
    const parts = args[i + 1].split(":");
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
