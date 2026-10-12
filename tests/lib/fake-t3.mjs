// A fake T3 server for tests: descriptor, session, ws ticket, HTTP shell, and a /ws endpoint
// speaking Effect-RPC JSON over a minimal RFC 6455 implementation (no dependencies).
import { createHash } from "node:crypto";
import { createServer } from "node:http";

const GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

function encodeFrame(text) {
  const payload = Buffer.from(text, "utf8");
  const len = payload.length;
  const header = len < 126 ? Buffer.from([0x81, len]) : len < 65536
    ? Buffer.from([0x81, 126, len >> 8, len & 255])
    : Buffer.concat([Buffer.from([0x81, 127]), (() => { const b = Buffer.alloc(8); b.writeBigUInt64BE(BigInt(len)); return b; })()]);
  return Buffer.concat([header, payload]);
}

function* decodeFrames(state, chunk) {
  state.buf = Buffer.concat([state.buf, chunk]);
  for (;;) {
    const b = state.buf;
    if (b.length < 2) return;
    const opcode = b[0] & 0x0f;
    let len = b[1] & 0x7f;
    let off = 2;
    if (len === 126) { if (b.length < 4) return; len = b.readUInt16BE(2); off = 4; }
    else if (len === 127) { if (b.length < 10) return; len = Number(b.readBigUInt64BE(2)); off = 10; }
    const masked = (b[1] & 0x80) !== 0;
    const maskOff = off;
    if (masked) off += 4;
    if (b.length < off + len) return;
    const data = Buffer.from(b.subarray(off, off + len));
    if (masked) for (let i = 0; i < data.length; i++) data[i] ^= b[maskOff + (i % 4)];
    state.buf = b.subarray(off + len);
    yield { opcode, data };
  }
}

export class FakeT3 {
  constructor({ environmentId = "env-1", token = "tok", snapshot } = {}) {
    this.environmentId = environmentId;
    this.token = token;
    this.snapshot = snapshot ?? { schemaVersion: 2, snapshotSequence: 10, projects: [], threads: [], archivedThreads: [] };
    this.sockets = new Set();
    this.received = [];     // client → server RPC messages
    this.subscriptions = []; // { socket, id, tag, payload }
    this.config = { version: 1, type: "snapshot", config: { providers: [] } };
    this.server = createServer((req, res) => this.http(req, res));
    this.server.on("upgrade", (req, socket) => this.upgrade(req, socket));
  }

  listen() {
    return new Promise((resolve) => this.server.listen(0, "127.0.0.1", () => {
      this.url = `http://127.0.0.1:${this.server.address().port}`;
      resolve(this.url);
    }));
  }

  close() {
    for (const s of this.sockets) s.destroy();
    return new Promise((resolve) => this.server.close(resolve));
  }

  authorized(req) { return req.headers.authorization === `Bearer ${this.token}`; }

  http(req, res) {
    const json = (status, body) => { res.writeHead(status, { "content-type": "application/json" }); res.end(JSON.stringify(body)); };
    const path = req.url.split("?")[0];
    if (path === "/.well-known/t3/environment") return json(200, { environmentId: this.environmentId, label: "fake", serverVersion: "test", orchestrationProtocolVersion: 2 });
    if (!this.authorized(req)) return json(401, { error: "unauthorized" });
    if (path === "/api/auth/session") return json(200, { authenticated: true, scopes: ["orchestration:read"], expiresAt: new Date(Date.now() + 20 * 86400_000).toISOString() });
    if (path === "/api/auth/websocket-ticket") return json(200, { ticket: "ticket-1", expiresAt: new Date(Date.now() + 300_000).toISOString() });
    if (path === "/api/orchestration/shell") return json(200, this.snapshot);
    json(404, {});
  }

  upgrade(req, socket) {
    const url = new URL(req.url, "http://x");
    if (url.searchParams.get("orchestrationProtocol") !== "2") { socket.end("HTTP/1.1 426 Upgrade Required\r\n\r\n"); return; }
    if (url.searchParams.get("wsTicket") !== "ticket-1") { socket.end("HTTP/1.1 401 Unauthorized\r\n\r\n"); return; }
    const accept = createHash("sha1").update(req.headers["sec-websocket-key"] + GUID).digest("base64");
    socket.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${accept}\r\n\r\n`);
    this.sockets.add(socket);
    const state = { buf: Buffer.alloc(0) };
    socket.on("data", (chunk) => {
      for (const frame of decodeFrames(state, chunk)) {
        if (frame.opcode === 8) { socket.end(); return; }
        if (frame.opcode !== 1) continue;
        this.onMessage(socket, JSON.parse(frame.data.toString("utf8")));
      }
    });
    socket.on("close", () => this.sockets.delete(socket));
    socket.on("error", () => {});
  }

  send(socket, message) { if (!socket.destroyed) socket.write(encodeFrame(JSON.stringify(message))); }

  onMessage(socket, msg) {
    this.received.push(msg);
    if (msg._tag === "Ping") return this.send(socket, { _tag: "Pong" });
    if (msg._tag !== "Request") return;
    this.subscriptions.push({ socket, id: msg.id, tag: msg.tag, payload: msg.payload });
    if (msg.tag === "orchestration.subscribeShell") {
      if (msg.payload.afterSequence === undefined) this.chunk(socket, msg.id, [{ kind: "snapshot", snapshot: this.snapshot }]);
      this.chunk(socket, msg.id, [{ kind: "synchronized" }]);
    } else if (msg.tag === "subscribeServerConfig") {
      this.chunk(socket, msg.id, [this.config]);
    } else if (msg.tag === "orchestration.subscribeThread") {
      this.chunk(socket, msg.id, [{ kind: "snapshot", snapshotSequence: 1, projection: this.projection?.(msg.payload.threadId) ?? { turnItems: [], runs: [], runtimeRequests: [], providerThreads: [], subagents: [] } }, { kind: "synchronized" }]);
    }
  }

  chunk(socket, requestId, values) { this.send(socket, { _tag: "Chunk", requestId, values }); }

  /** Push shell items to every live shell subscription. */
  pushShell(values) {
    for (const s of this.subscriptions) if (s.tag === "orchestration.subscribeShell") this.chunk(s.socket, s.id, values);
  }

  dropConnections() { for (const s of this.sockets) s.destroy(); this.subscriptions = []; }

  acks(requestId) { return this.received.filter((m) => m._tag === "Ack" && m.requestId === requestId).length; }
}
