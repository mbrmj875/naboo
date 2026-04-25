"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useState, FormEvent } from "react";

function LoginForm() {
  const router = useRouter();
  const search = useSearchParams();
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      const res = await fetch("/api/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ password }),
      });
      const data = (await res.json()) as { error?: string };
      if (!res.ok) {
        setError(data.error ?? "فشل الدخول");
        return;
      }
      const next = search.get("next") || "/";
      router.replace(next);
      router.refresh();
    } catch {
      setError("لا يوجد اتصال بالخادم");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="login-page">
      <div className="login-card">
        <h1>لوحة إدارة NABOO</h1>
        <p>دخول للمشرفين فقط. لا تشارك كلمة المرور.</p>
        <form onSubmit={onSubmit}>
          {error ? <div className="err">{error}</div> : null}
          <label htmlFor="pw">كلمة المرور</label>
          <input
            id="pw"
            type="password"
            autoComplete="current-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
          />
          <button type="submit" disabled={loading}>
            {loading ? "جاري الدخول…" : "دخول"}
          </button>
        </form>
      </div>
    </div>
  );
}

export default function LoginPage() {
  return (
    <Suspense fallback={<div className="login-page">…</div>}>
      <LoginForm />
    </Suspense>
  );
}
