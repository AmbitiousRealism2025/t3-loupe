// Phase 0 probe: records raw T3 WebSocket frames for fixture building.
// Output goes to a private cache dir (titles and paths are private data).
// Usage: node tools/probe.ts [seconds=20]
import { readFileSync, mkdirSync, writeFileSync, readdirSync, readlinkSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const seconds = Number(process.argv[2] ?? 20);
const config = JSON.parse(readFileSync(join(homedir(), ".config/t3-loupe/connections.json"), "utf8"));
const outDir = join(homedir(), ".cache/t3-loupe/probe");
mkdirSync(outDir, { recursive: true, mode: 0o700 });

function tunnelUrl(host: string): string | null {
  for (const pid of readdirSync("/proc").filter((p) => /^\d+$/.test(p))) {
    try {
      if (statSync(`/proc/${pid}`).uid !== process.getuid!()) continue;
      if (readFileSync(`/proc/${pid}/comm`, "utf8").trim() !== "ssh") continue;
      const args = readFileSync(`/proc/${pid}/cmdline`, "utf8").split("\0").filter(Boolean);
      if (!args.some((a) => a === host || a.endsWith("@" + host))) continue;
      for (let i = 0; i < args.length - 1; i++) {
        if (args[i] !== "-L") continue;
        const parts = args[i + 1].split(":");
        const [local, rhost, rport] = parts.length === 4 ? parts.slice(1) : parts;
        if (["127.0.0.1", "localhost"].includes(rhost) && rport === "3773") return `http://127.0.0.1:${local}`;
      }
    } catch {}
  }
  return null;
}
void readlinkSync;

async function probe(env: any) {
  const base = env.sshHost ? tunnelUrl(env.sshHost) : env.url;
  const log: any[] = [];
  const note = (dir: string, data: unknown) => log.push({ t: Date.now(), dir, data });
  if (!base) { console.log(env.label, "no tunnel"); return; }
  const headers = { authorization: `Bearer ${env.token}`, "x-t3-orchestration-protocol": "2", accept: "application/json" };
  const descriptor = await (await fetch(`${base}/.well-known/t3/environment`)).json();
  note("descriptor", descriptor);
  const session = await fetch(`${base}/api/auth/session`, { headers });
  note("session", { status: session.status, body: await session.json().catch(() => null) });
  const ticketRes = await fetch(`${base}/api/auth/websocket-ticket`, { method: "POST", headers });
  const ticket = await ticketRes.json();
  note("ticket", { status: ticketRes.status, expiresAt: ticket.expiresAt });
  const wsUrl = `${base.replace(/^http/, "ws")}/ws?orchestrationProtocol=2&wsTicket=${encodeURIComponent(ticket.ticket)}&clientSurface=t3-loupe-probe`;
  await new Promise<void>((resolve) => {
    const ws = new WebSocket(wsUrl);
    const send = (m: unknown) => { note("out", m); ws.send(JSON.stringify(m)); };
    ws.onopen = () => {
      send({ _tag: "Request", id: "1", tag: "orchestration.subscribeShell", payload: { requestCompletionMarker: true }, headers: [] });
      send({ _tag: "Request", id: "2", tag: "subscribeServerConfig", payload: {}, headers: [] });
      send({ _tag: "Ping" });
    };
    ws.onmessage = (ev) => {
      const msg = JSON.parse(String(ev.data));
      note("in", msg);
      if (msg._tag === "Chunk") send({ _tag: "Ack", requestId: msg.requestId });
    };
    ws.onerror = (e: any) => { note("error", String(e?.message ?? e)); };
    ws.onclose = (e) => { note("close", { code: e.code, reason: e.reason }); resolve(); };
    setTimeout(() => ws.close(1000), seconds * 1000);
  });
  const file = join(outDir, `${env.label}.raw.ndjson`);
  writeFileSync(file, log.map((l) => JSON.stringify(l)).join("\n") + "\n", { mode: 0o600 });
  const inbound = log.filter((l) => l.dir === "in");
  console.log(env.label, base, "descriptor v" + descriptor.orchestrationProtocolVersion, "session", log[1].data.status,
    "frames in:", inbound.length, "tags:", [...new Set(inbound.map((l) => l.data._tag))].join(","), "->", file);
}

await Promise.all(config.environments.map((e: any) => probe(e).catch((err) => console.log(e.label, "error", err.message))));
