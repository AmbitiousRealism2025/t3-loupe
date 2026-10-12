// Minimal Effect-RPC client over T3's /ws endpoint (JSON serialization, one message per frame).
// Streams must be acknowledged chunk by chunk; the server waits for each Ack.
import { Failure, isObject } from "./util.ts";

export const MAX_FRAME = 16 * 1024 * 1024;
const PING_INTERVAL = 20_000;
const PONG_TIMEOUT = 10_000;

export interface StreamHandlers {
  onValues: (values: unknown[]) => void;
  onExit: (exit: unknown) => void;
}

export class RpcSocket {
  private ws: WebSocket;
  private nextId = 1;
  private streams = new Map<string, StreamHandlers>();
  private pingTimer: ReturnType<typeof setInterval> | undefined;
  private pongDeadline: ReturnType<typeof setTimeout> | undefined;
  private closed = false;
  onClose: (code: string) => void = () => {};

  private constructor(ws: WebSocket) {
    this.ws = ws;
  }

  static connect(base: string, ticket: string, timeoutMs = 10_000): Promise<RpcSocket> {
    const url = new URL("/ws", base.replace(/^http/, "ws"));
    url.searchParams.set("orchestrationProtocol", "2");
    url.searchParams.set("wsTicket", ticket);
    url.searchParams.set("clientSurface", "t3-loupe");
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(url);
      const timer = setTimeout(() => { ws.close(); reject(new Failure("offline", "socket open timeout")); }, timeoutMs);
      ws.onopen = () => {
        clearTimeout(timer);
        const socket = new RpcSocket(ws);
        socket.attach();
        resolve(socket);
      };
      ws.onerror = () => { clearTimeout(timer); reject(new Failure("offline", "socket error")); };
      ws.onclose = (event) => {
        clearTimeout(timer);
        // An HTTP 426 on upgrade surfaces as a failed open.
        reject(new Failure(event.code === 1008 ? "authentication_required" : "offline", `socket closed ${event.code}`));
      };
    });
  }

  private attach() {
    this.ws.onmessage = (event) => this.receive(event.data);
    this.ws.onerror = () => {};
    this.ws.onclose = (event) => this.shutdown(event.code === 1008 ? "authentication_required" : "offline");
    this.pingTimer = setInterval(() => this.ping(), PING_INTERVAL);
  }

  private ping() {
    this.send({ _tag: "Ping" });
    if (!this.pongDeadline) this.pongDeadline = setTimeout(() => this.close("offline"), PONG_TIMEOUT);
  }

  private send(message: unknown) {
    if (!this.closed && this.ws.readyState === WebSocket.OPEN) this.ws.send(JSON.stringify(message));
  }

  private receive(data: unknown) {
    const text = typeof data === "string" ? data : Buffer.from(data as ArrayBuffer).toString("utf8");
    if (text.length > MAX_FRAME) return this.close("response_too_large");
    let message: any;
    try {
      message = JSON.parse(text);
    } catch {
      return this.close("failed");
    }
    if (!isObject(message)) return;
    switch (message._tag) {
      case "Pong":
        clearTimeout(this.pongDeadline);
        this.pongDeadline = undefined;
        return;
      case "Chunk": {
        const id = String(message.requestId);
        const stream = this.streams.get(id);
        // Ack first so server back-pressure never stalls on our processing.
        this.send({ _tag: "Ack", requestId: id });
        if (stream && Array.isArray(message.values)) stream.onValues(message.values);
        return;
      }
      case "Exit": {
        const id = String(message.requestId);
        const stream = this.streams.get(id);
        this.streams.delete(id);
        stream?.onExit(message.exit);
        return;
      }
      case "ClientProtocolError":
      case "Defect":
        return this.close("failed");
    }
  }

  /** Opens a streaming RPC; returns its request id. */
  stream(tag: string, payload: unknown, handlers: StreamHandlers): string {
    const id = String(this.nextId++);
    this.streams.set(id, handlers);
    this.send({ _tag: "Request", id, tag, payload, headers: [] });
    return id;
  }

  /** Cancels a stream; the server answers with an interrupted Exit, which is ignored. */
  interrupt(id: string) {
    if (!this.streams.delete(id)) return;
    this.send({ _tag: "Interrupt", requestId: id, interruptors: [] });
  }

  /** Unary RPC: resolves with the Success value of the Exit. */
  call(tag: string, payload: unknown, timeoutMs = 15_000): Promise<unknown> {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { this.streams.delete(id); reject(new Failure("offline", "rpc timeout")); }, timeoutMs);
      const id = this.stream(tag, payload, {
        onValues: () => {},
        onExit: (exit: any) => {
          clearTimeout(timer);
          if (exit?._tag === "Success") resolve(exit.value);
          else reject(new Failure(exitIsForbidden(exit) ? "authentication_required" : "failed", "rpc failure"));
        },
      });
    });
  }

  get isOpen() {
    return !this.closed;
  }

  close(code = "closed") {
    if (this.closed) return;
    try { this.ws.close(1000); } catch {}
    this.shutdown(code);
  }

  private shutdown(code: string) {
    if (this.closed) return;
    this.closed = true;
    clearInterval(this.pingTimer);
    clearTimeout(this.pongDeadline);
    const streams = [...this.streams.values()];
    this.streams.clear();
    for (const s of streams) s.onExit({ _tag: "Failure", cause: [{ _tag: "Interrupt" }] });
    this.onClose(code);
  }
}

function exitIsForbidden(exit: any): boolean {
  return JSON.stringify(exit ?? "").includes("Forbidden") || JSON.stringify(exit ?? "").includes("scope");
}
