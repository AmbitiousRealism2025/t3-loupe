// Phase 0 probe: records raw T3 WebSocket frames for fixture building.
// Output goes to a private cache dir (titles and paths are private data).
// Usage: node tools/probe.ts [seconds=20]
import { readFileSync, mkdirSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { checkEndpoint, getDescriptor, requestJson } from "../daemon/http.ts";
import { assertOwnListener } from "../daemon/listener.ts";
import { existingTunnel } from "../daemon/tunnel.ts";
import { failureCode } from "../daemon/util.ts";

const seconds = Number(process.argv[2] ?? 20);
const config = JSON.parse(readFileSync(join(homedir(), ".config/t3-loupe/connections.json"), "utf8"));
const outDir = join(homedir(), ".cache/t3-loupe/probe");
mkdirSync(outDir, { recursive: true, mode: 0o700 });

// Same rules as the collector, through the same helpers: the pinned identity is verified
// before the token is used, and every request carrying the token or the socket ticket checks
// that a loopback listener belongs to this user (requestJson and the explicit check before the
// WebSocket). Redirects, timeouts and size caps come from requestJson too.
async function probe(env: any) {
  const base = env.sshHost ? existingTunnel(env.sshHost) : env.url;
  const log: any[] = [];
  const note = (dir: string, data: unknown) => log.push({ t: Date.now(), dir, data });
  const descriptor = await getDescriptor(base);
  note("descriptor", descriptor);
  if (descriptor.environmentId !== env.environmentId) { console.log(env.label, "server identity changed; not sending the token"); return; }
  const session = await requestJson(base, "/api/auth/session", { token: env.token, maxBytes: 64 * 1024 })
    .then((body) => ({ status: 200, body }), (error) => ({ status: failureCode(error), body: null }));
  note("session", session);
  const ticket = await requestJson(base, "/api/auth/websocket-ticket", { method: "POST", token: env.token, maxBytes: 16 * 1024 });
  note("ticket", { expiresAt: ticket.expiresAt });
  assertOwnListener(checkEndpoint(base));
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
