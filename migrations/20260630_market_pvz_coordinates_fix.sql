-- إحداثيات PVZ — العشار، البصرة (شغّل في Supabase SQL Editor)
-- Run AFTER 20260620_market_mock_seed.sql

-- بالمعرّف (الأضمن):
UPDATE marketplace_stores
SET
  pickup_latitude = 30.5085,
  pickup_longitude = 47.7835,
  is_pickup_point = true,
  is_published = true
WHERE id = '00000000-0000-0000-0000-000000000001';

UPDATE marketplace_stores
SET
  pickup_latitude = 30.5060,
  pickup_longitude = 47.7810,
  is_pickup_point = true,
  is_published = true
WHERE id = '00000000-0000-0000-0000-000000000002';

-- بالـ slug الصحيح من الـ seed:
UPDATE marketplace_stores
SET
  pickup_latitude = 30.5085,
  pickup_longitude = 47.7835,
  is_pickup_point = true,
  is_published = true
WHERE slug IN ('al-noor-market', 'supermarket-noor');

UPDATE marketplace_stores
SET
  pickup_latitude = 30.5060,
  pickup_longitude = 47.7810,
  is_pickup_point = true,
  is_published = true
WHERE slug IN ('al-salam-grocery', 'baqala-salam');

-- تحقق:
SELECT id, name, slug, pickup_latitude, pickup_longitude, is_pickup_point, is_published
FROM marketplace_stores
ORDER BY name;
