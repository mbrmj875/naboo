/**
 * أدوات تُنفَّذ في الدالة لا على الهاتف (4.9، م1-13، م1-18).
 *
 * الهاتف لا يعرفها في سجله، فيعلنها الخادم بنفسه لمستوى «كامل». نتيجتها تُرسل
 * مع حدث tool_call في الحقل result، فيضعها الهاتف في المحادثة كما هي بدل أن
 * ينفّذ شيئاً، وتكمل الخطوة التالية عادياً.
 */
import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { type Usage, ZERO_USAGE } from '../_shared/llm.ts';
import { sendOpsMail } from '../_shared/ops_mail.ts';
import { sanitizeForLog } from '../_shared/sanitize.ts';
import { carSpec, type LookupDeps } from './car_spec.ts';
import { checkMemoryText, MEMORY_LIMIT } from './knowledge.ts';

export const SERVER_TOOLS = new Set(['car_spec', 'support_handoff', 'memory_save']);

export type ServerToolCtx = {
  admin: SupabaseClient;
  tenantId: string;
  userId: string;
  roleKey: string;
  routeId: string | null;
  isDemo?: boolean;
  /** من حفظ المعلومة: «المالك» أو «موظف». الاسم لا يصل الخادم (ق35). */
  createdBy?: string | null;
  search?: LookupDeps['search'];
  searchTimeoutMs?: number;
};

export type ServerToolOut = { result: Record<string, unknown>; usage: Usage; usedWeb: boolean };

export async function runServerTool(name: string, args: Record<string, unknown>, ctx: ServerToolCtx): Promise<ServerToolOut> {
  try {
    if (name === 'car_spec') {
      const year = Number(args.year);
      return await carSpec({
        make: String(args.make ?? ''),
        model: String(args.model ?? ''),
        year: Number.isFinite(year) ? year : undefined,
        engine: args.engine ? String(args.engine) : undefined,
        fuel: args.fuel ? String(args.fuel) : undefined,
      }, { admin: ctx.admin, search: ctx.search, timeoutMs: ctx.searchTimeoutMs });
    }
    if (name === 'memory_save') {
      const chk = checkMemoryText(String(args.text ?? ''));
      if (!chk.ok) return fail(name, chk.error);
      const { count } = await ctx.admin
        .from('assistant_shop_memory')
        .select('id', { count: 'exact', head: true })
        .eq('tenant_id', ctx.tenantId);
      if ((count ?? 0) >= MEMORY_LIMIT) return fail(name, 'memory_full');
      const { data, error } = await ctx.admin
        .from('assistant_shop_memory')
        .insert({ tenant_id: ctx.tenantId, text: chk.text, created_by: ctx.createdBy?.slice(0, 80) ?? null })
        .select('id')
        .single();
      if (error || !data) return fail(name, 'failed');
      return {
        result: { ok: true, tool: name, rows: [{ id: data.id, text: chk.text }], total: 1, source: 'ذاكرة المحل', extra: { saved: true } },
        usage: ZERO_USAGE,
        usedWeb: false,
      };
    }
    if (name === 'support_handoff') {
      // بلا أرقام مالية ولا هواتف ولا أسماء: نفس تنظيف السجل.
      const summary = sanitizeForLog(String(args.summary ?? ''), { maxLength: 600 }).trim();
      if (!summary) return fail(name, 'bad_args:missing_summary');
      const { data: row, error } = await ctx.admin.from('assistant_support_requests').insert({
        tenant_id: ctx.tenantId,
        user_id: /^[0-9a-f-]{36}$/i.test(ctx.userId) ? ctx.userId : null,
        role_key: ctx.roleKey.slice(0, 40),
        route_id: ctx.routeId?.slice(0, 80) ?? null,
        summary,
      }).select('id').single();
      if (error) return fail(name, 'failed');
      // م5-10: تنبيه فوري لفريق نابو بالبريد. الطلب محفوظ حتى لو فشل البريد.
      await notifySupport(ctx, Number(row?.id), summary);
      return {
        result: { ok: true, tool: name, rows: [{ sent: true }], total: 1, source: 'أُرسل لفريق نابو', extra: {} },
        usage: ZERO_USAGE,
        usedWeb: false,
      };
    }
  } catch {
    return fail(name, 'failed');
  }
  return fail(name, 'unknown_tool');
}

async function notifySupport(ctx: ServerToolCtx, id: number, summary: string): Promise<void> {
  try {
    const { data } = await ctx.admin.from('ops_edge_cron_config').select('value').eq('key', 'assistant_support_email')
      .maybeSingle();
    const to = String(data?.value ?? '').trim();
    if (!to) return;
    const text = [
      'طلب دعم جديد من مساعد نابو.',
      `المحل: ${ctx.tenantId}`,
      `الدور: ${ctx.roleKey}`,
      `الشاشة: ${ctx.routeId ?? '—'}`,
      '',
      summary,
      '',
      'التفاصيل في لوحة الإدارة ← معرفة المساعد ← طلبات الدعم.',
    ].join('\n');
    const r = await sendOpsMail(to, `دعم المساعد #${id}`, text);
    if (r.ok && Number.isFinite(id)) {
      await ctx.admin.from('assistant_support_requests').update({ notified_at: new Date().toISOString() }).eq('id', id);
    } else if (!r.ok) {
      console.warn('support mail failed', r.detail);
    }
  } catch { /* الطلب محفوظ، والبريد ليس حرجاً */ }
}

function fail(tool: string, error: string): ServerToolOut {
  return { result: { ok: false, tool, error }, usage: ZERO_USAGE, usedWeb: false };
}
