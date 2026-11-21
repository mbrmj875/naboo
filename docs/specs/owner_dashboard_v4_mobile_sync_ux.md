# Phase 4 — Owner Dashboard UX + Sync Trust (v1.1)

**الحالة:** معتمد — مدمج مع [`owner_dashboard_ui_restructure_v1.md`](owner_dashboard_ui_restructure_v1.md)  
**المراجع:** `owner_role_dashboard_master_plan.md` · `owner_command_center_v3_vertical_profiles.md` · `owner_command_center_v1.md` **v1.1.2**

هذه المواصفة تكمّل خطة المالك وتهدف إلى 3 محاور:
1. **موثوقية البيانات (Data Trust):** المزامنة واضحة ومطمئنة.
2. **تجربة الهاتف (Mobile UX):** ترتيب وتفاعل متجاوب.
3. **المظهر (Aesthetics):** Dark/Light + قراءة جيدة — **بعد** استقرار الحالات (S4.5 → S5a).

> **ترتيب التنفيذ:** Sprint A ↔ **S4.5** في restructure · Sprint B ↔ **S5b UI** · Sprint C ↔ **S5c UI**.  
> **لم يبدأ التنفيذ بعد** — راجع [`owner_dashboard_ui_restructure_v1.md`](owner_dashboard_ui_restructure_v1.md).

---

## القرارات المعمارية

### 1. المزامنة والبيانات

- **لا RPC** لبطاقات KPI — القراءة من SQLite المحلي.
- **صحة البيانات:** `CloudSyncService` + `remoteImportGeneration` → `invalidateAll()`.
- **Realtime Watchdog:** تعزيز Realtime الحالي — لا polling جديد.
- **TTL + Offline:** v1.1.2 §5–§6 — **S4.5** قبل polish UI.

### 2. الواجهة وتجربة المستخدم

- **Theme:** `ThemeProvider` — لا مزود جديد.
- **النمط البصري (قرار موحّد مع restructure §4.1):**
  - **خلفية + Header:** هوية «زجاجية» = **gradient/glow فقط** (`GlassBackground`) — **بدون** `BackdropFilter` على Desktop.
  - **بطاقات KPI / Charts / Audit:** **صلبة** (`colorScheme.surface`) — قراءة تحت الشمس.
  - **`BackdropFilter` / `GlassSurface`:** **ممنوع** على scroll areas وKPI في لوحة المالك (Windows/macOS/Android).
- **التجاوب:** `context.screenLayout` — لا `width > 850` ثابت.

### 3. مؤشر الاتصال

- **Online / Offline / Syncing** في Header — إلزامي في **S4.5** (يكمّل `lastSyncAt` وزر sync).
- Offline UX per-card: v1.1.2 §6 — «آخر تحديث: منذ X دقيقة».

---

## خطة التنفيذ (Sprints)

### Sprint A — ثقة البيانات والمزامنة (= restructure **S4.5** + جزء v4)

| مهمة | حالة الكود |
|------|------------|
| زر مزامنة + `CloudSyncService.syncNow` / hydrate | ✅ جزئي |
| `lastSyncAt` في Header | ✅ موجود |
| Banner/Spinner «جارٍ المزامنة…» | ✅ `_SyncTrustBanner` |
| مؤشر **Online/Offline/Syncing** | ❌ S4.5 |
| Pull-to-refresh → hydrate + `refreshAll` | تحقق |
| TTL v1.1.2 + background refresh | ❌ S4.5 |
| Integration `remoteImportGeneration` | `test/owner/` |

### Sprint B — تجاوب الهاتف (= restructure **S5b UI**)

- إزالة `width > 850` الثابت.
- Grid ديناميكي (1 / 2 / 3 أعمدة).
- `OwnerStaffActivityPanel` — ارتفاع مرن (لا `height: 700` ثابت).
- `owner_dashboard_layout_sheet` — مناسب للموبايل.
- Charts/Live empty states + polish.

### Sprint C — الجماليات (= restructure **S5c UI**)

- Theme toggle في Header — ✅ موجود.
- `OwnerKpiCard` / `OwnerHeroKpiCard` → `colorScheme` بالكامل.
- `AnimatedSwitcher` / `TweenAnimationBuilder` للأرقام.
- Morphing charts — **بعد** S4.5.
- اختبار 60fps Desktop بدون blur على scroll.

---

## مطابقة Sprintات

| v4 | Restructure | v1.1.2 |
|----|-------------|--------|
| Sprint A | S4.5 | §5–§6 |
| Sprint B | S5b UI | Charts TTL |
| Sprint C | S5c UI | — |

**الوثيقة الموحّدة:** [`owner_dashboard_ui_restructure_v1.md`](owner_dashboard_ui_restructure_v1.md)

---

## خطة التحقق

1. **E2E جهازين:** بيع على جهاز → sync → KPI محدّث على الجهاز الثاني.
2. **DB:** `customers.balance`, `cash_ledger` بعد pull.
3. **تجاوب:** phone / tablet / desktop scroll.
4. **Offline:** cache + «آخر تحديث»؛ Audit محلي فقط (v1.1.2 §6 ④).
5. **Desktop perf:** لا هبوط إطارات على scroll KPI grid.
