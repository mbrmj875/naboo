"use client";

import { useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { FIELD_MESSAGES } from "@/lib/field-messages";

export default function FieldLoginPage() {
  const router = useRouter();
  const params = useSearchParams();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(
    params.get("reason") === "session"
      ? FIELD_MESSAGES.SESSION_INVALIDATED
      : null,
  );
  const [loading, setLoading] = useState(false);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError(null);
    try {
      const res = await fetch("/api/field/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ username, password }),
      });
      const data = await res.json();
      if (!res.ok) {
        setError(data.error ?? FIELD_MESSAGES.LOGIN_FAILED);
        return;
      }
      const next = params.get("next");
      router.replace(next && next.startsWith("/field") ? next : "/field");
    } catch {
      setError(FIELD_MESSAGES.NETWORK_OFFLINE);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="field-login-page">
      <form className="field-login-card" onSubmit={(e) => void submit(e)}>
        <h1>مندوبو نابو</h1>
        <p>دخول الميدان</p>
        {error && <div className="field-alert err">{error}</div>}
        <label className="field-label">اسم المستخدم</label>
        <input
          className="field-input"
          autoComplete="username"
          value={username}
          onChange={(e) => setUsername(e.target.value)}
          required
        />
        <label className="field-label" style={{ marginTop: 12 }}>
          كلمة المرور
        </label>
        <input
          className="field-input"
          type="password"
          autoComplete="current-password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          required
        />
        <button
          type="submit"
          className="field-btn primary"
          style={{ width: "100%", marginTop: 18 }}
          disabled={loading}
        >
          دخول
        </button>
      </form>
    </div>
  );
}
