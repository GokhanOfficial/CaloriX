# RAPOR — A2r11-data — 2026-09-28 — Tur 11

## Özet (5 madde)

1. **P1 asılı (A4r10 aktarımı) kapatıldı.** `FoodItem.canDelete` eklendi;
   `search()`/`favorites()`/`recents()`/`frequentFoods()` `created_by`'i seçiyor.
   Seed gıdaya (`created_by IS NULL`) artık silme düğmesi çizilmiyor → kullanıcı
   RLS reddi + hata toast'ı yaşamıyor.
2. **Karar RLS'in kendisi:** `canDelete == (created_by == auth.uid())`.
   Postgres 16.15'te ölçüldü: kendi gıda → `DELETE 1 satır`; seed → `0 satır`;
   başkasınınkisi → `0 satır`. **`source` karara girmiyor** (gerekçe aşağıda).
3. **Sorgu maliyeti ölçüldü: `%0.00`.** 50.000 satır, 200 tekrar, medyan fark
   **0.0000 ms**. Plan değişmedi (`Index Scan using idx_foods_popularity` aynı).
   Yeni index/migration **gerekmiyor**.
4. **⭐ Yeni P0 bulundu (raporlandı, düzeltilmedi — kapsam dışı):** kullanıcı
   kendi gıdasını sildiğinde `meal_entries.food_id` `ON DELETE SET NULL`
   oluyor, `custom_name` de `NULL` → **dashboard'da "Bilinmeyen"** görünüyor.
5. **1044 → 1067 test**, hepsi geçti (+23). Negatif ölçüm 2 ayrı düzeltmede
   yapıldı: `search()`'te kolon geri alınınca **kırmızı**, `canDelete` hesabı
   sabitlenince **3 kırmızı**.

## Düzeltilenler

| Sev | Dosya | Ne yapıldı | Doğrulama |
|---|---|---|---|
| **P1** | `lib/data/models/food_item.dart` | `canDelete` alanı eklendi, varsayılan **`false`** (fail-closed). Gerekçe dokümanı: RLS ile birebir aynı koşul, `foodId != null` yetki **değildir** | `food_delete_permission_a2r11_test.dart` grup 4 (3 test) |
| **P1** | `lib/data/repositories/food_repository.dart:206` `search()` | `select()` listesine `created_by`; `canDelete: _ownerOf(row) == userId` | 6 test (kendi/seed/baska/karışık/`source` yok/ayrım) |
| **P1** | `food_repository.dart:149` `favorites()` | Join içinden `created_by` → `_favoriteToItem(row, userId)` | 1 test |
| **P1** | `food_repository.dart:340` `frequentFoods()` | Join içinden `created_by` → `_rowToItem(..., userId:)` | 1 test |
| **P1** | `food_repository.dart:378` `recents()` | Join içinden `created_by` → `_rowToItem(..., userId:)` | 1 test |
| **P2** | `food_repository.dart:217` | `_ownerOf` yardımcısı + sınıf dokümanında ölçüm/bağlamama gerekçesi | — |
| **P2** | `food_repository.dart:236` | `deleteFood` dokümanındaki **yanlış satır referansı** düzeltildi (`full_setup.sql:287` → `:424`; ayrıca satır 133'teki "gıda silme yolu fiziksel silmedir ve istemci süzgeci gerekmez" yorumu `deleteFood`'in varlığıyla çelişiyordu, dokümana sadık kılındı) | — |
| — | `test/data/repositories/food_delete_permission_a2r11_test.dart` | 23 yeni test | `+23` |

## `canDelete` kararı — gerekçe

### Ölçüm (Postgres 16.15 Alpine, `docker run postgres:16-alpine`, 50.000 `foods`)

`tool/a2r11_consistency.sql` (ölçüm scripti `tool/` = A6 alanı olduğu için
`/tmp/opencode/a2r11_tool/` altında çalıştırıldı, **commit edilmedi**):

| `foods.created_by` | `DELETE … WHERE created_by = <auth.uid()>` | Sonuç | `canDelete` |
|---|---|---|---|
| `= auth.uid()` | **1 satır** | silinir | **`true`** |
| `IS NULL` (seed/topluluk) | **0 satır**, satır duruyor | reddedilir | **`false`** |
| başka kullanıcı | **0 satır** | reddedilir | **`false`** |

RLS politikası: `full_setup.sql:424` → `USING (created_by = auth.uid())`.

### Neden `source` **değil**

Görev metni "`created_by` ve `source` kolonlarını seçmiyor" diyordu.
`source` **seçilmedi** ve gerekçeyle:

- `foods.source` = `food_source` enum (`photo`/`text`/`manual`,
  `full_setup.sql:63`). Bu **kayıt kökenidir, yetki değildir.**
- Seed (import edilmiş topluluk) gıdaları da `manual` olabilir → `source`
  "seed" ayrımı yapamaz.
- Kullanıcının **kendi** eklediği gıda `photo`/`text` da olabilir (AI tanıma
  akışı) → `source != manual` filtresi **kullanıcının kendi gıdasını** da
  gizlerdi.
- İki kriter birlikte uygulansaydı aynı gıda iki yerde **farklı** karar görür
  ve düğme "cansız" görünürdü.

Tek doğruluk kaynağı RLS'in kendi koşulu olmalı; istemci onu **aynalar**.

### Neden varsayılan `false` (fail-closed)

`canDelete` kanıtlanmadan `true` ilan edilmez. `recognized_food.toItem()`
(`models/recognized_food.dart:71`) ve elle kurulan `FoodItem`'larda alan `false`
kalır → düğme gizli. Kullanıcı "neden silemiyorum" **toast'ı** yerine düğmeyi
hiç görmez. `deleteFood` yine de `false` dönebilir (yarış: gıda başka cihazda
silinmiş olabilir) ve o durum arayüzde zaten ayrı mesajla karşılanır.

## ⭐ AKTARIM 1 — A4r10'ya (features): düğme nerede gizlenmeli

**Tek satır.** `shared/widgets/delete_food_button.dart:174` `build()`:

```dart
@override
Widget build(BuildContext context) {
  final foodId = widget.food.foodId;
  if (foodId == null) return const SizedBox.shrink();   // mevcut: custom
+ if (!widget.food.canDelete) return const SizedBox.shrink();  // ⭐ EKLE
  ...
}
```

Gerekçe: `canDelete` veri katmanında **kanıtlanmış** tek ölçüt. A4r10'ın
`add_page.dart:286`'daki yorumu ("başkasının gıdasında düğme görünür ama
`deleteFood` `false` döner ve kullanıcıya bunun nedeni söylenir") artık
**geçersiz** — düğme hiç görünmemeli.

**Arayüz değişikliği gerekmez:** `_FoodTile` her iki durumda da aynı satırı
çiziyor, `canDelete` yalnızca düğmenin görünürlüğünü etkiliyor. `add_page.dart`'in
4 bölümü (`recents` / `frequent` / `favorites` / arama sonuçları) **otomatik**
düzeltilir — hepsi aynı `_FoodTile`/`DeleteFoodButton` kullanıyor.

**A4r10'ın testine eklenmesi gereken (yeni olgu değil, mevcut test kırılır):**
`test/features/settings/notification_range_and_food_delete_a4r10_test.dart:511`
"custom girdide (foodId null) düğme GİZLENİR" ve satır 528'deki tooltip testi
`canDelete: false` içermeyen `FoodItem` kuruyor → **tooltip testi kırmızıya
döner** (`foodId: 'f1'` ama `canDelete` varsayılan `false`). O testlere
`canDelete: true` eklenmeli. Bu **bilinçli** bir davranış değişikliğidir,
tesadüfi kırılma değil.

## ⭐ AKTARIM 2 — A4r10'ya: ⭐ YENİ **P0** — silinen gıda dashboard'da "Bilinmeyen" oluyor

Bu bulgu A4r10'ın **ekran tarafının** konusudur, `add_page.dart`'ya
dokunmadığım için aktarıyorum.

### Ölçüm (Postgres 16.15, `tool/a2r11_consistency.sql`)

| Adım | Ölçülen |
|---|---|
| Kullanıcı gıda oluşturur → `popularity_count` | `0` (trigger yalnız `meal_entries` INSERT'inde) |
| Öğün ekler (`add_from_food_dialog.dart:87-98`: `foodId` dolu, `customName` **null**) | `food_id = <id>`, `custom_name = NULL` |
| Kullanıcı gıdayı **siler** (`deleteFood`) | `foods` **SILINDI**, `food_nutrition` **SILINDI** (CASCADE) |
| Aynı öğün satırı | **KORUNDU** ✅ |
| `meal_entries.food_id` | `NULL` (`ON DELETE SET NULL`) |
| `meal_entries.custom_name` | **`NULL`** |
| `MealEntry.displayName` (`meal_entry.dart:89`) | **`"Bilinmeyen"`** |

### Etki

Kullanıcı gıdayı siler → **dashboard'daki geçmiş öğün satırı "Bilinmeyen"a
dönüşür.** `meal_section.dart:157` → `Text(entry.displayName)`. Öğün **kayıp
değil** (kcal/makro/miktar duruyor, `DashboardRepository.fetchDaily` 3 sorguda
`.eq('user_id')` taşıyor — **BOLA yok**), ama kullanıcı günlüğünde yemek
**adları geri döndürülemez**. "Yemek sil" özelliğinin fiyatı: geçmiş kayıtlar
anonimleşiyor. Dahası: kullanıcı farkında değil silmeye devam eder, sonra
"neden geçmişimde 'Bilinmeyen' var?" diye sorar.

### Öneri (karar: `features` + kısmen `supabase`)

1. **`lib/features/add/widgets/add_from_food_dialog.dart:90`** — `customName`
   koşulu tersine çevrilebilir:
   ```dart
   customName: widget.food.isCustom || widget.food.canDelete
       ? widget.food.name   // kendi gıdası → ad öğünde de tutulsun
       : null,
   ```
   Bu tek satır, `food_id` **NULL** olduğu durumda (`displayName` fallback'i
   çalışsın) ve `food_id` **dolduğu** durumda (`displayName` zaten `foods.name`
   join'inden geliyor) **çift koruma** sağlar. **Sadece kendi gıdaları için**
   (`canDelete == true`) — başkasının/seed gıdasını kopyalamak `recents`
   listesine sahte "custom" kayıt sokar.
2. **Ya da `MealEntry.displayName` (`lib/data/models/meal_entry.dart:89`)** —
   `displayName` sorguya `foods(name)` join'i ekleyip `custom_name ??
   foods.name ?? 'Bilinmeyen'` yapılabilir. Bu **daha genel** ama her gün
   sorgusuna join ekler (ölçüm gerekli).
3. **En temiz (supabase, A1 alanı):** `meal_entries` üzerinde
   `ON DELETE SET NULL` yerine **`ON DELETE SET DEFAULT`** kullanılamaz
   (`foods` satırı zaten siliniyor). Alternatif: silmeden **önce**
   `custom_name`'i gıdanın adıyla doldurmak (trigger veya repository).
   **A1 değerlendirmesi gerekir.**

**A2r11'in önerisi: (1)** — en küçük, en düşük riskli, ölçümü bitti
(`displayName` zaten `custom_name`'i okuyor, ek sorgu yok). **Doğrulanacak
nokta:** `DiaryRepository.addMealEntry`'de `customName` + `foodId` **aynı anda**
dolu olması şema için yasak mı? `meal_entries` CHECK'leri
(`20260928400000_data_integrity_check_constraints.sql`) yalnızca `calculated_*`
aralıklarını kontrol ediyor — `custom_name` üzerinde kısıt **yok**, ölümsüz
veri gerekmiyor. **Ölçülmedi** (canlı veri doğrulaması gerekiyor) → A1'e not.

## Yeni avlanan hatalar

| Sev | Konu | Tespit | Durum |
|---|---|---|---|
| **P0 ⭐** | Silinen gıda → `meal_entries` satırı `custom_name = NULL` + `food_id = NULL` → dashboard'da **"Bilinmeyen"** | Yukarıda ölçüldü | **AKTARIM 2** (A4r10 + A1) |
| — | `recent_foods` tablosu Flutter'da **hiç yazılmıyor** | `grep -rn "recent_foods" lib/` → yalnız `data_transfer_repository.dart` okuma/yazma (import/export). `addMealEntry` **yazmıyor** → `recents()` türetilmiş `meal_entries`'ten okuduğu için bugün zararsız | Bilgi (düzeltme yok) |
| — | `popularity_count` silme sonrası | Tutmuyor **diye bir şey yok**: sayaç `foods` satırıyla birlikte **fiziksel siliniyor**. Trigger `AFTER INSERT` (`full_setup.sql:744`) — `meal_entries` UPDATE/DELETE tetiklemez. `food_id` NULL'a düşse bile `increment_food_popularity` bir daha çalışmaz | Tutarlı |
| — | `recent_foods.use_count` silme sonrası | `foods` FK'si `ON DELETE CASCADE` → satır yok, sayaç da yok. Flutter yazmadığı için zaten artmıyor | Tutarlı |
| — | `favorite_foods` silme sonrası | CASCADE siler + `deleteFood` ayrıca `removeFavoritesForFood` ile idempotent temizlik yapar. Gerekçeli (yarış durumu + ölü `food_id` yazan yedek) | Tutarlı |
| — | BOLA taraması — `lib/data/**` | `user_id`/`created_by` **eşitlik filtresi olmayan tek okuma yolu** yok. `favorites()` `user_id=eq` taşıyor; `recents()`/`frequentFoods()` `meal_entries.user_id=eq`; `search()`'in `foods` sorgusu `SELECT ... USING (true)` — **kullanıcı kavramı yok** (herkes her gıdayı arayabilir, kasıtlı). `data_transfer_repository.dart:107` `created_by=eq` taşıyor | **Temiz** |
| — | `catch (_)` yutma taraması — `lib/data/**` | 3 nokta: `analytics_repository.dart:286` (`_safeDateLabel`, tarih parse edilemezse ham dize döner — **kullanıcı verisi kaybı yok**, kasıtlı), `recognition_repository.dart` (`FunctionException`'ı `RecognitionException`'a çevirir, kaybolmaz), `add_from_food_dialog.dart:123` + `add_manual_entry_dialog.dart:102` (**features alanı**, `catch (_)` toast gösteriyor ama **loglamıyor** — A4r10'un P2 notu). `diary_repository.dart:210` `AppLog.w` ile logluyor | Temiz (`lib/data/**`'de sessiz yutma yok) |

## Sorgu maliyeti — ölçüm

**Kurulum:** `docker run postgres:16-alpine` → **16.15**, `foods` 50.000 satır
(49.000 seed / 1.000 kullanıcı), `food_nutrition` 50.000, `meal_entries` 200.000.
Şema `full_setup.sql:151-322` + `20260927120000`'den birebir kopyalandı
(`foods_created_by_rls`, `idx_foods_popularity`, `foods_name_brand_unique` dahil).

**Sorgu:** `search()`'in PostgREST karşılığı —
`WHERE name ILIKE '%Gida 1%' ORDER BY popularity_count DESC LIMIT 10`
(join `food_nutrition` dahil).

### Plan karşılaştırması — **DEĞİŞMEDİ**

```
A) created_by YOK               B) created_by VAR
Limit                            Limit
  -> Index Scan using              -> Index Scan using
     idx_foods_popularity             idx_foods_popularity
     Filter: (name ~~* ...)           Filter: (name ~~* ...)
       Rows Removed: 8                Rows Removed: 8
```

Ek kolon **indekse takılmıyor** — `foods` zaten `idx_foods_popularity` ile
taranıyor, `created_by` yalnızca heap okuması (16 bayt uuid).

### 200 tekrarlı süre ölçümü (ısınma 30 tekrar ayrı)

| | min | medyan | ortalama |
|---|---|---|---|
| A) `created_by` **yok** | 0.0460 ms | 0.0470 ms | 0.0537 ms |
| B) `created_by` **var** | 0.0460 ms | 0.0470 ms | 0.0497 ms |
| **fark** | **0.0000 ms (%0.00)** | **0.0000 ms (%0.00)** | −7.5% (gürültü) |

**Sonuç: maliyet farkı sıfır. Yeni index gerekmiyor, migration önerilmiyor.**

⭐ **Metodoloji notu (A4r7b/A4r10 dersi):** ilk ölçümde "A = 0.317 ms,
B = 0.069 ms → %78 **hızlanma**" çıktı. Bu **yanlıştı** — ısınma (JIT plan
önbelleği + buffer) ilk denemeleri çarpıyordu. `PERFORM` iki varyantı
**dönüşümlü** çalıştırdığında ilk çalışan yavaş, ikinci hızlı ölçülür. Isınma
ekleyip min/medyan alınca fark **tam olarak sıfır** çıktı. *İlk ölçüme güvenme.*

## Yeni testler (23 → 1044'ten 1067'ye)

`test/data/repositories/food_delete_permission_a2r11_test.dart`

| Grup | Test | Ölçtüğü |
|---|---|---|
| 1) Kolon envanteri (6) | `search`/`favorites`/`recents`/`frequentFoods` `created_by` **istiyor** | Aktarımın kapattığı boşluğun regresyonu |
| | ⭐ `source` **istenmiyor** + `source` **olmadan** da doğru karar | Kararın `source`'a bağımlı olmadığı |
| 2) `search()` üç durum (6) | kendi → `true` · **seed → `false`** · başkası → `false` | Asıl P1 senaryosu |
| | ⭐ `canDelete == false` iken `foodId` **dolu** | A4r10 tuzağının net ayrımı |
| | karışık sonuç → `[true, false, false]` | Satır bazlı doğru karar |
| 3) Diğer 3 yol (5) | `favorites`/`recents`/`frequentFoods` aynı kural | 4 bölümün hepsi |
| | custom girdi → `false` · `deleted_at` kararı **etkilemez** | İki savunma katmanı bağımsız |
| 4) Fail-closed (3) | varsayılan `false`; `foodId` dolu olsa bile `false` | Kanıtsız yetki asla `true` olmaz |
| 5) `deleteFood` (3) | `true` → silinir · seed → `false` · DELETE `created_by=eq` taşır | Arayüzün gördüğü ile repository'nin yaptığı **aynı kural** |

## ⭐ Negatif test ölçümü (2 düzeltme, ikisi de kırmızı görüldü)

**N-1 — `search()`'ten `created_by` kolonu geri alındı:**
```
Expected: contains 'created_by'
  Actual: 'id,name,brand,serving_size_g,food_nutrition(kcal,protein_g,carbs_g,fat_g)'
   Which: does not contain 'created_by'
→ Some tests failed.  (23 → 22, 1 kırmızı)
```
Teşhis **hatanın yerini** veriyor (kolon eksik), "test kırmızı" değil.

**N-2 — `canDelete` hesabı sabit `false` yapıldı** (kolon duruyor, hesap yok):
```
00:00 +18 -3: ... kırmızı ×3
→ Some tests failed.
```
Çünkü "kolon geliyor **ama** kullanılmıyor" tuzağını da yakalıyor — yani test
sadece kolon varlığını değil **kararın doğru türetildiğini** ölçüyor.

İkisi de `git`-ten geri kondu, `1067 test tekrar yeşil` doğrulandı.

## Doğrulama

```
$ cd flutter_app && flutter analyze
No issues found! (ran in 5.6s)

$ cd flutter_app && flutter test
00:40 +1067: All tests passed!      (taban: 1044 → +23)

$ node tool/check_versions.cjs
✓ Sürüm tutarlı: 1.3.0+4 (pubspec = AppConstants = CHANGELOG = README)
  · web 1.1.0 (package.json = APP_VERSION) · varsayılan hedefler ve
    makro oranları iki istemcide aynı.

$ git diff --name-only | grep -E "features/|shared/|core/|supabase/|src/|assets/"
TEMIZ: başka alanlara dokunulmadı
```

## Commit

`3438424` — `fix(data): silme yetkisi canDelete ile belirlenir — seed gida artik silinemez gorunmuyor (Tur 11, A2r11)`

```
 flutter_app/lib/data/models/food_item.dart                          |  34 ++
 flutter_app/lib/data/repositories/food_repository.dart             | 106 ++++++-
 flutter_app/test/data/repositories/food_delete_permission_a2r11_test.dart | 485 +++++
 3 files changed, 616 insertions(+), 9 deletions(-)
```

## Kalan riskler

1. **⭐ P0 açık (AKTARIM 2):** gıda silme → geçmiş öğünler "Bilinmeyen". Bu
   turda **düzeltilmedi** (features/supabase alanı). A4r10 kararı bekliyor.
2. **A4r10'ın mevcut testi kırılacak** (bilinçli): `foodId: 'f1'` ama
   `canDelete` varsayılan `false` kuran tooltip testi kırmızıya döner. O
   testlere `canDelete: true` eklenmeli — yoksa `flutter test` kırmızı.
   ⭐ Bu, A4r10'ya **işaret edilmesi gereken** bir sonuçtur (bilinçli kırılma,
   tesadüfi değil).
3. **`foods` INSERT yolu yok.** `grep`'te `foods` yazan tek yer
   `data_transfer_repository.dart:701` (yedek içe aktarımı). Yani "kendi
   eklediği gıda" **normalde hiç oluşmuyor** — kullanıcı gıda kaydı yaratmıyor,
   `meal_entries` custom girişi yapıyor. Bu yüzden `canDelete == true` olan
   satır bugün pratikte **nadir**. Doğru davranış (düğme gizli) ama özelliğin
   görünürlüğü düşük. Ürün kararı: "kendi gıdam" oluşturma girişi isteniyorsa
   ayrı tur.
4. **`search()` `ilike` indeks kullanmıyor** (planda `Filter: name ~~* ...`).
   50.000 satırda 0.047 ms, sorun yok; ama 1M+ gıda tabanında `pg_trgm`
   gerekebilir. **Şimdi gerekmiyor** — kanıtsız index = index şişmesi
   (A1r5'in kuralı).
5. **Ölçüm ortamı shim şema.** `auth.users` yerine `users` tablosu ve
   `gen_random_uuid()` kullanıldı (tam `auth` şeması yok). RLS politikaları
   `created_by = <uuid>` filtresiyle **taklit edildi** — gerçek RLS motoru
   çalışmadı. Yine de `created_by` indeksli/indekssiz ayrımı, satır sayısı ve
   `DELETE` davranışı gerçekçi. **Supabase projesi frozen olduğu için**
   canlı ölçüm yapılamadı; A1 canlı doğrulama yaparsa bu ölçüm teyit edilebilir.
6. **`/tmp/opencode/a2r11_tool/` ölçüm scriptleri commit edilmedi** (`tool/` =
   A6 alanı). Kalıcı olmaları istenirse A6'ya aktar.
7. **`canDelete` yarış durumu.** Silme anında gıda başka cihazda silinirse
   `canDelete` bayat kalır, `deleteFood` `false` döner → mevcut hata mesajı
   çıkar. Doğru davranış; yalnızca "düğme var ama silinmiyor" bir an olabilir.
