-- تصحيح على 20261115_sync_changes.sql (مطبّق): الاستلام بعد الاسترجاع.
--
-- بعد الاسترجاع يرتفع رقم الجيل. كان رد 'generation_changed' بلا آخر رقم، فيبقى
-- الجهاز على مؤشره القديم بعد أخذ النسخة، ثم يسحب تعديلات ما قبل الاسترجاع.
-- الآن:
--   * الرد يحمل last_seq، فيقفز الجهاز إليه بعد أخذ النسخة.
--   * الاستلام يعيد تعديلات الجيل الحالي فقط.
-- لا يغيّر شيئاً لحساب غير مشغّل.
--
-- رجوع: 20261115_sync_changes_restore_cursor.rollback.sql (يعيد الدالة السابقة).

begin;

create or replace function public.rpc_pull_changes(
  p_device_id text,
  p_after_seq bigint,
  p_generation integer,
  p_limit integer default 500
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_state public.sync_account_state%rowtype;
  v_min bigint;
  v_limit integer := least(greatest(coalesce(p_limit, 500), 1), 1000);
  v_rows jsonb;
  v_max bigint;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  end if;
  if p_after_seq is null or p_after_seq < 0 then
    return jsonb_build_object('ok', false, 'reason', 'bad_cursor');
  end if;
  if exists (
    select 1 from public.account_devices d
    where d.user_id = v_uid and d.device_id = p_device_id
      and d.access_status = 'revoked'
  ) then
    return jsonb_build_object('ok', false, 'reason', 'device_revoked');
  end if;

  select * into v_state from public.sync_account_state where user_id = v_uid;
  if not found or not v_state.changes_enabled then
    return jsonb_build_object('ok', false, 'reason', 'disabled');
  end if;
  if p_generation is distinct from v_state.generation then
    return jsonb_build_object('ok', false, 'reason', 'generation_changed',
                              'generation', v_state.generation,
                              'last_seq', v_state.last_seq,
                              'snapshot_required', true);
  end if;

  select min(c.seq) into v_min from public.sync_changes c
    where c.user_id = v_uid;
  if (v_min is not null and p_after_seq < v_min - 1)
     or (v_min is null and p_after_seq < v_state.last_seq) then
    return jsonb_build_object('ok', false, 'reason', 'too_old',
                              'generation', v_state.generation,
                              'last_seq', v_state.last_seq,
                              'snapshot_required', true);
  end if;

  select
    coalesce(jsonb_agg(jsonb_build_object(
      'seq', s.seq,
      'device_id', s.device_id,
      'table', s.table_name,
      'row_key', s.row_key,
      'op', s.op,
      'row', s.row_data
    ) order by s.seq), '[]'::jsonb),
    max(s.seq)
  into v_rows, v_max
  from (
    select c.seq, c.device_id, c.table_name, c.row_key, c.op, c.row_data
    from public.sync_changes c
    where c.user_id = v_uid and c.seq > p_after_seq
      and c.generation = v_state.generation
    order by c.seq
    limit v_limit
  ) s;

  return jsonb_build_object(
    'ok', true,
    'generation', v_state.generation,
    'last_seq', v_state.last_seq,
    'changes', v_rows,
    'has_more', coalesce(v_max, p_after_seq) < v_state.last_seq
  );
end $$;

revoke all on function public.rpc_pull_changes(text, bigint, integer, integer)
  from public, anon;
grant execute on function public.rpc_pull_changes(text, bigint, integer, integer)
  to authenticated;

commit;
