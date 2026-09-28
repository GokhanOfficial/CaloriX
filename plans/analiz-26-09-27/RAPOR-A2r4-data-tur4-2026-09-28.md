# RAPOR — A2r4-data (veri katmanı) — 2026-09-28 — Tur 4

**Kapsam:** `flutter_app/lib/data/**` (7 dosya) + `flutter_app/test/data/**` (4 yeni).
`supabase/**` **yalnızca okundu** (şema/CHECK/enum/kanıt). `lib/core/**`,
`lib/features/**`, `src/**`, `assets/translations/**` **dokunulmadı**.

**Commit'ler:**

| Hash | Stat |
|---|---|
| `7f7cde0` — `fix(data)` yedek içe aktarma atomikliği | 3 dosya, **+2554 / −322** |
| `befb5d9` — `fix(data)` activityLevel enum + eşzamanlılık + food süzgeci | 7 dosya, **+1061 / −105** |

**Doğrulama:** `flutter analyze` → **No issues found!** ·
`flutter test` → **597/597** (Tur 3'te 517) · `node tool/check_versions.cjs` → ✓

---

## Özet (5 madde)

1. **P0/P1 — `importData` kısmi import artık mümkün değil.** Üç fazlı akış:
   *önce doğrula (ağ yok) → varlık kontrolü (yalnız GET) → toplu + telafili
   yazma*. Tek bir ölümcül ihlalde **hiçbir istek atılmaz**; yazma hatasında o
   turda yazılan satırlar `id` ile **fiziksel olarak silinir** ve `counts`
   her zaman dolu bir `ImportReport` ile döner. Ölçüm: istek **4506 → 37**.
2. **P1 — Ölümcül olmayan "güvenli" dönüştürmeler aslında ölümcüldü.**
   `amount_ml`/`weight_kg` geçersizde `0` yazılıyordu; DB CHECK
   (`full_setup.sql:618/620`) 400 döndürüyordu ve **tüm import**, öğünler ve su
   kayıtları yazıldıktan sonra düşüyordu. Besin satırında sayı olmayan zorunlu
   alan `0`'a çevriliyordu — **sessiz yanlış besin değeri**. Artık ikisi de
   ön-uçu ölümcül ihlali.
3. **P1 — 2000 istek sorunu ölçüldü ve çözüldü.** Satır satır yazım yerine
   `importBatchSize = 500` toplu `insert`. Postgres parametre tavanı 65535;
   en geniş tablo `meal_entries` (14 kolon) → 500×14 = 7000 (%11). Toplu
   `POST` **tek SQL deyimi** olduğu için dilim ya tamamen yazılır ya hiç.
4. **P1 — `Profile.activityLevel` artık `ActivityLevel?`.** `json_serializable`
   bu alanda **kullanılamıyor** (`as ActivityLevel?` derlenmez, tanımsız DB
   değerinde istisna fırlatır) → `fromJson`/`toJson` elle yazıldı,
   `profile.g.dart` silindi. `rawActivityLevel` ham değeri korur.
5. **P1 — Kayıp güncelleme (race) kapatıldı.** `updateMealEntry` artık
   `expectedUpdatedAt` ile **iyimser kilit** uygular; çakışma
   `MealEntryConflictError` (yeni sınıf) ile ayrışır, "bulunamadı" ile
   "çakıştı" karışmaz. `food_repository`'nin 3 okuma yoluna da
   `deleted_at` istemci süzgeci eklendi.

---

## 1) Kısmi import: A/B kararı

### A seçeneği — `import_data(jsonb)` Postgres RPC'si

| | |
|---|---|
| Atomiklik | **Mükemmel** — tek transaction |
| İstemci değişikliği | Sıfır (aynı imza) |
| `foods` → `food_nutrition` id eşlemesi | Postgres `RETURNING` ile doğru |
| Gereken iş | Yeni migration + `GRANT EXECUTE` + RLS politikası + istemci dışı **iki istemcinin** (web/React `useDataExport.ts`, Flutter) aynı RPC'ye geçmesi |
| Ölçülebilir risk | RPC gövdesi ~200 satır PL/pgSQL; **canlı Postgres'te test edilemiyor** (ortamda docker yok, `PROTOKOL §11`), yani 2 ajanlık tur + migration + RLS denetimi + iki istemci değişikliği |

### B seçeneği — istemcide "önce doğrula, sonra yaz" + telafi — **SEÇİLDİ**

| | |
|---|---|
| Atomiklik | **Yok** (PostgREST transaction vermiyor) — ama kısmi import **görünür ve geri alınır** |
| Gereken iş | `lib/data/**` içinde, migration yok → **proje kurulmadan da çalışır** |
| Doğrulama maliyeti | 42 test, `MockClient` + **gerçek PostgREST URL'leri** (`?select=…&id=eq.m1&updated_at=eq.…`) |
| Kalan risk | Telafi de başarısız olursa kayıtlar kalır → `rolledBack = false` + **kalan satır id'leri** raporda; tekrar denemek dedup sayesinde güvenli |

### Gerekçe

1. **"Görünmez kısmi veri" P0'u B ile tamamen kapanıyor.** Geriye kalan tek
   risk "yazılan kayıtlar durdu" ve bu **sayılarak** raporlanıyor
   (`report.counts`, `report.writtenTables`).
2. **B, migration gerektirmiyor.** A'nın tek avantajı (atomiklik) ancak
   migration + RLS + iki istemci değişikliği + **canlı test edilemeyen**
   PL/pgSQL demek. Protokolde yazıcı (bende) bu ortamda Postgres çalıştıramıyor;
   A1r3 geçen turda edge function'ları "gerçek Postgres'te uçtan uca
   doğruladı" demişti ama o ajanın ortamı farklıydı — **benim ölçümüm
   doğrulanabilir değil**, "rapora göre doğrulandı" demek zorundayım.
3. **B ölçek avantajını da getiriyor** (4506 → 37 istek). A yalnız atomiklik
   sağlardı, istek sayısı aynı kalırdı.
4. **B A'yı kapatmıyor:** RPC sonradan eklenirse `buildImportPlan` saf bir
   fonksiyon olarak kalır; doğrulama katmanı RPC'ye taşınır. Aktarım yazıldı.

### A'nın raporlanması → A1r4 (migration/RPC)

Bknz. AKTARIM bölümü.

---

## 2) Hata sınıfları ve `features/` aktarımı (A4r4)

`lib/data/repositories/data_transfer_import.dart` (yeni, 312 satır) — hata
sınıfları repository gövdesinden **ayrı** ki arayüz katmanı sözleşmeyi
bağımsız okuyabilsin.

| Sınıf | Ne zaman | Arayüzün yapması gereken |
|---|---|---|
| `ImportFormatError` (`: FormatException` **alt sınıfı**) | Dosya CaloriX yedeği değil | **Hiçbir şey.** Mevcut `on FormatException` kolu zaten doğru mesajı gösteriyor (`settings.import.fileNote`) |
| `ImportValidationError` | Yedek DB sözleşmesine uymuyor | `e.summary` göster + **"hiçbir şey yazılmadı"** bilgisini ver. `e.issues` (tablo, satır id'si, alan, neden), `e.totalIssues` |
| `ImportWriteError` | Yazma sırasında hata | `e.report.counts` (**her zaman dolu**), `e.report.failedStage`, `e.report.rolledBack`. `e.summary` kullanıcı metnidir — `e.cause`'ı gösterme (PostgREST mesajı tablo/kısıt adı sızdırır, `full_setup.sql:618` gibi) |
| `ImportReport` (başarı) | `importBackup` normal döndü | `counts`, `skipped`, `coerced` (sessiz düzeltmeler) |

**`features/` tarafı — dokunmadım, üç değişiklik gerekiyor:**

1. `transfer_dialogs.dart:80-101` — `catch (_)` yerine:
   ```dart
   } on ImportFormatException {          // zaten çalışıyor, ayrı kola gerek yok
   } on ImportValidationError catch (e) {
     // settings.import.invalidBackup  (yeni çeviri, 12 dil)  ← e.summary
   } on ImportWriteError catch (e) {
     // settings.import.partialImport  (yeni çeviri, 12 dil)  ← e.report
   }
   ```
   Veya `importBackup`'ı kullanıp `report`'u gösterin (önerilen: `coerced`
   bilgisi kullanıcıya "6 öğünde tarih düzeltildi" der, ekran `ImportReport`u
   okumaya hazır).
2. `recognition_confirm_dialog.dart:543-551` — `r.amount <= 0` dalı
   `dialogs.amountRequired` → **`dialogs.invalidAmount`**. 0 çeviri işi
   (12 dilde var). Ek olarak `DiaryRepository.isUsableAmount(r.amount)`
   kullanın: "ne zaman kaydedilebilir" artık tek kaynaktan geliyor.
3. `edit_meal_entry_dialog.dart:132` — `updateMealEntry`'ye
   `expectedUpdatedAt: widget.entry.updatedAt` geçirip
   `on MealEntryConflictError catch` → "bu öğün başka yerde değişti" mesajı
   (mevcut `catch (_)` bunu yutuyor, `ArgumentError` kolu var, çakışma kolu yok).

---

## 3) 2000 istek ölçümü ve geçiş önerisi

**Ölçüm** (gerçek `SupabaseClient` + `MockClient`, ağ gecikmesi yok):

| Senaryo | Önce (satır satır) | Sonra (toplu) |
|---|---|---|
| 2000 öğün + 2000 su + 400 kilo + 40 gıda | **4506 istek** (26 GET + 4480 POST) | **37 istek** (34 GET + 9 POST) |
| 10/10/10/5 küçük yedek | 44 istek | 9 istek |
| Yazma hatası (1580. satırda) | — | 32 istek + 1 DELETE (telafi) |

`importBatchSize = 500` seçimi:

- **Postgres parametre tavanı 65535** → en geniş tablo 500×14 = **7000 (%11)**.
- Gövde boyutu: 500 öğün ≈ 200 KB (mobilde güvenli; 25 MB üst yedek sınırının
  çok altında).
- `importTables` sabiti + `_insertColumns` tablo başına sabit kolon kümesi →
  `PGRST102` ("All object keys must match") koruması; eksik kolon
  `StateError` fırlatır (sessiz `PGRST102` yerine).

**Web parity notu:** React `useDataExport.ts:150-320` hâlâ satır satır yazıyor
ve `created_at`'i gövdeye taşımıyor. Aynı `PGRST102`/CHECK sorunları orada
da var. **Aktarım → A5/A6.**

---

## 4) `activityLevel` → enum kararı

**Karar: yapıldı.** `Profile.activityLevel: String?` → **`ActivityLevel?`**.

- **Yazma tarafı türle korundu:** `copyWith(activityLevel: …)` artık
  `ActivityLevel` kabul ediyor. `ActivityLevel.veryActive.name`
  (`'veryActive'`) **derlenmiyor** — DB CHECK kısıtı modelin içine taşındı.
- **Okuma tarafı çökmez:** `ActivityLevelMap.fromDb` bozuk değerleri
  `moderate`'a düşürüp `AppLog` yazıyor. `null` **korunuyor** (onboarding
  tamamlanmamış profil `moderate` görünmemeli).
- **`json_serializable` kullanılamıyor:** üretilen kod
  `json['activity_level'] as ActivityLevel?` yazardı → (a) derleme hatası,
  (b) tanımsız DB değerinde **istisna** → profil ekranı çöker. `fromJson`/
  `toJson` elle yazıldı, `profile.g.dart` **silindi** (ölü üretilmiş kod).
- **A4'ün tükettiği API bozulmadı:** `activityLevelFromDb(p.activityLevel)`
  hâlâ derleniyor ve aynı sonucu veriyor (girdi artık `String?` yerine
  `ActivityLevel?` — `fromDb(Object?)` kabul ediyor). **A4 için zorunlu
  değişiklik yok**; isteğe bağlı sadeleştirme:
  `p.activityLevel ?? ActivityLevelMap.fallback`.
- **Yedek uyumu:** `toJson()` **kanonik** CHECK değerini yazar, ham değeri
  değil. `rawActivityLevel` yalnızca teşhis/yedek okuması için korunur.
  Böylece Flutter yedeği web istemcisine de aktarılabilir (A2r3'ün
  "web parity" kuralı).

---

## Düzeltilenler

| Sev | Dosya | Ne yapıldı | Doğrulama |
|---|---|---|---|
| **P0** | `data_transfer_repository.dart` | Üç fazlı import: ön-uçu doğrulama (ağ yok) → varlık kontrolü (GET) → toplu + telafili yazma. `ImportValidationError` **hiçbir istek atmaz**; `ImportWriteError.report` her zaman dolu | `import_atomicity_test.dart` (42) |
| **P1** | aynı | Telafi: yazılan satırların `id`'leri `DELETE … in.(…)` ile **fiziksel** silinir (bağımlılık sırasının tersi, 100'lük dilim). Telafi de başarısızsa `rolledBack=false` + **kalan satır id'leri** | aynı (2 test) |
| **P1** | aynı | `amount_ml`/`weight_kg` geçersizde `0` yazmak yerine **ölümcül ihlal** (eski hâli DB 400 → tüm import düşüyordu) | aynı (3 test) |
| **P1** | aynı | Zorunlu sayısal alanlar `0`'a çevriliyordu → **ölümcül** (sessiz yanlış besin değeri) | aynı (1 test) |
| **P1** | aynı | Su dedup'u **dize → epoch mikrosaniye** (`+00:00` ↔ `Z` farkı aynı kaydı iki kez ekliyordu) | aynı (1 test) |
| **P1** | aynı | `nova_score` (`smallint`) aralık dışı → 400 yerine null; `serving_size_g` güvenli varsayılan | aynı |
| **P1** | aynı | `foods`: `verified`/`popularity_count` **yazılmıyor** (popmod trigger'ı kendi artırıyor; web de kopyalamıyor) | aynı (1 test) |
| **P1** | aynı | `created_at` yedeğin damgasıyla taşınıyor (toplu yazım sırayı taşımıyor); 2000'den eski/gelecek damga yazılmaz | aynı (2 test) |
| **P1** | aynı | Yazılabilir satırda tarih/zaman çözümlenemiyorsa **atlanmaz, ölümcül olur** (sessiz veri kaybı) | aynı (3 test) |
| **P1** | aynı | DB'de zaten olan gıda yeniden yazılmıyor; öğün/besin satırı **mevcut** id'ye bağlanıyor (`23505` UNIQUE koruması) | aynı (2 test) |
| **P2** | aynı | Toplu `insert` + sabit kolon kümesi (`PGRST102`), boş girdide istek yok | aynı (3 test) |
| **P2** | aynı | Bozuk tablo/satır girdileri (`"abc"`, `42`, liste değil) çökme yerine atlanıyor | aynı (2 test) |
| **P1** | `profile.dart` | `activityLevel: ActivityLevel?`; `fromJson`/`toJson` elle; `rawActivityLevel` | `profile_activity_level_test.dart` (14) |
| **P1** | `diary_repository.dart` | `updateMealEntry` **iyimser kilit** (`expectedUpdatedAt`) + `MealEntryConflictError` | `concurrency_and_food_filter_test.dart` (8) |
| **P2** | `diary_repository.dart` | `isUsableAmount(double?)` — miktar doğrulamasının tek kaynağı | aynı (5) |
| **P2** | `food_repository.dart` | 3 okuma yoluna `deleted_at` istemci süzgeci + kolon `select()` | aynı (5) |
| **P3** | `data_transfer_repository.dart` | `exportData` kapsam denetimi (hassas tablo sorgulanmıyor) | `export_scoping_test.dart` (4) |

---

## Bulunurlar (düzeltilmedi, gerekçe)

| Sev | Dosya:satır | Bulgu | Etki | Öneri |
|---|---|---|---|---|
| P1 | `data_transfer_repository.dart` — `importBackup` | **Telafi de başarısız** olabilir (ağ kesildi, RLS `DELETE` reddetti) | Yazılan kayıtlar kalır; dedup sayesinde tekrar denemek güvenli, ama kullanıcı bunu bilmiyor | `report.rolledBack == false` → A4 **"bazı kayıtlar eklendi, tekrar deneyebilirsin"** göstermeli. Aktarıldı |
| P2 | `data_transfer_repository.dart` — `exportData` | `select()` ile tüm kolonlar (yedek boyutu) | Büyük yedek = bellek + paylaşım yavaşlığı | Web parity gereği **dokunulmadı**; beyaz liste `foods` için zaten `verified`/`popularity_count` dışlandı |
| P2 | `data_transfer_repository.dart` — `photo_url` | Öğün fotoğrafı yedeğe girer ama `meal-photos` bucket'ı **yedeğe dahil değil** | Geri yüklemede öğün fotoğrafı 404 → kırık görsel | Dosya içeriği yedeğe almak 25 MB sınırını aşar. **Karar gerekli**, önermiyorum |
| P2 | `data_transfer_repository.dart` — `favorite_foods`/`recent_foods`/`notification_preferences` | Dışa aktarılıyor ama **içe aktarılmıyor** (döngüsel bağımlılık: `food_id` yeni gıdaya bağlanmalı) | Yedek→geri yüklemede favoriler kaybolur | Yeni tur: `favorite_foods` ekle (aynı desen, `UNIQUE(user_id, food_id)` → `upsert`) |
| P2 | `_idMapByBackupName` | Dönen satır sayısı plandan farklıysa `StateError` | RLS `RETURNING`'i kısarsa (nadir) import durur | Doğru davranış; Postgres her zaman tam döner |
| P3 | `sanitizeFood` | Artık içe aktarma yolunda **kullanılmıyor** (yalnız test/uyumluluk) | Ölü kod riski | `import_sanitize_test.dart` kullanıyor; silmek A6 alanında test düzenlemesi gerektirir |
| P3 | `MealEntry.updatedAt` nullable | `updated_at` DB'de `NOT NULL` ama modelde `String?` | `expectedUpdatedAt` null kalırsa kilit **devre dışı** | Çağıran `null` geçerse son yazan kazanır (belgeli). `MealEntry` alanı `String` yapılabilir → A4 etkilenir, ertelendi |

---

## AKTARIM

### → A1r4 (`supabase/**`) — atomik import RPC'si (**yazma, uygulama**)

**Gerekçe:** PostgREST transaction sağlamaz; istemcide telafi **çoğu** durumda
yeterli ama garanti değil. RPC gerçek garantidir.

**Önerilen migration** (yeni dosya, `supabase/migrations/<tarih>_import_data_rpc.sql`):

```sql
-- jsonb gövde: {user_id, foods[], food_nutrition[], meal_entries[],
--               water_entries[], weight_entries[]}
-- DÖNDÜRÜR: jsonb {counts, skipped, failed_stage}
CREATE OR REPLACE FUNCTION public.import_data(payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user uuid := auth.uid();
  ...
BEGIN
  -- 1) kullanıcının food_id'leri ikame et (isim bazlı dedup)
  -- 2) food_nutrition (UNIQUE food_id → ON CONFLICT DO NOTHING)
  -- 3) meal_entries / water_entries / weight_entries (ON CONFLICT DO NOTHING)
  -- 4) RETURN jsonb_build_object('counts', ...)
END $$;

REVOKE ALL ON FUNCTION public.import_data(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.import_data(jsonb) TO authenticated;
```

**Kritik uyarılar (A1 için önceden bulundu):**

1. **`SECURITY DEFINER` + `search_path = ''`** zorunlu — `full_setup.sql:438`
   (`increment_food_popularity`) bu deseni kullanıyor. `auth.uid()` her zaman
   `v_user`'a **göre** yazmalı; gövdedeki `user_id` **görevli değil** (başka
   birinin yedeği başka birine yazılmamalı).
2. `meal_entries` üzerinde `UNIQUE(user_id, entry_date, custom_name, meal_type)`
   **yok** (`full_setup.sql:117-131`) → dedup `ON CONFLICT` ile **mümkün
   değil**; `INSERT … SELECT … WHERE NOT EXISTS` gerekir. Yani migration
   **yalnız RPC'yi** eklemek yetmez, dedup mantığı plpgsql'da yazılmalı.
3. `food_nutrition.food_id UNIQUE` (`full_setup.sql:121`) → burada
   `ON CONFLICT (food_id) DO NOTHING` çalışır.
4. **A1r3'ün hesap silme denetimine ekleyin:** `import_data` **yeni bir
   mass-write yüzeyi**. `REVOKE … FROM PUBLIC` + `GRANT … TO authenticated`
   ve `pg_proc.proacl` doğrulaması gerekir.

**Etkisi:** Flutter'da `importBackup` içindeki `_loadExistingKeys` +
`_apply` blokları RPC'ye taşınır; `buildImportPlan` (saf doğrulama) **kalır**
çünkü istemci ön-uçu ağ hatasında erken uyarı veriyor.

### → A4r4 (`lib/features/**`) — üç zorunlu değişiklik

1. `transfer_dialogs.dart:97` `catch (_)` → `on ImportValidationError` /
   `on ImportWriteError` (ayrıntı ve yeni çeviri anahtarları yukarıda).
2. `recognition_confirm_dialog.dart:547` `dialogs.amountRequired` →
   `dialogs.invalidAmount` (+ `DiaryRepository.isUsableAmount` kullanımı).
3. `edit_meal_entry_dialog.dart:132` `updateMealEntry` →
   `expectedUpdatedAt: widget.entry.updatedAt` + `on MealEntryConflictError`.

**Zorunlu değil (mevcut kod derleniyor, davranış aynı):**
`activityLevelFromDb(p.activityLevel)` → `p.activityLevel ?? ActivityLevelMap.fallback`.

### → A5/A6 (`src/**`) — web içe aktarma aynı hataları taşıyor

`src/hooks/useDataExport.ts:150-320` (tur 3'te zaten tespit edilmişti):
- satır satır yazıyor (ölçek),
- `created_at`'i gövdeye taşımıyor,
- `meal_entries` dedup'u `maybeSingle()` ile iki eşleşmede patlar,
- **`import_data` RPC'si gelirse web de geçmeli** (aksi halde iki istemci
  farklı atomiklik semantiğine sahip olur).

### → A3 (`lib/core/**`) — yok (bu tur `core/**`'e dokunulmadı).

---

## Yeni testler (+80 → toplam 597)

| Dosya | Test | Kapsam |
|---|---|---|
| `test/data/repositories/import_atomicity_test.dart` (yeni) | 42 | Doğrulama hatasında **0 istek** (8 senaryo, hepsi `postCount == 0` + `deleteCount == 0`); varlık kontrolü ve dilimleme; yazma hatası + telafi (başarılı/başarısız); 4506 → 37 istek ölçümü; gövde sözleşmesi (beyaz liste, enum, `created_at`, yeni `food_id`, `PGRST102`); geriye dönük uyum; bozuk girdi dayanıklılığı |
| `test/data/models/profile_activity_level_test.dart` (yeni) | 14 | 5 DB değeri → enum; `null` korunur; 7 bozuk değer fallback + ham korunur; `very_active` **düşmez** (TDEE regresyonu); `toJson` her zaman CHECK'te; `.name` sızmaz; tam profil round-trip; `copyWith` |
| `test/data/repositories/export_scoping_test.dart` (yeni) | 10 | `isUsableAmount` (9 senaryo); `exportData` yalnız kendi verisi; 3 tabloda `deleted_at=is.null`; **6 hassas tablo sorgulanmıyor** (`push_subscriptions`, `user_settings`, `chat_messages`, `chat_threads`, `notifications`, `user_roles`) |
| `test/data/repositories/concurrency_and_food_filter_test.dart` (yeni) | 13 | `updated_at` filtresi gider/geçmez; 4 ayrı 0-satır senaryosu (çakışma / silinmiş / yok / damgasız); yazma sınırı ağa **gitmeden** çalışır; food_repository 3 yolda `deleted_at` istenir + süzgeç; kolon yoksa seri boşalmaz |

**Komut ve sonuç:**
```
cd flutter_app && flutter analyze
  → No issues found!

cd flutter_app && flutter test
  → +597: All tests passed!      (tur 3: 517  ·  test/data: 153 → 230)

node tool/check_versions.cjs
  → ✓ Sürüm tutarlı: 1.3.0+4 (pubspec = AppConstants = CHANGELOG = README)
     · web 1.1.0 (package.json = APP_VERSION) · varsayılan hedefler ve
       makro oranları iki istemcide aynı.
```

**Test felsefesi notu:** `MockClient` + gerçek `SupabaseClient` kullanıldı —
`postgrest` isteği yanıtta taşımadığı için sarmalayıcı ilişkiyi geri
kurar. Böylece **gerçek PostgREST URL'i** üretilir ("hangi filtre gitti?"
sorusu zincir kurmadan yanıtlanır). `import_sanitize_test.dart` (8 test)
bozulmadı; `sanitizeFood` sarmalayıcısı eski "null alanlar düşer" sözleşmesini
koruyor.

---

## Sonraki öneriler (tur N+1 için)

1. **`import_data` RPC** (A1r4, yukarıda ayrıntılı) — tek garantili atomiklik.
2. **`favorite_foods` içe aktarımı** — yedek→geri yüklemede favoriler
   kayboluyor (P2, aynı desen, `UNIQUE(user_id, food_id)` → `upsert`).
3. **`photo_url` kararı** — bucket içeriği yedeğe alınamıyor, öğün fotoğrafları
   geri yüklemede kırık. Karar gerekli (25 MB sınırı).
4. **Web istemcisi (`src/hooks/useDataExport.ts`)** aynı üç fazlı akışa
   geçmeli (A5/A6).
5. `MealEntry.updatedAt` → `String` (nullable olmaktan çıkar, `NOT NULL`
   sözleşmesi).
6. `sanitizeFood` ölü kod — test düzenlemesiyle silinebilir (A6).
7. `importTables` sabitini `exportData` da kullansın: bugün iki liste
   bağımsız; yeni tablo import'a eklenip export'a eklenmezse yedek→geri
   yükleme sessiz veri kaybı üretir (test kapsamı belgeliyor, kod bağlı değil).
