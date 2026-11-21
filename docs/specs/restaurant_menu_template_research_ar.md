# بحث تصاميم المنيو — كتالوج 28 إلهاماً (Figma)

**ترخيص:** إلهام بصري فقط — لا استيراد ملفات Community كأصول إنتاج. مصدر الحقيقة = الكود + Stitch الأصلي.

**قاعدة العدد:** كل رابط Community/Design = بطاقة واحدة في المعرض بهيكل مميز (ليس لوناً فقط).

## محركات الهيكل (14)

| محرك CSS / Flutter | وصف مختصر |
|--------------------|-----------|
| `photo-stack` | صور عريضة فوق كل طبق |
| `editorial` | قائمة تحريرية بعناوين وخطوط |
| `app-grid` | شبكة تطبيق طلب 2×n |
| `paper-list` | صفوف صورة صغيرة على ورق |
| `hero-cover` | غلاف بطل ثم صفوف |
| `story-cards` | بطاقات طولية (قصة) |
| `compact-tiles` | بلاطات كثيفة صغيرة |
| `side-rail` | شريط تصنيفات جانبي |
| `soft-cards` | بطاقات ظل مرتفعة |
| `magazine` | عمودان مجلّة |
| `banner-menu` | شرائح تصنيفات فوق قائمة |
| `split-row` | صف أفقي صورة+نص+سعر |
| `cover-then-list` | غلاف ثم قائمة ورقية |
| `menu-board` | لوحة نصّية كثيفة بلا صور |

## جدول الإلهام → المعرض → المحرك

| # | Figma key | اسم عربي | preset_key | محرك |
|---|-----------|----------|------------|------|
| 1 | `3b022JEFQ5AoO2B88dN6nV` | ورق تايلندي | `classic` | photo-stack |
| 2 | `kKj2x61LVRNSM3SGM1GTh1` | طقم طلب QR | `modern` | app-grid |
| 3 | `1359993…` | حبر ليلي | `dark` | editorial |
| 4 | `1210424…` | مقهى ورقي | `cafe` | paper-list |
| 5 | `1156774…` | مجلّة فاخرة | `elegant` | magazine |
| 6 | `1280892…` | صف نظيف | `minimal` | split-row |
| 7 | `1205630…` | لوحة ملكية | `royal` | menu-board |
| 8 | `1412705…` | حديقة ناعمة | `garden` | soft-cards |
| 9 | `1457659…` | بحري بشريط | `ocean` | side-rail |
| 10 | `1415899…` | بازار شريطي | `bazaar` | banner-menu |
| 11 | `1340375…` | بطل تايلندي | `thaiQr` | hero-cover |
| 12 | `1278025…` | بلاطات طلب | `foodOrder` | compact-tiles |
| 13 | `1148211…` | ستيك ثم قائمة | `steakhouse` | cover-then-list |
| 14 | `1303823…` | سوشي ورقي | `sushiBar` | paper-list |
| 15 | `1279449…` | بيتزا ناعمة | `pizzeria` | soft-cards |
| 16 | `1430970…` | مخبز بطل | `bakery` | cover-then-list |
| 17 | `1258746…` | عصائر شريطية | `juiceBar` | banner-menu |
| 18 | `1557830…` | Fine لوحة | `fineDining` | menu-board |
| 19 | `9848125…` | شارع صفوف | `streetFood` | split-row |
| 20 | `1548225…` | نباتي قصصي | `veganGreen` | story-cards |
| 21 | `1319184…` | حلويات ناعمة | `dessertPastel` | soft-cards |
| 22 | `1576541…` | شواء بطل | `smokeBbq` | hero-cover |
| 23 | `1554784…` | متوسطي بشريط | `mediterranean` | side-rail |
| 24 | `1229997…` | لاكيه مجلّة | `lacquerRed` | magazine |
| 25 | `1403768…` | باستا صور | `pastaHouse` | photo-stack |
| 26 | `1641115…` | برانش قصصي | `brunchAir` | story-cards |
| 27 | `1541987…` | سوق ليلي | `nightMarket` | banner-menu |
| 28 | `1231521…` | مزة لوحة | `mezzeTable` | menu-board |

Presets إضافية في الكود (`dockSeafood`, `neonNight`) متاحة من الإعدادات المتقدمة وليست في صفوف المعرض الـ28.

## قائمة تحقق إضافة رابط جديد
1. Brief في هذا الملف (صف جدول).
2. شاشة Stitch عربية (قشرة ثابتة).
3. `preset` + صف `gallery_catalog` + محرك chrome.
4. `presetCssVars` + CSS `data-rst-chrome`.
5. QA: فرق هيكلي، هوية، تباين بحث، RTL، قشرة.
