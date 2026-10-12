// Loopback trust: before a secret (bearer token, socket ticket, pairing credential) goes to a
// loopback address, check that the socket listening there belongs to this user. Any local account
// can bind a vacant port, so a loopback address alone proves nothing about who answers.
// Linux only: reads /proc/net/tcp and /proc/net/tcp6. When ownership can't be established, the
// secret isn't sent.
import { readFileSync } from "node:fs";
import { Failure } from "./util.ts";

const LISTEN = "0A";
const ANY4 = "00000000";
const ANY6 = "0".repeat(32);
const LOOPBACK6 = "00000000000000000000000001000000"; // ::1 as /proc writes it

/** True for the loopback hosts `checkEndpoint` accepts plain HTTP on. */
export function isLoopbackHost(hostname: string): boolean {
  return hostname === "[::1]" || /^127\.\d+\.\d+\.\d+$/.test(hostname);
}

/** An IPv4 address as /proc/net/tcp writes it: one little-endian 32-bit word in hex. */
function ipv4Hex(ip: string): string {
  return ip.split(".").map((part) => Number(part).toString(16).padStart(2, "0")).reverse().join("").toUpperCase();
}

/** Local addresses (by /proc file) whose listener would accept a connection to `hostname`. */
function acceptingAddresses(hostname: string): { tcp: Set<string>; tcp6: Set<string> } {
  if (hostname === "[::1]") return { tcp: new Set(), tcp6: new Set([LOOPBACK6, ANY6]) };
  const v4 = ipv4Hex(hostname);
  return { tcp: new Set([v4, ANY4]), tcp6: new Set([ANY6, "0000000000000000FFFF0000" + v4]) };
}

/** UIDs of the sockets listening on `hostname:port` that a connection there could reach. */
export function listenerUids(hostname: string, port: number, procRoot = "/proc"): number[] {
  const accepting = acceptingAddresses(hostname);
  const wantPort = port.toString(16).toUpperCase().padStart(4, "0");
  const uids: number[] = [];
  let readable = false;
  for (const file of ["tcp", "tcp6"] as const) {
    let text: string;
    try {
      text = readFileSync(`${procRoot}/net/${file}`, "utf8");
      readable = true;
    } catch {
      continue;
    }
    for (const line of text.split("\n").slice(1)) {
      const cols = line.trim().split(/\s+/);
      if (cols.length < 8 || cols[3] !== LISTEN) continue;
      const [address, hexPort] = cols[1].split(":");
      if (hexPort !== wantPort || !accepting[file].has(address)) continue;
      uids.push(Number(cols[7]));
    }
  }
  if (!readable) throw new Failure("listener_untrusted", "cannot read /proc/net");
  return uids;
}

/** Throw unless every socket that could answer a loopback `url` is owned by `uid`. Non-loopback URLs pass (they need HTTPS). */
export function assertOwnListener(url: URL, procRoot = "/proc", uid = process.getuid!()): void {
  if (!isLoopbackHost(url.hostname)) return;
  const port = Number(url.port || (url.protocol === "https:" ? 443 : 80));
  const uids = listenerUids(url.hostname, port, procRoot);
  if (uids.length === 0) throw new Failure("offline", "nothing is listening");
  if (uids.some((owner) => owner !== uid)) throw new Failure("listener_untrusted", "the listening socket belongs to another user");
}
