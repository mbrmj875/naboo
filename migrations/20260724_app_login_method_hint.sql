-- تلميح طريقة الدخول للواجهة (Google مقابل البريد) بدون كشف أسرار.
-- يُستدعى من Flutter عند فشل الدخول المحلي بالبريد+PIN.

create or replace function public.app_login_method_hint(p_email text)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid;
  v_provider text;
  v_providers text[];
begin
  if p_email is null or length(trim(p_email)) < 3 then
    return jsonb_build_object('exists', false);
  end if;

  select u.id,
         nullif(trim(both from coalesce(u.raw_app_meta_data->>'provider', '')), ''),
         coalesce(
           (
             select array_agg(distinct i.provider::text)
             from auth.identities i
             where i.user_id = u.id
           ),
           array[]::text[]
         )
    into v_uid, v_provider, v_providers
  from auth.users u
  where lower(u.email) = lower(trim(p_email))
  limit 1;

  if v_uid is null then
    return jsonb_build_object('exists', false);
  end if;

  if v_provider is null or v_provider = '' then
    if 'google' = any (v_providers) and not ('email' = any (v_providers)) then
      v_provider := 'google';
    elsif 'email' = any (v_providers) then
      v_provider := 'email';
    else
      v_provider := coalesce(v_providers[1], 'email');
    end if;
  end if;

  return jsonb_build_object(
    'exists', true,
    'provider', v_provider,
    'providers', to_jsonb(v_providers)
  );
end;
$$;

revoke all on function public.app_login_method_hint(text) from public;
grant execute on function public.app_login_method_hint(text) to anon, authenticated;

comment on function public.app_login_method_hint(text) is
  'Login UX hint: whether email belongs to google-only or email auth user.';
