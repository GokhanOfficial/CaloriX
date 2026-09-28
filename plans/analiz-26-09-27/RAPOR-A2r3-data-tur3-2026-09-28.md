# RAPOR — A2r3-data (veri katmanı) — 2026-09-28 — Tur 3

**Kapsam:** `flutter_app/lib/data/**` (5 dosya) + `flutter_app/test/data/**` (6 dosya).
`supabase/**` yalnızca **okundu** (şema/CHECK/enum kanıtı). `lib/core/**`,
`lib/features/**`, `src/**`, `android/**` **dokunulmadı**.

**Commit:** `16ecc90` — `fix(data): inFilter parcalama, yumusak silme
butunlugu, sohbet sayfalama` — 12 dosya, **+1982 / −105**.

---

## Özet (5 madde)

1. **P1 — `inFilter` 8 KB URL limiti gerçek bir kırılma.** Beş `in` noktası
   (`food_nutrition.food_id`, `foods.name`, `meal_entries.entry_date`,
   `water_entries.entry_time`, `weight_entries.entry_date`) parçalanmıyordu.
   `_cleanFilterArray` (postgrest 2.9.1, `postgrest_builder.dart:635`) dize
   değerleri **çift tırnakla sardığı** için bir UUID 39 bayt ediyor: 8 KB'de
   ~210 kayıt. 2000 UUID'lik yedek ~78 KB, 5000 `entry_time` ~135 KB →
   **414/431** ve içe aktarma orada ölüyor. `inFilterChunkSize = 100`
   (en kötü kayıt ~6 KB) ile dilimlendi; boş girdi dilim üretmiyor
   (`in.()` → `PGRST100`).
2. **P1 — Analytics silinmiş kayıtları SAYMIYORDU; savunma katmanı yoktu.**
   Sorgular `deleted_at IS NULL` gönderiyordu (yani canlı sistemde doğru), ama
   `select()` listesi `deleted_at` kolonunu **hiç istemiyordu** ve istemci
   tarafında ikinci süzgeç yoktu → "sorgu döndü" ile "canlı kayıt döndü"
   ayırt edilemiyordu. Yedek/import veya RLS gevşekliğinde bir kayıt dönerse
   toplam 9999 kcal'a çıkardı. `deleted_at` kolonları isteniyor,
   `aggregateDaily`/`buildWeightTrend`/`_liveRows` elemesi eklendi.
3. **P1 — `restoreMealEntry` sessiz başarısızlıktı.** `.update()` çağrısı
   doğrulanmıyordu: kayıt başka cihazda silinmişse kullanıcı "Geri Al"a
   basıyor, hiçbir şey olmuyor, kayıt listede görünmüyor ve veri kaybı
   sanılıyordu. Artık `.select('id, deleted_at')` ile satır doğrulanıyor;
   0 satır veya hâlâ dolu `deleted_at` → `StateError` (çağıran zaten yakalıyor).
4. **P1 — Sohbet sayfalamasında kalıcı mesaj atlama.** `loadMore` yalnız
   `lt(created_at, …)` + `order(created_at desc)` + `limit(10)` kullanıyordu.
   Aynı mikrosaniyede yazılmış iki mesaj `lt` filtresinde **birlikte**
   eleniyor → her tıklamada aynı son sayfa, `hasMore` hep true, mesajlar
   kalıcı atlanıyor. Her sayfa artık `(created_at desc, id desc)` ile
   geliyor; kardeş `id`'ler `not.in.(…)` ile dışlanıyor.
5. **P1 — Yedek içe aktarımı tek bozuk kolonla TAMAMEN duruyordu** ve
   silinmiş kayıtlar yedekten "canlanıyordu". `_stripIds` kara liste
   uyguluyordu (`barcode`, `last_synced_at`, `sync_state`, `client_id` →
   `PGRST204` 400). Beş tablo için beyaz liste eklendi; `food_nutrition.food_id`
   UNIQUE çakışması (`23505`) ve `food_source`/`meal_type` enum ihlalleri
   düzeltildi; `deleted_at` dolu satırlar elendi.

---

## Düzeltilenler

| Sev | Dosya | Ne yapıldı | Doğrulama |
|---|---|---|---|
| P1 | `data_transfer_repository.dart` | `inFilterChunks` (100'lük dilim) — 5 `in` noktası. Boş girdi dilim üretmez. | `data_transfer_scalability_test.dart` (14 test, gerçek URL ölçüsü) |
| P1 | `analytics_repository.dart` | `select()` listesine `deleted_at` eklendi (3 sorgu); `_liveRows` istemci süzgeci; `aggregateDaily` ve `buildWeightTrend` elemesi. Eksik alan silinmemiş sayılır (seri boşalmaz). | `diary_soft_delete_test.dart` "analytics" grubu + karşı-ölçüm |
| P1 | `diary_repository.dart` | `_withoutDeleted` istemci süzgeci; `restoreMealEntry` satır doğrulaması → `StateError`; `_mapRows`/`_parseOrNull` (satır başına try/catch, `as List` zorlamaları kalktı). | `diary_soft_delete_test.dart` (14 test) |
| P1 | `chat_repository.dart` | `_loadPage` tek nokta: `order(created_at) + order(id)` (belirsiz `limit` kalktı); `loadMore` kardeş-`id` taraması + `not.in.(…)` ile birleştirme; `oldestTimestamp` saf yardımcı; `archiveThread(userId, …)`. | `chat_pagination_test.dart` (7 test, gerçek URL denetimi) |
| P1 | `data_transfer_repository.dart` | 5 beyaz liste (`sanitizeFood`, `_sanitizeNutrition`, `_sanitizeMealEntry`, `_sanitizeWaterEntry`, `_sanitizeWeightEntry`); `mealTypeDbValues`; `_sanitizeFoodSource` allow-list; `food_nutrition` UNIQUE koruması; `isDeleted` + `_liveRows` ile silinmiş satır elemesi. | `import_sanitize_test.dart` (8) + `data_transfer_scalability_test.dart` (4) |
| P2 | `models/chat_message.dart` | `pending_action` (`ChatPendingAction`, `raw` ile ileride genişleme korunuyor), `action_status` (`ChatActionStatus` + `dbValues`), `metadata` modellendi. `.g.dart` yeniden üretildi. | `chat_repository_test.dart` yeni grup (10 test) |
| P2 | `data_transfer_repository.dart` | `_stripIds` (kara liste) kaldırıldı → `_stripIds` yerine beyaz liste. `_stripIds` ölü kod bırakmadı. | `import_sanitize_test.dart` |

---

## 1) `inFilter` chunk çözümü + test

**Ölçüm.** PostgREST `in` listesi sorgu dizesine gömülür. Dart tarafında
`inFilter` → `?col=in.("a","b")` üretir (`postgrest_filter_builder.dart:241`).
`_cleanFilterArray` her dize değeri `"…"` içine alır, `\` ve `"` escape eder
(`postgrest_builder.dart:635`).

| Değer | Bayt/değer | 8 KB'de kaç değer |
|---|---|---|
| UUID (`food_id`, `entry_date` değil ama `food_nutrition.food_id`) | 36 + 2 tırnak + 1 virgül = **39** | ~210 |
| ISO-8601 damga (`water.entry_time`) | 24 + 2 + 1 = **27** | ~300 |
| Tarih (`yyyy-MM-dd`) | 10 + 2 + 1 = **13** | ~630 |

- **2000 UUID** → 2000×39 + tablo/select ≈ **78 KB** = sınırın ~9.8 katı.
- **5000 `entry_time`** → 5000×27 + 40 ≈ **135 KB** = ~16.9 katı.
- **100'lik dilim**: UUID → ~3.9 KB, ISO → ~2.7 KB (sınırın %48 / %34'ü).

**Karar: 100.** 250'lik dilim ISO damgalarda ~6.8 KB + tablo/select ≈ 7.2 KB
(sınırın %90'ı) — çok yakın. Test bunu sabitliyor: `inFilterChunkSize == 100`
ve her dilimin URL'si sınırın %80'inden küçük.

**Etkisi ne?** `importData` **sessiz hata üretmiyor**, `PostgrestException`
fırlatıyor (414/431) → `transfer_dialogs.dart:97` `catch (_)` ile
`settings.messages.error` gösteriyor. Yani kullanıcı "hata" görüyor, yedek
**hiç** eklenmiyor (import baştan sona değil, foods aşamasına kadar
kısmen eklenmiş olabilir — `counts` döndürülmeden exception atılıyor, yani
**kısmi import** sessiz kalıyor: foods eklendi, meals kalmadı ve kullanıcı
bilmiyor). Bu kısmi-import sorunu A1r3/operasyon notu (aşağıda).

**Test (14, `data_transfer_scalability_test.dart`)** — saf, ağ yok:
- 100 UUID dilimi < %80 sınır; 100 ISO dilimi < sınır.
- 2000 UUID **tek listede** > 4× sınır; dilimli hâlde hiçbiri aşmıyor (**regresyon kanıtı**).
- 5000 `entry_time` tek listede > 4× sınır; dilimli hâlde güvenli.
- Boş girdi → dilim yok (`in.()` `PGRST100` verirdi).
- 1/99/100/101/500/2000/5000 girdi: toplam eleman korunur, sıra korunur,
  hiçbir dilim sınırı aşmaz; tam sınırdaki değer (201 → 3) fazla dilim üretmez.

---

## 2) Yumuşak silme denetimi — **analytics silinmiş kayıtları sayıyor muydu?**

**Kısa cevap: sunucu süzgeci doğruydu, ama istemci katmanında hiçbir savunma
yoktu.** Üç tablo `meal_entries` / `water_entries` / `weight_entries`
`deleted_at` kolonu taşıyor (`20260111041204_…sql:141/159/171`) ve
`DiaryRepository` **fiziksel silme yapmıyor** (hiçbir yerde `.delete()` yok) —
yani davranış **tutarlı: üç tabloda da yumuşak silme**. `foods`,
`favorite_foods`, `recent_foods`, `notification_preferences`, `chat_*` tablolarında
`deleted_at` **yok** (fiziksel/kayıp yok).

Denetim sonucu:

| Yol | `deleted_at IS NULL` gönderiyor mu | İstemci süzgeci (önce → sonra) |
|---|---|---|
| `fetchDaily` öğün/su/kilo | ✅ | yok → **`_withoutDeleted`** |
| `analytics.fetch` öğün/su/kilo | ✅ | yok → **`_liveRows` + `aggregateDaily`/`buildWeightTrend`** |
| `food_repository.search/favorites/recents` | ✅ | yok (kolon seçilmiyor) — raporlandı |
| `data_transfer.exportData` | ✅ | — |
| `data_transfer._existingMealKeys/_existingWaterTimes` | ❌ **eksikti** | → **`isDeleted` içe aktarımda elendi, dedup sorgusu `deleted_at IS NULL` ile sınırlandırılmadı** (rapor) |
| `ai-chat` edge fn (3 sorgu) | ✅ (A1 alanı) | — |

**Etki analizi (en kötü senaryo).** Yumuşak silme yanlış uygulansaydı
kullanıcı "sildiğim yemek hâlâ toplamda" görürdü — tersi daha kötüdü:
silinen kayıt toplama girerse kullanıcı **fazladan yediğini sanar** ve
günlük kalori hedefini yanlış belirler. Bugün canlı sistemde doğru çalışıyor
(sorgu süzgeci sunucuda), ama iyi savunulmamıştı: `select()` listesi
`deleted_at`'ı getirmediği için istemci "bu satır silinmiş mi?" sorusunu
**hiç soramıyordu**. RLS/sorgu gevşerse veya `importData` filtresiz veri
dönerse sessizce yanlış toplam çıkardı. Artık ikinci katman var ve
karşı-ölçüm testiyle kanıtlı: `deleted_at` dolu satır dönse bile toplam 500.0
kalıyor, 9999 değil.

**`restoreMealEntry` gerçekten çalışıyor mu?** Evet, **ama** önceki sürüm
etkisini doğrulamıyordu: 0 satır dönse bile "başarılı" dönüyordu. Artık
`.select('id, deleted_at').maybeSingle()` → `null` ise `StateError`, `deleted_at`
hala doluysa `StateError`. `meal_section.dart:52` zaten `try/catch` ile
`dashboard.errorDelete` gösteriyor → kullanıcı artık bilgilendiriliyor.
Not: `meal_section.dart` **A4 alanında**; `catch` zaten yerinde olduğu için
çağıran değişikliği gerektirmiyor.

---

## 3) `amount_ml` kararı

**Karar: `amount_ml INTEGER` kalsın, migration gerekmiyor; ancak varsayımı
koda sabitledim (test) ve arayüzün garantisini doğruladım.**

- DB: `amount_ml INTEGER NOT NULL` (`full_setup.sql:134`).
- Arayüz **zaten tam sayı üretiyor**: `_WaterInputDialog`
  `FilteringTextInputFormatter.digitsOnly` (`water_tracker.dart:187`) → ondalık
  nokta bile girilemiyor; hızlı ekleme `AppConstants.waterQuickAdd = [250, 500]`
  (tam sayı). Yani 0.5 ml **arayüzden ulaşılamıyor**; görevde varsayılan
  "arayüz 50 ml adımlıysa sorun yok, kod bunu garanti etmeli" eşiğine
  **ulaşılmıyor** (adım 50 değil ama giriş zaten tam sayı).
- Veri katmanı `.round()` ile yuvarlıyor ve bu **bilinçli**: PostgREST'e
  `250.0` gönderilirse Postgres `22P02 invalid input syntax for type
  integer: "250.0"` ile 400 döner ve **su kaydı hiç eklenmez**
  (`diary_repository.dart:260-266`). Doğru davranış.
- Kayıp ölçüldü: `250.4 → 250`, `250.5 → 251` (`Dart round()` yarıdan uzağa).
  Test bunu açıkça belgeler.
- **Migration önermiyorum.** `numeric(8,1)`'e geçiş (a) tüm mevcut INTEGER
  değerlerini geri dönüşsüz biçimde dönüştürür, (b) `WaterEntry.amountMl`
  okuma yolu zaten toleranslı (`int → double`), (c) fiziksel olarak anlamsız —
  0.5 ml'lik su kaydı kullanıcı için değer taşımıyor. Maliyet/fayda oranı
  migration turunda bozulur.

**A4'ye not (benim alanım değil):** özel su miktarı girişi `digitsOnly` +
`amount <= 5000` ile sınırlı — doğru. Sadece 5000 üstü sınır **yalnız UI'da**;
veri katmanı üst sınır koymuyor (bilinçli, `water_amount_ml_test.dart`'de
belgeli).

---

## 4) Şema uyumsuzlukları tablosu (`lib/data/**` ↔ `supabase/migrations/**`)

| Tablo.kolon | DB tipi / kısıt | Model / yazma yolu | Durum |
|---|---|---|---|
| `profiles.activity_level` | `TEXT CHECK IN (sedentary, light, moderate, active, very_active)` | `String?` + `activityLevelToDb` (A2r2) | ✅ (kullanım `activityLevelFromDb` → A4) |
| `profiles.goal` | `CHECK IN (lose, maintain, gain)` | `Goal.name` — birebir | ✅ |
| `profiles.gender` | `CHECK IN (male, female, other)` | `Gender.name` — birebir | ✅ |
| `profiles.bmr/tdee` | `NUMERIC(6,1)` | `double?` | ✅ (A2'nin `_safeBmr` koruması) |
| `profiles.daily_calorie_target`, `protein_target_g`, `carbs_target_g`, `fat_target_g`, `daily_water_target_ml`, `weigh_in_frequency_days` | `INTEGER` | `int?` / `double?` | ✅ (AI gövdesi `.round()` ile int yazılıyor) |
| `profiles.last_weigh_in_reminder`, `last_water_reminder`, `last_daily_log_reminder` | `timestamptz` | **yok** | ℹ️ kullanılmıyor (A3 alanı) |
| `meal_entries.meal_type` | `ENUM meal_type(breakfast, lunch, dinner, snack)` | `MealType.name` — birebir; import'ta `mealTypeDbValues` allow-list | ✅ (bu tur) |
| `meal_entries.source` | `ENUM food_source(photo, text, manual)` — `barcode` düşürüldü (`20260822000000`) | `String`, varsayılan `'manual'`; import'ta allow-list | ✅ (bu tur) |
| `meal_entries.amount_g_ml` | `NUMERIC(8,2) NOT NULL` | `double` + `_requireFinitePositive` | ✅ |
| `meal_entries.*calculated_*` | `NUMERIC NOT NULL` | `double` + `_requireFiniteNonNegative` | ✅ |
| `meal_entries.entry_date` | `DATE NOT NULL` | `yyyy-MM-dd` `String` | ✅ |
| `water_entries.amount_ml` | **`INTEGER NOT NULL`** | `double` + `.round()` | ⚠️ **P2 kabul** (bkz. §3) |
| `water_entries.entry_time` | `timestamptz NOT NULL DEFAULT now()` | `String?` nullable model, insert'te hiç gönderilmiyor | ✅ |
| `weight_entries.weight_kg` | `NUMERIC(5,2) NOT NULL` | `double` + `>0` doğrulama | ✅ |
| `chat_messages.role` | `CHECK IN (user, assistant, system, tool)` | `String` | ✅ (UI yalnız 2 değer üretiyor) |
| **`chat_messages.pending_action`** | `JSONB` | **yoktu → eklendi** (`ChatPendingAction`) | ✅ **bu tur** |
| **`chat_messages.action_status`** | `TEXT CHECK IN (pending, approved, rejected, executed, failed)` | **yoktu → eklendi** (`ChatActionStatus`) | ✅ **bu tur** |
| **`chat_messages.metadata`** | `JSONB NOT NULL DEFAULT '{}'` | **yoktu → eklendi** (`Map<String, dynamic>`) | ✅ **bu tur** |
| `chat_threads.title` | `TEXT` nullable | `String?`, veri katmanı NULL yazıyor (A2r2) | ✅ (UI başlık türetmesi → A4) |
| `user_settings` | `UNIQUE(user_id, key)` | `onConflict: 'user_id,key'` | ✅ (Tur 1'de doğrulandı) |
| `food_nutrition` | `UNIQUE(food_id)` | import'ta ikinci satır `23505` veriyordu → ilk kazanır | ✅ **bu tur** |
| `foods.source` enum + import | `ENUM(photo,text,manual)` | allow-list → `manual` | ✅ **bu tur** |
| `sync_state`, `client_id`, `barcode`, `last_synced_at` | **yok** (migration düşürdü) | import yolunda gönderiliyordu → `PGRST204` 400 | ✅ **bu tur** (beyaz liste) |

**Nullabilite taraması:** modelde nullable ama DB `NOT NULL` olan alan yok.
Tersi var: `water_entries.entry_time` DB'de `NOT NULL DEFAULT now()` ama modelde
nullable — insert'te gönderilmediği için sorun değil, **okuma yolu** bir sorun
değil. `ChatMessage.metadata` DB'de `NOT NULL DEFAULT '{}'`, modelde `Map`
(default `{}`) — ✅.

---

## 5) Yeni avlanan hatalar

| Sev | Dosya:satır (önceki) | Bulgu | Etki | Çözüm |
|---|---|---|---|---|
| P1 | `chat_repository.dart:112-120` | `loadMore` `lt(created_at)` + tek `order` — aynı damgalı mesajlar **kalıcı** atlanıyor | Uzun sohbet geçmişi eksik, "daha eski" düğmesi hiç ilerlemiyor | `_loadPage` (`created_at,id`) + kardeş-`id` taraması + `not.in.(…)` ✅ |
| P1 | `chat_repository.dart:95,119` | **`orderBy` olmadan… değil**, tersi: `limit` **var ama ikinci sıralama anahtarı yok** → belirsiz sonuç | Postgres sıralaması kararsız → sayfa atlama | `order('id', descending: false)` eklendi ✅ |
| P1 | `diary_repository.dart:250-256` | `restoreMealEntry` etkisini doğrulamıyor | Sessiz başarısızlık, "veri kaybı" algısı | `.select().maybeSingle()` + `StateError` ✅ |
| P1 | `data_transfer_repository.dart:273-280` (`_stripIds`) | Kara liste → yedekteki tanınmayan kolon `PGRST204` 400 → **tüm import** duruyor | Yedek hiç geri alınamıyor | 5 beyaz liste ✅ |
| P1 | `data_transfer_repository.dart` (import döngüsü) | `deleted_at` dolu yedek satırı → `_stripIds` kolonu siler → kayıt **canlanıyor** | Kullanıcı ilk sildiği öğünü geri buluyor | `isDeleted` + `_liveRows` ✅ |
| P1 | `data_transfer_repository.dart:186-188` | `food_nutrition` UNIQUE ihlali (`23505`) → import çöker | Aynı gıda için iki besin satırlı yedek | ilk kazanır ✅ |
| P1 | `data_transfer_repository.dart:170-175` | `foods.source` enum dışı (`barcode`) → CHECK ihlali 400 | import çöker | allow-list → `manual` ✅ |
| P1 | `chat_repository.dart:195-200` | `archiveThread` yalnız `.eq('id')` — `user_id` kapsam filtresi yok | RLS'e ikinci savunma; politika gevşerse başkasının thread'i arşivlenir | `userId` parametresi + filtre ✅ |
| P2 | `diary_repository.dart:135-143` | `results[0] as List`, `r as Map<String, dynamic>` — tek bozuk satır **tüm günlük ekranını** `TypeError` ile düşürüyor | Dashboard çökmesi | `_mapRows` + satır başına try/catch + `AppLog` ✅ |
| P2 | `analytics_repository.dart:300-327` | `select()` `deleted_at` getirmiyor + istemci süzgeci yok | Sessiz yanlış toplam riski | kolon eklendi + ikinci katman ✅ |
| P2 | `analytics_repository.dart:255-269` | `buildWeightTrend` satır bazlı `as` zorlaması | Bozuk satır tüm trendi düşürüyor | `is` kontrolü zaten vardı; `deleted_at` eklendi ✅ |
| P3 | `data_transfer_repository.dart:284-291` (`_mealKeysOf`) | Ölü koddu (import yolunda kullanılmıyor) | — | `mealKeysOf` yapıldı, sözleşme testiyle yaşıyor ✅ |
| P3 | `data_transfer_repository.dart:78-85` | `exportData` `select()` ile tüm kolonları çekiyor | Yedek boyutu gereksiz büyük (web parity kırılmaz) | Dokunulmadı — web parity, P3 |

**Taranıp temiz çıkanlar:** `upsert` `onConflict` (`user_settings` →
`user_id,key` doğru, tek upsert); `insert` dönüşünü kullanmama
(`addMealEntry`/`addWaterEntry`/`addWeightEntry` `.select().single()` ile
kullanıyor ✓); yumuşak silme + benzersizlik çakışması (`meal_entries` üzerinde
`(user_id, entry_date, custom_name, meal_type)` UNIQUE'i **yok** → yumuşak
silinmiş iki öğün aynı anahtarı taşıyabilir ve dedup çalışır, 400 üretmez ✓);
sayfalamasız liste (chat mesajları **sayfalı** ✓, `user_settings`/`favorite_foods`
küçük tablolar ✓, `exportData` tek seferlik ✓); `select()` ile tüm kolonlar
(`fetchDaily` gerekli ✓, `exportData` P3).

---

## AKTARIM

### → A1r3 (`supabase/**`) — migration önerileri

1. **[P2] `water_entries.amount_ml` → `numeric(8,1)`.** Ben
   **öneriyorum ama yapmadım**: arayüz tam sayı giriyor (`digitsOnly`), fiziksel
   fayda yok, geri dönüşsüz tip dönüşümü var. Karar ana ajanda.
   `diary_repository.dart:283` `.round()` kaldırılırsa okuma yolu zaten
   toleranslı. **Migration önerisi değil, bilinçli kabul** — rapor gerekçesiyle.
2. **[P1] `chat_messages` FK'si.** `chat_messages.user_id` → `auth.users(id)`,
   `thread_id` → `chat_threads(id)`. Yani bir mesajın `user_id`'si ile
   `thread_id`'si **her zaman aynı kullanıcıya** aittir (`chat_messages`
   RLS SELECT politikası da bunu `EXISTS` ile zorunlu kılıyor:
   `20260927220000_rls_update_with_check.sql:139`). Ancak **CHECK kısıtı yok**:
   yazma yolları istemcide `user_id`yi `thread`'in sahibinden türetiyor
   (`chat_repository.insertUserMessage` → `userId` parametresi). Aynı
   `freeze_immutable_columns` deseni `chat_messages.user_id` için de
   uygulanabilir (şu an yalnız `thread_id` dondurulmuş, satır ~404).
   → **Düşük öncelik, savunma-derinliği.**
3. **[P2] `importData` kısmi import.** 414 ya da tek satır 400'ünde import
   ortada kesiliyor (`counts` dönmüyor) → kullanıcı "başarısız" sanıyor ama
   `foods` tablosu **kısmi** yazılmış oluyor. Düzeltme ya istemcide
   (A2r4/bir sonraki tur: aşamalı raporlama + rollback) ya da RPC ile
   atomik import. **`supabase/**` alanı gerektirmiyor → kendi alanımda,
   "sonraki tur" notu.**
4. **[P3] `foods` üzerinde `UNIQUE(created_by, name) NULLS NOT DISTINCT`
   yok.** Yedek import dedup'ı isim bazlı; iki kullanıcı yemeği aynı adı
   taşıyabilir ve `importData` ilk eşleşmeyi alıp ikincisini atar. Migration
   eklemek veri birleştirme kararı gerektirir → **karar gerekli, önermiyorum.**

### → A3r2 (`lib/core/**`)

- `test/core/widgets/widget_bridge_scope_test.dart` **git'te değil
  (untracked)** ve `flutter test`'i 10 dakika timeout ile kilitliyor:
  `WidgetBridge.publish(...)` widget testinde `home_widget` platform kanalını
  bulamayınca sonsuza kadar bekliyor. `HomeWidgetSave` DI injection'ı
  save/read için var ama **`publish`'te `HomeWidgetPlugin.updateWidget` /
  `saveWidgetData` doğrudan çağrılıyor** → mock'lanmıyor.
  Bu dosya `flutter analyze`'i de kirletiyor mu? Hayır (temiz geçiyor) ama
  `flutter test`'i **kırmızı** bırakıyor. **Ya `publish` de injectable
  yapılmalı ya da test `skip`/mock'lanmalı.** Ben dokunmadım (`core/**`).
  Kanıt: `flutter test test/features` → +56 geçiyor, `test/core` → +304 **−1**,
  `test/data` → +153 geçiyor. Aynı dosya `git stash`/commit'lenmemiş bir A3r2
  çalışma ağacı kalıntısı.

### → A4 (`lib/features/**`)

1. **Sozleşme değişikliği (derleme zorunluluğu):**
   `ChatRepository.archiveThread(String userId, String threadId)` →
   `chat_page.dart:293` zaten `user.id` geçiriyor (A4r3'te uyarlanmış),
   `flutter analyze` temiz. Yeni davranış: `restoreMealEntry` artık
   **`StateError` fırlatabilir**; `meal_section.dart:52` `try/catch` zaten var →
   kullanıcıya `dashboard.errorDelete` gösterilir. **Ek değişiklik gerekmiyor.**
2. **Yeni model alanları kullanılmıyor (bilinçli):** `ChatMessage.pendingAction`
   / `actionStatus` / `metadata` artık okunabiliyor ama sohbet ekranında
   kullanılmıyor. AI önerisi onay/ret akışı **A4'ün alanında**:
   `m.hasPendingAction` → onay/ret butonları → `action_status` güncellemesi
   (yeni repository metodu gerekir: `updateActionStatus(…)` — **eklemedim**,
   çünkü UI kararı olmadan ölü kod olur).
3. **`water_tracker`**: özel giriş `digitsOnly` → veri katmanı `INTEGER`
  yuvarlaması erişilebilir değil. Değişiklik gerekmiyor.

### → A5/A6

- `src/hooks/useDataExport.ts` **beyaz liste uyguluyor** (satır 160-180) ve
  `source` allow-list'i var (162-168) → web bu turda bulduğum iki P1'in
  (kara liste `PGRST204`, `food_source` enum) zaten çözülmüş. **React tarafı
  sağlam; Flutter yedek yolu değilmiş.** Ayrıca web'in
  `UNIQUE(food_nutrition.food_id)` çakışması ve `deleted_at` canlanması sorunu
  **web'de de var** (kaynak: `useDataExport.ts:202-210` besin insert'inde
  `maybeSingle` ile varlık kontrolü yok).

---

## Yeni testler (+64)

| Dosya | Test | Kapsam |
|---|---|---|
| `test/data/repositories/data_transfer_scalability_test.dart` (yeni) | 18 | `inFilterChunks` 100 sabit; gerçek URL ölçüsü (postgrest'in `_cleanFilterArray` üretimi birebir kopyalandı); 2000/5000 kayıt regresyon kanıtı; boş girdi `PGRST100` koruması; 2000 öğünlük yedek JSON sözleşmesi; `isDeleted` |
| `test/data/repositories/diary_soft_delete_test.dart` (yeni) | 14 | Gerçek `SupabaseClient` + `MockClient` (URL'ler gerçekten üretilir): 3 tabloda `deleted_at=is.null`; **karşı-ölçüm** (silinmiş satır dönse toplam 500.0); analytics 3 tablo; `PATCH` + UTC damga + kapsam filtresi; `restoreMealEntry` 3 senaryo; bozuk satır tüm günü düşürmez |
| `test/data/repositories/chat_pagination_test.dart` (yeni) | 7 | `order=created_at.desc.nullslast,id.desc.nullslast` + `limit=10`; tam sayfa → `hasMore`; `lt` + ikincil sıralama; kardeş `id` → `not.in.(a,b)` → **hiç mesaj atlanmıyor**; boş sayfa; `archiveThread` kapsam filtresi |
| `test/data/repositories/import_sanitize_test.dart` (yeni) | 8 | `sanitizeFood` beyaz liste (`barcode`/`sync_state`/`client_id`/`last_synced_at` düşer); `source` allow-list (5 geçersiz + 3 geçerli); null alanlar; `mealTypeDbValues` ⟷ `MealType` küme bütünlüğü |
| `test/data/repositories/water_amount_ml_test.dart` (yeni) | 7 | Yazma sınırı (DB'ye ulaşmaz); `int` gönderimi (`22P02` koruması); 250.4→250 / 250.5→251 / 249.6→250 kayıp ölçümü; `int↔double` okuma toleransı |
| `test/data/repositories/chat_repository_test.dart` (genişletildi) | +10 | `pending_action` (3 aksiyon tipi), `action_status` 5 durum, `metadata`, `raw` koruması, round-trip, `ChatActionStatus.dbValues`; `oldestTimestamp` 4 senaryo |

**Komut ve sonuç:**
```
cd flutter_app && flutter analyze
  → No issues found!

cd flutter_app && flutter test test/data
  → +153: All tests passed!      (tur 2: 88 → +65)

cd flutter_app && flutter test test/core/utils
  → 98 geçti (num_parsing, calculations, data_write_safety)

node tool/check_versions.cjs
  → ✓ Sürüm tutarlı: 1.3.0+4 (pubspec = AppConstants = CHANGELOG = README)
```

**Tam suite:** `flutter test` → **+515 −1**. Tek hata
`test/core/widgets/widget_bridge_scope_test.dart`
(`TimeoutException after 0:10:00`) — **untracked A3r2 dosyası**, benim
alanımda değil ve benim değişikliklerimden bağımsız (bkz. AKTARIM → A3r2).
Kanıt: dosyayı geçici olarak skip ederek koştum → 4 test geçti, kalan grup
yine kilitlendi; `test/features` (56) ve `test/data` (153) bağımsız yeşil.

---

## Kalan riskler

1. **[P1] `importData` hâlâ kısmi import yapabilir.** 414 (artık 100'lük
   dilimlerle beklenmiyor) veya tek satır 400'ünde `foods` yazılmış kalıyor,
   `counts` dönmüyor. Transaction yok. Sonraki tur: aşamalı raporlama +
   `TransferResult` (başarılı/başarısız tablo listesi) veya RPC. Etki: düşük
   (kullanıcı tekrar deneyebilir, dedup çalışır → veri kaybı yok).
2. **[P1] `importData` satır satır yazıyor.** 2000 öğün = 2000 HTTP isteği.
   Ölçeklenebilirlik **URL** tarafında çözüldü, **istek sayısı** tarafında
   çözülmedi (bilinçli: satır sırası `created_at`'i korumak için gerekliydi,
   web parity). 2000 kayıt ≈ 2000 istek ≈ mobilde dakikalar + pil. Öneri:
   toplu insert (`insert(List)`) + `created_at`'i gövdede taşıma. Sonraki tur.
3. **[P2] `food_nutrition` besin kaybı.** UNIQUE ihlalinde yalnız ilk satır
   ekleniyor, kullanıcı bilmiyor. `counts['food_nutrition']` da dönmüyor →
   import özeti eksik.
4. **[P2] `analytics` `select()` +%7 alan** (`deleted_at` ×3) — payload
   ~%2 büyüdü, ihmal edilebilir.
5. **[P2] `loadMore` artık 2-3 istek.** Kardeş `id` taraması her sayfada bir
   ek istek; `chat_messages.thread_id, created_at` index'i var
   (`20260518080500:52`) ve `eq(created_at)` taraması index kullanır → ihmal
   edilebilir. Çok eski sohbetlerde 3 istek/page = 30 istek/10 mesaj.
   Alternatif: composite imleç (`created_at,id`) tek sorguda — PostgREST'te
   `or=(created_at.lt.X,and(created_at.eq.X,id.lt.Y))` gerekir, **yapmadım**
   (URL karmaşıklığı + okunabilirlik). Sonraki tur adayı.
6. **[P2] `Profile.activityLevel` hâlâ `String?`.** A2r2'de "tur 3'e bırakıldı"
   diye yazılmıştı; bu turda **dokunmadım** (A4'ün iki okuma noktası hâlâ
   `asNameMap()` kullanıyor → onları değiştirmeden modeli enum'a çevirmek
   `ActivityLevel?` alanı + `copyWith` + 4 test değişikliği demek; A4 ile
   eşleştirilmiş iş, tek başıma yarım bırakmak daha kötü). **Aktarım → A4.**
7. **[P3] `exportData` `select()` ile tüm kolonları çekiyor** (P3, web parity).
8. **[P3] `food_repository` okuma yollarında istemci süzgeci yok**
   (`search`/`favorites`/`recents` `deleted_at` kolonunu getirmiyor). Sunucu
   süzgeci doğru; analytics/fetchDaily ile aynı savunma derinliği burada da
   uygulanabilir ama `FoodItem` üretimi zaten `isCustom` yoluna düşüyor
   (düşük etki).
