import { EnvironmentConnection } from "../../daemon/connection.ts";

export async function stoppedConnect(stage, reject = false) {
  const originalFetch = globalThis.fetch;
  const originalSocket = globalThis.WebSocket;
  const reached = Promise.withResolvers();
  const resume = Promise.withResolvers();
  const sockets = [];
  const requests = [];
  const responses = {
    descriptor: { environmentId: "env-1", orchestrationProtocolVersion: 2 },
    session: { authenticated: true },
    ticket: { ticket: "ticket" },
    shell: { schemaVersion: 2, projects: [], threads: [] },
  };
  const routes = {
    "/.well-known/t3/environment": "descriptor",
    "/api/auth/session": "session",
    "/api/auth/websocket-ticket": "ticket",
    "/api/orchestration/shell": "shell",
  };
  globalThis.fetch = async (url) => {
    const route = routes[new URL(url).pathname];
    requests.push(route);
    if (route === stage) {
      reached.resolve();
      await resume.promise;
      if (reject) throw new Error("fetch failed");
    }
    return Response.json(responses[route]);
  };
  globalThis.WebSocket = class {
    static OPEN = 1;
    readyState = 0;
    messages = [];
    constructor() {
      sockets.push(this);
      queueMicrotask(async () => {
        if (stage === "socket") {
          reached.resolve();
          await resume.promise;
        }
        if (stage === "shell" || reject) return this.onerror();
        this.readyState = 1;
        this.onopen();
      });
    }
    send(message) { this.messages.push(JSON.parse(message)); }
    close() { this.readyState = 3; }
  };
  const conn = new EnvironmentConnection({ environmentId: "env-1", label: "Mock", url: "https://mock.example", token: "tok" });
  try {
    const connecting = conn.connect();
    await reached.promise;
    conn.stop();
    resume.resolve();
    await connecting;
    return {
      openSockets: sockets.filter((s) => s.readyState === 1).length,
      subscriptions: conn.socket?.streams.size ?? 0,
      subscriptionRequests: sockets.flatMap((s) => s.messages).filter((m) => m._tag === "Request").length,
      polling: Boolean(conn.pollTimer),
      requests,
    };
  } finally {
    conn.stop();
    globalThis.fetch = originalFetch;
    globalThis.WebSocket = originalSocket;
  }
}
