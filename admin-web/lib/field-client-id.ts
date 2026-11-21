/** Client-side helpers — browser only */

const UI_SESSION_KEY = "field_ui_session_id";

export function getOrCreateUiSessionId(): string {
  if (typeof sessionStorage === "undefined") {
    return crypto.randomUUID();
  }
  let id = sessionStorage.getItem(UI_SESSION_KEY);
  if (!id) {
    id = crypto.randomUUID();
    sessionStorage.setItem(UI_SESSION_KEY, id);
  }
  return id;
}

export function newClientOpId(): string {
  return crypto.randomUUID();
}
