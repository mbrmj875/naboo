import { getSupabaseAdmin } from "@/lib/supabase-admin";
import type { OpsCrmMeta, OpsCrmNote, OpsCrmTask } from "@/lib/ops-crm";

export async function fetchCrmBundle(accountUserId: string): Promise<{
  meta: OpsCrmMeta | null;
  notes: OpsCrmNote[];
  tasks: OpsCrmTask[];
}> {
  const supabase = getSupabaseAdmin();
  const [metaRes, notesRes, tasksRes] = await Promise.all([
    supabase
      .from("ops_crm_meta")
      .select("*")
      .eq("account_user_id", accountUserId)
      .maybeSingle(),
    supabase
      .from("ops_crm_notes")
      .select("*")
      .eq("account_user_id", accountUserId)
      .order("created_at", { ascending: false })
      .limit(50),
    supabase
      .from("ops_crm_tasks")
      .select("*")
      .eq("account_user_id", accountUserId)
      .order("created_at", { ascending: false })
      .limit(50),
  ]);

  return {
    meta: (metaRes.data as OpsCrmMeta) ?? null,
    notes: (notesRes.data as OpsCrmNote[]) ?? [],
    tasks: (tasksRes.data as OpsCrmTask[]) ?? [],
  };
}

export async function listOpenTaskAccountIds(): Promise<Set<string>> {
  const supabase = getSupabaseAdmin();
  const nowIso = new Date().toISOString();
  const { data } = await supabase
    .from("ops_crm_tasks")
    .select("account_user_id")
    .is("done_at", null)
    .not("account_user_id", "is", null)
    .or(`due_at.is.null,due_at.lte.${nowIso}`);
  const set = new Set<string>();
  for (const row of data ?? []) {
    const id = (row as { account_user_id?: string }).account_user_id;
    if (id) set.add(id);
  }
  return set;
}
