# Naboo Market — مواصفات MVP تقنية (Pilot)
## MVP Spec v1.0 | 7 شاشات · SQL · API · ERP

> **الحالة:** مواصفات تنفيذ — Pilot العشار  
> **التاريخ:** 2026-06-20  
> **المراجع:**  
> - [`naboo_pilot_90_days_v1.md`](./naboo_pilot_90_days_v1.md)  
> - [`naboo_market_master_plan_v1.md`](./naboo_market_master_plan_v1.md)  
> - [`naboo_ecosystem_master_plan_v1.md`](./naboo_ecosystem_master_plan_v1.md) §11  

---

## 1. نطاق MVP

### داخل النطاق ✅

| المكوّن | الوصف |
|---------|--------|
| **Market** Flutter | 7 شاشات · OTP · COD · PVZ |
| **admin-web** | Concierge رفع منتجات + محلات |
| **ERP** | شاشة طلبات أونلاين (قبول/تجهيز) |
| **Supabase** | `marketplace_*` · Auth · Storage · FCM |

### خارج النطاق ❌

محفظة مستهلك · دفع إلكتروني · AI · Web · Hub · محفظة تاجر إلزامية · عنوان بائع في Market

---

## 2. الشاشات السبع (Market)

| # | الشاشة | Route | Provider |
|---|--------|-------|----------|
| 1 | اختيار حي + PVZ | `/onboarding` | `LocationProvider` |
| 2 | الرئيسية | `/` | `HomeFeedProvider` |
| 3 | قائمة منتجات / تصنيف | `/category/:id` | `CatalogProvider` |
| 4 | صفحة منتج | `/p/:slug` | `ProductProvider` |
| 5 | السلة + Checkout | `/cart` | `CartProvider` |
| 6 | طلباتي | `/orders` | `OrdersProvider` |
| 7 | حسابي | `/account` | `AuthProvider` |

### 2.1 حالات UI (كل شاشة)

`loading` · `empty` · `error` + retry — إلزامي.

### 2.2 خصوصية العنوان

- API عام: **لا** `internal_address` للبائع  
- PVZ فقط: `pickup_address` في `/pickup-points` و`t_order.pickup`

---

## 3. SQL — migrations (Pilot)

### 3.1 `marketplace_neighborhoods`

```sql
CREATE TABLE marketplace_neighborhoods (
  id          TEXT PRIMARY KEY,  -- 'ashar'
  name_ar     TEXT NOT NULL,
  city        TEXT NOT NULL DEFAULT 'basra',
  is_active   BOOLEAN DEFAULT true
);
INSERT INTO marketplace_neighborhoods (id, name_ar) VALUES ('ashar', 'العشار');
```

### 3.2 `marketplace_stores` (ملخص)

```sql
CREATE TABLE marketplace_stores (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_uuid         UUID,
  name                TEXT NOT NULL,
  slug                TEXT UNIQUE NOT NULL,
  description         TEXT,
  logo_url            TEXT,
  neighborhood_label  TEXT,
  internal_address    TEXT,          -- ops فقط — RLS يمنع قراءة عامة
  location_type       TEXT DEFAULT 'commercial',
  pickup_address      TEXT,
  pickup_latitude     DOUBLE PRECISION,
  pickup_longitude    DOUBLE PRECISION,
  is_published        BOOLEAN DEFAULT false,
  is_pickup_point     BOOLEAN DEFAULT false,
  pickup_hours        JSONB,
  commission_rate_bps INTEGER DEFAULT 0,  -- Pilot: 0 أول 30 يوم
  pilot_started_at    DATE,
  created_at          TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now()
);
```

### 3.3 `marketplace_products`

```sql
CREATE TABLE marketplace_products (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  store_id            UUID NOT NULL REFERENCES marketplace_stores(id),
  product_global_id   TEXT UNIQUE,
  name                TEXT NOT NULL,
  description         TEXT,
  category_id         TEXT,
  price_fils          INTEGER NOT NULL CHECK (price_fils >= 0),
  images              TEXT[] DEFAULT '{}',
  in_stock            BOOLEAN DEFAULT true,
  is_published        BOOLEAN DEFAULT true,
  sort_order          INTEGER DEFAULT 0,
  created_at          TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_mp_pub ON marketplace_products(store_id, is_published)
  WHERE is_published = true;
```

### 3.4 `marketplace_customers`

```sql
CREATE TABLE marketplace_customers (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id    UUID UNIQUE REFERENCES auth.users(id),
  phone           TEXT UNIQUE NOT NULL,
  display_name    TEXT,
  neighborhood_id TEXT REFERENCES marketplace_neighborhoods(id),
  default_pickup_store_id UUID REFERENCES marketplace_stores(id),
  created_at      TIMESTAMPTZ DEFAULT now()
);
```

### 3.5 `marketplace_orders`

```sql
CREATE TYPE marketplace_order_status AS ENUM (
  'pending', 'accepted', 'ready_to_ship', 'in_transit',
  'at_pickup_point', 'delivered', 'cancelled'
);

CREATE TABLE marketplace_orders (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_number        TEXT UNIQUE NOT NULL,
  buyer_id            UUID REFERENCES marketplace_customers(id),
  seller_store_id     UUID NOT NULL REFERENCES marketplace_stores(id),
  pickup_store_id     UUID NOT NULL REFERENCES marketplace_stores(id),
  status              marketplace_order_status NOT NULL DEFAULT 'pending',
  payment_method      TEXT NOT NULL DEFAULT 'cod',
  payment_status      TEXT NOT NULL DEFAULT 'pending',
  subtotal_fils       INTEGER NOT NULL,
  delivery_fee_fils   INTEGER NOT NULL DEFAULT 0,
  total_fils          INTEGER NOT NULL,
  commission_fils     INTEGER NOT NULL DEFAULT 0,
  commission_rate_bps INTEGER NOT NULL DEFAULT 0,
  pickup_code         TEXT,
  buyer_notes         TEXT,
  cancelled_at        TIMESTAMPTZ,
  cancel_reason       TEXT,
  created_at          TIMESTAMPTZ DEFAULT now(),
  accepted_at         TIMESTAMPTZ,
  delivered_at        TIMESTAMPTZ
);
```

### 3.6 `marketplace_order_items`

```sql
CREATE TABLE marketplace_order_items (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id            UUID NOT NULL REFERENCES marketplace_orders(id),
  product_global_id   TEXT,
  product_name        TEXT NOT NULL,
  quantity            NUMERIC NOT NULL CHECK (quantity > 0),
  unit_price_fils     INTEGER NOT NULL,
  line_total_fils     INTEGER NOT NULL
);
```

### 3.7 View عام للمتاجر (بدون عنوان بائع)

```sql
CREATE VIEW marketplace_stores_public AS
SELECT
  id, name, slug, description, logo_url,
  neighborhood_label, is_pickup_point,
  pickup_address, pickup_latitude, pickup_longitude,
  pickup_hours, rating_avg, rating_count
FROM marketplace_stores
WHERE is_published = true;
-- لا internal_address
```

---

## 4. RLS (ملخص)

| جدول | قراءة عامة | كتابة |
|------|------------|-------|
| `marketplace_products` | `is_published` | service role / admin |
| `marketplace_stores_public` | الكل | admin |
| `marketplace_orders` | `buyer_id = auth` | buyer insert · merchant update status |
| `internal_address` | **لا RLS عام** — Edge Function ops فقط |

---

## 5. API — Edge Functions

### 5.1 `GET /catalog/home`

```json
{
  "neighborhood_id": "ashar",
  "sections": [
    { "id": "trending", "title": "الأكثر مبيعاً", "products": [...] },
    { "id": "stores", "title": "متاجر قريبة", "stores": [...] }
  ]
}
```

Query: `?neighborhood_id=ashar&pickup_store_id=uuid`

### 5.2 `GET /catalog/products`

- `?category_id=` · `?store_id=` · `?after_id=` · `limit=20`  
- cursor pagination — **لا OFFSET**

### 5.3 `GET /catalog/products/:slug`

- منتج + `store: { name, slug, neighborhood_label }` — **بدون عنوان**

### 5.4 `GET /pickup-points`

```json
{
  "points": [
    {
      "id": "uuid",
      "name": "بقالة السلام",
      "pickup_address": "شارع …، العشار",
      "distance_m": 800,
      "hours": { "sat": ["09:00","22:00"] }
    }
  ]
}
```

### 5.5 `POST /orders`

```json
{
  "pickup_store_id": "uuid",
  "payment_method": "cod",
  "items": [
    { "product_id": "uuid", "quantity": 2 }
  ],
  "buyer_notes": ""
}
```

Response: `{ "order_id", "order_number", "pickup_code", "total_fils" }`

**Server-side:** إعادة حساب الأسعار · `validate stock` · `generate order_number` · FCM للتاجر.

### 5.6 `GET /orders` · `GET /orders/:id`

- المشتري يرى طلباته فقط  
- Timeline statuses بالعربي

### 5.7 `POST /orders/:id/cancel`

- مسموح فقط: `pending` | `accepted` | `ready_to_ship` (قبل `in_transit`)  
- Pilot COD: لا استرداد مالي

### 5.8 admin — `POST /admin/stores` · `POST /admin/products`

- مصادقة admin-web session  
- رفع صور → Storage `marketplace/{store_id}/{product_id}.jpg`

---

## 6. ERP — شاشة طلبات أونلاين

**المسار:** `lib/screens/online_orders/online_orders_screen.dart` (جديد)

| التبويب | status |
|---------|--------|
| جديدة | pending |
| قيد التجهيز | accepted |
| جاهزة | ready_to_ship |

**إجراءات:**

- قبول → `accepted` + Realtime → Market  
- رفض → `cancelled`  
- جاهز → `ready_to_ship` + إشعار مندوب (واتساب Pilot)

**Realtime:** subscribe `marketplace_orders` where `seller_store_id = tenant`.

---

## 7. admin-web — Concierge

| صفحة | وظيفة |
|------|--------|
| `/market/stores` | إنشاء متجر · `internal_address` · `location_type` |
| `/market/stores/:id/products` | رفع صور · سعر · نشر |
| `/market/orders` | مراقبة Pilot |

**حقول إلزامية تاجر Pilot:**

- `name` · `slug` · `internal_address` (سري) · `neighborhood_label`  
- `pilot_started_at` → حساب 30 يوم 0% عمولة

---

## 8. إشعارات FCM

| الحدث | المستلم | نص |
|-------|---------|-----|
| `order_created` | تاجر ERP | «طلب جديد #NAB-…» |
| `order_accepted` | مشتري | «تم قبول طلبك» |
| `at_pickup_point` | مشتري | «طردك جاهز — [PVZ]» |

---

## 9. ترتيب البناء (4 أسابيع)

| أسبوع | مهام |
|-------|------|
| 1 | migrations · Storage · admin stores/products |
| 2 | Market onboarding · home · product · cart |
| 3 | POST order · ERP online orders · FCM |
| 4 | طلباتي · PVZ list · اختبار 3 تجار |

---

## 10. معايير قبول MVP

- [ ] 15 منتج من 3 متاجر تظهر في Market  
- [ ] طلب COD كامل end-to-end  
- [ ] عنوان بائع **غير** ظاهر في أي response عام  
- [ ] إلغاء `pending` يعمل  
- [ ] RTL · loading/empty/error على 7 شاشات  
- [ ] كل المبالغ `int fils`

---

*الإصدار: 1.0 | 2026-06-20*
