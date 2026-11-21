"use client";

type Listener = (online: boolean) => void;

export class NetworkMonitor {
  private listeners = new Set<Listener>();
  private timer: ReturnType<typeof setInterval> | null = null;
  private _reachable = false;
  private started = false;

  get reachable(): boolean {
    return this._reachable;
  }

  start(healthUrl = "/api/field/health") {
    if (this.started || typeof window === "undefined") return;
    this.started = true;
    this.healthUrl = healthUrl;

    const bump = () => void this.checkConnectivity();
    window.addEventListener("online", bump);
    window.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "visible") bump();
    });
    this.timer = setInterval(bump, 10_000);
    void this.checkConnectivity();
  }

  private healthUrl = "/api/field/health";

  stop() {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
    this.started = false;
  }

  onChange(cb: Listener): () => void {
    this.listeners.add(cb);
    return () => this.listeners.delete(cb);
  }

  private notify() {
    for (const cb of this.listeners) cb(this._reachable);
  }

  async checkConnectivity(): Promise<boolean> {
    try {
      const controller = new AbortController();
      const t = setTimeout(() => controller.abort(), 3000);
      const res = await fetch(this.healthUrl, {
        method: "HEAD",
        cache: "no-store",
        signal: controller.signal,
      });
      clearTimeout(t);
      const ok = res.ok || res.status === 204;
      if (ok !== this._reachable) {
        this._reachable = ok;
        this.notify();
      } else {
        this._reachable = ok;
      }
      return ok;
    } catch {
      if (this._reachable) {
        this._reachable = false;
        this.notify();
      }
      return false;
    }
  }
}

export const fieldNetwork = new NetworkMonitor();

export async function fetchWithTimeout(
  input: RequestInfo | URL,
  init: RequestInit = {},
  timeoutMs = 3000,
): Promise<Response> {
  const controller = new AbortController();
  const t = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(input, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(t);
  }
}
