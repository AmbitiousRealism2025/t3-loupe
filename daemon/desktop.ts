// Clipboard for the panel's Copy title action. The title is private, and a process's argv is
// readable by other local accounts (/proc/<pid>/cmdline), so the text goes to wl-copy on
// stdin, never as an argument.
import { spawn } from "node:child_process";
import { Failure, failureCode } from "./util.ts";

const MAX_TEXT = 2000;
const COPY_TIMEOUT = 3_000;

/** Put text on the Wayland clipboard by piping it to wl-copy. Resolves only when all of the text
 *  was written to wl-copy's stdin and wl-copy's first process exited with 0, which it does after
 *  taking the selection (a forked child keeps serving it). Rejects on a spawn error, a stdin error
 *  (such as EPIPE from a helper that never read), a non-zero exit or a timeout; on a timeout the
 *  pending helper's process group is killed so it can't take the clipboard later. */
export function copyText(value: string, command: string[] = ["wl-copy"], timeoutMs = COPY_TIMEOUT): Promise<void> {
  return new Promise((resolve, reject) => {
    let settled = false, written = false, exitedClean = false;
    const fail = (error: Error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      reject(error);
    };
    const maybeDone = () => {
      if (settled || !written || !exitedClean) return;
      settled = true;
      clearTimeout(timer);
      resolve();
    };
    // detached: wl-copy and its clipboard-serving child get their own process group, which
    // outlives a collector restart and can be killed as a unit if it stalls.
    const child = spawn(command[0], command.slice(1), { stdio: ["pipe", "ignore", "ignore"], detached: true });
    const timer = setTimeout(() => {
      child.stdin?.destroy();
      try { if (child.pid) process.kill(-child.pid, "SIGKILL"); } catch {}
      fail(new Failure("copy_timeout"));
    }, timeoutMs);
    child.on("error", () => fail(new Failure("copy_unavailable")));
    child.on("exit", (code) => {
      if (code !== 0) return fail(new Failure("copy_failed", `exit ${code}`));
      exitedClean = true;
      maybeDone();
    });
    child.stdin!.on("error", () => fail(new Failure("copy_failed", "stdin")));
    child.stdin!.end(value, (error?: Error | null) => {
      if (error) return fail(new Failure("copy_failed", "stdin"));
      written = true;
      maybeDone();
    });
  });
}

/** Handle a desktop command from the shell. Returns false when `cmd` isn't one. Never throws;
 *  failures are logged by code only, never with the text. */
export async function handleDesktopCommand(
  cmd: unknown,
  copy: (value: string) => Promise<void> = copyText,
  log: (line: string) => void = (line) => process.stderr.write(line + "\n"),
): Promise<boolean> {
  if (!cmd || typeof cmd !== "object" || (cmd as any).cmd !== "copy") return false;
  const text = (cmd as any).text;
  if (typeof text !== "string" || text.length === 0) return true;
  try {
    await copy(text.slice(0, MAX_TEXT));
  } catch (error) {
    log(`copy failed: ${failureCode(error)}`);
  }
  return true;
}
