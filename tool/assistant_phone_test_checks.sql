-- فحوص الخادم بعد كل مجموعة من الاختبار النهائي (م7-4). للقراءة فقط.
--
-- يشغَّل كله مرة واحدة: كل فحص صف واحد (check، pass، detail).
-- pass = null يعني «للعلم» لا نجاح ولا فشل (مثل عدد لم يحدث بعد).
-- النافذة: آخر 6 ساعات افتراضياً، غيّرها في params إن طال الاختبار.
-- المحل: محل تجربة (is_demo) وحده، فلا يُقرأ شيء من محلات حقيقية.

with params as (
  select s.tenant_id as tenant, s.tenant_id::uuid as tenant_uuid, now() - interval '6 hours' as since
  from public.assistant_tenant_settings s
  where s.is_demo
  -- محلّا تجربة: حساب التقييم الآلي، وحساب الاختبار على الهاتف. يُختار آخر ما ضُبط منهما
  -- (حساب الهاتف ضُبط 2026-11-25). لتغييره: حدّث updated_at لصف الحساب المطلوب.
  order by s.updated_at desc
  limit 1
),
turns as (
  select t.* from public.assistant_turns t, params p
  where t.tenant_id = p.tenant and t.created_at >= p.since and coalesce(t.app_version, '') <> 'eval'
),
app as (select * from turns where channel = 'app'),
wa as (select * from turns where channel = 'whatsapp'),
txt as (select id, channel, coalesce(question_clean, '') || ' ' || coalesce(answer_clean, '') as t from turns)

-- ------------------------------------------------------------------ ت0 الأساس
select 1 as n, 'محل النموذج موجود ومفعّل' as check, bool_and(s.v2_enabled and s.is_demo) as pass,
       'tenant ' || left(max(s.tenant_id), 8) || '…' as detail
from public.assistant_tenant_settings s join params p on s.tenant_id = p.tenant

union all
select 2, 'أدوار المساعد في النافذة', null, (select count(*) from app)::text || ' في التطبيق، '
       || (select count(*) from wa)::text || ' في واتساب'

-- ------------------------------------------------------------------ الخصوصية (ق35، 4.7أ)
union all
select 3, 'لا أرقام هواتف في المحفوظ',
       not exists (select 1 from txt where t ~ '(\+?964[ -]?7[0-9]{2}|07[0-9]{2})[ -]?[0-9]{3}[ -]?[0-9]{4}'),
       coalesce((select string_agg(left(id::text, 8), ',') from txt
                 where t ~ '(\+?964[ -]?7[0-9]{2}|07[0-9]{2})[ -]?[0-9]{3}[ -]?[0-9]{4}'), 'لا شيء')
union all
select 4, 'لا مبالغ خام في المحفوظ',
       not exists (select 1 from txt where t ~ '[0-9][0-9,٬.]*\s*(ألف|الف)?\s*(دينار|د\.?\s?ع)'),
       coalesce((select string_agg(left(id::text, 8), ',') from txt
                 where t ~ '[0-9][0-9,٬.]*\s*(ألف|الف)?\s*(دينار|د\.?\s?ع)'), 'لا شيء')
union all
select 5, 'لا تسلسل 5 أرقام فأكثر (لوحات، عدادات، حسابات)',
       not exists (select 1 from txt where t ~ '[0-9]{5,}'),
       coalesce((select string_agg(left(id::text, 8), ',') from txt where t ~ '[0-9]{5,}'), 'لا شيء')
union all
select 6, 'لا أسماء موظفين ولا زبائن المحل النموذجي في أسئلة التطبيق',
       not exists (select 1 from app where coalesce(question_clean, '') || coalesce(answer_clean, '')
                   ~ '(حيدر|سجاد|كرار|أبو مصطفى|ابو مصطفى|مرتضى|علي كاظم|ابو احمد|أبو أحمد|ابو علي|أبو علي)'),
       coalesce((select string_agg(left(id::text, 8), ',') from app
                 where coalesce(question_clean, '') || coalesce(answer_clean, '')
                       ~ '(حيدر|سجاد|كرار|أبو مصطفى|ابو مصطفى|مرتضى|علي كاظم|ابو احمد|أبو أحمد|ابو علي|أبو علي)'), 'لا شيء')
union all
select 7, 'الصور لا تُحفظ (علامة فقط)', null,
       (select count(*) from app where has_image)::text || ' سؤال بصورة، والنص وحده محفوظ'

-- ------------------------------------------------------------------ العدّاد والسقف (ق8، ق53)
union all
select 8, 'عدّاد الشهر تحرّك مع الأسئلة (قارن micro_usd بالتشغيل السابق: الفرق ≈ مجموع النافذة)',
       case when not exists (select 1 from app where cost_micro_usd > 0) then null
            else exists (select 1 from public.assistant_budget b, params p
                         where b.tenant_id = p.tenant and b.channel = 'app' and b.updated_at >= p.since) end,
       (select coalesce(string_agg(channel || ': ' || micro_usd || ' µ$ / ' || requests || ' طلب', '، '), 'لا صف')
        from public.assistant_budget b, params p
        where b.tenant_id = p.tenant and b.month = date_trunc('month', now() at time zone 'Asia/Baghdad')::date)
       || ' · مجموع أدوار النافذة ' || (select coalesce(sum(cost_micro_usd), 0) from app)::text || ' µ$'
union all
select 9, 'كلفة السؤال الواحد في النافذة', null,
       coalesce((select round(avg(cost_micro_usd))::text || ' µ$ متوسط، ' || max(cost_micro_usd)::text || ' أعلى، '
                 || percentile_cont(0.5) within group (order by latency_ms)::int::text || ' ms وسيط'
                 from app where cost_micro_usd > 0), 'لا أسئلة')
union all
select 10, 'وضع الميزانية في الأدوار', null,
       coalesce((select string_agg(budget_mode || '=' || n, '، ') from
                (select coalesce(budget_mode, 'normal') budget_mode, count(*) n from turns group by 1) x), 'لا أدوار')

-- ------------------------------------------------------------------ الأدوات والإشارات
union all
select 11, 'الأدوات المستدعاة', null,
       coalesce((select string_agg(name || '×' || n || case when fails > 0 then ' (فشل ' || fails || ')' else '' end, '، '
                                   order by n desc)
                 from (select e->>'name' name, count(*) n, count(*) filter (where (e->>'ok')::boolean is false) fails
                       from app, jsonb_array_elements(coalesce(tools, '[]'::jsonb)) e
                       where (e->>'prior') is distinct from 'true' group by 1) x), 'لا أدوات')
union all
select 12, 'إشارات الهاتف وصلت (إعادة صياغة، إغلاق سريع، إرشاد، تنفيذ، تصحيح)', null,
       (select format('صياغة %s، إغلاق %s، إرشاد بدأ %s تم %s ترك %s، تنفيذ %s حُفظ %s، تصحيح %s',
                      count(*) filter (where s_rephrased), count(*) filter (where s_closed_fast),
                      count(*) filter (where s_guide_started), count(*) filter (where s_guide_done),
                      count(*) filter (where s_guide_abandon_step is not null),
                      count(*) filter (where s_action_kind is not null), count(*) filter (where s_action_saved),
                      count(*) filter (where s_user_corrected)) from app)
union all
select 13, 'بحث الويب للسيارات', null, (select count(*) from app where used_web)::text || ' سؤال استعمل البحث'

-- ------------------------------------------------------------------ الذاكرة والدعم والتعلّم
union all
select 14, 'ذاكرة المحل (ق19)', null,
       (select count(*)::text || ' سطر، آخرها: ' || coalesce(max(left(text, 60)), '—')
        from public.assistant_shop_memory m, params p where m.tenant_id = p.tenant and m.created_at >= p.since)
union all
select 15, 'التسليم للدعم وصل بالبريد (م5-10)',
       case when not exists (select 1 from public.assistant_support_requests r, params p
                             where r.tenant_id = p.tenant and r.created_at >= p.since) then null
            else not exists (select 1 from public.assistant_support_requests r, params p
                             where r.tenant_id = p.tenant and r.created_at >= p.since and r.notified_at is null) end,
       (select count(*)::text || ' طلب، ' || count(notified_at)::text || ' أُرسل بريده'
        from public.assistant_support_requests r, params p where r.tenant_id = p.tenant and r.created_at >= p.since)
union all
select 16, 'الدروس المستعملة في الأدوار', null,
       (select count(*) filter (where cardinality(lesson_ids) > 0)::text || ' دور استعمل درساً' from turns)
union all
select 17, 'الحَكَم الليلي (بعد 23:30)', null,
       (select count(*) filter (where judged_at is not null)::text || ' محكوم من ' || count(*)::text
               || '، فشل ' || count(*) filter (where j_answered is false or j_grounded is false
                                                  or j_perm_ok is false or j_no_invention is false)::text
        from turns)

-- ------------------------------------------------------------------ مجيب واتساب (ت13)
union all
select 18, 'صفحة المجيب لمحل النموذج',
       (select enabled from public.whatsapp_responder_profiles r, params p where r.tenant_user_id = p.tenant_uuid),
       (select 'مفعّل=' || enabled || '، ملاحظات ' || jsonb_array_length(notes) || '، تصحيحات '
               || (select count(*) from jsonb_array_elements(notes) e where e->>'source' = 'correction')
        from public.whatsapp_responder_profiles r, params p where r.tenant_user_id = p.tenant_uuid)
union all
select 19, 'ردود المجيب وتدخلات الحارس', null,
       (select count(*)::text || ' رد، حارس: ' || coalesce((select string_agg(e->>'name', '، ')
                from wa w, jsonb_array_elements(coalesce(w.tools, '[]'::jsonb)) e), 'لا شيء') from wa)
union all
select 20, 'التسليم لإنسان وإشعاره',
       case when not exists (select 1 from public.whatsapp_handoffs h, params p
                             where h.tenant_user_id = p.tenant_uuid and h.started_at >= p.since) then null
            else (select count(*) from public.notifications n, params p
                  where n.user_id = p.tenant_uuid and n.route = 'app_oil_whatsapp_queue' and n.created_at >= p.since) > 0 end,
       (select coalesce(string_agg(reason || coalesce('→' || ended_by, ' مفتوح'), '، ' order by started_at), 'لا تسليم')
        from public.whatsapp_handoffs h, params p where h.tenant_user_id = p.tenant_uuid and h.started_at >= p.since)
union all
select 21, 'طلبات الزيارة', null,
       (select coalesce(string_agg(status || ' ' || coalesce(car, ''), '، '), 'لا طلبات')
        from public.whatsapp_visit_requests v, params p where v.tenant_user_id = p.tenant_uuid and v.created_at >= p.since)
union all
select 22, 'لا رقم زبون آخر في ردود المجيب',
       not exists (select 1 from wa where coalesce(answer_clean, '') ~ '07[0-9]{9}'),
       'يُفحص على النص المنظّف'
order by n;
