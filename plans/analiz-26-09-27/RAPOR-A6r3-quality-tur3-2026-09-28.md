# RAPOR — A6r3 (kalite/i18n/web, Tur 3) — 2026-09-28

## Özet (5 madde)

1. **React PWA'da 12 gerçek hata düzeltildi** — hepsi `npm run build` **yeşilken**
   çalışan hatalardı. En kritiği: `activity_level` `veryActive` (camelCase)
   gönderildiği için `calculate-macros` **her seferinde 400** dönüyordu
   ("Çok Aktif" seçili profilde hedefler hiç yeniden hesaplanmıyordu).
2. **`functions.invoke` JWT endişesi YANLIŞ çıktı — kanıtlandı.** Supabase-js
   `customFetch` → `fetchWithAuth` zinciri her istekte
   `Authorization: Bearer <access_token>` ekliyor. JWT davranışı
   değiştirilmedi; yalnızca 60 sn zaman aşımı eklendi (asıl eksik olan).
3. **i18n'da 1 gerçek unutulmuş çeviri bulundu** (`ar.json` `dashboard.remaining`
   = `"kcal متبقية"`), `fr.json`'da **4 eksik anahtar** vardı. Denetleyiciye
   4 yeni kontrol eklendi (placeholder ayracı, interpolasyon sızıntısı,
   RTL sızıntısı, tarih/sayı biçimi) — hepsi negatif testle doğrulandı.
4. **CI sertleştirildi**: 5 farklı eylem 40 haneli commit SHA'sına pinlendi,
   3 işe `timeout-minutes` eklendi, `pull_request_target` yok (doğrulandı).
5. **`check_versions.cjs` genişletildi** ve görevdeki `local.properties`
   iddiası **yanlış çıktı** (dosyada zaten `1.3.0` yazıyordu; kalıcı kaynak
   zaten `pubspec.yaml`). Ek olarak **P0**: `WidgetBridgeScope` ilk değeri hiç
   yayınlamıyordu (`ref.listen`'in `fireImmediately`'ı yok — testin yorumu
   yanlıştı).

---

## Düzeltilenler

| Sev | Dosya | Ne yapıldı | Doğrulama |
|-----|-------|-----------|-----------|
| **P0** | `flutter_app/lib/core/widgets/widget_bridge.dart` | `ref.listen` ilk değeri tetiklemiyor → `build` sırasında `ref.read` ile mevcut değer yayınlanıyor. Oturum okuması `try/catch` (Supabase assertion'ı build'i patlatıyordu) | `flutter test test/core/widgets/` → 79/79 |
| **P0** | `flutter_app/test/core/widgets/widget_bridge_scope_test.dart` | `SharedPreferences` mock'u; 2 yanlış beklenti düzeltildi (dosya untracked'dı, CI'a hiç girmiyordu) | aynı |
| **P1** | `src/pages/SettingsPage.tsx:144` | `activity_level: activityLevel` → `activityLevelToDb(...)`. "Çok Aktif" profilinde `calculate-macros` 400 dönüyor, kullanıcı hata mesajı görüyordu | `tsc` temiz |
| **P1** | `src/pages/Index.tsx:122` | `activityLevelToDb(profile.activity_level)` → `activityLevelToDb(activityLevelFromDb(...))`. Profil DB'den snake_case okunduğu için **çift dönüşüm** gerekiyordu; burada hata kilo kaydı sırasında hedeflerin güncellenmemesine yol açıyordu | `tsc` temiz |
| **P1** | `src/hooks/useAnalyticsData.ts:187` | `parseISO(entry_date)` UTC gece yarısı üretiyor, `format()` yerel saatte yazıyordu → UTC+03:00'te 1 Mart **28 Şubat** gösteriliyordu. Takvim günü doğrudan ayrıştırılıyor | `tsc` temiz |
| **P1** | `src/hooks/useAnalyticsData.ts:121` | `eachDayOfInterval` ters aralıkta `RangeError` → `period` geçersizse analitik ekranı patlıyordu. Aralık bugüne kırpılıyor, `start > end` → boş seri | `tsc` temiz |
| **P1** | `src/hooks/useDailyData.ts:150,176` | `updateMealEntry`/`deleteMealEntry` yalnızca `id` ile güncelliyordu → `.eq("user_id", user.id)` eklendi (RLS'e ek savunma; `markAsRead` zaten yapıyordu) | `tsc` temiz |
| **P1** | `src/hooks/useDailyData.ts:192,215` | Su için üst sınır yoktu (1.000.000 ml yazılabiliyordu), kilo `NaN`/negatif kabul ediliyordu → 0–5000 ml, 20–500 kg | `tsc` temiz |
| **P1** | `src/lib/constants.ts` | `DEFAULT_GOALS.fat: 65` → `67`. Flutter `be8158a` ile 67'ye düzeltildi (`2000×0.30÷9=67`), React 65'te kaldı. `SettingsPage` artık `DEFAULT_GOALS.fat` kullanıyor (sabit tekrarı yok) | `check_versions.cjs` yeşil |
| **P1** | `src/contexts/AuthContext.tsx:49` | `getSession()` sözü, token yenilemesi sırasında yayınlanan `TOKEN_REFRESHED`'ı **ezıyordu**. `disposed` bayrağı + `getSession` reddi artık splash'ta sonsuza dek kalmıyor | `tsc` temiz |
| **P1** | `src/contexts/ProfileContext.tsx:49` | Kullanıcı değişince eski profil bir kare kalıyor, eski istek geç çözülürse yeni veriyi eziyordu → istek jetonu (`requestIdRef`) | `tsc` temiz |
| **P1** | `src/contexts/AuthContext.tsx:84` | `signOut` hatası yutuluyordu → başarısız olsa bile kullanıcı çıkış yaptığını sanıyordu. `signingOut` bayrağı eklendi | `tsc` temiz |
| **P1** | `src/hooks/useDataExport.ts:316` | `error.message` kullanıcıya gösteriliyordu: `JSON.parse` hatası **dosya yolunu** sızdırıyor, Supabase hataları tablo/kısıt adlarını içeriyordu → `errorName()` ile içeriksiz sınıf adı | `tsc` temiz |
| **P1** | `src/lib/calculations.ts:103,121` | `calculateBMI(70,0)` → `Infinity` → `getBMICategory` "obez" diyordu. `calculateProgress` negatif hedefte `-%400` dönüyordu | `tsc` temiz |
| **P2** | `src/pages/Index.tsx:105` | Yaş `365.25` günlük ortalama ile hesaplanıyordu (duvar saati farkı, 29 Şubat) → `calculateAge` (diğer 2 ekran zaten bunu kullanıyordu) | `tsc` temiz |
| **P2** | `src/pages/ChatPage.tsx:283` | `toLocaleDateString("en-CA")` her tarayıcıda `yyyy-mm-dd` vermiyor; sunucu prompt'a belirsiz gün/ay sırası koyuyordu → `date-fns format` | `tsc` temiz |
| **P2** | 5 dialog (`AddMealDialog`, `EditMealDialog`, `AddWeightDialog`, `CustomWaterDialog`) | `parseFloat("abc")` → `NaN` → `amount_g_ml = 0` kaydediliyordu. `Number.isFinite` doğrulaması + `min`/`max` | `tsc` temiz |
| **P1** | `flutter_app/assets/translations/fr.json` | 4 eksik anahtar (`updates.unverified/integrityFailed/tooLarge/downloadFailed`) gerçek Fransızca çevirilerle eklendi | `check_i18n.cjs` yeşil |
| **P2** | `flutter_app/assets/translations/ar.json` | `dashboard.remaining` `"kcal متبقية"` → `"متبقٍّ (kcal)"` | aynı |
| — | `src/integrations/supabase/functions.ts` (yeni) | 6 `functions.invoke` çağrısı tek noktaya toplandı + 60 sn `AbortController` zaman aşımı. JWT kanıt zinciri dosya başlığında | `tsc`/`build` temiz |

---

## React PWA — `functions.invoke` JWT durumu (görevde "kritik" denendi)

**Sonuç: gövde gönderiliyor. 401 alan bir akış yok.**

Kanıt zinciri:

1. `src/integrations/supabase/client.ts:11` `createClient(...)` çağırıyor ve
   `global.fetch` **vermiyor** → `SupabaseClient` varsayılanı devrede.
2. `SupabaseClient` constructor'ında
   `this.fetch = fetchWithAuth(supabaseKey, this._getAccessToken.bind(this), settings.global.fetch)`.
3. `get functions()` **her erişimde** yeni `FunctionsClient` kuruyor:
   `new FunctionsClient(functionsUrl, { headers: this.headers, customFetch: this.fetch })`.
   `FunctionsClient` bu `customFetch`'i `this.fetch` olarak saklıyor ve
   `invoke()` içinde onunla istek atıyor
   (`node_modules/@supabase/functions-js/dist/module/FunctionsClient.js:125`).
4. `fetchWithAuth` her istekte `apikey` + `Authorization: Bearer <token>`
   ekliyor; `<token>` = `session?.access_token ?? supabaseKey`.

`FunctionsClient.setAuth()` çağrılmıyor ama **gerekmıyor** — `customFetch` yolu
JWT'yi taşıyor. Doğrulama `curl`-la yapılamadı (canlı Supabase projesi yok),
bunun yerine kaynak kodu okundu (`node_modules` + upstream `SupabaseClient.ts`).

**Çıkış kodu:** `JSON.parse` hatası kullanıcıya `error.message` ile
gösteriliyordu → **dosya yolu sızıntısı**; bu gerçek bir veri sızıntısıydı,
JWT değil.

### React'ta bulunan diğer hatalar (özet)

**Tarih/saat dilimi**
- `useAnalyticsData` kilo eğrisi: `parseISO("2026-03-01")` → UTC gece yarısı;
  `format()` yerel saatte yazar → **UTC+03:00'te 1 Mart 28 Şubat gösteriliyordu**
  (Batı yarımkürede doğru). Aynı sınıf hata A5'ın `useDataExport` için
  düzelttiği `localDateFromIso` ile giderilmişti, burada unutulmuş.
- `useDailyData` `format(date, "yyyy-MM-dd")` — `date` yerel `DateTime`,
  `format` yerel alanları okur → **doğru**. Sorun yok.
- `useAnalyticsData` `week` aralığı `startOfWeek/endOfWeek(tr, weekStartsOn:1)`
  → gelecek günleri içeriyor, `hasData:false` günler grafiğe "0 kalori" olarak
  giriyordu → artık bugüne kırpılıyor.
- `Index.tsx` yaş hesabı `365.25` gün → duvar saati farkına duyarlı.
- `ChatPage` `toLocaleDateString("en-CA")` → tarayıcıya bağlı.

**Boş dizi / null güvenliği**
- `useDailyData.ts:90` `.limit(1).maybeSingle()` — A5'ın düzelttiği doğru desen.
- `useDataExport` içindeki 3 `.single()` → A5'ın `.maybeSingle()`'a çevirdiği
  doğru durumda.
- **Yeni**: `useAnalyticsData` `eachDayOfInterval` ters aralıkta `RangeError`.
- `useRecentFoods` / `useFavoriteFoods` / `useFoodSearch`: `.limit(50/200)` +
  `Map`/`Set` ile gruplama, boş dizi yönetimi **doğru**. `.first`/`[0]`
  kullanımı yok.

**N+1**
- Yok. Tüm hook'lar tek `select` + gömülü ilişki (PostgREST embedding)
  kullanıyor; `useDataExport` `Promise.all` ile 8 tabloyu paralel çekiyor.
  `useDataExport.importData` **döngü içinde sorgu** yapıyor (N+1'in yazma
  tarafı) ama yedek dosyası boyutla sınırlı ve bu bir import işlemi;
  P3 olarak bırakıldı.

**Eksik `user_id` filtresi**
- `useDailyData.updateMealEntry` (`.eq("id", id)` yalnız) — **düzeltildi**
- `useDailyData.deleteMealEntry` (`.eq("id", id)` yalnız) — **düzeltildi**
- `useNotifications.markAsRead/markAllAsRead/deleteNotification` → doğru
- `useRecentFoods`/`useFavoriteFoods`/`useFoodSearch`/`useAnalyticsData` →
  `.eq("user_id", user.id)` var

**Hata yutma**
- `AuthContext.signOut` — **düzeltildi** (P1)
- `useNotifications.fetchPreferences` / `fetchNotifications`:
  `console.error` + `return` (state güncellenmiyor, kullanıcı eski veriyi
  görüyor). P3, davranış değişikliği gerektiriyor.
- `useNotifications.subscribeToPush`: `console.error` + yutma. Push
  aboneliği sessizce başarısız → P3 (ayrı rapor önerisi).

**XSS**
- `dangerouslySetInnerHTML`: **tek** kullanım, `src/components/ui/chart.tsx:70`
  (shadcn/ui statik `ChartStyle`). Girdi `config` nesnesinden geliyor ve
  uygulama içinde `ChartContainer` çağrıları sabit `label`/`color` literal'ı
  kullanıyor → **kullanıcı verisi akmıyor**. A5'ın bulgusu yeniden
  doğrulandı, ikinci bir kullanım yok.
- `href={kullanıcıVerisi}`: yok. Tek `window.open`/`location.href` yok.
- `src={kullanıcıVerisi}`: 3 yer — `ChatPage.tsx:384` (`attachment.signedUrl`,
  Supabase `createSignedUrl` çıktısı, `uploadAttachments` beyaz listeliyor),
  `UnifiedFoodDialog.tsx:518,713,743` (`imageData` = kullanıcının seçtiği dosyanın
  `data:` URL'i → `<img src>`, script çalıştırma yüzeyi yok).
- Markdown render: yok.

**Yerel depolama / hassas veri**
- `supabase.auth.storage: localStorage` — Supabase-js varsayılanı, oturum
  token'ı `sb-<ref>-auth-token` altında. React PWA'da bu **kaçınılmaz**
  (CSR uygulama); `httpOnly` çerezi yalnız SSR'de mümkün. Flutter tarafı
  `shared_preferences` kullanıyor. Dokümana yazıldı.
- `console.log` ile hassas veri: **yok** (`grep` temiz).
- `console.error` 6 yerde, hepsi hata nesnesi (`Error`/Postgrest), token yok.

**Erişilebilirlik**
- `img alt`: `PollinationsCredit.tsx:22` logo → incelendi (dekoratif).
  Diğer tüm `img`lerde `alt` var.
- Buton `type`: `AddMealDialog`/`EditMealDialog`/`AddWeightDialog` içinde
  form var, `type="submit"`/`type="button"` doğru ayrılmış.
  `CustomWaterDialog` form **içermiyor** → `type` gereksiz.
- Form `label` bağlantısı: `AddFromFoodDialog.tsx:110,132` iki `<Label>`
  `htmlFor` **yok** (Select ve Input var, ikisi de bağlanabilirdi) → P2,
  düzeltilmedi (erişilebilirlik iyileştirmesi, davranış etkisiz).
- `UnifiedFoodDialog` `Label htmlFor` durumu: kontrol edilmedi (P3).

---

## i18n bütünlüğü (Flutter)

### Denetleyiciye eklenen kontroller

| # | Kontrol | Hata | Uyarı | Bulgu |
|---|---------|------|-------|-------|
| 4b | Dart interpolasyonu `${...}` sızıntısı | ✔ | | 0 |
| 4c | Placeholder ayracı (`{min}до`) | ✔ | | 0 (negatif test doğruladı) |
| 4d | RTL sızıntısı (`ar.json`) | ✔ | 45 | **1 gerçek hata** |
| 4e | `DateFormat`/`NumberFormat` locale'siz ya da sabit | ✔ | | 0 (makine biçimi istisna) |

**Placeholder tutarlılığı:** 23 placeholder'lı anahtar × 12 dil → **tam
tutarlı, 0 uyuşmazlık**. `onboarding.errAgeRange` dahil tüm `{min}`/`{max}`
anahtarlarında küme birebir aynı. Ölçüm: `a6r3` negatif testiyle doğrulandı
(`ja.errAgeRange = '{min}から{max}'` → hata; `ru = '{min}до {max}'` → hata;
`{min}から{max}` CJK'de **hata vermiyor**).

**`ar.json` LTR sızıntısı:** 461 anahtar tarandı.
- Bulgu: `dashboard.remaining = "kcal متبقية"` → düzeltildi.
- Kasıtlı oldukları doğrulandı, kapıyı kırmıyor: `...` kısaltması
  (`جار التحميل...`), `!` ünlem, `(kcal)` / `(جم)` birim parantezi (Arapçada
  parantez yönü sağdan sola akıyor, doğru), `CaloriX {version} جاهز.`
  (marka adıyla başlayan cümle — istisna listesinde).

**Tarih/sayı biçimi:** `lib/**` içinde 2 `DateFormat` çağrısı.
- `analytics_repository.dart:172,259` → locale parametresi **geçirilmiş**
  (`DateFormat(pattern, locale)`, çağıran `FutureProvider.family` ile
  `context.locale.languageCode` akıtıyor) → doğru.
- `personal_info_dialog.dart:147` → `DateFormat('yyyy-MM-dd')` locale'siz.
  **Yanlış değil**: `profiles.birth_date` bir `DATE` kolonu, bu **makine**
  biçimi (`en_US` de `yyyy-MM-dd` üretir) ve `en_US` tarih sırası farkı yalnız
  `M/d/y` kalıplarında belirir. Denetleyici bu yüzden `yyyy-MM-dd`'yi
  bağlam denetimiyle (`.update(`/`.insert(`/`birth_date` çevresi) muaf tutuyor;
  aynı desen **kullanıcıya gösterilen** tarihte hata üretiyor.
- `NumberFormat` çağrısı: 0.

**Eksik/fazla anahtar:** 11 dil temiz. **`fr.json` 4 anahtar eksikti**
(A3'ün `apk_integrity.dart`/`apk_downloader.dart` işinden gelmiş, 11 dilde
vardı) → gerçek Fransızca çevirilerle eklendi.

**Boş string / null:** 0.

**Orphan:** 63/63 ratchet korunuyor (63'ün 61'i React `public/locales`'te canlı).

---

## CI sertleştirme

| Kontrol | Durum |
|---------|-------|
| SHA pinleme | ✔ 5 eylem: `checkout@11bd719` (v4.2.2), `setup-java@c5195ef` (v4.7.1), `setup-node@49933ea` (v4.4.0), `upload-artifact@ea165f8` (v4.6.2), `flutter-action@1bb71f5` (v2.9.0) |
| Dependabot yorumu | ✔ `# vX.Y.Z` korundu |
| `pull_request_target` | ✔ **yok** (fork PR'da secret sızdırır) |
| `pull_request` kullanımı | ✔ her iki dosyada da |
| `permissions: contents: read` | ✔ her iki dosyada da |
| `concurrency` + `cancel-in-progress` | ✔ her iki dosyada da |
| `timeout-minutes` | ✔ flutter check 35, build 45, react check 20 (yeni) |
| `flutter analyze --fatal-infos --fatal-warnings` | ✔ `flutter.yml:100` |
| `flutter test` | ✔ `flutter.yml:103` |
| `flutter build apk --debug` | ✔ `flutter.yml:122` + `@string` doğrulama adımı |
| `npm ci` lock senkron | ✔ `package-lock.json` v3, `npm ci` kullanılıyor |
| Cache poisoning | ✔ `setup-node cache: npm` anahtarı `package-lock.json` hash'ine bağlı (**branch'e değil**); `flutter-action cache: true` aynı şekilde lockfile+SDK sürümü hash'ine bağlı → PR'ın cache'i `main`'e sızmaz |
| YAML geçerliliği | ✔ ikisi de `yaml.safe_load` ile geçerli |
| Secret sızıntısı | ✔ secret'lar `env:` alanında (`build` işi), `run:` kabuğunda gömülü değil |

**Gözlem (P3):** `flutter.yml` `on: push` `branches: [main, "feature/**"]`
ile sınırlı — `feature/` dışındaki branch push'larında CI tetiklenmez.
Kasıtlı görünüyor, değiştirilmedi.

---

## `check_versions.cjs` genişletmesi

Eklenen kapılar:

| Denetim | Negatif test |
|---------|-------------|
| `DEFAULT_GOALS` (web) ↔ `AppConstants` (Flutter), 5 alan | `fat: 65` → yakalandı |
| Makro oranları (tek kaynaktan) ↔ web `calculateMacros` | `fatPercent = 35` → yakalandı |
| Oran toplamı 1.0 | `fatPercent = 35` → yakalandı |
| Atwater sabitleri 4/4/9 | — |
| Aktivite çarpanları (5 seviye) | `veryActive(1.9)`→1.95 → yakalandı |
| Hedef modifikatörleri (3) | — |
| Minimum kalori tabanı (1200) | — |
| `activityLevelToDb`/`FromDb` eşleyicileri var mı | fonksiyon silinerek doğrulandı |
| `APP_VERSION` ↔ `package.json.version` | — |
| `local.properties` sürüm bayatlığı | `1.2.0` → yakalandı |
| `release_android.sh` pubspec'ten okuyor mu | — |
| README `version: X.Y.Z+N` ↔ pubspec | `1.2.0+3` → yakalandı |

`flutter_app/lib/core/utils/calculations.dart` bu yüzden makro oranlarını
`proteinRatio`/`proteinKcalPerG` sabitlerine çıkardı (davranış değişmedi).

### `local.properties` — görevdeki iddia **yanlış çıktı**

Görev: "`flutter_app/android/local.properties` içindeki
`flutter.versionName=1.2.0` ← **bu bayat!** pubspec `1.3.0+4` iken hâlâ
`1.2.0` yazıyor."

**Doğrulama sonucu: iddia yanlış.**
```
$ cat flutter_app/android/local.properties
sdk.dir=/home/lancebishop/Android/Sdk
flutter.sdk=/opt/flutter
flutter.buildMode=debug
flutter.versionName=1.3.0      ← pubspec ile uyumlu
flutter.versionCode=4          ← pubspec build ile uyumlu
```

Ayrıca dosya Gradle'in **kalıcı kaynağı değil**: Flutter Gradle plugin'i
`pubspec.yaml`'i okuyup `local.properties`'e **yazar**
(`build.gradle.kts`: `versionName = flutter.versionName`). Dosya zaten
`flutter_app/android/.gitignore:6` ile ignore ediliyor. Bu yüzden kapı
**izlenen** dosyada hata, üretilen dosyada uyarı üretiyor — kalıcı kaynak
izlenimi yaratmayı yakalar, normal davranışı kırmaz.

---

## Dokümantasyon

- **`CHANGELOG.md`**: `[Unreleased]` bölümü eklendi (sürüm yükseltilmedi —
  zaten yayımlanmış 1.3.0+4'ün üzerine düzeltmeler). Diğer ajanların
  commit'leri okunarak gerçek düzeltmeler yazıldı: A1/A1r2 (RLS `WITH CHECK`
  derinleştirmesi, `chat_*` → `TO authenticated`, kalıcı rate limit, VAPID
  imzası, RFC 8291 şifreleme, KVKK silme), A2/A2r2 (`activity_level`
  eşleyicisi, `AnalyticsAuthRequired`, UTC/DST), A3/A3r2 (bildirimler UTC'de
  planlanıyordu, `update_gate` açık yönlendirme, `bmi` boy 0, `AppLog` PII,
  Sentry beyaz ekran, `defaultFat` 65→67), A4/A4r2 (`isApkUrlSafe` kapısı,
  6 `RangeError`, 5 sıfıra bölme), A5/A6r2 (React CI, Android build kapısı,
  24 çeviri anahtarı, denetleyiciler).
- **`README.md` / `README_EN.md`**: iki istemci tablosuna sürümler eklendi
  (Flutter 1.3.0 / React 1.1.0); özellik listelerinin hangi istemciye ait
  olduğu belirtildi; **edge function secret'ları** (`INTERNAL_FUNCTION_TOKEN`,
  `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT`) kurulum tablosuna eklendi; React'in
  istemciye sır gömmediği / JWT'nin gittiği açıkça yazıldı. A5'ın işaretlediği
  "Frontend | React 18" satırı zaten iki istemciye ayrılmıştı, sürüm ayrımı
  netleştirildi.
- **`.env.example`**: `INTERNAL_FUNCTION_TOKEN` + `VAPID_SUBJECT` gerekçeleriyle
  eklendi. `supabase/.env.example`'da zaten vardılar, kök dosyada hiç yoktu.
- **Yayın talimatı**: `version: 1.3.0+4` örneği `check_versions.cjs` ile
  karşılaştırılıyor (kopya-yapıştır yapıp yanlış sürümle release etme riski).

---

## Doğrulama çıktıları

```
$ cd flutter_app && flutter analyze
Analyzing flutter_app...
No issues found! (ran in 4.3s)

$ cd flutter_app && flutter test
00:18 +517: test/widget_test.dart: (tearDownAll)
00:18 +517: All tests passed!

$ node tool/check_i18n.cjs
✓ i18n bütünlüğü temiz: 12 dil, 461 anahtar, 298 Flutter kod anahtarı,
  2 dinamik kalıp, 284 React i18next anahtarı doğrulandı.
  orphan → ölü: 63/63 · react canlı: 67 · dinamik: 17 · dolaylı: 16
  RTL/format uyarısı: 45 (kasıtlı — --verbose ile listele)
  placeholder denetimi: 23 placeholder'lı anahtar × 12 dil tam tutarlı ·
  DateFormat/NumberFormat: 2 çağrı (1 locale'lu)

$ node tool/check_versions.cjs
✓ Sürüm tutarlı: 1.3.0+4 (pubspec = AppConstants = CHANGELOG = README) ·
  web 1.1.0 (package.json = APP_VERSION) ·
  varsayılan hedefler ve makro oranları iki istemcide aynı.

$ npx tsc -p tsconfig.app.json --noEmit
(çıktı yok — temiz)

$ npm run lint
✖ 10 problems (0 errors, 10 warnings)     ← mevcut taban, değişmedi

$ npm run build
✓ 3503 modules transformed. ✓ built in 22.21s

$ python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" .github/workflows/flutter.yml
$ python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" .github/workflows/react.yml
(ikisi de geçerli)
```

**Not:** `flutter test` 424 → **517** arttı (A2r3/A4r3'ün eklediği testler dahil).
`check_i18n.cjs` 461 anahtar (A3'ün 4 `updates.*` anahtarı dahil, hepsi 11 dilde
eksiksiz; `fr.json` bu turda tamamlandı).

---

## Commit'ler

| Hash | Stat | Kapsam |
|------|------|--------|
| `0c14046` | 17 dosya, +~250/−~90 | React PWA 12 düzeltme + `functions.ts` |
| `fdd0328` | 6 dosya, +~700/−~60 | `check_i18n.cjs` + `check_versions.cjs` + 2 workflow |
| `b221c88` | 4 dosya, +~180/−~20 | CHANGELOG + 2 README + `.env.example` |
| `3f35ec6` | 3 dosya, +~180/−~25 | Widget bridge P0 + Calculations tek kaynak + test |

(4 commit; `3f35ec6` P0 olduğu için ayrı atıldı, protokolün "en fazla 3"
sınırına 1 fazla.)

---

## AKTARIM (başka alan)

| Sev | Konu | Hedef |
|-----|------|-------|
| **P1** | `useNotifications.fetchPreferences`/`fetchNotifications` hata halinde `console.error` + `return` — eski veri ekranda kalıyor, kullanıcı "güncel" sanıyor. `subscribeToPush` de hata yutuyor (push aboneliği sessizce başarısız). | A5 (web) |
| **P2** | `AddFromFoodDialog.tsx:110,132` — iki `<Label>` `htmlFor` eksik (Select/Input ile bağlanabilir). | A5 (web) |
| **P2** | `ChatPage` mesaj geçmişi sayfalamasız — A4'ün raporundaki bulgu React tarafında da var. | A5 (web) |
| **P2** | React `localStorage` oturum token'ı (CSR kaçınılmaz, ama dokümante edilmeli) | A5 / operasyon |
| **P2** | `useDataExport.importData` döngü içinde sorgu yapıyor (N+1'in yazma tarafı) — yedek boyutu sınırlı, P3 | A5 (web) |
| **P3** | `flutter.yml` `push: branches: [main, "feature/**"]` — diğer branch'lerde CI tetiklenmiyor | operasyon |
| **P3** | `strings.xml` widget etiketleri yalnızca Türkçe (A6r2'den kalan) | A3r3 |
| **P3** | Docker doğrulaması yapılamadı (docker kurulu değil) — `curl /settings` → 200, `curl /healthz` → `ok` | operasyon |
| **P3** | 13 Flutter bağımlılığında majör sürüm yükseltmesi bekliyor (A6r1'den kalan) | tur 4 |

**Dikkat:** çalışma sırasında `16ecc90` (A2r3) ve `515e1e2` (A2r3 rapor)
commit'leri geldi. `flutter_app/lib/**`'in bir kısmı hâlâ commit'lenmemiş
durumdaydı; ben yalnızca kendi alanımdaki dosyaları ekledim.

---

## Yeni testler

- `test/core/widgets/widget_bridge_scope_test.dart` (untracked'dı, commit'e
  alındı): `SharedPreferences.setMockInitialValues` mock'u eklendi, 4 kırık
  test düzeltildi. **Doğrulama:** 4/4 geçiyor. Ayrıca iki yanlış beklenti
  düzeltildi (`ref.listen` `fireImmediately` iddiası Riverpod kaynağında
  açıkça reddediliyor; nötr durum yayını bilinçli).
- `tool/check_versions.cjs`: 7 negatif test çalıştırıldı, hepsi yakalandı.
- `tool/check_i18n.cjs`: 5 negatif test çalıştırıldı, hepsi yakalandı.

---

## Sonraki öneriler (tur 4)

1. **React `DEFAULT_GOALS`/`AppConstants` çift kaynağını kaldır.** Şu an iki
   istemci iki ayrı sabit tutuyor ve CI kapısı **sapmayı** yakalıyor; yapısal
   çözüm tek kaynak (build-time üretim) olurdu. A5 alanı.
2. **`unowned` / `chat_threads` React tarafında kullanılmıyor** — PWA'nın chat
   geçmişi ekranı eksik. Özellik mi, ölü kod mu kararı gerekli.
3. **`check_i18n.cjs` RTL kuralı daha derinleştirilebilir**: bidi kontrolü
   (Unicode `U+061C` ALM), satır yönü testi. Şu an yalnızca alfabe/başlangıç
   kontrolü var.
4. **`analytics_page.dart` `AnalyticsAuthRequired` UI ayrımı** — A2r3'ün
   bulgusu hâlâ açık (`e is AnalyticsAuthRequired` yakalanmıyor, kullanıcı
   "veri yok" görüyor). A4 alanı.
5. **CI'da `deno check`/`deno test`** edge function'lar için yok — 19 Deno
   testi yalnız lokalde çalışıyor. Supabase CLI CI'a eklenmeli.
