/*
  جدولة التسوية كل ساعة، للخصومات التي تلي لحظة التطبيق فقط.
  الخصومات الأقدم لا تمسها الدورية، وتسويتها تنفيذ منفصل بعد القرار 5.
*/

select cron.schedule(
  'wa-wallet-settle-failed',
  '7 * * * *',
  format(
    $cmd$select public.wa_wallet_settle_failed(%L::timestamptz, false)$cmd$,
    now()
  )
);
