// Reconciles orchestration.subscribeShell items into a local replica.
// Rules (ws.ts / ShellStream.ts @ fed41fa8): an authoritative snapshot resets the replica;
// a snapshot carrying resolvedRepositoryIdentityRoots refreshes project metadata only;
// events at or below the applied sequence are duplicates from resume overlap.
import { isObject } from "./util.ts";

export const SCHEMA_VERSION = 2;

export class ShellStore {
  sequence = -1;
  synchronized = false;
  projects = new Map<string, Record<string, any>>();
  threads = new Map<string, Record<string, any>>();

  /** Returns ids of threads whose content changed (for transition detection); "*" on reset. */
  apply(item: unknown): Set<string> {
    const changed = new Set<string>();
    if (!isObject(item)) return changed;
    switch (item.kind) {
      case "synchronized":
        this.synchronized = true;
        break;
      case "snapshot": {
        const snapshot = item.snapshot;
        if (!isObject(snapshot) || snapshot.schemaVersion !== SCHEMA_VERSION) throw new Error("unsupported");
        const projects = Array.isArray(snapshot.projects) ? snapshot.projects : [];
        if (Array.isArray(item.resolvedRepositoryIdentityRoots)) {
          for (const p of projects) if (isObject(p) && typeof p.id === "string") this.projects.set(p.id, p);
          break;
        }
        this.projects = new Map(projects.filter((p: any) => isObject(p) && typeof p.id === "string").map((p: any) => [p.id, p]));
        const threads = Array.isArray(snapshot.threads) ? snapshot.threads : [];
        this.threads = new Map(threads.filter(validThread).map((t: any) => [t.id, t]));
        if (typeof snapshot.snapshotSequence === "number") this.sequence = snapshot.snapshotSequence;
        changed.add("*");
        break;
      }
      case "thread.updated":
        if (!this.fresh(item.sequence)) break;
        if (isObject(item.thread) && typeof item.thread.id === "string") {
          if (validThread(item.thread)) this.threads.set(item.thread.id, item.thread);
          else this.threads.delete(item.thread.id);
          changed.add(item.thread.id);
        }
        break;
      case "thread.removed":
        if (!this.fresh(item.sequence)) break;
        if (typeof item.threadId === "string" && this.threads.delete(item.threadId)) changed.add(item.threadId);
        break;
      case "project.updated":
        if (!this.fresh(item.sequence)) break;
        if (isObject(item.project) && typeof item.project.id === "string") this.projects.set(item.project.id, item.project);
        changed.add("*projects");
        break;
      case "project.removed":
        if (!this.fresh(item.sequence)) break;
        if (typeof item.projectId === "string") this.projects.delete(item.projectId);
        changed.add("*projects");
        break;
    }
    return changed;
  }

  /** Loads an HTTP /api/orchestration/shell response (used by the polling fallback). */
  loadHttpSnapshot(snapshot: Record<string, any>): Set<string> {
    return this.apply({ kind: "snapshot", snapshot });
  }

  private fresh(sequence: unknown): boolean {
    if (typeof sequence !== "number") return true;
    if (sequence <= this.sequence) return false;
    this.sequence = sequence;
    return true;
  }
}

function validThread(t: unknown): t is Record<string, any> {
  return isObject(t) && typeof t.id === "string" && !t.archivedAt && !t.deletedAt;
}
