# RAPOR — A2-backend-data — 2026-09-27 — Tur 1

**Kapsam:** `flutter_app/lib/data/**` (12 model + 5 `.g.dart` + 10 repository +
`supabase_client_provider.dart`) ve gevşek bağlı `flutter_app/lib/core/utils/calculations.dart`.
`supabase/**` yalnızca **okundu** (şema/RLS kanıtı için), hiçbir dosya değiştirilmedi.

---

## Özet (5 madde)

1. **`user_id` kapsam filtresi eksikliği (P0, savunma-derinliği).** `DiaryRepository`'nin
   `updateMealEntry` / `deleteMealEntry` / `restoreMealEntry` / `deleteWaterEntry`
   çağrılarında sorgu **yalnızca** `.eq('id', id)` ile kısıtlanıyordu; `user_id`
   hiçbir yazma yolunda filtrelenmiyordu. RLS bunu zaten engellediği için *canlı*
   bir veri sızıntısı değildi, ancak RLS politikası bir gün gevşetilirse başkasının
   kaydı sessizce ezilirdi. Dört metoda `userId` parametresi eklendi ve
   `.eq('user_id', userId)` filtresi kondu.
2. **PostgREST filtreleme hatası (P1, uygulama kırık).** `.filter(col, 'is', null)`
   çağrıları `col=is.null` üretir; PostgREST `is` operatörü `null` değeri için
   **`isFilter(col, null)`** ister. `postgrest-2.9.1` kaynağı doğrulandı
   (`lib/src/postgrest_filter_builder.dart:227` → `appendSearchParams(column, 'is.$value')`
   — `isFilter` de aynı URL'i üretir, ama API'nin belgelenmiş/beklenen yolu).
   `diary_repository.dart` (3), `food_repository.dart` (4), `chat_repository.dart` (3)
   olmak üzere **10 çağrı** düzeltildi.
3. **Sessizce yutulan hatalar (P1).** `macro_calculator.dart` AI hatasında
   `catch (_) {}` idi; `chat_repository.invokeAssistant` boş gövde/`{error}`
   yanıtında `null` döndürüyordu (UI "asistan cevap vermedi" sanıyor);
   `recognition_repository` non-2xx yanıtta ham `FunctionsHttpException`'ı
   UI'ye fırlatıyordu; `auth_repository` üç metotta yalnızca `AuthException`
   yakalıyor, diğer tüm hatalar kullanıcıya sızıyordu. Hepsi artık
   `AppLog` ile loglanıyor / alan bazlı `Exception` üretiyor.
4. **N+1 + `PGRST116` çökmesi (P1).** `data_transfer_repository.importData` dedup
   kontrolünü kayıt başına `maybeSingle()` ile yapıyordu → aynı anahtara sahip
   **2 satır** bulunduğunda `maybeSingle()` 0 satır döndürüp
   `PGRST116` fırlatıyor, tüm içe aktarma çöküyordu. Tek `inFilter` sorgusuna
   çevrildi (aynı desen `food_id`/`name`/`entry_date` için zaten vardı).
5. **DST ve UTC doğruluğu (P1/P2).** `diary_repository` `_nowIso()` **yerel**
   saati yazıyordu (`+03:00` ofsetli istemcide sunucuda ~3 saat kaymış `updated_at`/
   `deleted_at`); `profile_repository` ve `user_settings_repository` `updated_at`
   için aynı hata vardı (`.toUtc()` ile düzeltildi). `analytics_repository`
   `add(Duration(days:1))` ve `subtract(Duration(days:90))` kullanıyordu;
   `TZ=Europe/Berlin` altında 2026-03-29'da bir gün **atlanıyor**,
   2026-03-30'dan geriye 90 gün **2025-12-29** yerine 2025-12-30'a gidiyordu
   (grafik eksik/fazla nokta). **Önemli düzeltme (nüans):** `meal_entries`,
   `water_entries`, `weight_entries` ve `user_settings` tablolarında
   `update_updated_at_column` BEFORE UPDATE trigger'ı `NEW.updated_at = now()`
   ile **her UPDATE'i geçersiz kılıp** sunucu UTC'sine (`now()` = `timestamptz`
   → UTC) yeniden yazar. Yani istemcinin gönderdiği ofsetli `updated_at` diskte
   kalmaz; `.toUtc()` düzeltmesi **doğru/taşınabilir** ama etkisi pratikte
   yalnızca trigger'ın devre dışı bırakıldığı ortamlar (yedek/import, kısmen
   denetim) ve **`deleted_at`** (trigger kapsamı dışında) için geçerlidir.

---

## Düzeltilenler

| Sev | Dosya | Ne yapıldı | Doğrulama |
|---|---|---|---|
| P0 | `lib/data/repositories/diary_repository.dart` | `updateMealEntry`/`deleteMealEntry`/`restoreMealEntry`/`deleteWaterEntry` → `userId` eklendi, `.eq('user_id', userId)` kondu. 2 çağıran (`meal_section.dart`, `edit_meal_entry_dialog.dart`) imzaya uyarlandı. | `flutter analyze` temiz; `test/core/utils/data_write_safety_test.dart` |
| P1 | `lib/data/repositories/diary_repository.dart` | `_nowIso()` → `DateTime.now().toUtc().toIso8601String()` | `test/data/repositories/diary_repository_test.dart` |
| P1 | `lib/data/repositories/diary_repository.dart` | 3× `.filter(...,'is',null)` → `.isFilter(...,null)` | `flutter analyze` |
| P1 | `lib/data/repositories/diary_repository.dart` | Yazma doğrulaması: `_requireFinitePositive` / `_requireFiniteNonNegative`. `addMealEntry` (miktar>0, 4 makro ≥0), `addWaterEntry` (ml>0), `addWeightEntry` (kg>0), `updateMealEntry` (kısmi güncelleme alan denetimi). `ArgumentError` fırlatılır → çağıranların mevcut `catch`'leri hatayı yüzeye taşır. | `data_write_safety_test.dart` grup 1 (6 test, "DB'ye ulaşmadan" `from()`'a `StateError` ile guard) |
| P1 | `lib/data/repositories/food_repository.dart` | `_customItem` → `customItem` (saf yardımcı, test edilebilir). `amount_g_ml` null/0/negatif/NaN → 100 g varsayılanı; `x/0 → Infinity → Infinity.round()` **istisnası** giderildi (favoriler/son-yenilenler listesini tümden düşürüyordu). Sonuç sonlu değilse 0. | `data_write_safety_test.dart` grup 2 (5 test) |
| P1 | `lib/data/repositories/food_repository.dart` | 4× `.filter(...,'is',null)` → `.isFilter` (`deleted_at` ×3, `food_id` ×1) | `flutter analyze` |
| P1 | `lib/data/repositories/macro_calculator.dart` | Gövde doğrulaması saf statik `goalsFromAiBody(...)` fonksiyonuna çıkarıldı: 6 zorunlu alan `num` **ve sonlu** olmalı; `String`/eksik/`NaN` → `null` → yerel formül. `catch (_) {}` → `AppLog.w(...)`; 200-dışı/eksik-gövde yoluna da `AppLog.w`. | `data_write_safety_test.dart` grup 3 (5 test) |
| P1 | `lib/data/repositories/chat_repository.dart` | Yeni `ChatException`. `invokeAssistant`: `data == null` ve `data['error'] != null` → `ChatException` (eskiden sessiz `null`). `containsKey('error')` → `data['error'] != null`. 3× `.filter(...,'is',null)` → `.isFilter` (`archived_at`, `deleted_at` ×2). `_nowIso()` zaten UTC. | `flutter analyze`; `test/data/repositories/chat_repository_test.dart` |
| P1 | `lib/data/repositories/recognition_repository.dart` | `FunctionException` (`FunctionsHttpException` **ve** `FunctionsRelayException` bu sınıftan türer) yakalanıyor; `.details['error']` yeni `_errorFrom(...)` ile okunup `RecognitionException` mesajına giriyor. `containsKey('error')` → `data['error'] != null`. | `flutter analyze` |
| P1 | `lib/data/repositories/auth_repository.dart` | `resetPassword`/`resendVerificationEmail`/`updatePassword` artık `on AuthException` **+** genel `catch` ile `AppLog.w`; `signUp`/`signIn` de `AppLog` ekledi. `app_logger.dart` import edildi. | `test/data/repositories/auth_repository_test.dart` (12 test yeşil) |
| P1 | `lib/data/repositories/data_transfer_repository.dart` | N+1 dedup → tek `inFilter` sorgusu. Yeni saf yardımcılar: `_mealKeysOf`, `_mealKey`, `_existingMealKeys`, `_existingWaterTimes`. `maybeSingle()` PGRST116 çökmesi giderildi. | `flutter analyze` |
| P1 | `lib/data/repositories/analytics_repository.dart` | DST-safe `_addDays` = `DateTime(y, m, d ± n)` ve `_daysBetween` (UTC gün farkı); `dateRange(threeMonths)` ve `buildDays` bunları kullanıyor. `as String`/`as num` → `_num()` / `_safeDateLabel()`. Kilo trendi sorgusu son 365 günle sınırlandı (grafik penceresi zaten 1 yıl). | `data_write_safety_test.dart` grup 4 (11 test) + mevcut `analytics_repository_test.dart` |
| P2 | `lib/data/repositories/profile_repository.dart` | `updated_at` → `.toUtc()` | `flutter analyze` |
| P2 | `lib/data/repositories/user_settings_repository.dart` | `updated_at` → `.toUtc()` | `flutter analyze` |
| P2 | `lib/data/models/recognized_food.dart` | `const []` → `const <dynamic>[]` (tip çıkarımı uyarısı) | `flutter analyze` |

**Doğrulama (final):** `flutter analyze` → `No issues found!` ·
`flutter test` → `312 tests, All tests passed!` (önceki turda diğer ajanların
in-flight dosyalarından gelen derleme hataları artık yok).

---

## Bulunurlar (düzeltilmedi, gerekçe)

| Sev | Dosya:satır | Bulgu | Etki | Öneri |
|---|---|---|---|---|
| P1 | `lib/data/repositories/chat_repository.dart:59` | `chat_threads.title` DB'ye **çeviri anahtarı** `'chat.newThread'` olarak yazılıyor (İngilizce/çeviri uygulanmamış dize). Thread başlığı hiç güncellenmiyor ve UI'da gösterilmiyor. | Kullanıcı veri dışa aktarımında (`exportData`) anlamsız bir başlık görür; ileride başlık gösterilirse çeviri hatası. | Başlık üretimini A4'ün `features/chat` katmanına taşı (`l10n` ile ilk mesajdan türet). Veri katmanı `title`'ı `null` bırakabilir. |
| P2 | `lib/data/models/chat_message.dart` | `chat_messages` tablosunda `pending_action`, `action_status`, `metadata` kolonları var, modelde yok. `select()` deserialize `json_serializable` bunları yok sayıyor (veri kaybı yok, işlev eksik). | AI önerilen aksiyonları ("şu öğünü ekle") onay/ret mekanizması Flutter'da taşınamaz. | Web'de kullanılıyorsa modele alan ekleyip tur 2'de bağla. |
| P2 | `lib/data/repositories/diary_repository.dart:284` | `water_entries.amount_ml` Postgres'te `integer`; Dart `double` gönderiyor. `.round()` ile gönderiliyor (250.0 → 250). 250.5 → 250, sessiz hassasiyet kaybı. | Su miktarı 0.5 ml hassasiyetinde kaydedilmiyor (bilinçli, web parity). | Dokunulmadı: kasıtlı, kodda belgeli. Gerekirse A1 ile kolon tipi değişimi (`numeric`). |
| P3 | `lib/data/repositories/diary_repository.dart:141-148` | `fetchDaily` `results[0] as List` gibi zorlamalar kullanıyor; `select()` her zaman liste döndürdüğü için pratikte güvenli. | Gelecekte şema değişimiyle sessiz `TypeError` riski. | Tur 2'de `List<dynamic>.from(...)` ile savunulabilir. |
| P3 | `lib/data/repositories/data_transfer_repository.dart:84` | `inFilter('food_id', foodIds)` — `foodIds` binlerce girdiye ulaşırsa PostgREST URL uzunluk limiti (~8 KB) aşılabilir; parçalama yapılmıyor. | Çok büyük yedeklerde içe aktarma `414` alabilir. | 1000'lik parçalar halinde `inFilter` + toplu insert. |
| P3 | `lib/data/repositories/chat_repository.dart` | `_randomUuid` elle yazılmış (RFC 4122 v4 biçiminde ama `crypto` kütüphanesi yok). | Çakışma olasılığı ihmal edilebilir; yine de standart dışı. | Tur 2'de `uuid` bağımlılığı değerlendirilsin. |
| P3 | `lib/core/utils/calculations.dart` | `bmr`/`bmi`/`macros`/`age`/`progress` sayısal güvenlik kontrolleri eksikti. | A3'ün alanı. | **A3 zaten düzeltti** (`minBmr`, `maxAge`, `bmi == 0` koruması) — `macro_calculator` ve `analytics` yolları bu sayede güvenli. Ben dokunmadım. |

---

## AKTARIM (başka alana)

### → A1-security (`supabase/**`) — dokunulmadı, öneri
1. **`chat_threads.title` çeviri anahtarı**: DB'ye `chat.newThread` yazılıyor
   (bkz. yukarıdaki P1). Düzeltme A4'te.
2. **`chat_messages` kolonları**: `pending_action` / `action_status` / `metadata`
   migration'da var ama Flutter modeli yok. Kullanılmayan kolonlar mı, yoksa
   web'e özgü mü? Buna göre ya migration'da düşürülmeli ya da A2 tur 2'de
   modellenmeli.
3. **`water_entries.amount_ml` `integer`**: Flutter `double` gönderiyor ve
   `.round()` ile yuvarlanıyor (bilinçli, `diary_repository.dart:284`).
   Kullanıcı 250.5 ml kaydederse 250 olur. Kolon `numeric` yapılırsa yuvarlama
   gerekmez.
4. **RLS doğrulaması (A2'nin bulgularını doğrulayan kanıt):**
   `supabase/full_setup.sql:217/223/230` — `meal_entries`, `water_entries`,
   `weight_entries` UPDATE politikaları `USING (auth.uid() = user_id)`
   içeriyor. Yani benim bulduğum eksik `user_id` filtreleri canlı bir açık
   **değildir**, savunma-derinliği düzeltmesidir.
   → **A1'e somut soru:** bu üç UPDATE politikasında **`WITH CHECK` yok**.
   Postgres'te UPDATE politikası yalnızca `USING` ile sınırlıysa, bir kullanıcı
   `user_id`'yi başka bir `auth.users.id`'ye UPDATE edebilir (kendine yabancı
   satır yazabilir). Örnek: `UPDATE meal_entries SET user_id = '<başkası>'`
   → `USING` geçer, `WITH CHECK` yok → kabul edilir. INSERT politikalarında
   `WITH CHECK (auth.uid() = user_id)` **var** (satır 216/222/228), UPDATE'te
   **eksik**. `user_settings` UPDATE (satır 240) ve `profiles` UPDATE için de
   aynı kontrolü öneriyorum. → **P0 adayı, A1'in alanında.**
5. **`user_settings` UNIQUE(user_id, key)** (`full_setup.sql:165`): mevcut
   `onConflict: 'user_id,key'` **doğru**; değiştirilmesi gereken bir şey yok.
   Doğrulandı.
6. **`update_updated_at_column` trigger'ı `NEW.updated_at = now()` ile her
   UPDATE'i ezer** (`full_setup.sql:264-270`, trigger'lar 297-303). Bu
   `deleted_at` için sorun değil ama istemcinin `updated_at`'ı yazması
   anlamsız (sessizce atılıyor). A1'in bilgisine: `profiles.updated_at`'i
   istemciden göndermek de aynı şekilde işsiz.

### → A3-flutter-core
- `calculations.dart` sayısal güvenlik düzeltmelerini zaten yapmışsınız; ben
  `macro_calculator`/`analytics` çağrı noktalarını bu korumalara dayandırdım.
  `_numOrNull`/`_num` gibi "sonlu sayı okuyucuları" için ortak bir yardımcı
  (`lib/core/utils/num_parsing.dart`) düşünülebilir — şu an `analytics_repository`
  ve `macro_calculator` kendi kopyasını taşıyor (2 kopya, ileride 3 kopya riski).
- `formatEntryDate` (`diary_repository.dart`) ve `ChatRepository.localDateOnly`
  (`chat_repository.dart`) aynı `yyyy-MM-dd` mantığını iki kez uygular —
  ortak yardımcıya taşınabilir.

### → A4-flutter-features
1. **İmza değişikliği (uygulandı, bilgilendirme):**
   `updateMealEntry(userId, id, updates)`, `deleteMealEntry(userId, id)`,
   `restoreMealEntry(userId, id)`, `deleteWaterEntry(userId, id)` — yeni
   `userId` parametresi. Benim dokunduğum 2 çağıran:
   `lib/features/dashboard/widgets/meal_section.dart`,
   `lib/features/add/widgets/edit_meal_entry_dialog.dart` (her ikisi de
   `auth_repository` importu ekledi). Başka çağıran varsa `flutter analyze`
   yakalar.
2. **`addMealEntry` artık `ArgumentError` fırlatabilir** (NaN/negatif/0 miktar).
   Çağıran tarafta zaten boş metni `0`'a çeviren `_parse` var; öneri: giriş
   alanı seviyesinde de doğrulama + kullanıcıya görsel geri bildirim, çünkü
   şu an hata mesajı ham `ArgumentError` olarak ekrana düşebilir.
3. **`addWeightEntry` 0/negatif kiloyu reddediyor** — `weight_card.dart`
   zaten filtreliyor, yine de UI'da kullanıcıya "geçersiz" mesajı gösterin.
4. **`invokeAssistant` artık `ChatException` fırlatıyor** (eskiden `null`).
   `features/chat/chat_page.dart` bu tipi yakalayıp kullanıcıya mesaj göstermeli
   (`chat_page.dart`'ta `_loadFailed` alanı zaten vardı — o alanı bu hataya
   bağlamak mantıklı olur).
5. **Data transfer** içe aktarma artık O(N) sorgu yerine toplu `inFilter`
   kullanıyor; `transfer_dialogs.dart` ilerleme göstergesi ekleyebilir.

---

## Yeni testler

**`flutter_app/test/core/utils/data_write_safety_test.dart`** (yeni, 27 test) —
ağ çağrısı yok, `mocktail` ile `SupabaseClient` mock'lanır.

| Grup | Kapsam | Test sayısı |
|---|---|---|
| 1) `DiaryRepository` yazma sınırı | `addMealEntry` NaN/Infinity/negatif/0 miktar → `ArgumentError`; `addWeightEntry` 0/negatif/NaN/Infinity; `addWaterEntry` 0/negatif/NaN; `updateMealEntry` kısmi güncelleme 0/NaN; **ve** geçerli güncellemenin DB'ye ulaştığı (korumanın aşırı-geniş olmadığının kanıtı) | 7 |
| 2) `FoodRepository.customItem` | `amount_g_ml` 0/null/negatif/NaN → 100 g varsayılanı, `Infinity.round()` istisnası yok; 250 g girdinin 100 g'ye ölçeklenmesi (web parity) | 5 |
| 3) `MacroCalculator.goalsFromAiBody` | NaN alan → `null`; eksik alan → `null`; `String` alan → `null`; tam gövde kabul; su hedefi AI'da yoksa yerel formül | 5 |
| 4) `AnalyticsRepository` | `buildDays` 31 gün / 29 Şubat (leap) / ay sınırı aşımı / `end > today` kırpma; `dateRange` week + Şubat-2024; `aggregateDaily` bozuk satır (null tarih, null sayı, `String`, `NaN`) seriyi düşürmez; `buildWeightTrend` bozuk satırlar seriyi düşürmez; `computeAverages` boş günleri bölen dışı bırakır ve NaN üretmez | 10 |

**Komut ve sonuç:**
```
cd flutter_app
flutter analyze   →  No issues found!
flutter test      →  312 tests, All tests passed!
```

> Not: A3'ün `calculations_edge_cases_test.dart` dosyasıyla çakışma yok
> (farklı dosya adı, farklı kapsam).

---

## Sonraki öneriler (tur 2 için)

1. **Ortak sayı okuyucu** — `_numOrNull` / `_num` iki ayrı kopyada;
   `lib/core/utils/` altına taşı (A3 ile koordinasyon).
2. **`chat_threads.title`** üretimini A4'e devret; veri katmanı `null` bıraksın.
3. **`chat_messages` ek kolonları** — A1 cevabına göre ya modellenir ya
   migration'da düşürülür.
4. **`fetchDaily` zorlamaları** → `List<dynamic>.from(...)` ile savunulabilir
   hale getirilmesi.
5. **Data transfer `inFilter` parçalama** (1000'lik dilimler) — 8 KB URL limiti.
6. **`exportData`/`importData` için gerçek entegrasyon testi** (Supabase yerel
   instance) — şu an tüm veri katmanı testleri mock'lu; dedup mantığının
   gerçek `maybeSingle`/tekil kısıt davranışıyla uyumu hiç test edilmiyor.
   (Bu, bulduğum `PGRST116` çökmesinin ancak canlı DB'de yakalanabilecek
   türden bir test ile güvence altına alınabileceği tek yol.)
7. **Tüm repository'lerde yazma doğrulaması** tek bir ortak yardımcıya
   (ör. `Validate.finitePositive`) taşınsın; şu an yalnızca diary'de var.
