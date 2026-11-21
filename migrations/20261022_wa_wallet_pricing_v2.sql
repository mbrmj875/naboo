-- تسعير محفظة واتساب v2: 25 د.ع/رسالة، سنوي = 10 أشهر (شهران مجاناً).

alter table public.wa_message_platform_settings
  add column if not exists annual_free_months integer;

update public.wa_message_platform_settings
set
  unit_price_iqd_x100 = 2500,
  annual_free_months = 2,
  updated_at = now(),
  updated_by = 'migration_20261022_wa_wallet_pricing_v2'
where id = 1;

alter table public.wa_message_platform_settings
  alter column unit_price_iqd_x100 set default 2500;

alter table public.wa_message_platform_settings
  alter column annual_free_months set default 2;

alter table public.wa_message_platform_settings
  drop constraint if exists wa_message_platform_settings_annual_free_months_check;

alter table public.wa_message_platform_settings
  add constraint wa_message_platform_settings_annual_free_months_check
  check (annual_free_months >= 0 and annual_free_months <= 11);

update public.wa_message_platform_settings
set annual_free_months = 2
where id = 1 and annual_free_months is null;

alter table public.wa_message_platform_settings
  alter column annual_free_months set not null;
