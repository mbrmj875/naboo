-- تراجع 20261129_assistant_b7.sql
drop function if exists public.whatsapp_correct_reply(uuid, text);
drop table if exists public.whatsapp_visit_requests;
drop table if exists public.whatsapp_handoffs;
drop table if exists public.whatsapp_responder_profiles;
alter table public.whatsapp_message_logs drop column if exists assistant_turn_id;
alter table public.assistant_knowledge drop constraint if exists assistant_knowledge_audience_check;
alter table public.assistant_knowledge drop column if exists audience;
