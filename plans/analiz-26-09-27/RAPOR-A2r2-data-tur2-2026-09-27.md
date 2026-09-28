# RAPOR — A2r2-data (veri katmanı) — 2026-09-27 — Tur 2

**Kapsam:** `flutter_app/lib/data/**` (yeni dosyalar dahil) ve oluşturduğum
`flutter_app/lib/core/utils/num_parsing.dart` + `flutter_app/test/data/**` /
`flutter_app/test/core/utils/**`.
`supabase/**` **yalnızca okundu** (CHECK kısıtı ve edge function
`ACTIVITY_LEVELS` doğrulaması için). `lib/features/**` **dokunulmadı**.

---

## Özet (5 madde)

1. **P1 `activity_level` enum eşleyicisi kuruldu.** `lib/data/activity_level_map.dart`
   altında `String activityLevelToDb(ActivityLevel)` ve
   `ActivityLevel activityLevelFromDb(Object?)`. DB değerleri
   `supabase/migrations/20260111041204_db829bb7-...sql:39` ve
   `supabase/full_setup.sql:21`'deki **CHECK kısıtından okundu**:
   `sedentary, light, moderate, active, very_active`. `exhaustive switch`
   sayesinde yeni enum değeri eklenirse derleme hatası verir.
2. **`macro_calculator.dart:68` düzeltildi.** Edge function gövdesine
   `ActivityLevel.name` (`veryActive`) gönderiliyordu; `calculate-macros`
   `ACTIVITY_LEVELS` yalnızca snake_case kabul ediyor → **her onboarding
   AI isteği 400 alıyordu**. Artık `activityLevelToDb(...)`. (`.name`
   gönderen 2 features çağrısı A4'ün alanında — aktarım bölümü.)
3. **P1 `macro_calculator` savunmasız hesap yolu kapandı.** BMI/BMR/TDEE/
   kalori/su hedefi hesapları `_safeBmi` / `_safeBmr` / `_safeInt`
   sarmalayıcılarıyla korundu: boy 0, negatif boy, NaN/Infinity girdide
   onboarding ekranı düşmüyor, hedefler üretiliyor.
4. **P2 `analytics_repository` oturum durumu ayrıldı.** Oturum yokken
   `AnalyticsData.empty` dönmek yerine `AnalyticsAuthRequired` fırlatılıyor.
   Durum repository'de bırakıldı; `features/analytics` **dokunulmadı**
   (A4'e aktarım). `profileProvider`'ın `null` dönmesi durumunda hâlâ
   "oturum yok" gösterilir — router `/analytics`'e oturumsuz erişimi zaten
   `/auth`'a yönlendiriyor, dolayısıyla kapsam dar.
5. **Ortak yardımcı + çeviri anahtarı sızıntısı giderildi.**
   Yeni `lib/core/utils/num_parsing.dart` (`numOr`, `numOrNull`,
   `formatDateOnly`, `randomUuidV4`); `_num`/`_numOrNull` ve
   `formatEntryDate`/`localDateOnly` kopyaları tek uygulamaya taşındı.
   `chat_threads.title` artık çeviri anahtarı (`'chat.newThread'`)
   **yazmıyor** — başlık verilmezse kolon NULL kalır.

---

## Düzeltilenler

| Sev | Dosya | Ne yapıldı | Doğrulama |
|---|---|---|---|
| **P1** | `lib/data/activity_level_map.dart` (yeni) | `ActivityLevelMap` + üst düzey `activityLevelToDb` / `activityLevelFromDb`. `dbValues`/`dbValueSet` CHECK kısıtından birebir. `fromDb` null/boş/bozuk/tanımsız değerde **çökmez** → `ActivityLevel.moderate` (web `activityLevelFromDb` ile aynı varsayılan) + `AppLog.w`. | `test/data/activity_level_map_test.dart` (12 test) |
| **P1** | `lib/data/repositories/macro_calculator.dart:68` | `'activity_level': activityLevelToDb(activityLevel)` — `ACTIVITY_LEVELS` 400 hatası giderildi. | `data_write_safety_test.dart` grup 5, "activity_level … snake_case gönderilir" (edge function gövdesi mock `FunctionsClient` ile yakalanıyor) |
| **P1** | `lib/data/repositories/macro_calculator.dart:56` | `Calculations.bmi` çağrısı `_safeBmi` ile sarıldı (`try` **dışında** kalan yerel risk); ayrıca `_safeBmr` / `_safeInt` ile BMR/TDEE/kalori/su hedefleri de korundu. `goalsFromAiBody` ortak `numOrNull`'a taşındı. | `data_write_safety_test.dart` grup 5 (6 test: edge hatası, boy 0, negatif boy, kilo 0/negatif, NaN, Infinity) |
| **P2** | `lib/data/repositories/analytics_repository.dart:379` | `analyticsDataProvider`: oturum yoksa `AppLog.i` + `throw const AnalyticsAuthRequired()`. Yeni `AnalyticsAuthRequired implements Exception` tipi. `_num` kopyası → `numOr`. | `data_write_safety_test.dart` grup 6 (2 test) |
| **P1** | `lib/data/repositories/chat_repository.dart:42` | Yeni saf `ChatRepository.threadInsertPayload(userId, {title})`: `title` verilmezse/boşsa `null` (NULL) yazılır. `ensureThread` bunu kullanıyor — `'chat.newThread'` çeviri anahtarı artık DB'ye gitmiyor. | `test/data/repositories/chat_repository_test.dart` grup "ensureThread" (4 test) |
| **P3** | `lib/data/repositories/chat_repository.dart` | `_randomUuid` (elle yazılmış, `Random()` — CSPRNG değil) → `core/utils/num_parsing.dart` → `randomUuidV4()`: `Random.secure()` + RFC 4122 §4.4 sürüm/variant bit masking. **Bağımlılık eklenmedi.** | `test/core/utils/num_parsing_test.dart` (4 test: biçim, version/variant nibble, deterministik tohum, 1000 benzersiz) |
| **P2** | `lib/core/utils/num_parsing.dart` (yeni) | `numOr`/`numOrNull` (ortak sayı okuyucu) + `formatDateOnly` (ortak `yyyy-MM-dd`) + `randomUuidV4`. `diary_repository.formatEntryDate` ve `ChatRepository.localDateOnly` bu uygulamayı **kendi imzalarını koruyarak** çağırıyor (A4'ün çağırdığı API bozulmadı). | `test/core/utils/num_parsing_test.dart` (13 test) |

### `activity_level` eşleme tablosu (migration'dan okundu)

| `ActivityLevel` (Dart) | `ActivityLevel.name` | DB değeri (CHECK) | `multiplier` |
|---|---|---|---|
| `ActivityLevel.sedentary` | `sedentary` | `sedentary` | 1.2 |
| `ActivityLevel.light` | `light` | `light` | 1.375 |
| `ActivityLevel.moderate` | `moderate` | `moderate` | 1.55 |
| `ActivityLevel.active` | `active` | `active` | 1.725 |
| `ActivityLevel.veryActive` | **`veryActive`** | **`very_active`** | 1.9 |

Kaynaklar: `supabase/migrations/20260111041204_db829bb7-56ca-465d-bc88-c9fa6c7b3649.sql:39`,
`supabase/full_setup.sql:21`,
`supabase/functions/calculate-macros/index.ts:21` (`ACTIVITY_LEVELS`),
`supabase/functions/ai-chat/index.ts:247/372`.

**Round-trip testi:** 5/5 enum değeri `toDb` → `fromDb` ile aynı enum'a
dönüyor. **Küme bütünlüğü:** `ActivityLevel.values.map(toDb).toSet()` ile
`dbValueSet` **her iki yönde** birebir eşit (kayıp yok, ekstra yok, boyut 5).
**Tolerans:** `null`, `''`, `'   '`, `'veryActive'` (eski hatanın bıraktığı
değer), `'VERY_ACTIVE'`, `'Hareketsiz'`, `42`, `true`, liste, `NaN`,
`Object()` → hepsi `moderate` + `AppLog.w`, istisna yok (`returnsNormally`
testi). Toplam **12 test**.

---

## Doğrulama

```
cd flutter_app && flutter analyze   →  No issues found!
cd flutter_app && flutter test      →  379 tests, All tests passed!   (tur 1: 335 → +44)
node tool/check_versions.cjs        →  ✓ Sürüm tutarlı: 1.3.0+4 (pubspec = AppConstants = CHANGELOG)
```

> `check_versions.cjs` artık **yeşil**. İlk çalıştırmada iki ajanın
> in-flight değişiklikleri (`app_constants.dart` `defaultFat`, A6r2'nin
> `tool/check_versions.cjs` güncellemesi) yüzünden kırmızıydı; commit
> sonrası tekrar çalıştırıldığında yeşil. A3'ün `defaultFat` düzeltmesi
> çalışmış görünüyor.

**Commit:** `e5a9d44` — `fix(data): activity_level eşleyicisi, savunmalı hedef
hesabı, oturum durumu ve ortak yardımcılar` — 10 dosya, **+850/−71**.

---

## AKTARIM (başka alana)

### → A4 (`lib/features/**`) — **imzalar birebir**

```dart
// import 'package:calorix/data/activity_level_map.dart';
String activityLevelToDb(ActivityLevel level);      // 'veryActive' → 'very_active'
ActivityLevel activityLevelFromDb(Object? value);  // çökmez, loglar, 'moderate' fallback
// yardımcı: Set<String> ActivityLevelMap.dbValueSet
```

Kullanılacak yerler (hiçbiri A4 alanı dışında):
1. `features/onboarding/onboarding_page.dart:150` → `'activity_level': _activity.name` → `activityLevelToDb(_activity)`
2. `features/settings/widgets/goals_dialog.dart:129` → aynı
3. `features/dashboard/widgets/weight_card.dart:72` ve
   `features/settings/widgets/personal_info_dialog.dart:166` →
   `ActivityLevel.values.asNameMap()[p.activityLevel] ?? ActivityLevel.moderate`
   → `activityLevelFromDb(p.activityLevel)` (şu an DB'den camelCase bekliyor,
   yani `"very_active"` geldiğinde daima `moderate`'a düşüyor → **kilo
   güncellemesinde aktivite seviyesi kayboluyor**)
4. `features/onboarding/onboarding_page.dart:152` → `'goal': _goal.name`
   (`Goal` değerleri DB ile aynı, dokunulmadı — ama `_gender.name`
   (`male/female/other`) da DB CHECK ile aynı, doğrulandı)

**Sözleşme testleri:** `test/data/activity_level_map_test.dart` — kırılırsa
DB yazımı sessizce çöker.

### → A4 (`features/analytics`) — oturum durumu

```dart
// import 'package:calorix/data/repositories/analytics_repository.dart';
class AnalyticsAuthRequired implements Exception { final String message; }
```

`analyticsDataProvider(locale)` artık oturum yoksa `AnalyticsData.empty`
**yerine** bu hatayı fırlatır. `analytics_page.dart:99`'daki `error:` dalında:

```dart
error: (e, _) => e is AnalyticsAuthRequired
    ? const _SignInRequiredView()      // "giriş yap" mesajı
    : _ErrorView(onRetry: () => ref.invalidate(analyticsDataProvider(locale))),
```

Not: `profileProvider` da oturum yoksa `null` döner ve `_Targets.fromProfile`
bunu zaten "hedef yok" olarak ele alıyor. Yeni ihtiyaç doğarsa aynı desen
(`ProfileRepository` tarafında) ayrıca ele alınabilir.

### → A4 (`features/chat`) — thread başlığı

`ensureThread(userId, {title})` artık `title` verilmezse kolonu NULL
bırakıyor. `features/chat/chat_page.dart` ilk mesajdan başlık üretmek
istiyorsa `ensureThread(userId, title: <türetilmiş metin>)` çağırabilir;
aksi halde `null` sorun değil (`ChatThread.title` nullable). `chat_page.dart:194`
`ChatRepository.localDateOnly` kullanmaya devam edebilir — imza korundu.

### → A3 (`lib/core/**`)

1. **`num_parsing.dart` kopyaları hâlâ duruyor (bilinçli, dokunulmadı):**
   - `core/widgets/widget_snapshot.dart:95/170/197/273/301` → kendi
     `formatEntryDate`'ini kullanıyor. `formatDateOnly` ile **aynı**
     çıktıyı verdiği için davranış farkı yok; yalnızca kod tekrarı var.
     İstersen `formatDateOnly`'a yönlendirebilirsin.
   - `core/notifications/web_reminder.dart:73` → "gün anahtarı" üretimi
     (`widget_snapshot.dart` ile aynı mantık, farklı dosya).
   - `core/utils/calculations.dart` **dokunulmadı** (senin alanın).
2. `_num`/`_numOrNull` artık tek yerde: `core/utils/num_parsing.dart`.
   `AnalyticsRepository._num` ve `MacroCalculator._numOrNull` kaldırıldı.

### → A1r2 (`supabase/**`) — dokunulmadı

- Tur 1'de bildirdiğim `chat_threads.title` sızıntısı Flutter tarafında
  düzeltildi; **mevcut üretim verisinde `title = 'chat.newThread'` kayıtları
  varsa** tek seferlik bir veri temizliği gerekebilir:
  `UPDATE chat_threads SET title = NULL WHERE title = 'chat.newThread';`
  (Proje frozen + üretim verisi yok → gerekli değil, ama not.)
- `chat_messages`'ta `pending_action` / `action_status` / `metadata`
  kolonları hâlâ Flutter modelinde yok (tur 1 aktarımı, değişmedi).

---

## Yeni testler (44)

| Dosya | Test | Kapsam |
|---|---|---|
| `test/data/activity_level_map_test.dart` (yeni) | 12 | enum→DB tablosu, 5/5 üretilebilirlik, camelCase sızıntısı, 5/5 round-trip, her DB değeri eşlenir, **küme bütünlüğü (kayıp/ekstra yok)**, `dbValues`↔`dbValueSet` tutarlılığı, null/boş/belirsiz, 9 tanımsız değer, 10 benzersiz girişte `returnsNormally`, web fallback'i ile aynı |
| `test/core/utils/num_parsing_test.dart` (yeni) | 17 | `numOr`/`numOrNull` (tip/NaN/Infinity/fallback/sonluluk), `formatDateOnly` (sıfır dolgu, tek haneli yıl, saat yok sayımı, **diary/chat iki kopyası artık aynı**), `randomUuidV4` (200 biçim, version/variant nibble, deterministik tohum, 1000 benzersiz) |
| `test/core/utils/data_write_safety_test.dart` (genişletildi) | +11 | grup 5: `MacroCalculator.calculate` — edge hatası → yerel formül, boy 0, negatif boy, kilo 0/negatif, NaN, Infinity, **edge gövdesinde `very_active`**. grup 6: oturum yokken `AnalyticsAuthRequired` + mesaj metni |
| `test/data/repositories/chat_repository_test.dart` (genişletildi) | +5 | `threadInsertPayload`: title yok/boş → NULL, çeviri anahtarı yazılmaz, kırpma, boş string yazılmaz; `ChatThread` NULL başlık testi |

---

## Bulunurlar (düzeltilmedi, gerekçe)

| Sev | Dosya:satır | Bulgu | Etki | Öneri |
|---|---|---|---|---|
| **P1** | `features/onboarding/onboarding_page.dart:150`, `features/settings/widgets/goals_dialog.dart:129` | İki çağrı hâlâ `ActivityLevel.name` yazıyor → "Çok Aktif" seçilince profil UPDATE'i hâlâ başarısız. | A4 alanı; veri katmanı hazır. | A4: `activityLevelToDb(...)`. |
| **P2** | `features/dashboard/widgets/weight_card.dart:72`, `features/settings/widgets/personal_info_dialog.dart:166` | `asNameMap()` camelCase bekliyor, DB snake_case döner → aktivite seviyesi her zaman `moderate`a düşüyor. | A4 alanı. | `activityLevelFromDb(...)`. |
| **P2** | `lib/data/repositories/analytics_repository.dart:291` | `fetch` hâlâ `userId` parametresi alıyor; oturum yokluğu yalnızca provider seviyesinde ele alınıyor. Doğrudan repository kullanan kodda koruma yok. | Düşük (tek çağıran provider). | Provider tek giriş noktası olarak kalsın; `fetch`'e `userId` zorunlu kalmalı. |
| **P3** | `lib/data/repositories/diary_repository.dart:141-148` | Tur 1'den kalan `results[0] as List` zorlamaları. | Pratikte güvenli. | Tur 3. |
| **P3** | `lib/data/repositories/data_transfer_repository.dart:84` | `inFilter` parçalanmıyor (8 KB URL limiti). | Çok büyük yedeklerde 414. | Tur 3. |
| **P3** | `lib/data/repositories/macro_calculator.dart` | `activityLevelFromDb` repository'de henüz **kullanılmıyor** (okuma tarafı `Profile.activityLevel` string olarak saklanıyor, model enum değil). | Şimdilik ölü kod gibi görünüyor ama A4'ün okuma tarafına geçmesiyle kullanılacak. | A4'e aktarıldı; modeli enum'a çevirmek geniş refactor → tur 3. |
| **P3** | `core/utils/num_parsing.dart` → `randomUuidV4` | `Random.secure()` CSPRNG'dir ama Dart'ta platform kriptografik PRNG'si yok (parola/oturum için kullanılmamalı). | Dosya adı üretimi — çakışma ihmal edilebilir. | Bilinçli kabul; `uuid` bağımlılığı eklenmedi. |

---

## Sonraki öneriler (tur 3)

1. `Profile.activityLevel`'ı `String?` yerine bir `ActivityLevel?` alanı +
   `fromJson`'da `activityLevelFromDb` ile okuyan alan yapmak (okuma tarafı
   güvenliğini kalıcı kılar; `toJson` `toDb` kullanmalı).
2. `data_transfer_repository` `inFilter` parçalama (1000'lik dilimler).
3. `diary_repository.fetchDaily` zorlamaları → `List<dynamic>.from(...)`.
4. `ensureThread`/chat thread başlığı için ilk mesajdan türetme (A4).
5. `supabase/tests/` altında gerçek PostgREST entegrasyon testi — dedup ve
   `CHECK` kısıtı davranışı şu an yalnızca mock'la doğrulanıyor.
