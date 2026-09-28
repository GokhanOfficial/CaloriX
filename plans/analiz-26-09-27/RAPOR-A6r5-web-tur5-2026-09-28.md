# RAPOR — A6r5 (web/React PWA, CI, dokümantasyon) — 2026-09-28 — Tur 5

## Özet (5 madde)

1. **Web yedek içe aktarımı Flutter ile aynı hataları taşıyordu; hepsi
   düzeltildi.** Kısmi import (yarısı yazılmış hâlde "hata"), besin
   satırında sayı olmayan alanın `0`'a çevrilmesi (sessiz yanlış besin
   değeri), `amount_ml`/`weight_kg` geçersizde `0` → DB CHECK 400 →
   **öğünler yazıldıktan sonra** import'un ölmesi: dördü de mevcuttu.
   Ayrıca yumuşak silinen kayıtların canlanması, `created_at`'in
   kaybolması ve 4506 isteklik satır satır yazım da düzeltildi.
2. **`favorite_foods`/`recent_foods` tutarsızlığı web'de de vardı** ve
   kapatıldı: dışa aktarılıyor, içe aktarılmıyordu → yedek→geri
   yüklemede favoriler kayboluyordu. Artık `UNIQUE(user_id, food_id)`
   üzerinden `upsert` ile yazılıyor.
3. **Tarih UTC kayması web'de "yarı" düzeltilmişti**: `localDateFromIso`
   (A5) yalnızca **türetilen** tarihlerde kullanılıyordu; `meal_entries`
   ve `weight_entries` `entry_date`'si **yedeğin ham dizesiyle** yazılıyordu
   ve dedup anahtarı dize karşılaştırmasıydı. Artık tüm günler tek
   yardımcıdan (`dateString` → `localDateFromIso`) geçiyor.
4. **`useNotifications` sessiz hatası kapandı**: `error` (operation +
   görünür mesaj + konsola ayrıntı) ve `retry` durumu eklendi, iki ekran
   (ayarlar + bildirim paneli) hata ve "Tekrar Dene" gösteriyor. VAPID
   anahtarı yokken `console.warn` + `return` yapılması da görünür hataya
   çevrildi.
5. **CI kararları:** `deno.lock` **takip ediliyor** (ölçümle gerekçelendi),
   `supabase/deno.json` ile edge grafiğinden ayrıldı (8382 → 3285 bayt),
   üç workflow'un `push` tetiklemesi tüm branch'lere açıldı,
   `strings.xml` için 11 yeni çeviri dosyası **eklenmedi** (gerekçeli).

## Düzeltilenler

| Sev | Dosya | Ne yapıldı | Doğrulama |
|-----|-------|-----------|-----------|
| **P1** | `src/lib/import/backupImport.ts` (YENİ) | Saf katman: `decodeBackup` → `buildImportPlan` (beyaz liste, ölümcül/atlanan/düzeltilen ayrımı, `uniform` `PGRST102`, `INSERT_PREFER_DEFAULTS`). Hata sınıfları `ImportFormatError` / `ImportValidationError` / `ImportWriteError`. | 40 test |
| **P1** | `src/lib/import/backupRestore.ts` (YENİ) | Ağ katmanı: 100'lük dilimli varlık kontrolü (yalnız GET) → 500'lük toplu `insert` → hata halinde `id` ile fiziksel telafi. `rolledBack`/`survivors` raporlanır. | `tsc` 0 · `build` ✓ |
| **P1** | `src/hooks/useDataExport.ts` | Yeniden yazıldı: üç fazlı akış, 3 ayrı hata kolu, `skipped`/`coerced` kullanıcıya gösteriliyor, export hataları yutulmuyor, `deleted_at` dolu satırlar dışa aktarılmıyor, `favoriteFoods`/`recentFoods` içe aktarılıyor. | `npm test` 40/40 |
| **P2** | `src/hooks/useNotifications.ts` | `error`/`retry`/`clearError` eklendi; `fetchPreferences`/`fetchNotifications`/`subscribeToPush`/`updatePreference` görünür hata üretiyor; `requestPushPermission` gerçek sonucu döndürüyor; oturum kapanınca durum sıfırlanıyor. | `tsc` 0 · lint 0 hata |
| P2 | `src/components/notifications/NotificationPreferences.tsx` | Hata + "Tekrar Dene" (`role="alert"`, `aria-live`). | `tsc` 0 |
| P2 | `src/components/notifications/NotificationPanel.tsx` | Hata halinde "hiç bildirim yok" yerine hata + retry. | `tsc` 0 |
| P2 | `src/components/dialogs/AddFromFoodDialog.tsx` | İki `<Label htmlFor>` + iki `id` eklendi (`add-from-food-meal-type`, `add-from-food-amount`). | `tsc` 0 |
| P3 | `flutter_app/android/.../values/strings.xml` | Yalnızca yorum (gerekçe). Kaynak **değişmedi**. | `flutter analyze` ✓ |
| P3 | `tool/test_backup_import.mjs` (YENİ) | 40 mantık testi (`node:test` + `--experimental-strip-types`, sıfır yeni bağımlılık). | 40/40 |
| P3 | `.github/workflows/{react,flutter,supabase}.yml` | `push` tüm branch'lere; `react.yml`'a `npm test` + `check_versions.cjs`; `supabase.yml`'a `deno.lock` yolu. | YAML okundu |
| P3 | `supabase/deno.json` (YENİ) | `lock: "deno.lock"` + `nodeModulesDir: "none"`. | `deno check` 22/22 · `deno test` 100/0 |
| P3 | `deno.lock` (YENİ, kök→supabase) | Edge grafiğine indirildi. | deterministik |
| docs | `package.json` | `test`, `test:web-verify` scriptleri. | `npm test` ✓ |
| docs | `README.md`, `README_EN.md`, `.env.example`, `CHANGELOG.md` | `VITE_VAPID_PUBLIC_KEY`, localStorage güvenlik notu, `strings.xml` kararı, Tur 5 kayıtları. | `check_versions` ✓ |

## `deno.lock` kararı — **TAKİP EDİLSİN** (ölçüldü)

**A1r4'ün "P3, repoda takip edilmiyor → `cache: true` ilk çalışmada
faydasız" notu doğrulandı ve karar verildi.**

Kanıt zinciri:

1. `deno.lock` `.gitignore`'da **değil** (`git check-ignore` → exit 1).
   Yani izlemiyoruz; ama dosya her `deno` çağrısında yeniden üretiliyor.
2. **Sürüm sürgüsü ölçüldü.** `deno.lock` yokken `esm.sh` redirect'i
   çözüldü:
   - `deno.lock` **varken** → `https://esm.sh/@supabase/supabase-js@2.117.2`
   - `deno.lock` **yokken** → en güncel sürüme yönlendiriyor
     (`@2.180.x`, ölçümde `2.180.1`)
   Aynı kod, aynı repo, iki farklı bağımlılık grafiği. `deno.land/std`
   sürümleri kod içinde **sabit** (`@0.168.0`, `@0.190.0`) — sürgüden
   etkilenmeyen tek yer. Yani **kilitlenmesi gereken yer `esm.sh`'teki
   iki sürümsüz specifier** ve CI'da bunlar `deno.lock` olmadan gün
   gün değişebilirdi.
3. **`cache: true` ilk çalışmada faydasız değil, faydasız **değildi**:
   `denoland/setup-deno` `**/deno.lock` hash'ini cache anahtarı olarak
   kullanır; dosya yoksa `dependencies` cache'i hiç hit olmaz. Dosya
   repoda olursa ilk çalışmadan itibaren `DENO_DIR` yeniden kullanılır.
4. **Sorun başka yerdeydi (ve düzeltildi):** kökteki lock, çalışma
   dizini `supabase/` olduğu için React'ın **70 npm bağımlılığını** da
   içeriyordu (`workspace.packageJson.dependencies`) — edge'in
   kullandığı **hiçbir** paket değil (`@eslint/js` dahil 70 kaydın 70'i
   de web'e ait). 8382 bayt. `supabase/deno.json` (`lock: "deno.lock"`,
   `nodeModulesDir: "none"`) ile 3285 bayta indi ve **tamamen edge
   grafiği** kaldı.
5. Determinizm kanıtlandı: `deno.lock` silinip `deno check` + `deno test`
   çalıştırıldığında **birebir aynı** lock üretildi (iki bağımsız
   çalıştırma, byte-byte aynı).

Gerekçe: kilitlenmemiş bir uzak bağımlılık, güvenlik düzeltmesi
(ör. `deno.land/std` CVE) CI'da **görünmez** gelir. Supabase projesi
frozen ama edge function'lar hâlâ değişiyor; kilit dosyası olmadan bu
denetlenemez.

## `strings.xml` kararı — **ÇEVİRİ DOSYASI EKLENMEYECEKTİ**

Brif "diğer diller için kaynak ekle mi" diye soruyordu. Ölçtüm:
`values/strings.xml` **5** anahtar içeriyor ve **hepsi** şu üç yerden
referanslanıyor:

| Referans | Nerede | Ne gösteriyor |
|---|---|---|
| `widget_daily_label`, `widget_weekly_label` | `AndroidManifest.xml:74,87` | Launcher'ın gösterdiği **2 widget adı** |
| `widget_daily_desc`, `widget_weekly_desc` | `res/xml/widget_{daily,weekly}_info.xml:7` | `appwidget-provider`'ın `android:description` alanı (uzun basılınca açılan metin) |
| `widget_settings_cd` | `res/layout/widget_daily.xml:39` | Bir ikonun `contentDescription`'ı |

Yani `strings.xml` **tek bir şey** çeviriyor: widget'ın adı. Widget'ın
içeriği (gün etiketleri, "kalan", makro değerleri) `weekly.labels` gibi
`str.*` anahtarlarıyla **Dart tarafından** veri kanalıyla geliyor ve
`tool/check_i18n.cjs` 12 dil × 461 anahtarı denetliyor. `widget_weekly.xml`
yorumu bunu açıkça söylüyor ("Gün etiketleri de Dart tarafından
(`weekly.labels`, locale'a göre) gelir").

11 yeni `values-<lang>/strings.xml` eklemek yalnız **2 widget adını**
başka dile çevirirdi — içeriği değil. Bu, kullanıcıya "widget'ım
Almanca görünüyor, içeriği Türkçe" gibi **yarım** bir çeviri deneyimi
verir; widget adını çevirmeden bırakmak ise daha tutarlı. Karar:
**eklenmedi**, gerekçe dosyanın başına yazıldı.

Bu alan Flutter (`android/**`) altında ama **yalnız yorum** değişti;
`flutter analyze`/`flutter test` etkilenmedi.

## Bulunurlar (düzeltilmedi, gerekçe)

| Sev | Dosya:satır | Bulgu | Etki | Öneri |
|-----|-------------|-------|------|-------|
| P1 | `flutter_app/lib/data/repositories/data_transfer_import.dart` | **Flutter tarafındaki favori/son-kullanılan desteği yarım.** `backup_round_trip_test.dart` (untracked, A2r4'ün yeni dosyası) 9 testte kırmızı: `favorite_foods`/`recent_foods` için "DB'de zaten favorilenen gıda tekrar yazılmaz (23505 koruması)", "geçersiz `use_count` DB aralığına çekilir", "created_at round-trip", "idempotent" testleri başarısız. Bu dosya **A2r4 alanında** (`flutter_app/lib/data/**`) ve bu turda **başka bir ajanın** commit'lenmemiş işi. | `flutter test` 610/619 kırmızı — CI kırık | **AKTARIM → A2r5/A2r4.** Web tarafı aynı senaryoyu `ignoreDuplicates: true` ile çözdü (bkz. aşağıdaki not) |
| P2 | `src/hooks/useDataExport.ts:255` | `notificationPreferences` yedekleniyor ama içe aktarılmıyor (aynı tutarsızlık favorilerdeydi). Kasıtlı: geri yükleme kullanıcının **şu anki** bildirim tercihlerini ezmemeli — yedek 6 aylık önceki ayarları geri yükleyip bugünkü tercihi geri almak kullanıcıya zarar verir. | Yok (bilinçli) | Ürün kararı istenirse ayrı iş |
| P2 | `src/lib/import/backupImport.ts:404` | `photo_url` yedeğe giriyor, bucket içeriği girmiyor → geri yüklemede kırık görsel. 25 MB sınırı var. | Geri yüklemede kırık resim | Ürün kararı (A2r4'ün de aktardığı aynı madde) |
| P2 | `src/hooks/useNotifications.ts` | `push_subscriptions` tablosu her abonelikte `upsert` edilir ama **eski** abonelikler (farklı `endpoint`) biriktikçe temizlenmiyor. Edge tarafı tüm satırlara push atıyor. | Bildirim gecikmesi, DB şişmesi | A1r4'ün `send-notification` tarafıyla birlikte düşünülmeli |
| P3 | `.github/workflows/*.yml` | Dependabot **yok** (`.github/dependabot.yml` mevcut değil). Action'lar SHA'ya pinli (`fdd0328`), ama pin'ler elle güncelleniyor. | Güvenlik yaması gecikmesi | `dependabot.yml` eklenmeli (`github-actions` + `npm` + `pub`) |

## AKTARIM (başka alana)

### → A2r5 (veri, `flutter_app/lib/data/**`)
**`flutter test` kırık bırakıldı — 9 test.** `backup_round_trip_test.dart`
(A2r4'ün commit'lenmemiş yeni dosyası) favori/son-kullanılan ve
`created_at` round-trip sözleşmelerini doğruluyor ve **kırmızı**. Bu
turda `flutter_app/lib/data/**`'ya dokunmadım (alan sahipliği); web'de aynı
senaryoyu çözdüm:

- Web'de `favorite_foods`/`recent_foods` **ayrı tablolar** olarak
  `INSERT_TABLES`'e eklendi ve `ignoreDuplicates: true` ile `upsert`
  ediliyor (`ON CONFLICT DO NOTHING` → 23505 üretmez).
- `use_count` **bilinçli olarak** DB varsayılanına (1) çekiliyor ve
  `coerced` ile sayılıyor: `ignoreDuplicates` zaten mevcut sayacı
  koruyor, yedekteki sayıyı kopyalamak "mevcut gıdalarda eski, yenilerde
  yedek değeri" gibi tutarsız bir sonuç üretirdi.
- Yedeğin eski `id`'si (`id`) `food_id` olarak **asla** yazılmıyor; eşleme
  **ad** üzerinden yapılıyor (eski UUID başka kullanıcıya ait).

### → A4r5 (hesap silme arayüzü)
`supabase/functions/delete-account/index.ts` tarafı A1r4'te tamam;
arayüz `flutter_app/lib/features/**` altında. **`favorite_foods`/
`recent_foods` FK'si `foods`'e bağlı** (`ON DELETE CASCADE` değil,
`ON DELETE SET NULL` yok → `favorite_foods.food_id UUID REFERENCES
foods(id) NOT NULL`, yani `CASCADE`). Hesap silmede tablo sırası
`foods`'ten **önce** `favorite_foods`/`recent_foods`'i silmeli, aksi
hâlde FK ihlali. Doğrulayıp arayüze yansıtın.

### → Ana ajan (ürün kararı)
1. `photo_url` bucket içeriği — P2, iki turdur askıda.
2. `foods` topluluk verisi mi silinmeli (A1r4 aktarımı, P2).

## Yeni testler

`tool/test_backup_import.mjs` — **40 test**, `npm test` ile koşar
(Node'un yerleşik `node:test` + `--experimental-strip-types`; **yeni
bağımlılık yok**, `package.json`'a yalnız script eklendi).

| Grup | Testler | Sabitlenen sözleşme |
|---|---|---|
| Ön-uçu | 8 | Biçim hatası → `ImportFormatError`; `weight_kg: 0` / `amount_ml: 0,-5,10001,null,'çok'` / `amount_g_ml: 0,-1,10001` / `kcal: 'çok'` → `ImportValidationError`; **hiçbir yazma**; `summary` dosya yolu taşımıyor |
| Atlanan satırlar | 1 | İsimsiz gıda, anahtarsız öğün, `deleted_at` dolu satır (canlanmaz), yinelenen dedup anahtarı → `skipped`, import devam eder |
| Gövde bütünlüğü | 9 | `user_id` oturumdan; `verified`/`popularity_count`/`id` kopyalanmaz; enum → DB varsayılanı **sayılır**; küsüratlı `amount_ml` yuvarlanır **sayılır**; `created_at` taşınır / 2000 öncesi / gelecek / bozuk → `null`; eski `food_id` yazılmaz; `UNIQUE(food_id)` ikinci satır atlanır; yetim besin satırı atlanır; aynı anahtarlı 3 öğün → 1 |
| Dedup | 5 | Su `+00:00` ↔ `Z` **aynı**; `entry_time` yoksa gün başlangıcı **sayılır**; ne zaman ne gün yoksa ölümcül; `mealKey`; `isDeleted` |
| Tarih | 3 | `localDateFromIso` yerel gün; `dateString` beyaz liste; `epochMicros` iki biçim |
| Favoriler | 2 | Planlanır + `use_count` ezilmez **sayılır**; yetim favori atlanır |
| Gövde/ölçek | 5 | `PGRST102` 7 tabloda; `created_at: null` **gövdeden düşürülür** (`Prefer: missing=default`); 2000 UUID `in` URL'i < 8 KB (20 dilim); boş girdi dilim üretmez; `importBatchSize × 14 < 65535`; tablo sırası |
| Dayanıklılık | 4 | Liste olmayan tablo; nesne olmayan satır; bozuk `entry_date` ölümcül; 2000 öğün planlanabilir (500 gün → 5 dilim) |

### Bulunan gerçek hata (test yazınca çıktı)
`plan.mealDates` **benzersiz değildi**: 2000 öğün / 500 günde aynı gün
4 kez ekleniyordu → `in` sorguları 4× URL uzunluğuna çıkıyor, dilim sayısı
gereksiz 4 katına çıkıyordu. `pushUnique` ile düzeltildi ve teste
bağlandı. Flutter'daki karşılığı (`ImportPlan.mealDates` bir `Set`)
bu yüzden `Set` — web'de dizi + `Set` gölgesi kullanıyor.

## Doğrulama çıktıları

```
$ npm run build
✓ built in 11.41s                       (dist/assets/index-*.js 1430.51 kB)

$ npx tsc -p tsconfig.app.json --noEmit
exit 0                                    (0 hata)

$ npm run lint
✖ 10 problems (0 errors, 10 warnings)   ← Tur 3 tabanı **aynen korundu**
  (9× react-refresh/only-export-components + 1× tool/check_i18n.cjs
   unused eslint-disable; yeni uyarı yok)

$ npm test                               (YENİ)
ℹ tests 40  ℹ pass 40  ℹ fail 0

$ node tool/check_i18n.cjs
✓ 12 dil, 461 anahtar, 300 React i18next anahtarı   (300 ⇢ 284: +16 yeni
  `t()` çağrısı, hepsi mevcut anahtarlar) · orphan 63/63 · exit 0

$ node tool/check_versions.cjs
✓ 1.3.0+4 (pubspec = AppConstants = CHANGELOG = README) · web 1.1.0 · exit 0

$ cd supabase && deno check functions/
22 dosya, 0 hata                          (17 ⇢ 22: delete-account 5 dosya)

$ cd supabase && deno test --allow-env --allow-read --allow-net functions/
ok | 100 passed | 0 failed | 1 ignored

$ cd flutter_app && flutter analyze
No issues found!

$ cd flutter_app && flutter test
00:20 +610 -9: Some tests failed.        ← ⚠️ BENİM DEĞİL
  9 hata `backup_round_trip_test.dart` içinde; bu dosya
  `flutter_app/lib/data/**` alanında, commit'lenmemiş A2r4 işi
  (bkz. "Bulunurlar" → AKTARIM). Benim tek `flutter_app` değişikliğim
  `values/strings.xml` içindeki **yorum**.
```

## "Doğrulayamadığım şeyler"

- **Gerçek PostgREST'e yazma yapmadım.** Telafi (rollback) mantığı
  `uniform()`'ın `PGRST102`/`Prefer: missing=default` sözleşmesi üzerinden
  **statik** doğrulandı; `deno check`/test'in aksine ağ üzerinde
  çalıştırılmadı (proje frozen, production veri yok).
- **`favorite_foods`/`recent_foods` yazımı DB'de denenmedi.**
  `ignoreDuplicates: true` → `Prefer: resolution=ignore-duplicate` →
  `ON CONFLICT DO NOTHING` davranışı `postgrest-js` kaynak kodundan
  doğrulandı, ancak gerçek bir 23505 senaryosu Postgres'te üretilmedi.
- **CI'da ilk çalıştırma yapılmadı.** `deno.lock` determinizmi ve
  `deno check`/`deno test` lokalde doğrulandı; GitHub Actions üzerinde
  `denoland/setup-deno` + `cache: true` + iki `setup-node` adımının
  etkileşimi **test edilmedi** (Docker/act yok).
- **`--experimental-strip-types` için Node 22.6+ gerekir.** CI'a Node 24
  eklendi; lokal doğrulama Node 24.19.0 ile yapıldı. Node 20'de
  `npm test` **çalışmaz** — bu yüzden CI adımı ayrı bir `setup-node`
  bloğuyla Node 24'e geçiyor (`NODE_VERSION: "20"` diğer adımlarda
  korunuyor).

## Sonraki öneriler (tur 6 için)

1. **A2r5**: `flutter test`'i yeşile döndür (9 kırmızı test, yukarıdaki
   AKTARIM).
2. **A5/A6**: `favorite_foods`/`recent_foods` yazımını `delete-account`
   silme sırasıyla birlikte uçtan uca doğrula.
3. `.github/dependabot.yml` (github-actions + npm + pub) — SHA
   pinleri elle güncelleniyor.
4. `useDataExport` için **entegrasyon** testi: `fetch` mock'lu bir
   sahte PostgREST ile telafi senaryosu (`deno test` +
   `node:test` deseninin web'de karşılığı). Şu an saf katman test ediliyor,
   ağ katmanı (`backupRestore.ts`) test edilen **yok** — bu, kalıcı boşluk.
5. `photo_url` bucket içeriği — ürün kararı bekliyor (2 tur).
