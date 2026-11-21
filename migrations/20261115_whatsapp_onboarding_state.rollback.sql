/* يحذف جدول حالة الربط. الربط نفسه لا يعتمد عليه، وكتابته تتجاهل غيابه. */
begin;
drop table if exists public.whatsapp_onboarding_state;
commit;
