#!/usr/bin/env node
// t3-loupe — read-only T3 thread monitor for the Omarchy shell.
//
//   run                      stream NDJSON to stdout (the shell service runs this)
//   status                   one-shot connection/count summary (no titles)
//   doctor                   human-readable checks per paired environment
//   pair --url URL [--label NAME]                         paste a pairing link/token (hidden prompt)
//   pair-local [--url http://127.0.0.1:3773] [--label]    issue + exchange on this machine
//   pair-ssh --ssh-host HOST [--url URL] [--label]        issue on HOST over SSH (one-time remote command);
//                                                         URL is an ssh -L forward (found if omitted) or HOST's HTTPS address
//   forget --id ENV_ID_PREFIX                             drop a pairing from the local store
//   demo [offline]           stream synthetic data (UI development); offline: expired pairings, no threads
import { statSync } from "node:fs";
import { join } from "node:path";
import { createInterface } from "node:readline";
import { configDir, type Environment, loadConfig, saveConfig } from "./config.ts";
import { handleDesktopCommand } from "./desktop.ts";
import { EnvironmentConnection, type EnvironmentView } from "./connection.ts";
import type { Notice } from "./events.ts";
import { checkEndpoint, getDescriptor, requestJson } from "./http.ts";
import { exchange, extractCredential, issueCredential, READ_SCOPE } from "./pairing.ts";
import { fitState, PROTOCOL, summarize } from "./state.ts";
import { environmentBase, existingTunnel, usesTunnel } from "./tunnel.ts";
import { Failure, failureCode, validId } from "./util.ts";

const EMIT_DEBOUNCE = 200;
const HEARTBEAT = 30_000;

function write(message: Record<string, unknown>) {
  process.stdout.write(JSON.stringify({ v: PROTOCOL, ...message }) + "\n");
}

class Daemon {
  private connections = new Map<string, EnvironmentConnection>();
  private emitTimer: ReturnType<typeof setTimeout> | undefined;
  private configMtime = 0;
  private configError = "";

  start() {
    this.reload();
    setInterval(() => this.watchConfig(), 5_000);
    setInterval(() => this.emit(), HEARTBEAT);
    const rl = createInterface({ input: process.stdin });
    rl.on("line", (line) => this.command(line));
    rl.on("close", () => this.shutdown());
    process.on("SIGTERM", () => this.shutdown());
    process.on("SIGINT", () => this.shutdown());
  }

  private watchConfig() {
    let mtime = 0;
    try { mtime = statSync(join(configDir(), "connections.json")).mtimeMs; } catch {}
    if (mtime !== this.configMtime) this.reload();
  }

  private reload() {
    try { this.configMtime = statSync(join(configDir(), "connections.json")).mtimeMs; } catch { this.configMtime = 0; }
    let envs: Environment[] = [];
    try {
      envs = loadConfig().environments;
      this.configError = "";
    } catch (error) {
      this.configError = failureCode(error);
    }
    const next = new Map(envs.map((e) => [e.environmentId, e]));
    for (const [id, conn] of this.connections) {
      const env = next.get(id);
      if (!env || JSON.stringify(env) !== JSON.stringify(conn.env)) {
        conn.stop();
        this.connections.delete(id);
      }
    }
    for (const env of envs) {
      if (this.connections.has(env.environmentId)) continue;
      const conn = new EnvironmentConnection(env);
      conn.onChange = () => this.scheduleEmit();
      conn.onNotice = (n: Notice) => write({ type: "notice", ...n, envLabel: env.label });
      conn.onDetail = (threadId, detail) => write({ type: "detail", envId: env.environmentId, threadId, detail });
      this.connections.set(env.environmentId, conn);
      conn.start();
    }
    this.scheduleEmit();
  }

  private scheduleEmit() {
    if (this.emitTimer) return;
    this.emitTimer = setTimeout(() => {
      this.emitTimer = undefined;
      this.emit();
    }, EMIT_DEBOUNCE);
  }

  private emit() {
    const state = summarize([...this.connections.values()].map((c) => c.view()));
    const line = fitState({ ...state, ...(this.configError ? { configError: this.configError } : {}) } as any);
    process.stdout.write(line + "\n");
  }

  private command(line: string) {
    let cmd: any;
    try { cmd = JSON.parse(line); } catch { return; }
    if (cmd?.cmd === "copy") {
      void handleDesktopCommand(cmd);
    } else if (cmd?.cmd === "detail" && typeof cmd.envId === "string" && validId(cmd.threadId)) {
      this.connections.get(cmd.envId)?.requestDetail(cmd.threadId);
    } else if (cmd?.cmd === "refresh") {
      for (const c of this.connections.values()) c.retryNow();
      this.emit();
    } else if (cmd?.cmd === "reload") {
      this.reload();
    }
  }

  private shutdown() {
    for (const c of this.connections.values()) c.stop();
    process.exit(0);
  }
}

function arg(name: string): string | undefined {
  const i = process.argv.indexOf(`--${name}`);
  return i > 0 ? process.argv[i + 1] : undefined;
}

async function hiddenPrompt(question: string): Promise<string> {
  if (!process.stdin.isTTY) {
    const rl = createInterface({ input: process.stdin });
    for await (const line of rl) return line;
    return "";
  }
  process.stderr.write(question);
  process.stdin.setRawMode(true);
  process.stdin.resume();
  let value = "";
  return new Promise((resolve) => {
    const onData = (chunk: Buffer) => {
      for (const ch of chunk.toString("utf8")) {
        if (ch === "\r" || ch === "\n") {
          process.stdin.setRawMode(false);
          process.stdin.pause();
          process.stdin.off("data", onData);
          process.stderr.write("\n");
          return resolve(value);
        }
        if (ch === "\u0003") process.exit(130);
        if (ch === "\u007f") value = value.slice(0, -1);
        else value += ch;
      }
    };
    process.stdin.on("data", onData);
  });
}

function relative(ms: number): string {
  const d = ms - Date.now();
  const days = Math.round(d / 86400_000);
  return d < 0 ? "expired" : days >= 1 ? `in ${days} days` : `in ${Math.round(d / 3600_000)} hours`;
}

async function doctor() {
  const config = loadConfig();
  if (!config.environments.length) {
    console.log("No paired environments. Run `t3-loupe pair-local` or `t3-loupe pair --url …`.");
    return;
  }
  for (const env of config.environments) {
    console.log(`\n${env.label}  (${env.environmentId})`);
    const check = async (name: string, fn: () => Promise<string>) => {
      try { console.log(`  ✓ ${name}: ${await fn()}`); return true; } catch (e) { console.log(`  ✗ ${name}: ${failureCode(e)}`); return false; }
    };
    let base = env.url;
    if (usesTunnel(env) && !(await check("ssh forward", async () => (base = environmentBase(env))))) continue;
    if (!(await check("endpoint", async () => checkEndpoint(base).origin))) continue;
    if (!(await check("server", async () => {
      const d = await getDescriptor(base);
      if (d.environmentId !== env.environmentId) throw new Failure("environment_changed");
      return `${d.label || "?"} · T3 ${d.serverVersion} · protocol ${d.orchestrationProtocolVersion}`;
    }))) continue;
    await check("session", async () => {
      const s = await requestJson(base, "/api/auth/session", { token: env.token });
      const scopes = Array.isArray(s.scopes) ? s.scopes.join(" ") : "?";
      if (scopes !== READ_SCOPE) throw new Failure("unexpected_scope", scopes);
      return `${scopes} · expires ${relative(Date.parse(s.expiresAt))}`;
    });
    await check("shell snapshot", async () => {
      const s = await requestJson(base, "/api/orchestration/shell", { token: env.token });
      return `${s.threads?.length ?? 0} threads · ${s.projects?.length ?? 0} projects · sequence ${s.snapshotSequence}`;
    });
  }
}

async function oneShotStatus() {
  const config = loadConfig();
  const conns = config.environments.map((e) => new EnvironmentConnection(e));
  conns.forEach((c) => c.start());
  const deadline = Date.now() + 10_000;
  while (Date.now() < deadline && conns.some((c) => c.state === "connecting")) await new Promise((r) => setTimeout(r, 200));
  await new Promise((r) => setTimeout(r, 500));
  const s = summarize(conns.map((c) => c.view()));
  console.log(JSON.stringify({ counts: s.counts, environments: s.environments.map((e) => ({ label: e.label, state: e.state, providers: e.providers.length })) }));
  conns.forEach((c) => c.stop());
  process.exit(0);
}

async function main() {
  const command = process.argv[2] ?? "run";
  switch (command) {
    case "run":
      new Daemon().start();
      return;
    case "demo": {
      const { runDemo } = await import("./demo.ts");
      runDemo(write, process.argv[3] === "offline" ? "offline" : "full");
      return;
    }
    case "status":
      return oneShotStatus();
    case "doctor":
      return doctor();
    case "pair": {
      const url = arg("url");
      if (!url) throw new Failure("usage", "pair --url URL [--label NAME]");
      const credential = extractCredential(await hiddenPrompt("T3 pairing link or token (hidden): "));
      const env = await exchange(url, credential, arg("label") ?? "");
      console.log(JSON.stringify({ paired: true, label: env.label, environmentId: env.environmentId, scope: READ_SCOPE }));
      return;
    }
    case "pair-local": {
      const url = arg("url") ?? "http://127.0.0.1:3773";
      const port = Number(new URL(url).port || 80);
      const env = await exchange(url, await issueCredential(url, undefined, port), arg("label") ?? "");
      console.log(JSON.stringify({ paired: true, label: env.label, environmentId: env.environmentId, scope: READ_SCOPE }));
      return;
    }
    case "pair-ssh": {
      const host = arg("ssh-host");
      const url = arg("url") ?? (host ? existingTunnel(host) : undefined);
      if (!host || !url) throw new Failure("usage", "pair-ssh --ssh-host HOST [--url FORWARD_URL] [--label NAME]");
      const env = await exchange(url, await issueCredential(url, host, Number(arg("server-port") ?? 3773)), arg("label") ?? host, host);
      console.log(JSON.stringify({ paired: true, label: env.label, environmentId: env.environmentId, scope: READ_SCOPE }));
      return;
    }
    case "forget": {
      const id = arg("id");
      if (!id) throw new Failure("usage", "forget --id ENV_ID_PREFIX");
      const config = loadConfig();
      const keep = config.environments.filter((e) => !e.environmentId.startsWith(id));
      if (keep.length === config.environments.length) throw new Failure("not_found");
      saveConfig({ version: 1, environments: keep });
      console.log("Forgotten locally. Revoke the session in that environment's T3 Settings → Connections.");
      return;
    }
    default:
      throw new Failure("usage", `unknown command ${command}`);
  }
}

main().catch((error) => {
  console.error(JSON.stringify({ error: failureCode(error), detail: error instanceof Failure ? error.message : undefined }));
  process.exit(1);
});
