// Pairing: exchange a one-time T3 pairing credential for a session narrowed to orchestration:read.
// The wider pairing credential is consumed, never stored.
import { spawn } from "node:child_process";
import { type Environment, loadConfig, saveConfig, upsertEnvironment } from "./config.ts";
import { getDescriptor, requestJson } from "./http.ts";
import { Failure } from "./util.ts";

export const READ_SCOPE = "orchestration:read";
const CLIENT_LABEL = "T3 Loupe";

/** Accepts a bare token or a pairing link carrying it in the fragment or query. */
export function extractCredential(input: string): string {
  const text = input.trim();
  if (!text.includes("://")) return text;
  try {
    const url = new URL(text);
    const fromHash = new URLSearchParams(url.hash.replace(/^#/, "")).get("token");
    return fromHash || url.searchParams.get("token") || "";
  } catch {
    return "";
  }
}

export async function exchange(base: string, credential: string, label: string, sshHost?: string): Promise<Environment> {
  if (!credential) throw new Failure("credential_missing");
  const descriptor = await getDescriptor(base);
  const auth = await requestJson(base, "/oauth/token", {
    maxBytes: 64 * 1024,
    form: {
      grant_type: "urn:ietf:params:oauth:grant-type:token-exchange",
      subject_token: credential,
      subject_token_type: "urn:t3:params:oauth:token-type:environment-bootstrap",
      requested_token_type: "urn:ietf:params:oauth:token-type:access_token",
      scope: READ_SCOPE,
      client_label: CLIENT_LABEL,
      client_device_type: "desktop",
      client_os: "linux",
    },
  });
  const scopes = new Set(String(auth.scope ?? "").split(/\s+/).filter(Boolean));
  if (auth.token_type !== "Bearer" || scopes.size !== 1 || !scopes.has(READ_SCOPE) || typeof auth.access_token !== "string") {
    throw new Failure("unexpected_scope");
  }
  const env: Environment = {
    environmentId: descriptor.environmentId,
    label: label || descriptor.label || descriptor.environmentId.slice(0, 8),
    url: base,
    token: auth.access_token,
    expiresAt: Date.now() / 1000 + Number(auth.expires_in ?? 0),
    ...(sshHost ? { sshHost } : {}),
  };
  // Prove the narrowed session can read before persisting it.
  await requestJson(base, "/api/orchestration/shell", { token: env.token });
  saveConfig(upsertEnvironment(loadConfig(), env));
  return env;
}

// Runs on the T3 host (locally, or remotely over `ssh -T host python3 -`).
// Finds the process listening on the server port, verifies its data profile's environment id,
// and asks that installation's own CLI for a five-minute pairing credential. No file edits.
export const ISSUE_SCRIPT = String.raw`
import json, os, pathlib, subprocess
expected = EXPECTED_ID
port = SERVER_PORT
inodes = set()
for name in ["tcp", "tcp6"]:
    for line in pathlib.Path("/proc/net/" + name).read_text().splitlines()[1:]:
        fields = line.split()
        if int(fields[1].split(":")[-1], 16) == port and fields[3] == "0A":
            inodes.add("socket:[" + fields[9] + "]")
for process in pathlib.Path("/proc").glob("[0-9]*"):
    try:
        if process.stat().st_uid != os.getuid(): continue
        links = [os.readlink(fd) for fd in (process / "fd").iterdir()]
        if not any(link in inodes for link in links): continue
        dbs = [link for link in links if link.endswith("/userdata/statev2.sqlite")]
        if not dbs: continue
        base = pathlib.Path(dbs[0]).parent.parent
        if (base / "userdata/environment-id").read_text().strip() != expected:
            raise SystemExit(2)
        args = [s.decode() for s in (process / "cmdline").read_bytes().split(bytes([0])) if s]
        entry = next((arg for arg in args[1:] if arg.endswith(("bin.mjs", "index.mjs", "/t3", "bin.js"))), None)
        if not entry: raise SystemExit(3)
        executable = os.readlink(process / "exe")
        env = dict(os.environ)
        env["ELECTRON_RUN_AS_NODE"] = "1"
        result = subprocess.run([executable, entry, "auth", "pairing", "create", "--base-dir", str(base),
            "--ttl", "5m", "--label", "T3 Loupe", "--json"],
            capture_output=True, text=True, timeout=20, env=env)
        if result.returncode != 0: raise SystemExit(4)
        print(json.dumps({"credential": json.loads(result.stdout)["credential"]}))
        raise SystemExit(0)
    except (PermissionError, FileNotFoundError, ProcessLookupError): continue
raise SystemExit(5)
`;

const ISSUE_ERRORS: Record<number, string> = { 2: "target_mismatch", 3: "cli_not_found", 4: "pairing_create_failed", 5: "server_not_found" };

function runBounded(argv: string[], input: string, timeoutMs: number): Promise<string> {
  return new Promise((resolve, reject) => {
    const child = spawn(argv[0], argv.slice(1), { stdio: ["pipe", "pipe", "ignore"], detached: true });
    let out = "";
    const timer = setTimeout(() => { try { process.kill(-child.pid!, "SIGKILL"); } catch {} reject(new Failure("timeout")); }, timeoutMs);
    child.stdout.on("data", (chunk) => {
      out += chunk;
      if (out.length > 64 * 1024) { try { process.kill(-child.pid!, "SIGKILL"); } catch {} reject(new Failure("response_too_large")); }
    });
    child.on("error", () => { clearTimeout(timer); reject(new Failure("failed")); });
    child.on("close", (code) => {
      clearTimeout(timer);
      if (code === 0) resolve(out);
      else reject(new Failure(ISSUE_ERRORS[code ?? -1] ?? "failed"));
    });
    child.stdin.end(input);
  });
}

/** Issue a credential on the host that serves `base`: locally, or through an approved SSH target. */
export async function issueCredential(base: string, sshHost?: string, serverPort = 3773): Promise<string> {
  const descriptor = await getDescriptor(base);
  const script = ISSUE_SCRIPT.replace("EXPECTED_ID", JSON.stringify(descriptor.environmentId)).replace("SERVER_PORT", String(serverPort));
  let argv: string[];
  if (sshHost) {
    if (!/^[A-Za-z0-9][A-Za-z0-9_.@:-]{0,200}$/.test(sshHost)) throw new Failure("ssh_host_invalid");
    argv = ["/usr/bin/ssh", "-T", "--", sshHost, "/usr/bin/python3", "-"];
  } else {
    argv = ["/usr/bin/python3", "-I", "-"];
  }
  const out = await runBounded(argv, script, 30_000);
  const credential = JSON.parse(out).credential;
  if (typeof credential !== "string") throw new Failure("pairing_create_failed");
  return credential;
}
