# RAPOR — A5r8 (web/React PWA) — 2026-09-28 — Tur 8

## Özet (5 madde)

1. **⭐ `Gender.other` 166 kcal farkı kapatıldı (P1).** Web'de `other`/`null`
   **kadın** formülüne düşüyordu (BMR 1583), Flutter **erkek** formülünde
   (1749). TDEE farkı orta aktifte **257 kcal/gün** ve profile kalıcı
   yazılıyordu. Karar: `other` → **erkek**; eşleme tek yerde
   `genderForBmr()`.
2. **Hesap katmanı Flutter ile hizalandı (8 fark).** `bmi(70,-180) = 24.2`
   (kare pozitif → imkânsız kayıt "normal"), BMR'da `clamp`/NaN koruması
   yok, TDEE negatif, makro negatif gram, `age` üst sınırı yok, `progress`
   koruması **hiç kullanılmıyordu**, su hedefi `NaN` yazabiliyordu.
3. **UTC gün kaçıklığı 4 gerçek yerde** (`toISOString().split("T")`,
   `new Date("2000-01-15")`, `Math.floor(/864e5)`, `eachDayOfInterval`).
   Yeni `src/lib/dates.ts` tek kaynak; 27 test iki saat diliminde koşuyor.
4. **Veri katmanı:** 3 yerde `try/catch` **hiç çalışmıyordu**
   (`addMealEntry` fırlatmaz) — "eklendi" toast'u hiçbir kayıt
   yazılmadan gösteriliyordu. `addMealEntry`'de miktar sınırı yoktu.
   3 yerde yarış (race), 1 belirsiz `orderBy`, 1 eksik `user_id`,
   1 kalıcı artık (yarım yazma).
5. **`check_versions.cjs` formül seviyesine genişletildi** (6 yeni kapı).
   Üçü **regresyon enjeksiyonuyla kırmızya döndürülerek** kanıtlandı.

---

## Düzeltilenler

### P1 — `Gender.other` (A3r6 aktarımı, `plans/…/TRANSFER-defteri.md:376`)

`src/lib/calculations.ts` **önce**: `gender === 'male' ? +5 : -161`
→ `other` **kadın** formülüne düşüyor.
**Sonra**: `genderForBmr(gender)` → yalnız `'female'` kadın; `other`/`null`/
bilinmeyen → erkek. Flutter `calculations.dart:15` ile birebir.

**Gerekçe (kararın özeti, tam gerekçe kodda):**
1. **Sözleşme:** Flutter `Gender.other` erkek formülünde, A3r6 testleri
   bunu kilitledi. Görev metni Flutter'ı kaynak olarak almamı söyledi.
2. **Formülün kökeni:** Mifflin-St Jeor'un `−161` sabiti 60+ yaş kadın
   grubundan, `+5` daha genç/geniş kitleden türetildi. "Belirtilmemiş" için
   iki taraf da yaklaşık eşit temelli; **ortalama (`−78`) hiçbir iki
   istemcide mevcut değildi**, yani seçim zorunluydu.
3. **Risk yönü:** Yüksek tarafı seçmek, ihlal riski (yetersiz beslenme)
   bakımından güvenli taraftır. Düşük taraf, "hedefim 300 kcal arttı"
   yanılgısı üretir.

**Somut etki (testle kilitli):** 80 kg / 175 cm / 30 yaş
→ BMR `1749` (eskiden `1583`), TDEE orta aktif `2711` (eskiden `2454`),
fark `257` kcal/gün.

**Test:** `tool/test_calculations_parity.mjs` — 5 test
(⭐ işaretli), hepsi `1749 / 1583 / 166 / 257` sayılarını ve "other
erkekle aynı, kadından farklı" değişmezini sabitler; beş aktivite
seviyesinin **tamamında** döngüsel olarak doğrular.

**Ek düzeltme:** `Index.tsx:111` `gender: profile.gender || "other"`.
`null` cinsiyet de `other` demektir; bu yüzden **"belirtilmemiş" ile
"cinsiyetsiz seçildi"** aynı hesaba düşüyordu — `SettingsPage`/
`OnboardingPage` varsayılanı ise `"male"`. Kayıtlı profil ile ilk açılış
farklı hedef gösteriyordu. `?? genderForBmr(...)` ile tek kaynağa bağlandı.

---

### P1 — Hesap farkları (satır satır karşılaştırma)

`src/lib/calculations.ts` ↔ `flutter_app/lib/core/utils/calculations.dart`

| # | Fonksiyon | Web (önce) | Flutter | Etki | Web (sonra) |
|---|---|---|---|---|---|
| 1 | `bmr` | `NaN` yayılıyor, `clamp` yok | `!isFinite → minBmr`, `clamp(0, 2³¹)` | NaN dashboard'a, aşırı profil `Int` taşması | `MIN_BMR`/`MAX_BMR` kırpma |
| 2 | `bmr` cinsiyet | `=== 'male' ? +5 : -161` | `female ? -161 : +5` | **166/257 kcal** | `genderForBmr()` |
| 3 | `tdee` | negatif BMR → negatif TDEE | `bmr <= 0 → 0` | negatif hedef | `bmr <= 0 → 0` |
| 4 | `macros` | negatif → negatif gram | `target <= 0 → hepsi 0` | "−67 g yağ" | dört alan `0` |
| 5 | `bmi` | **negatif kilo kabul** (`bmi(70,-180) = 24.2`) | A3r6 düzeltti (`weightKg <= 0 → 0`) | imkânsız kayıt "normal" | `weightKg <= 0 → 0` |
| 6 | `age` | **üst sınır yok** | `maxAge = 120` | `1800` doğum → BMR `−1900` | `MAX_AGE = 120` |
| 7 | `progress` | **3 katmanlı savunma var ama HİÇ kullanılmıyor** | `progress()` kullanılıyor | hedef 0 → çubuk `NaN`/dolu | 3 bileşen de çağırıyor |
| 8 | `waterTargetMl` | `Math.round(kg*33)` × 2 yer, `NaN` koruması yok | `!isFinite → 0` | `NaN` profile yazılıyor | `waterTargetMl()` tek kaynak |
| 9 | per-100g | 3 kopya, `x/0` korumasız | `customItem` aynı korumada | `NaN` favori kartı / Dart'ta liste çökmesi | `per100gFromTotals()` |
| 10 | `calculateAge` | **3 ayrı kopya** (2'si üst sınırsız) | tek kaynak | onboarding 2265 kabul, ayarlar reddediyor | tek kaynak |

**Test:** `tool/test_calculations_parity.mjs` — **46 test**, her satır için.

---

### P1 — Tarih/saat dilimi ve gün sınırı

**Kaç yerde bulundu: 4 gerçek desen, 8 çağrı noktası.** Yeni
`src/lib/dates.ts` (160 satır) tek kaynak; `tool/test_dates.mjs` **27 test**
`Europe/Istanbul` + `America/New_York` + `UTC` + `Asia/Tokyo` altında
koşuyor (`inTz`).

| Desen | Yer | Etki |
|---|---|---|
| `toISOString().split("T")[0]` | `OnboardingPage.tsx:396` (dogum tarihi `max`) | TR'de 03:00 sonrası **yarın** seçilebilir |
| `new Date("2000-01-15")` (UTC gece yarısı) | `Index.tsx` (kilo), `OnboardingPage` (doğrulama), `WeightBanner` (`entry_date`) | TR'de yaş **bir gün önce** ilerliyor (BMR ~5 kcal) |
| `Math.floor((now - date) / 864e5)` | `WeightBanner.tsx:22` | gece 01:00'de tartılan kilo → "3 gündür" uyarısı **bir gün geç** |
| `eachDayOfInterval` | `useAnalyticsData.ts:146` | DST'de gün atlar; ters aralıkta `RangeError` |

**Ek:** `useAnalyticsData` kilo trendi **tüm geçmişten** iniyordu
(binlerce satır); Flutter 1 yıllık pencere kullanıyor → **iki istemci
arasındaki davranış farkı** olarak hizalandı.

**Dürüst ölçüm notu (rapora):** Avrupa'da `+86_400_000 ms` deseni
**yalnız saat 00:00'da** sapıyor (23 saatlik gün); 25 saatlik günde
kalem günü doğru. Gerçek risk **gün sayma** (`dayDiff`). Testler bunu
ölçtüğü için "her zaman kayar" gibi yanlış bir iddia kurmuyor.

---

### P1 — Veri katmanı boşlukları

| Bulgu | Yer | Etki |
|---|---|---|
| **`try/catch` hiç çalışmıyor** | `AddPage.tsx` ×3, `Index.tsx` ×1 | `addMealEntry` **fırlatmaz**, `{error}` döner → `catch` ölü, `{error: null}` dönüyor, **hiçbir öğün yazılmadan "eklendi"** toast'u. AI tanımanın ürettiği geçersiz miktar DB 400'üne takılınca kullanıcı hiçbir geri bildirim almıyordu. |
| **Miktar sınırı yok** | `useDailyData.addMealEntry` | AI tanıma yolu negatif/NaN/`1e9` miktar yazabiliyordu. `isUsableAmount` (Flutter `isUsableAmount`, DB CHECK `0 < x ≤ 10000`). |
| **Yarış (race)** | `useDailyData`, `useAnalyticsData`, `ChatPage` | Hızlı gün/period değişiminde yavaş istek yeni veriyi eziyordu → "bugün" başlığı altında **dünün** öğünleri. `requestIdRef` jetonları. |
| **Belirsiz `orderBy`** | `useDailyData` "en son kilo" | Yalnız `entry_date` sıralı; aynı gün iki kayıt varsa DB garanti vermiyor → kilo iki değer arasında **rastgele** değişiyor. `created_at` ikincil. |
| **Sonsuz döngü** | `ChatPage.loadMore` | Yalnız `created_at` ile sayfalama: aynı saniyede iki mesaj → her `loadMore` aynı kayıtları getirir, `hasMore` hep true, **kopya mesaj**. `id` ikincil + keyset `.or()`. (URL çözümlemesi doğrulandı.) |
| **Eksik `user_id`** | `ChatPage.clearVisibleChat` | Arşivleme isteği kullanıcı kapsamı dışına çıkabiliyordu. |
| **Kalıcı artık** | `ChatPage.uploadAttachments` | INSERT başarısız olunca yüklenen dosyalar **kalıcı** kalıyordu (bucket'ta silme yolu yok). Telafi eklendi. |
| **Uzantı beyaz listesi yok** | `ChatPage` | `kötü.html` yüklenebiliyordu (`file.name.split(".")`). Artık MIME'ten türetiliyor. |
| **Şema sızıntısı** | `UnifiedFoodDialog` ×2, `AuthPage`, `SettingsPage` | Ham `error.message` → `meal_entries_amount_g_ml_check` gibi tablo/kısıt adları kullanıcıya gösteriliyordu. Beyaz liste + konsol. |
| **Sessiz hedef kaybı** | `SettingsPage.savePersonalInfo` | `auto_recalculate_macros` açıkken AI hatası **yutuluyor**, hemen ardından "Kişisel bilgiler kaydedildi" toast'u geliyordu. Ayrı mesaj eklendi (12 dil). |

---

### P2 — Yeni avlananlar

**Erişilebilirlik**
- `WeightBanner`: `onClick` taşıyan `<div>` → klavyeyle **ulaşılamıyor**,
  ekran okuyucu buton olarak tanımıyor (WCAG 2.1.1). İçindeki `Button`
  yalnız dekoratifti ve `type` belirtilmediği için `<form>` içinde
  **submit** olurdu. → `<button type="button">`.
- `DateSelector`: iki ikon butonunda erişilebilir ad yok (WCAG 4.1.2) →
  `aria-label`/`title` (2 yeni i18n anahtarı × 12 dil). `type` de eklendi.
- `circular-progress`: `role="progressbar"` + `aria-valuetext` yok.
- 6 butonda `type` belirtilmemişti (`AddFromFoodDialog`,
  `CustomWaterDialog` ×3, `DateSelector` ×3).

**Yarış / yaşam döngüsü**
- `WaterTracker`: `requestAnimationFrame` **iptal edilmiyordu** → çözülmüş
  bileşene yazma + bellekte kalmış animasyon döngüsü. `cancelAnimationFrame`.
- `ChatPage`: `invokeAssistant` çözülmüş bileşene yazıyordu →
  `mountedRef`.

**Hesap dayanıklılığı**
- `AnalyticsPage`: 11 yerde korumasız `x / target` → `percentOf()` +
  hedef `> 0` doğrulaması (A4r2'nin Flutter'daki `_percent()` karşılığı).
- `EditMealDialog` / `AddFromFoodDialog` / `UnifiedFoodDialog` ×2: elle
  yazılmış 4'er ayrı besin hesabı → `calculateNutritionForAmount`.

**Temiz çıkanlar (ölçüldü):**
- `console.log` **0**, `eval`/`new Function` **0**, `catch (_)` **0**.
- `dangerouslySetInnerHTML` tek yerde (`chart.tsx:70`, shadcn kaynak
  kodu) ve girdisi `ChartConfig`'ten geliyor — kullanıcı verisi değil.
- `localStorage` yalnız tema + i18next dili (XSS yüzeyi yok; Supabase
  oturumu zaten `localStorage`).
- `nullish` guard'ları `useNotifications`/`useDataExport`'ta A6r3'ün
  düzelttiği gibi yerinde.

---

## `check_versions.cjs` genişlemesi (formül seviyesi)

6 yeni kapı. Üçü **negatif testle kanıtlandı** (regresyon enjekte
edildi → kırmızı → geri alındı):

| Kapı | Neyi korur | Kanıt |
|---|---|---|
| BMR cinsiyet sabitleri + **`genderForBmr` kuralı** | `other`'ın erkek tarafına düşmesi | `'female' : 'female'` enjekte → ✗ kırmızı |
| `calculateBMI` negatif ağırlık reddi | `bmi(70,-180) = 24.2` | guard kaldırıldı → ✗ kırmızı |
| `calculateProgress` **çağrılıyor mu** | Korumanın ölü kod olmaması | `macro-bar`'da çağrı `Math.min` yapıldı → ✗ kırmızı |
| Su çarpanı (`kg × 33`) | İki istemci aynı ml/kg | — |
| Yaş üst sınırı **+ uygulanıyor mu** | Sabit tanımlı ama kırpma yok | — |
| Öğün miktarı üst sınırı + `isUsableAmount` varlığı | DB CHECK paritesi | — |

**Metodoloji notu:** `calculateProgress` kapısı ilk iki denemede
**yanlış yeşil** verdi. Sebep: (a) bileşenlerin **açıklama yorumları**
`calculateProgress` kelimesini geçiriyor, (b) `import` satırı çağrı
kaldırıldığında da dosyada kalıyor. Kapı artık yorumları **ve import
satırlarını** temizleyip `\bcalculateProgress\s*\(` **çağrısını** arıyor.
A3r6'nın "DST testleri hiçbir şey ölçmüyordu" bulgusunun metin analizi
tarafındaki karşılığı.

**Mevcut kapılar iki kez kırıldı ve düzeltildi:** makro oranları artık
`PROTEIN_PERCENT` sabitlerinde olduğu için (`calculateMacros` imzasında
literal `30` değil), taban `Math.max(1200,…)` yerine
`MIN_TARGET_CALORIES`'ta olduğu için regex'ler güncellendi — ve "sabit
tanımlı ama **kullanılmıyor**" kontrolü eklendi (ölü sabit kapısı).

---

## Yeni testler

| Dosya | Test | Kapsam |
|---|---|---|
| `tool/test_calculations_parity.mjs` | **46** | BMR/TDEE/makro/BMI/progress/age/su/per-100g/miktar + `Gender.other` ⭐ |
| `tool/test_dates.mjs` | **27** | UTC gün, `parseDateOnly`, `addLocalDays`, `dayDiff`, `eachLocalDay`, `startOfLocalDay` — 4 saat diliminde |
| `tool/ts-resolve.mjs` + `…-hooks.mjs` | — | Uzantısız TS import çözücüsü. **Ek bağımlılık yok** (`test_backup_import.mjs` içe aktardığı modül göreli TS import içermiyordu; `calculations.ts` içeriyor). |
| **Toplam** | 40 → **113** | |

**Denetim (yanlış güveni kapatma):** `test_dates.mjs` bir testle
`Intl.DateTimeFormat().resolvedOptions().timeZone`'in gerçekten değiştiğini
doğrular ve UTC deseni ile yerel desenin **ayrıştığını** kanıtlar —
aksi hâlde "DST testleri hiçbir şey ölçmüyordu" tuzağı tekrarlanırdı.

---

## Doğrulama

```
npm run build   → ✓ built in 11.32s (3506 modül)
npm run lint    → ✖ 10 problems (0 errors, 10 warnings)   ← taban korundu
npx tsc -p tsconfig.app.json --noEmit → exit 0
npm test        → 113 tests / 113 pass / 0 fail
node tool/check_i18n.cjs   → ✓ 12 dil, 488 anahtar, 317 React anahtarı
node tool/check_versions.cjs → ✓ (1 uyarı, aşağıda)
```

**`check_versions.cjs` tek uyarısı kasıtlı:** BMI ağırlık alt sınırı
iki tarafta farklı — **Dart tarafı eksik** (`bmi(70,-180) = 24.2` hatası
üretiyor). Web doğru olan taraf; kapı bunu bir **ürün kararı** değil,
**açık Flutter borcu** olarak işaretliyor.

---

## AKTARIM (başka alana)

### → A2/A3 (Flutter çekirdek) — `calculations.dart`

| Sev | Bulgu | Kanıt |
|---|---|---|
| **P1** | `Calculations.bmi` **negatif ağırlığı reddetmiyor**: `if (!weightKg.isFinite) return 0;` — boy kontrolü `isFinite \|\| <= 0` iken ağırlıkta `<= 0` yok. Karesi pozitif olduğu için `bmi(70, -180) = 24.2` → **fiziksel olarak imkânsız kayıt "normal BMI"** olarak gösteriliyor. Web tarafı bu turda kapatıldı; `check_versions.cjs` uyarı olarak işaretliyor. | `calculations.dart:73` |
| P2 | `Calculations.bmi` ağırlık tarafında `isFinite`'ten başka hiçbir koruma yok — `weightKg = -1e9` `bmi = -1e-5` döner (kategori "düşük kilolu", sayı görünür). | `calculations.dart:73` |

### → A6 (test/CI/tool) — `tool/**`

| Sev | Bulgu | Kanıt |
|---|---|---|
| **P3** | `tool/ts-resolve.mjs` + `tool/ts-resolve-hooks.mjs` yeni eklendi: uzantısız **göreli** TS import çözücüsü. `npm test`'in üç dosyayı da koşabilmesi için gerekliydi; ek bağımlılık getirmiyor. React CI işi (`react.yml`) `npm test`'i çalıştırıyorsa `--import ./tool/ts-resolve.mjs` bayrağını doğrulamalı. | `package.json:8` |
| P3 | **`@hookform/resolvers` kullanılmıyor** — `src/**` içinde 0 referans ve `dist/assets/index-*.js` çıktısında **da yok** (tree-shaken). Yani runtime maliyeti yok, `package.json` kalabalığı. `tailwindcss-animate` **kullanılıyor** (`tailwind.config.ts:112`) — silinmemeli. | ölçüldü |
| P2 | **21 / 50 `src/components/ui/*` bileşeni ulaşılamaz** (shadcn artıkları): accordion, aspect-ratio, breadcrumb, calendar, carousel, chart, command, context-menu, drawer, form, hover-card, input-otp, menubar, navigation-menu, pagination, popover, resizable, sidebar, slider, table, toggle-group. Tur 1'den beri bekliyor. **Not:** `chart.tsx` `dangerouslySetInnerHTML` içeriyor — silinirse o yüzey de gider. | statik tarama |
| P3 | `src/App.css` (42 satır) hiç import edilmiyor (Tur 1'den beri). | — |

### → ana ajan (ürün kararı)

| Sev | Konu |
|---|---|
| P2 | **Kilo trendi penceresi:** web artık Flutter'la aynı şekilde **son 1 yıl**. 1 yıldan eski kilo kaydı analitik ekranda **görünmüyor** (ama veri duruyor). 1 yıl→3 yıl yapılırsa ikisinin değişmesi gerekir — `check_versions.cjs`'e pencere sabiti eklenmeli. |
| P2 | `favorite_foods`/`recent_foods` hâlâ **hiçbir istemci tarafından yazılmıyor** (Tur 6'da açıldı, karar bekliyor). Web tarafında `useFavoriteFoods`/`useRecentFoods` `meal_entries`'ten **türetiyor** (200/50 kayıt tarayıp ilk 10'u alıyor) — Flutter da öyle. İki tablo gereksiz. |

---

## Kalan riskler

1. **Test kapsamı saf katmanla sınırlı.** 73 yeni test `lib/` fonksiyonlarını
   kapsıyor; **hook bileşenleri test edilmiyor** (test koşucusu yok —
   `jsdom`/`@testing-library` ek bağımlılık gerektirir). Özellikle
   `requestIdRef` yarış korumaları ve `ChatPage` telafisi **statik
   incelemeyle** doğrulandı, çalıştırılarak değil. → A6'ya öneri: en
   yüksek riskli 3 hook için `@testing-library/react` + jsdom.
2. **`ChatPage` `.or()` keyset ifadesi URL düzeyinde doğrulandı**, gerçek
   PostgREST'e karşı çalıştırılamadı (Supabase CLI yok). UUID `lt`
   sıralamasının Postgres'te string karşılaştırması olduğu ve `hyphen`
   içerdiği için **sabit genişlikli** olduğu doğrulandı — ama canlı
   doğrulama önerilir.
3. **Yerel saat dilimi testleri `process.env.TZ` değiştirir.** V8'de
   çalışıyor ve doğrulandı; farklı bir runtime (Deno/Bun) bu testleri
   olduğu gibi taşımaz.
4. **`OnboardingPage`'de `loadProfile` hatası hâlâ yutuluyor**
   (`if (data && !error)` → sessiz `setIsLoading(false)`). Düzeltilmedi:
   P3 ve davranış değişikliği gerektiriyor (retry UI).
5. **`src/pages/SettingsPage.tsx` yorum satırları artık `MAX_AGE` /
   `parseDateOnly` atıfı yapıyor** ama `genderForBmr` değişikliğinin
   oradaki `gender` alanı üzerindeki etkisi test edilmedi.
6. **Docker doğrulaması yapılamadı** (docker kurulu değil) — Tur 1'den
   beri açık.
