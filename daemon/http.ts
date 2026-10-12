// Bounded HTTP for the few T3 endpoints the monitor reads.
import { Failure, isObject } from "./util.ts";

export const PROTOCOL_VERSION = 2;
export const MAX_RESPONSE = 16 * 1024 * 1024;

/** Accept https anywhere; plaintext http only on numeric loopback (local server or an SSH forward). */
export function checkEndpoint(url: string): URL {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    throw new Failure("endpoint_invalid");
  }
  const loopback = parsed.hostname === "127.0.0.1" || parsed.hostname === "[::1]" || /^127\.\d+\.\d+\.\d+$/.test(parsed.hostname);
  if (
    url.length > 512 ||
    !["http:", "https:"].includes(parsed.protocol) ||
    parsed.username || parsed.password || parsed.search || parsed.hash ||
    !["", "/"].includes(parsed.pathname) ||
    (parsed.protocol === "http:" && !loopback)
  ) {
    throw new Failure("endpoint_invalid");
  }
  return parsed;
}

export interface RequestOptions {
  token?: string;
  method?: "GET" | "POST";
  form?: Record<string, string>;
  json?: unknown;
  maxBytes?: number;
  timeoutMs?: number;
}

export async function requestJson(base: string, route: string, options: RequestOptions = {}): Promise<Record<string, any>> {
  const origin = checkEndpoint(base).origin;
  const headers: Record<string, string> = {
    accept: "application/json",
    "accept-encoding": "identity",
    "x-t3-orchestration-protocol": String(PROTOCOL_VERSION),
  };
  if (options.token) headers.authorization = `Bearer ${options.token}`;
  let body: string | undefined;
  if (options.form) {
    body = new URLSearchParams(options.form).toString();
    headers["content-type"] = "application/x-www-form-urlencoded";
  } else if (options.json !== undefined) {
    body = JSON.stringify(options.json);
    headers["content-type"] = "application/json";
  }
  const maxBytes = options.maxBytes ?? MAX_RESPONSE;
  let response: Response;
  try {
    response = await fetch(origin + route, {
      method: options.method ?? (body ? "POST" : "GET"),
      headers,
      body,
      // Never forward a bearer token through a redirect.
      redirect: "manual",
      signal: AbortSignal.timeout(options.timeoutMs ?? 10_000),
    });
  } catch {
    throw new Failure("offline");
  }
  if (response.status === 401 || response.status === 403) throw new Failure("authentication_required");
  if (response.status === 404 || response.status === 426) throw new Failure("unsupported");
  if (response.status !== 200) throw new Failure("failed", `HTTP ${response.status}`);
  const declared = Number(response.headers.get("content-length") ?? 0);
  if (declared > maxBytes) throw new Failure("response_too_large");
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    for await (const chunk of response.body as any as AsyncIterable<Uint8Array>) {
      size += chunk.byteLength;
      if (size > maxBytes) throw new Failure("response_too_large");
      chunks.push(chunk);
    }
  } catch (error) {
    if (error instanceof Failure) throw error;
    throw new Failure("offline");
  }
  let data: unknown;
  try {
    data = JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    throw new Failure("failed", "invalid JSON");
  }
  if (!isObject(data)) throw new Failure("failed", "unexpected body");
  return data;
}

export interface Descriptor {
  environmentId: string;
  label: string;
  serverVersion: string;
  orchestrationProtocolVersion: number;
}

export async function getDescriptor(base: string): Promise<Descriptor> {
  const d = await requestJson(base, "/.well-known/t3/environment", { maxBytes: 64 * 1024, timeoutMs: 5_000 });
  if (d.orchestrationProtocolVersion !== PROTOCOL_VERSION || typeof d.environmentId !== "string") throw new Failure("unsupported");
  return {
    environmentId: d.environmentId,
    label: typeof d.label === "string" ? d.label : "",
    serverVersion: typeof d.serverVersion === "string" ? d.serverVersion : "",
    orchestrationProtocolVersion: d.orchestrationProtocolVersion,
  };
}
