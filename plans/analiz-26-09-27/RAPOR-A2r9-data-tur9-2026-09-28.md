# RAPOR — A2r9 (veri katmanı + çapraz istemci borcu) — 2026-09-28 — Tur 9

## Özet (5 madde)

1. **⭐ `bmi(70, -180) = 24.2` kapatıldı.** `calculations.dart:88` artık
   `!weightKg.isFinite || weightKg <= 0` kontrolü yapıyor; web
   (`src/lib/calculations.ts:294`) ile birebir aynı. `node tool/check_versions.cjs`
   **tamamen yeşile döndü** (o tek uyarı düştü). 24 test.
2. **⭐ Web'in (A5r8) bulduğu 10 hesap hatasının Flutter karşılığı denetlendi:
   9'unda Flutter zaten doğruydu, 1'inde (`bmi` kilo) hatalıydı.** Kanıtlanan
   sonuçlar: BMR clamp **var**, TDEE negatif BMR'ı **kırpmıyor** (kaynak doğru),
   makro negatif gram **yok**, `maxAge=120` **uygulanıyor**, su hedefi `NaN`
   **yazmıyor**, AI gövdesi `NaN`'a düşmüyor. **Ama `Calculations.progress`
   Flutter'da da ÖLÜ**: üç katman savunma testte çalışıyor, `lib/`'de
   **0 çağıran** var (A5r8'ın web bulgusunun birebir karşılığı).
3. **⭐ `weigh_in_frequency_days` için veri katmanı savunması kuruldu.**
   `ProfileRepository.update` artık A1r8'in 5 CHECK'inin aralıklarını
   **istemci tarafında** uygular; `-5` **hiçbir istek atılmadan**
   `ProfileFieldRangeError` ile reddedilir. Önceden 5 ekran `catch (_)` ile
   yutup "Kaydedildi" **yalanı** söylüyordu.
4. **⭐ `_rollback` artık DELETE'in etkisini doğruluyor** (A2r5'ten kalan P3
   borcu). `DELETE` 200 dönse bile 0 satır silinirse `rolledBack = true`
   sayılıyor, `counts` sıfırlanıyor ve kullanıcıya "hiçbir şey yazılmadı"
   yalanı söyleniyordu. `.select('id')` ile `RETURNING id` ölçülüyor; kısmi
   silmede **yalnız kalanlar** raporlanıyor. Aynı düzeltmede
   `ImportReport.isPartial` tanımı düzeltildi (aşağıda).
5. **Yedek/geri yükleme A4r7'nin commit'iyle tutarlı; yeni av 3 bulgu üretti**
   (`select()` tüm kolonlar, soft-delete envanteri temiz, `isPartial` adı
   yanlış). 6 kişi iddiası: `_Client` `inFilter` ayrıştırma tuzağı ölçüldü.

> ⛔ **A4r7 çalışırken `test/features/shared/favorite_button_a4r7_test.dart`
> derlenmiyor** (`SemanticsFlags.checked` bu Flutter sürümünde yok) — benim
> alanım değil, dokunmadım. `flutter analyze` ve `flutter test` bu yüzden
> **tam yeşil değil**; benim alanımdaki 775 testin hepsi geçiyor.

## Düzeltilenler

| Sev | Dosya | Ne yapıldı | Doğrulama |
|---|---|---|---|
| **P1** | `lib/core/utils/calculations.dart:88` | `bmi` kilo alt sınırı: `weightKg <= 0` → 0. A3r6 boyu düzeltmişti, ağırlığı atlamıştı. Kare pozitif olduğu için `bmi(70,-180) = 21.6` → **`bmi.normal` (yeşil)** idi: imkânsız kayıt "sağlıklı" görünüyordu. | `check_versions.cjs` uyarısı düştü · `bmi_and_parity_a2r9_test.dart` 24 test · **negatif ölçüm**: kontrol geri alınınca 1 test kırmızı |
| **P1** | `lib/data/repositories/profile_repository.dart` | A1r8'in 5 `profiles` CHECK'inin **istemci karşılığı**. `update()` gövdeyi göndermeden önce `validateUpdates` çağırır → `ProfileFieldRangeError`. `clamp` **yok** (sessiz veri bozulması olurdu: "400 cm" → 250 yazılırdı). `null` her zaman geçer (`IS NULL OR …`). | `profile_field_range_test.dart` 19 test · **negatif ölçüm**: `validateUpdates` kaldırılınca 2 test kırmızı |
| **P2** | `lib/data/repositories/data_transfer_repository.dart:941` | `_rollback` DELETE etkisini doğruluyor: `.select('id')` → `RETURNING id`. 0 satır / kısmi silme / istek hatası → `rolledBack=false` + **ölçülmüş** `survivors`. | `rollback_effect_test.dart` 8 test · **negatif ölçüm**: `.select('id')` kaldırılınca 4 test kırmızı (ölçüldü) |
| **P2** | `lib/data/repositories/data_transfer_import.dart:255` | `ImportReport.isPartial`: `failedStage != null \|\| …` → `rolledBack == false && writtenTables.isNotEmpty`. Eski tanım **telafi başarılı olsa bile** `isPartial = true` dönüyordu (her yazma hatasında) → alan adı "kısmi bitti" dediği hâlde öyle anlam taşımıyordu. | `rollback_effect_test.dart` "tüm satırlar silindi" testi |
| **P3** | `lib/data/repositories/macro_calculator.dart:122` | `_safeBmr(weightKg: x.isFinite ? x : 0, …)` → girdi kırpması kaldırıldı. Sonuç değişmiyordu (`Calculations.bmr` zaten `minBmr`'a kırpıyor) ama **negatif** kilo/boy artık 0'a değerlendirilmeden kendi sözleşmesine gidiyor. | `bmi_and_parity_a2r9_test.dart` (uçtan uca 4 senaryo) |

## Görev 2 — Flutter'daki karşılık hatalar tablosu

| # | Web'de bulunan (A5r8) | Flutter durumu | Kanıt |
|---|---|---|---|
| 1 | `bmi` negatif kilo | ❌ **HAYALI — düzeltildi** (A3r6 boyu yapmış, ağırlığı atlamıştı) | `calculations.dart:88` · `check_versions` uyarısı düştü |
| 2 | BMR `clamp` yok | ✅ **Flutter'da ZATEN var** (`round().clamp(minBmr, 1<<31)`) | `calculations_reference_test.dart:…` yeniden yazılan parite testi |
| 3 | TDEE negatif | ✅ **ZATEN kırpıyor** (`bmr <= minBmr → 0`); **web** Flutter'dan kopyaladı | `tdee(-500, …) == 0` |
| 4 | Makro negatif gram | ✅ **ZATEN korumalı** (`targetCalories <= 0 → (0,0,0)`) | `macros(-500)` |
| 5 | `age` üst sınırı | ✅ **ZATEN uygulanıyor** (`years > maxAge → 120`) | `age(1800) == 120` |
| 6 | Su hedefi `NaN` | ✅ **ZATEN 0 yazıyor** (web `NaN` yazıyordu) | `waterTargetMl(NaN) == 0` |
| 7 | ⭐ `progress` koruması **3 katman vardı, HİÇ çağrılmıyordu** | ⭐ **Aynı sınıf Flutter'da da**: `Calculations.progress` üç katman savunma taşıyor, `lib/`'de **0 çağıran**. 3 widget kendi kopyasını yazıyor: `calorie_ring.dart:27`, `macro_cards.dart:101`, `water_tracker.dart:89` (`target > 0 ? (x/target).clamp(0,1) : 0`) | `grep -rn "Calculations\.progress" lib/` → **0 sonuç** |
| 8 | per-100g kopya/ayrışma | ⚠️ **Daraltıldı, kapanmadı**: `FoodRepository.customItem` güvenli (NaN/Infinity → 100g varsayılanı), ama `edit_meal_entry_dialog.dart:66` `_per100` **ayrı bir kopya** (`amount <= 0 → 0`). `features/` alanı → **AKTARIM** | `customItem` testleri · `edit_meal_entry_dialog.dart:66` |
| 9 | AI yanıtı bozuksa `NaN` | ✅ **ZATEN korumalı**: `goalsFromAiBody` eksik/NaN/Infinity alanda `null` döner, yerel formüle düşer | `bmi_and_parity_a2r9_test.dart` 4 test |
| 10 | — | ➕ **Yeni bulgu (A2r9)**: `MacroCalculator` negatif kilo girdisinde `goalsFromAiBody`'ye `-180` geçiyordu; `waterTargetMl` kurtarıyor (0) ama `Calculations.bmr` **kilo/boy pozitifliğini doğrulamıyor** — `bmr(-70, 180)` = `10*(-70)+…` = negatif hesaplanıp sonra `minBmr`'a kırpılıyor. Etki: `0` (doğru sonuç) ama **tüm makro hedefleri 1200 tabanına düşüyor**. `OnboardingPage` 20-400 aralığı zaten uyguladığı için pratikte erişilemez. | `bmr(-100, …) == minBmr` testi · `onboarding_page.dart:35-36` aralık kontrolü |

## Görev 3 — `weigh_in_frequency_days` savunması

**Bulgu (A1r8, doğrulanmış):** `notifications_dialog.dart:146`
`int.tryParse(_frequency.text.trim()) ?? 7` → metin kutusuna `-5` yazılabilir →
`profiles_weigh_in_frequency_days_range` (1-365) CHECK'i reddeder → **her
`check-reminders` koşusunda** hata.

**Neden `features/` düzeltmesi yetmez:** CHECK'i DB'de doğrulamak yerine
**istemcide hiç göndermemek** gerekir. Aksi halde 5 ayrı ekran `catch (_)`
ile yutup kullanıcıya "Kaydedildi" gösterir ama **hiçbir şey yazılmaz**.

| Alan | Aralık | DB kısıtı (migration `:205-228`) |
|---|---|---|
| `height_cm` | 100-250 | `profiles_height_cm_range` |
| `current_weight_kg` | 20-500 | `profiles_current_weight_kg_range` |
| `target_weight_kg` | 20-500 | `profiles_target_weight_kg_range` |
| `daily_water_target_ml` | 0-10000 | `profiles_daily_water_target_ml_range` |
| `weigh_in_frequency_days` | 1-365 | `profiles_weigh_in_frequency_days_range` |

Tasarım kararları:
- **`clamp` değil, hata** — `clamp` sessiz veri bozulmasıdır ("400 cm" → 250
  kaydedilir, kullanıcı 250 cm görür). Kısıtı öğrenmek iyidir.
- **`null` geçer** — CHECK'ler `IS NULL OR …`; onboarding tamamlanmamış profil normal.
- **Sonlu olmayan sayı reddedilir** — JSON `NaN` → PostgREST 400, `Infinity` →
  Postgres `numeric` ayrıştırma hatası.
- **Mesaj şema sızdırmaz** — kısıt adı (`profiles_…_range`) değil, okunabilir
  aralık (`1-365 gün`).
- **Doğrulama saf** (`validateField` / `validateUpdates`) → ağ olmadan test.

**Etkilenen 5 çağrı yeri (aktarım):** `onboarding_page.dart:180`,
`personal_info_dialog.dart:193`, `goals_dialog.dart:139`,
`weight_card.dart:96`, `notifications_dialog.dart:143`.

## Görev 4 — Yedek/geri yükleme borcu

| Borç | Durum | Kanıt |
|---|---|---|
| `_rollback` DELETE etkisini doğrulamıyor (P3) | ✅ **Kapatıldı** (yukarıda). Test edilebilir miydi? **Evet** — 4 ayrı sahte-DB davranışı (0 satır / tümü / kısmi / 403) taklit edildi. | 8 test + negatif ölçüm |
| `favorite_foods` artık A4r7 tarafından yazılıyor → export/import tutarlı mı? | ✅ **TUTARLI** — commit yok (A4r7 çalışıyor), `git status` ile untracked doğrulandı. `food_repository.dart:43-51` `addFavorite` **gerçek tabloya** yazıyor → `exportData` (`:108-111`) artık **dolu** `favorite_foods` okuyor → `importData` (`:471-509`) onu geri yükleyip **`FoodRepository.favorites()` UI'da gösteriyor**. A2r5'in yazdığı "geri yüklenen favoriler görünmez" sorunu **tabloya geçişle kapandı**. "Türetilmiş" varsayımı artık **yalnız `frequentFoods`** için geçerli (`addFood.recent` bölümü) ve o yol tabloya yazmıyor. | `new_write_paths_a2r9_test.dart` 4. grup (`addFavorite` gövdesi: `user_id`+`food_id` var, `created_at` **yok** → A2r5 hatası tekrarlanmıyor) |
| `exportData` `select()` tüm kolonlar (P3) | ✅ **Kasıtlı ve doğru** — `exportData` (`:90-115`) tüm `select()` kullanıyor: (a) yedek **kendi DB sözleşmesini** taşımalı, (b) `Profile.fromJson` tüm kolonu okuyor. **Yan etki bulunamadı.** Kapatıldı. | Kod okuma + `_loadExistingKeys`'teki dilimli `in` sorguları |
| — | ➕ **Yeni**: `ImportReport.isPartial` **her** yazma hatasında `true` dönüyordu (telafi başarılı olsa bile) → alan adı yanlış anlam taşıyor. Düzeltildi. | `data_transfer_import.dart:255` |

### ⭐ Ölçülen tuzak: `inFilter` ayrıştırma (test altyapısı, P3)

`_rollback`'u doğrulamak için sahte DB yazarken ölçüldü: `Uri.queryParameters`,
`inFilter`'ın **1 / 2 / 3+ elemanlı** üç biçimini **üç farklı** bozuyor:

| Eleman sayısı | URL | `queryParameters['id']` | Sonuç |
|---|---|---|---|
| 3+ | `in.("a","b","c")` | `in.("a","b","c")` | doğru |
| 2 | `in.(a,b)` | `in.a,b` | tırnak atlanır |
| 1 | `in.a` | `a` | **`in.` öneki bile yutulur** |

İlk denemem "1 elemanlı" durumda 2 id'yi yanlış eşleştirdi ve telafi testleri
sahte yeşil verdi. Doğru çözüm: `(` varsa parantezden sonrası, yoksa ham değer +
`in.` öneki temizliği. **Not:** aynı tuzak `backup_round_trip_test.dart`ın
kendi `_filter` yardımcısında da var olabilir — o dosyada 3 elemanlı dilimler
kullanıldığı için sorun görünmüyor.

## Görev 5 — Yeni av (kendi taramam)

| Sev | Bulgu | Etki / karar |
|---|---|---|
| — | `meal_entries` okuyan **3** yolun (`search` / `frequentFoods` / `recents`) hepsi `deleted_at IS NULL` **gönderiyor** | ✅ Temiz — A2r3'ün deseni A4r7'nin yeni yollarına taşınmamış ama gereken yerlerde duruyor |
| — | `favorites()` `deleted_at` **istemiyor** | ✅ **Doğru** — `favorite_foods` tablosunda `deleted_at` kolonu **yok** (`full_setup.sql:185-192`); istenirse `PGRST204` 400 dönerdi. Test bunu kilitliyor |
| — | `fetchDaily` `select()` → `select=*` (tüm kolonlar, `deleted_at` dâhil) | ✅ Doğru — istemci elemesi mümkün. Silinmiş öğün toplama girmiyor (test) |
| — | `addFavorite` gövdesi: `user_id`+`food_id` var, `created_at` **yok**; `on_conflict=user_id,food_id` | ✅ Doğru — A2r5'in iki hatasının ikisi de tekrarlanmamış |
| — | `deleteFood`: gıda silinemezse favorilere **dokunulmuyor** | ✅ Doğru — "favoriler silindi ama gıda silinemedi" yarım sonucu yok |
| — | `customItem`: null/NaN/negatif miktar → 100g varsayılanı; null besin → 0; null isim → "Bilinmeyen" | ✅ Temiz |
| P3 | `edit_meal_entry_dialog.dart:66` `_per100` = `customItem`'ın **kopyası** (farklı varsayılan: 0 vs 100) | **Aktarım** (features) |
| P2 | ⭐ `Calculations.progress` ölü (3 katman savunma, 0 çağıran) | **Aktarım** (features) |
| P3 | ⭐ `ImportReport.isPartial` adı yanlış anlam taşıyordu | ✅ Düzeltildi |

## AKTARIM (başka alana)

### → A4r7 (`lib/features/**`)

**1) ⭐ P2 `weigh_in_frequency_days` aralık denetimi (A1r8'in asıl bulgusu).**
`notifications_dialog.dart:146`:
```dart
'weigh_in_frequency_days': int.tryParse(_frequency.text.trim()) ?? 7,
```
Veri katmanı savunması kuruldu (`ProfileRepository.update` → `ProfileFieldRangeError`),
böylece artık **veri bozulmuyor** — ama kullanıcı "Kaydedilemedi" görüyor ve
**ne yapması gerektiğini bilmiyor**. Arayüz tarafı:
(a) `_validateFrequency` ile 1-365 kontrolü + **mevcut** `settings.errors.*`
çeviri anahtarı, ya da
(b) `Stepper`/`DropdownButtonFormField` (serbest giriş = hata kaynağı).
**Ayrıca:** onboarding'de 20-400 kg, kişisel bilgilerde 100-250 cm aralıkları
**zaten** var (`onboarding_page.dart:32-36`) — aynı deseni buraya da taşı.

**2) ⭐ P2 `Calculations.progress` ölü kod.** `lib/`'de 0 çağıran. Üç widget
kendi kopyasını yazıyor (`calorie_ring.dart:27`, `macro_cards.dart:101`,
`water_tracker.dart:89`). `target > 0 ? (x/target).clamp(0,1) : 0` ifadesinde
`target` **NaN** ise `NaN` üretir (`NaN > 0` false → `0`, ama `x` NaN ise
`clamp` NaN döner). Tek kaynağa bağlamak 3 satır + `core/utils` importu.
A5r8 web'de aynı işi yaptı; **parite** için de yapılmalı.

**3) P3 `_per100` kopyası.** `edit_meal_entry_dialog.dart:66` → veri katmanı
tek kaynağı (`FoodRepository.customItem` ya da yeni `Calculations.per100g`)
kullanmalı. Not: iki yol **farklı varsayılan** kullanıyor (0 vs 100g) —
`features` karar vermeli.

**4) Not (bilgi, iş yok):** `notification_preferences_repository.dart` (A4r7,
untracked) `interval_hours` CHECK'ini `toRow` içinde `clamp` ediyor → A5r8'in
web'de bulduğu `interval_hours: 0` hatasının Flutter karşılığı **yok**.
Doğrulandı (`toRow`:157-170). `clamp` yerine hata tercih edilirdi ama
burada `clamp` savunma-derinliği olarak makul.

### → A1 (`supabase/**`)

1. **P2 `cron.schedule` hâlâ yok** → `check-reminders` tetiklenmiyor (T8'den
   kalan operasyon borcu; dashboard'da kurulmalı).
2. **P2 SQL testleri CI'a bağlı değil** (`supabase.yml` yalnız `deno`).
3. `notification_preferences` artık Flutter tarafından yazılıyor (A4r7) →
   `notification_preferences_hours_range` CHECK'i **ilk kez gerçekten
   sınanabilir** hale geldi. Canlı veri doğrulaması önerilir.

## Yeni testler (test dosyaları `test/**` altında, `/tmp` dışında)

| Dosya | Test | Ne kanıtlıyor |
|---|---|---|
| `test/core/utils/bmi_and_parity_a2r9_test.dart` | 24 | `bmi` kilo alt sınırı (negatif/0/NaN/Inf/1e300/boy≈0) · 10 kalemlik web parite tablosu · `progress` üç katman · `MacroCalculator` AI gövdesi (4) + uçtan uca yerel fallback (4) |
| `test/data/repositories/profile_field_range_test.dart` | 19 | 5 CHECK aralığı · `null` geçerli · NaN/Inf/dize reddi · `update()` reddedilen alanda **0 istek** |
| `test/data/repositories/rollback_effect_test.dart` | 8 | 4 sahte-DB DELETE davranışı · kısmi silmede yalnız kalanlar · dilimleme (250→3 istek) |
| `test/data/repositories/new_write_paths_a2r9_test.dart` | 19 | A4r7 favori yollarının sözleşmesi · soft-delete envanteri · `customItem` null güvenliği · `fetchDaily` kenar durumları |
| `test/data/repositories/import_atomicity_test.dart` (düzeltme) | — | Sahte DB artık `DELETE` + `select=id` gövdesini döndürüyor |
| `test/data/repositories/backup_round_trip_test.dart` (düzeltme) | — | Aynı |

**Test sayısı: 784 → 910** (yeni 70, `flutter test` çıktısı `+910`).
**Alan bazlı:** `test/data` + `test/core` = **775/775 geçiyor**.

## Doğrulama

| Komut | Sonuç |
|---|---|
| `cd flutter_app && flutter analyze lib test/data test/core` | ✅ **No issues found!** |
| `cd flutter_app && flutter analyze` (tümü) | ⚠️ **4 hata — A4r7 alanında**: `test/features/shared/favorite_button_a4r7_test.dart:425/438` `SemanticsFlags.checked` / `CheckedState` **bu Flutter sürümünde tanımsız**. Benim alanım değil, dokunmadım. |
| `cd flutter_app && flutter test test/data test/core` | ✅ **775/775** |
| `cd flutter_app && flutter test` (tümü) | ⚠️ **910 geçti, 1 yükleme hatası** (yukarıdaki A4r7 derleme hatası — test koşmadı, sadece derlenmedi) |
| `node tool/check_versions.cjs` | ✅ **Tamamen yeşil** — "BMI ağırlık alt sınırı iki tarafta farklı" uyarısı **düştü** |
| `node tool/check_i18n.cjs` | ✅ Yeşil (çeviri dosyasına dokunulmadı) |

**Negatif ölçümler (3, hepsi ölçüldü ve geri kondu):**
1. `bmi` `weightKg <= 0` kontrolü geri alınınca → 1 test kırmızı.
2. `ProfileRepository.update`'te `validateUpdates` kaldırılınca → 2 test kırmızı.
3. `_rollback`'ta `.select('id')` kaldırılınca → 4 test kırmızı.

## Kalan riskler

1. **P0/P1 yok.** Düzeltilenlerin hepsi testle kilitli.
2. **A4r7 derleme hatası** `flutter analyze`/`test`'i kırmızı bırakıyor —
   Tur 9 çıktısı "tamamen yeşil" olamaz; A4r7'nin dosyası.
3. **`Calculations.bmr` kilo/boy pozitifliğini doğrulamıyor.** Negatif girdi
   `minBmr`'a kırpılıyor → tüm hedefler 1200 tabanına düşüyor (fiziksel
   olarak anlamsız ama **çökmez**). `MacroCalculator` girdileri kırpmıyor
   (A2r9 düzeltmesi sonrası) — kaynak `Calculations` tek doğruluk yeri
   olarak bırakıldı. Web'de de aynı. Ürün kararı: `bmr` de pozitiflik kontrolü
   eklenip eklenmeyecek (düşük öncelik, erişilemez yol).
4. **`ImportReport.isPartial` değişikliği** arayüzde kullanılmıyor
   (`grep` → yalnız test) → geri dönüş riski yok.
5. **`_rollback` artık `DELETE` + `RETURNING`** → telafi başarısız olduğunda
   `rolledBack` **daha sık** `false` olacak (doğru davranış, ama rapor metni
   "geri alınamadı" daha fazla görünecek). Üretimde RLS sıkı olduğu için
   beklenen değişim yok.
6. **A4r7'nin `favorite_foods` geçişi henüz commit'li değil** → tutarlılık
   kontrolü `git status` (untracked) üzerinden yapıldı, commit üzerinden
   doğrulanamadı. A4r7 commit'leyince bu bölüm yeniden bakılmalı.
