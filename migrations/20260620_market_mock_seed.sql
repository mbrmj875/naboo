-- Naboo Market — Mock seed (Pilot العشار)
-- Run AFTER 20260620_market_pilot.sql
-- Supabase SQL Editor أو: psql $DATABASE_URL -f 20260620_market_mock_seed.sql

-- ثابت UUIDs للتطوير والـ onboarding PVZ
-- Store 1: سوبر ماركت النور (بائع + PVZ)
-- Store 2: بقالة السلام (PVZ فقط في Pilot)

INSERT INTO marketplace_stores (
  id, tenant_uuid, name, slug, description,
  neighborhood_label, location_type,
  internal_address, pickup_address,
  is_published, is_pickup_point, commission_rate_bps, pilot_started_at
)
VALUES (
  '00000000-0000-0000-0000-000000000001',
  NULL,
  'سوبر ماركت النور',
  'al-noor-market',
  'أفضل المنتجات بأفضل الأسعار في العشار',
  'العشار',
  'commercial',
  'تقاطع العشار — داخلي للمندوب',
  'تقاطع العشار، قرب سوق الجملة',
  true,
  true,
  0,
  CURRENT_DATE
),
(
  '00000000-0000-0000-0000-000000000002',
  NULL,
  'بقالة السلام',
  'al-salam-grocery',
  'نقطة استلام — بقالة حي العشار',
  'العشار',
  'commercial',
  'شارع 14 تموز — داخلي للمندوب',
  'شارع 14 تموز، العشار',
  true,
  true,
  0,
  CURRENT_DATE
)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  is_published = EXCLUDED.is_published,
  is_pickup_point = EXCLUDED.is_pickup_point,
  pickup_address = EXCLUDED.pickup_address;

-- price_fils = المبلغ بالدينار (عرض التطبيق: 5000 → 5,000 د.ع)

INSERT INTO marketplace_products (
  id, store_id, product_global_id, name, description,
  category_id, price_fils, is_published, in_stock, sort_order
)
VALUES
(
  '10000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000001',
  'MOCK-PROD-001',
  'قهوة تركية فاخرة 200غ',
  'قهوة تركية محمصة بعناية.',
  'grocery',
  5000,
  true, true, 1
),
(
  '10000000-0000-0000-0000-000000000002',
  '00000000-0000-0000-0000-000000000001',
  'MOCK-PROD-002',
  'عسل طبيعي 500غ',
  'عسل جبلي طبيعي غير مبستر.',
  'grocery',
  15000,
  true, true, 2
),
(
  '10000000-0000-0000-0000-000000000003',
  '00000000-0000-0000-0000-000000000001',
  'MOCK-PROD-003',
  'شاي أحمر فاخر 100 ظرف',
  'شاي أحمر كلاسيكي.',
  'grocery',
  3500,
  true, true, 3
),
(
  '10000000-0000-0000-0000-000000000004',
  '00000000-0000-0000-0000-000000000001',
  'MOCK-PROD-004',
  'تمر خلاص 1 كغ',
  'تمور خلاص درجة أولى.',
  'grocery',
  7000,
  true, true, 4
),
(
  '10000000-0000-0000-0000-000000000005',
  '00000000-0000-0000-0000-000000000001',
  'MOCK-PROD-005',
  'زيت نباتي 1 لتر',
  'زيت طبخ عالي الجودة.',
  'grocery',
  4500,
  true, true, 5
),
(
  '10000000-0000-0000-0000-000000000006',
  '00000000-0000-0000-0000-000000000001',
  'MOCK-PROD-006',
  'أرز بسمتي 5 كغ',
  'أرز بسمتي طويل الحبة.',
  'grocery',
  12000,
  true, true, 6
),
(
  '10000000-0000-0000-0000-000000000007',
  '00000000-0000-0000-0000-000000000001',
  'MOCK-PROD-007',
  'حليب طازج 1 لتر',
  'حليب بقري طازج.',
  'grocery',
  2500,
  true, true, 7
),
(
  '10000000-0000-0000-0000-000000000008',
  '00000000-0000-0000-0000-000000000001',
  'MOCK-PROD-008',
  'صابون غسيل 3 كغ',
  'منظف غسيل مركز.',
  'home',
  8000,
  true, true, 8
),
(
  '10000000-0000-0000-0000-000000000009',
  '00000000-0000-0000-0000-000000000001',
  'MOCK-PROD-009',
  'شوكولاتة بالحليب',
  'لوح شوكولاتة 100غ.',
  'grocery',
  1500,
  true, true, 9
),
(
  '10000000-0000-0000-0000-000000000010',
  '00000000-0000-0000-0000-000000000001',
  'MOCK-PROD-010',
  'مياه معدنية 12 حبة',
  'عبوة مياه 500مل.',
  'grocery',
  4000,
  true, true, 10
)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  price_fils = EXCLUDED.price_fils,
  is_published = EXCLUDED.is_published,
  in_stock = EXCLUDED.in_stock;
