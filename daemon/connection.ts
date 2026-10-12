// One live connection per paired environment.
//   resolve URL (SSH forward) → descriptor (pinned id) → session check → ws ticket
//   → /ws: subscribeShell (+ resume cursor), subscribeServerConfig, subscribeThread per watched thread.
// Falls back to HTTP polling while the socket cannot be established; keeps last-good rows as stale.
import type { Environment } from "./config.ts";
import { type Notice, TransitionDetector } from "./events.ts";
import { getDescriptor, requestJson } from "./http.ts";
import { ATTENTION, BUSY, buildRows, countRows, type Counts, type Row } from "./model.ts";
import { RpcSocket } from "./rpc.ts";
import { ShellStore } from "./shell-store.ts";
import { type Detail, ThreadWatch } from "./thread-watch.ts";
import { existingTunnel } from "./tunnel.ts";
import { clean, Failure, failureCode, isObject, ms } from "./util.ts";

export type ConnectionState =
  | "connecting" | "live" | "polling" | "offline" | "tunnel_missing" | "authentication_required"
  | "unsupported" | "environment_changed" | "expired" | "response_too_large" | "failed";

export interface UsageWindow { label: string; kind: string; usedPercent: number; resetsAt: number | null; durationMins: number }
export interface ProviderView {
  id: string; name: string; driver: string; status: string; auth: string;
  version: string; windows: UsageWindow[]; checkedAt: number | null;
}

export interface EnvironmentView {
  id: string;
  label: string;
  hostLabel: string;
  state: ConnectionState;
  stale: boolean;
  url: string;
  serverVersion: string;
  lastLiveAt: number | null;
  sessionExpiresAt: number | null;
  retryAt: number | null;
  providers: ProviderView[];
  counts: Counts;
  rows: Row[];
}

const MAX_WATCHES = 8;
const WATCH_LINGER = 20_000;
const POLL_INTERVAL = 15_000;
const SESSION_RECHECK = 6 * 3600_000;
const BACKOFF_MAX = 60_000;

interface WatchSlot {
  watch: ThreadWatch;
  requestId: string | null;
  pinnedUntil: number;   // explicit detail request keeps it alive
  lingerUntil: number;
}

export class EnvironmentConnection {
  readonly env: Environment;
  state: ConnectionState = "connecting";
  private store = new ShellStore();
  private socket: RpcSocket | null = null;
  private base = "";
  private hostLabel = "";
  private serverVersion = "";
  private lastLiveAt: number | null = null;
  private sessionExpiresAt: number | null;
  private sessionCheckedAt = 0;
  private providers: ProviderView[] = [];
  private rows: Row[] = [];
  private hasData = false;
  private watches = new Map<string, WatchSlot>();
  private detector = new TransitionDetector();
  private failures = 0;
  private timer: ReturnType<typeof setTimeout> | undefined;
  private pollTimer: ReturnType<typeof setInterval> | undefined;
  private retryAt: number | null = null;
  private stopped = false;
  private connecting = false;
  private wasLive = false;
  private outageNotified = false;
  private expiryTimer: ReturnType<typeof setInterval> | undefined;
  private expiryNoticeDay = "";

  onChange: () => void = () => {};
  onNotice: (n: Notice) => void = () => {};
  onDetail: (threadId: string, detail: Detail) => void = () => {};

  constructor(env: Environment) {
    this.env = env;
    this.sessionExpiresAt = env.expiresAt ? env.expiresAt * 1000 : null;
  }

  start() {
    this.connect();
    this.expiryTimer = setInterval(() => this.checkExpiry(), 3600_000);
  }

  /** One "pairing expiring" notice per day while fewer than three days remain. */
  checkExpiry(now = Date.now()) {
    if (this.sessionExpiresAt === null) return;
    const left = this.sessionExpiresAt - now;
    const day = new Date(now).toDateString();
    if (left <= 0 || left > 3 * 86400_000 || this.expiryNoticeDay === day) return;
    this.expiryNoticeDay = day;
    const days = Math.max(1, Math.round(left / 86400_000));
    this.onNotice({
      kind: "session_expiring", severity: "attention", envId: this.env.environmentId, threadId: "",
      title: `${this.env.label}: T3 pairing expires in ${days} day${days === 1 ? "" : "s"}`,
      body: "Re-pair to keep monitoring (see `t3-loupe doctor`).", at: now,
    });
  }

  stop() {
    this.stopped = true;
    clearInterval(this.expiryTimer);
    clearTimeout(this.timer);
    clearInterval(this.pollTimer);
    this.socket?.close();
  }

  /** Re-attempt now (e.g. user pressed refresh or a tunnel appeared). */
  retryNow() {
    if (this.state === "live" || this.connecting) return;
    clearTimeout(this.timer);
    this.connect();
  }

  private setState(state: ConnectionState) {
    if (this.state === state) return;
    this.state = state;
    const notice = (kind: "environment_offline" | "environment_restored", title: string, body = "") =>
      this.onNotice({ kind, severity: "info", envId: this.env.environmentId, threadId: "", title, body, at: Date.now() });
    // One notice per outage: only after having been live, and only for real failures (not a reconnect blip).
    if (state === "live" || state === "polling") {
      if (this.outageNotified) notice("environment_restored", `${this.env.label} reconnected`);
      this.outageNotified = false;
      this.wasLive = true;
    } else if (state !== "connecting" && this.wasLive && !this.outageNotified) {
      this.outageNotified = true;
      notice("environment_offline", `${this.env.label} disconnected`, label(state));
    }
    this.onChange();
  }

  private schedule(delay: number) {
    clearTimeout(this.timer);
    if (this.stopped) return;
    this.retryAt = Date.now() + delay;
    this.timer = setTimeout(() => this.connect(), delay);
  }

  private backoff(): number {
    const base = Math.min(BACKOFF_MAX, 1000 * 2 ** Math.min(this.failures, 6));
    return Math.round(base * (0.8 + Math.random() * 0.4));
  }

  private async connect() {
    if (this.stopped || this.connecting) return;
    this.connecting = true;
    this.retryAt = null;
    try {
      if (this.sessionExpiresAt !== null && this.sessionExpiresAt <= Date.now()) throw new Failure("expired");
      this.base = this.env.sshHost ? existingTunnel(this.env.sshHost) : this.env.url;
      const descriptor = await getDescriptor(this.base);
      if (descriptor.environmentId !== this.env.environmentId) throw new Failure("environment_changed");
      this.hostLabel = clean(descriptor.label, 40);
      this.serverVersion = clean(descriptor.serverVersion, 60);
      await this.checkSession();
      const { ticket } = await requestJson(this.base, "/api/auth/websocket-ticket", { method: "POST", token: this.env.token, maxBytes: 16 * 1024 });
      if (typeof ticket !== "string") throw new Failure("failed", "no ticket");
      const socket = await RpcSocket.connect(this.base, ticket);
      this.attach(socket);
    } catch (error) {
      this.socket = null;
      const code = failureCode(error);
      this.failures++;
      if (code === "offline" || code === "failed") {
        // Socket path down; keep data flowing over HTTP if the server still answers.
        if (await this.pollOnce()) {
          this.setState("polling");
          this.startPolling();
          this.schedule(this.backoff());
          return;
        }
      }
      this.stopPolling();
      this.setState(code as ConnectionState);
      const slow = code === "authentication_required" || code === "expired" || code === "environment_changed" || code === "unsupported";
      this.schedule(slow ? 5 * 60_000 : code === "tunnel_missing" ? 15_000 : this.backoff());
    } finally {
      this.connecting = false;
    }
  }

  private async checkSession() {
    if (Date.now() - this.sessionCheckedAt < SESSION_RECHECK) return;
    const session = await requestJson(this.base, "/api/auth/session", { token: this.env.token, maxBytes: 64 * 1024 });
    if (session.authenticated !== true) throw new Failure("authentication_required");
    const expires = ms(session.expiresAt);
    if (expires !== null) this.sessionExpiresAt = expires;
    this.sessionCheckedAt = Date.now();
  }

  private attach(socket: RpcSocket) {
    this.socket = socket;
    this.stopPolling();
    socket.onClose = (code) => {
      if (this.socket !== socket) return;
      this.socket = null;
      for (const slot of this.watches.values()) slot.requestId = null;
      if (this.stopped) return;
      this.failures++;
      this.setState(code === "authentication_required" ? "authentication_required" : "connecting");
      this.schedule(this.backoff());
    };
    const payload: Record<string, unknown> = { requestCompletionMarker: true };
    if (this.store.sequence >= 0) payload.afterSequence = this.store.sequence;
    this.store.synchronized = false;
    socket.stream("orchestration.subscribeShell", payload, {
      onValues: (values) => {
        let changed = false;
        for (const v of values) {
          try {
            if (this.store.apply(v).size || (isObject(v) && v.kind === "synchronized")) changed = true;
          } catch {
            socket.close("unsupported");
            return;
          }
        }
        if (this.store.synchronized && this.state !== "live") {
          this.failures = 0;
          this.lastLiveAt = Date.now();
          this.setState("live");
          this.checkExpiry();
        }
        if (changed) this.refresh();
      },
      onExit: () => { if (this.socket === socket) socket.close("offline"); },
    });
    socket.stream("subscribeServerConfig", {}, {
      onValues: (values) => {
        for (const v of values) this.applyServerConfig(v);
        this.onChange();
      },
      onExit: () => {},
    });
    for (const [threadId, slot] of this.watches) this.subscribeThread(threadId, slot);
  }

  private applyServerConfig(v: unknown) {
    if (!isObject(v)) return;
    const providers = v.type === "snapshot" ? v.config?.providers : v.type === "providerStatuses" || v.type === "configUpdated" ? v.payload?.providers : undefined;
    if (!Array.isArray(providers)) return;
    this.providers = providers
      .filter((p: any) => isObject(p) && p.enabled !== false && p.status !== "disabled")
      .slice(0, 16)
      .map((p: any) => ({
        id: clean(p.instanceId, 40),
        name: clean(p.displayName, 40) || clean(p.instanceId, 40),
        driver: clean(p.driver, 30),
        status: clean(p.status, 16),
        auth: clean(p.auth?.status, 20),
        version: clean(p.version, 30),
        checkedAt: ms(p.usageLimits?.checkedAt),
        windows: (Array.isArray(p.usageLimits?.windows) ? p.usageLimits.windows : [])
          .filter((w: any) => isObject(w) && Number.isFinite(w.usedPercent))
          .slice(0, 4)
          .map((w: any) => ({
            label: clean(w.label, 24),
            kind: clean(w.kind, 16),
            usedPercent: Math.max(0, Math.min(100, w.usedPercent)),
            resetsAt: ms(w.resetsAt),
            durationMins: Number.isFinite(w.windowDurationMins) ? w.windowDurationMins : 0,
          })),
      }));
  }

  private startPolling() {
    if (this.pollTimer) return;
    this.pollTimer = setInterval(() => void this.pollOnce(), POLL_INTERVAL);
  }

  private stopPolling() {
    clearInterval(this.pollTimer);
    this.pollTimer = undefined;
  }

  private async pollOnce(): Promise<boolean> {
    try {
      if (!this.base) return false;
      const snapshot = await requestJson(this.base, "/api/orchestration/shell", { token: this.env.token });
      this.store.loadHttpSnapshot(snapshot);
      this.store.synchronized = true;
      this.lastLiveAt = Date.now();
      this.refresh();
      return true;
    } catch (error) {
      const code = failureCode(error);
      if (code === "authentication_required") {
        this.stopPolling();
        this.setState("authentication_required");
      }
      return false;
    }
  }

  /** Recompute rows from the replica, merge live activity, detect transitions, adjust watches. */
  private refresh() {
    const rows = buildRows(this.env.environmentId, this.store.threads.values(), this.store.projects);
    for (const row of rows) {
      const slot = this.watches.get(row.id);
      if (slot?.watch.synchronized || (slot && slot.watch.sequence >= 0)) row.activity = slot.watch.detail().activity;
    }
    for (const n of this.detector.diff(rows, this.env.label, this.store.synchronized)) this.onNotice(n);
    this.rows = rows;
    this.hasData = true;
    this.reconcileWatches();
    this.onChange();
  }

  private reconcileWatches() {
    const now = Date.now();
    const wanted = this.rows
      .filter((r) => BUSY.has(r.state) || ATTENTION.has(r.state))
      .sort((a, b) => Number(Boolean(a.parentId)) - Number(Boolean(b.parentId)))
      .slice(0, MAX_WATCHES)
      .map((r) => r.id);
    for (const id of wanted) {
      const slot = this.watches.get(id) ?? { watch: new ThreadWatch(), requestId: null, pinnedUntil: 0, lingerUntil: 0 };
      slot.lingerUntil = now + WATCH_LINGER;
      if (!this.watches.has(id)) {
        this.watches.set(id, slot);
        this.subscribeThread(id, slot);
      }
    }
    for (const [id, slot] of this.watches) {
      if (slot.lingerUntil > now || slot.pinnedUntil > now) continue;
      if (slot.requestId) this.socket?.interrupt(slot.requestId);
      this.watches.delete(id);
    }
  }

  private subscribeThread(threadId: string, slot: WatchSlot) {
    if (!this.socket || slot.requestId) return;
    const payload: Record<string, unknown> = { threadId, requestCompletionMarker: true, acceptBoundedSnapshot: true };
    if (slot.watch.sequence >= 0) payload.afterSequence = slot.watch.sequence;
    const socket = this.socket;
    slot.requestId = socket.stream("orchestration.subscribeThread", payload, {
      onValues: (values) => {
        let changed = false;
        for (const v of values) changed = slot.watch.apply(v) || changed;
        if (!changed) return;
        const row = this.rows.find((r) => r.id === threadId);
        if (row) row.activity = slot.watch.detail().activity;
        if (slot.pinnedUntil > Date.now()) this.onDetail(threadId, slot.watch.detail());
        this.onChange();
      },
      onExit: () => { if (this.socket === socket) slot.requestId = null; },
    });
  }

  /** Detail drawer: keep a thread subscribed for a while and push its detail. */
  requestDetail(threadId: string, holdMs = 60_000) {
    const now = Date.now();
    let slot = this.watches.get(threadId);
    if (!slot) {
      slot = { watch: new ThreadWatch(), requestId: null, pinnedUntil: 0, lingerUntil: now };
      this.watches.set(threadId, slot);
    }
    slot.pinnedUntil = now + holdMs;
    if (slot.watch.sequence >= 0) this.onDetail(threadId, slot.watch.detail());
    this.subscribeThread(threadId, slot);
    clearTimeout((slot as any).sweep);
    (slot as any).sweep = setTimeout(() => this.reconcileWatches(), holdMs + 1000);
  }

  view(): EnvironmentView {
    const live = this.state === "live" || this.state === "polling";
    return {
      id: this.env.environmentId,
      label: this.env.label,
      hostLabel: this.hostLabel,
      state: this.state,
      stale: !live && this.hasData,
      url: this.base || (this.env.sshHost ? "" : this.env.url),
      serverVersion: this.serverVersion,
      lastLiveAt: live ? Date.now() : this.lastLiveAt,
      sessionExpiresAt: this.sessionExpiresAt,
      retryAt: live ? null : this.retryAt,
      providers: this.providers,
      counts: countRows(this.rows),
      rows: this.rows,
    };
  }
}

function label(state: ConnectionState): string {
  return {
    connecting: "Reconnecting", live: "Connected", polling: "Connected (polling)", offline: "Offline",
    tunnel_missing: "SSH tunnel not running", authentication_required: "Pairing required", unsupported: "Unsupported T3 version",
    environment_changed: "Different T3 server at this address", expired: "Pairing expired", response_too_large: "Too much data", failed: "Connection error",
  }[state];
}
