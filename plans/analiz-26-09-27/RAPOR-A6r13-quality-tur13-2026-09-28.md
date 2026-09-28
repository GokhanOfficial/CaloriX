# RAPOR — A6r13 (borç temizliği + kalite kapıları) — 2026-09-28 — Tur 13

## Özet (5 madde)

1. **Orphan ratchet 63 → 60.** A2r13'ün `rangeNoNight` endişesi ölçümle
   çürütüldü: anahtar Tur 12'de (`91439a3`) **zaten silinmişti**, bu turun
   başında mevcut değildi. 63 ölünün **59'u `public/locales/*` altında
   canlı** (React PWA çalışma zamanı kaynağı) → silinemez. Yalnız 4'ü
   Flutter'a özgüydü; 3'ü kanıtlanıp silindi (525 → 522 anahtar),
   1'i gerekçeli korundu.
2. **`check_i18n.cjs`'e 3 yeni hata kapısı** (çevrilmemiş kopya, satır
   sonu tutarlılığı, ayraç dengesi) + "aynı metnin bir kopyası çevrilmiş,
   diğeri çevrilmemiş" kapısı. Bulunan **gerçek** hatalar: `it`/`ru`
   `notificationTypes.email` çevrilmemişti, `ja`/`ko`
   `about.footer.copyright` İngilizce kalmıştı. ⭐ **"Kırpılmış cümle"
   kapısı 4 tasarım denendi, 302 yanlış pozitif ölçüldü, YAZILMADI.**
3. **`supabase/tests/*.sql` artık CI'da** (A1r5/A1r8/A1r10'un üç kez
   raporladığı boşluk). "supabase start gerekiyor" gerekçesi **ölçümle
   çürütüldü**: ihtiyaç iki şema + üç rol. `auth_shim.sql` +
   `storage_shim.sql` + `run_sql_tests.sh` ile stock `postgres:16`'da
   19 migration, `full_setup` 3× ve 5 SQL testi koşuyor.
4. **P0 — `paths:` kapsam denetimi.** 3 workflow'un **kendi girdileri**
   path listeleriyle karşılaştırıldı. **`.env.example` hiçbir workflow'ta
   tetiklemiyordu** ama `flutter.yml` `cp .env.example .env` ile asset
   paketlemesi yapıyor → bozulunca **her iki** Flutter işi kırılıyor,
   PR'da görünmüyordu. `README.md`/`README_EN.md` ve
   `public/locales/**` de eksikti.
5. **⭐ En değerli bulgu: koşu sırası hatayı sessizce onarıyordu.**
   BOLA enjeksiyonu (`USING (true)`) iki denemede **yeşil** kaldı. Nedeni
   test değil, harness: `full_setup.sql` politikaları yeniden yazıyor ve
   şablon üzerinde 3× çalıştırılıyordu. Elle koşulunca "48/1 başarısız"
   verdi. Düzeltildi → aynı enjeksiyon kırmızı verdi.

---

## Düzeltilenler

| Sev | Dosya | Ne yapıldı | Doğrulama |
|-----|-------|-----------|-----------|
| P2 | `tool/check_i18n.cjs` | Ratchet 63→60 + 3 yeni kapı (4f1/4f3/4f4) + 4g | 522 anahtar, 60/60; negatif ölçüm 4/4 |
| P2 | `tool/remove_dead_i18n_keys.cjs` *(yeni)* | 3 kanıtlanmış ölü anahtarı 12 dilden siler | `check_i18n` yeşil |
| P1 | `translations/{it,ru,ja,ko}.json` | 4 gerçek çeviri hatası düzeltildi | yeni kapı artık kırmızı vermiyor |
| **P0** | `.github/workflows/supabase.yml` | **`sql` job**: 5 SQL testi CI'da | 19 mig · full_setup 3× · RLS 49/49 |
| **P0** | `.github/workflows/flutter.yml` | `paths` +`.env.example`, `README*.md`, `public/locales/**` | kapsam denetimi ✓ |
| P0 | `.github/workflows/react.yml` | `paths` +`.env.example`, `README*.md` | kapsam denetimi ✓ |
| P0 | `tool/run_sql_tests.sh` *(yeni)* | Harness; ⭐ **koşu sırası hatası düzeltildi** | BOLA enjeksiyonu artık kırmızı |
| P1 | `supabase/tests/auth_shim.sql` *(yeni)* | `auth.users`/`uid()`/`role()` + 3 rol | 19 mig sıfırdan |
| P1 | `supabase/tests/storage_shim.sql` *(yeni)* | `storage.buckets`/`objects`/`foldername()` | 19 mig sıfırdan |
| P1 | `CHANGELOG.md` | Tur 6-13 (+236 satır), koşu sırası kaydı | `check_versions` yeşil |
| P1 | `README.md` / `README_EN.md` | Widget, hesap silme, favori, sunucu bildirim, **Vault**, **`pg_cron`** | her satır koda karşı doğrulandı |
| P2 | `plans/analiz-26-09-27/00-INDeks.md` *(yeni)* | Dizin indeksi + 8 turlar-arasi ders | — |

---

## ⭐ Görev 1 — Orphan ratchet: ölçüm ve karar

**Ölçüm (tur başı):** 63 ölü / 63 baseline → **değişmedi**.

**A2r13'ün notu doğrulandı:** `settings.notifications.server.rangeNoNight`
artık **mevcut değil** — `git log -S` ile bulundu: `91439a3` (Tur 12,
A2r12) gece aralığını açarken **12 dilden de silmiş**. Bu turun başında
`grep -rn rangeNoNight flutter_app/assets/` → 0 eşleşme. Dolayısıyla
ratchet'i değiştirecek bir *artış* yoktu.

**Ayrıntılandırma (63 ölünün dağılımı):** `public/locales/en/translation.json`
ile karşılaştırıldı → **59'u React PWA'nın çalışma zamanı kaynağında hâlâ
var** (silinemez), yalnız **4'ü** Flutter'a özgü:

| Anahtar | Kanıt | Karar |
|---------|-------|-------|
| `server.goalAchieved` | `server_notification_preferences_section.dart:72` **açıkça** dışlıyor: "goalAchieved bilinçli olarak yok (A4r10, ürün kararı 2-B)" | **Silindi** |
| `server.serverScope` | `channelNote` ile **aynı cümleyi** söylüyor; ikisi de hiç bağlanmamış, `channelNote` koda bağlı | **Silindi** (`channelNote` kaldı) |
| `dialogs.fiberG` | `food.dart:14` alan var ama **hiçbir ekranda gösterilmiyor**; `grep dialogs.fiberG` → 0 | **Silindi** |
| `settings.widgets.androidOnly` | 1.3.0 widget'ının ileride kullanılacak uyarı metni | **Korundu** (gerekçeli) |

**Karar: 63 → 60.** Görev "azaldıysa ratchet'i düşür, gevşek kapı bırakma"
diyordu; 3 anahtar silindiği için düşürüldü. 525 → 522 anahtar.

---

## Görev 2 — `check_i18n` yeni kapıları

| Kapı | Ne yakalar | Bulgu | Negatif ölçüm |
|------|-----------|-------|---------------|
| **4f1** çevrilmemiş kopya | Hedef dilin değeri `en.json` ile birebir | `it`/`ru` `notificationTypes.email`, `ja`/`ko` copyright | ✅ `de settings.deleteAccount.title = en` → kırmızı |
| **4f3** satır sonu sayısı | `\n` bir dilde var, başka dilde yok | 0 | ✅ `de common.healthDisclaimer` + `\n` → kırmızı |
| **4f4** ayraç dengesi | `(`/`[` sayısı ≠ `)`/`]` sayısı | 0 | ✅ `de "Kein (Problem"` → kırmızı |
| **4g** kısmi çeviri | Aynı metnin bir kopyası çevrilmiş, diğeri çevrilmemiş | **`it`/`ru` "Email"** | ✅ `fr notificationTypes.email = 'Email'` → kırmızı |
| **4f2** kırpılmış cümle | — | ⭐ **YAZILMADI** | 4 tasarım elendi |

### ⭐ 4f2 neden yazılmadı (4 deneme, 302 yanlış pozitif)

| # | Kural | Sonuç |
|---|-------|-------|
| 1 | "İngilizce `.!?` ile bitiyorsa hedef dil de bitirmeli" | **52** eşleşme, hepsi CJK (`ja`/`zh`) yazım sistemi |
| 2 | "Son kelime İngilizceyle aynıysa kesilmiştir" | **0** bulgu — gerçek kesilmede son kelime **çevrilmiştir** ("kurtarılamaz" ↔ "recovered"); kural hatayı **ters yönde** kaçırıyordu |
| 3 | "Bağlaç/zarf ile bitiyorsa yarım cümlüdür" | **18** eşleşme, hepsi gürültü: "Yeniden kontrol et" (TR bitiş fiili), "Acerca de" (ES başlık), "Gib dein Passwort ein" (DE tam emir cümlesi) |
| 4 | "40+ karakter, İngilizcenin %60'ı, noktalama yok → uyarı" | **232** uyarı; `--verbose` listesini kullanılamaz hâle getirdi |

**Sonuç:** cümle noktalaması eksikliği **tek başına bir dil kuralıdır**
(etiket, başlık ve bitiş fiili noktalamasız biter) ve sözlüksüz hiçbir
kural onu güvenilir kılamaz. Kesilmenin **yapısal** kanıtı kapanmamış
ayraçtır ve o zaten 4f4'te denetleniyor. Gerekçe kodda yazılı.

### 4f1 istisna listesi — kognatlar

`UNTRANSLATED_OK`'e alınan 5 anahtarın **2'si gerçek hataydı**
(düzeltildi), 3'ü kanıtlanmış kognat/marka:
- `de auth.nameOptional` = "Name (Optional)" → Almanca'da isim **"Name"**'dir
  (`auth.name` de "Name"). Yanlış pozitif.
- `fr settings.goals.calories` = "Calories (kcal)" → Fransızca'da calorie
  kelimesi **"Calories"** yazılır. Yanlış pozitif.
- `about.footer.copyright` / `chat.roleAssistant` / `about.version` → marka.

**Uyarı sayısı taban değerinde:** 72 → 70 (3 silinen anahtar). Yeni
kapılar gürültü **eklemiyor**.

### Tarih/saat formatı istisnası — hâlâ geçerli mi? **EVET**

İki çağrı, ikisi de meşru:
- `personal_info_dialog.dart:147` `DateFormat('yyyy-MM-dd')` → `profiles.birth_date`
  (DATE kolonu) **makine biçimi**. Bağlam denetimi (yazma/DB kolonu) ile muaf.
- `analytics_repository.dart:268` `DateFormat('d MMM', locale)` → **locale'lu**,
  kullanıcı diline bağlı. Meşru.

Denetim yeniden yazılmadı; iki istisna da ölçülerek doğrulandı.

---

## ⭐ Görev 3 — CI kapsam denetimi

### P0 — `paths:` boşlukları (4 bulgu, düzeltildi)

Her workflow'un **kendi tükettiği dosyalar** path listesiyle karşılaştırıldı
(elle + `fnmatch` betiği). **P0 bulgular:**

| # | Dosya | Hangi iş tüketiyor | Etki |
|---|-------|--------------------|------|
| 1 | **`.env.example`** | `flutter.yml:109` ve `:224` → `cp .env.example .env` | ⭐ **hiçbir workflow'ta tetiklemiyordu.** `.env` gitignore'da ama pubspec'te asset olarak paketleniyor; dosya bozulursa/anahtar kaybolursa **her iki** Flutter işi "unable to find directory entry" ile kırılır — **PR'da hiç görünmez** |
| 2 | **`README.md` / `README_EN.md`** | `check_versions.cjs:752` yayın talimatındaki sürüm örneğini okur | Sürüm kayması kapıyı kırmalı ama tetiklenmiyordu |
| 3 | **`public/locales/**`** | `check_i18n.cjs` orphan sınıflandırması bu kaynağı okur | `react.yml`'de vardı, `flutter.yml`'de yoktu |
| 4 | `tool/run_sql_tests.sh` *(yeni)* | `supabase.yml` `sql` job'ı | Harness değişirse koşmazdı |

Doğrulama: `flutter.yml` 8, `react.yml` 17, `supabase.yml` 3 path →
**"✓ TÜM workflow kapsamı tam"**.

### ⭐ `supabase/tests/*.sql` — 3 kez raporlanan boşluk KAPANDI

**"Kurulamıyor" gerekçesi yanlıştı; ölçüldü.** Repo'nun Supabase'den
ihtiyaç duyduğu yüzey (`grep -o "auth\.[a-zA-Z_.]*"` ve `storage\.`):

- `auth.users` (id/email/raw_user_meta_data), `auth.uid()`, `auth.role()`
- `storage.buckets`, `storage.objects`, `storage.foldername()`
- `cron`/`net`/`vault` → **zaten** `tests/a1r10_cron_shim.sql` vardı
- roller `anon`/`authenticated`/`service_role` → Supabase DB kurulumunda
  yaratır, migration'lar değil

→ `supabase start` **gerekmiyor**. Stock `postgres:16` + 2 yeni shim yeterli.
Sonuç: **19 migration 0 hata · full_setup 3× 0 hata · RLS 49/49 ·
CHECK 58 deneme · şema sözleşmesi 16 tablo/14 FK · 5/5 test geçti.**

**Test izolasyonu (zorunlu kılındı):** `rls_policies.sql`
`public.cx_test_result` tablosunu kurup dosya sonunda düşürüyor; ortada
başarısız olunca tablo kalıyor ve `schema_contract.sql`
"KALDI: semada yok: cx_test_result" deyip **kendine özgü olmayan** hatayla
düşüyordu. Artık her test **kendi taze veritabanında**.

### ⭐⭐ Koşu sırası hatası (en pahalı bulgu)

BOLA enjeksiyonu (`meal_entries` SELECT → `USING (true)`, yani kullanıcı
başkasının öğünlerini okuyabilir) **üç denemede yeşil** kaldı.

| Deneme | Sonuç |
|--------|-------|
| Migration'ın ilk yazan dalını boz | yeşil — `full_setup.sql` `CREATE TABLE IF NOT EXISTS` olduğu için sonraki adım onu **düzeltiyor** |
| `full_setup.sql`'i boz | yeşil — migration yolu **düzeltiyor** |
| **Son yazan migration** (`20260927120000`) | **yine yeşil** |
| **Elle koşum** (full_setup çalıştırılmadan) | ⭐ **`48 test / 1 basarisiz`**, `[KALDI] A yalnizca kendi meal kaydini gorur -- gorulen: 2` |

**Neden:** `full_setup.sql` `DROP POLICY IF EXISTS` + `CREATE POLICY` ile
politikaları **yeniden yazıyor**. Harness bu 3× idempotans doğrulamasını
**doğrudan şablon veritabanında** çalıştırıyordu → migration yolundaki
regresyon sessizce onarılıyordu.

**Düzeltme:** idempotans doğrulaması **ayrı bir veritabanına** taşındı.
Sonrasında aynı BOLA enjeksiyonu `48 test / 1 basarisiz` ile **kırmızı**
verdi, harness exit 1 ile durdu. Enjeksiyon geri alındı, 49/49 yeşil.

> **Ders:** hata testte değil, **testi çalıştıran kodda**ydı. Yeşil sonuç
> "regresyon yok" değil, "regresyon **ölçülmedi**" demektir. Bu, 13 turdaki
> 8. vaka ve ilk kez kapının kendisinin kusurlu olduğu örnek.

### Diğer CI doğrulamaları
- `flutter build apk --debug` → **✓ Built** , **56 sn** (soğuk Kotlin
  önbelleği; A6r2'nin 33 sn'i warm cache ölçümüydü).
- Action SHA pinleri: 3 workflow'ta da `40 haneli` (A6r3'ün işi, güncel).
- `permissions: contents: read` → 3 workflow'ta da.
- `timeout-minutes`: edge 15 · flutter check 35 · build 45 · react 20 ·
  **sql 20** (yeni).
- `deno check/test --frozen=true` → güncel, `supabase/deno.lock` takipte.

---

## Görev 4 — CHANGELOG + dokümantasyon

### CHANGELOG'da eksik olanlar
`[Unreleased]` bölümü **Tur 3'te bitiyordu**; Tur 6-13'ün düzeltmeleri
**hiç yazılmamıştı**. Yeni `[Unreleased — Tur 6-13]` bölümü (+236 satır):

| Başlık | Eksikti |
|--------|---------|
| Güvenlik | widget tazeleme P0, push RFC 8291, **3993-4058 off-by-one**, chat `TO public`, full_setup parite+idempotans, 13 CHECK, `foods.created_by` CASCADE (KVKK), kısmi silme "başarı", rate limit tablosu, VAPID imzası |
| Çalışmayan özellikler | `recognize-food` derlenmiyordu, VAPID imzası yoktu, **widget'in native tarafı hiç yazılmamıştı** (`workmanager` 0 referans → kaldırıldı), **`cron.schedule` 4 tur yoktu** |
| Veri bozulması | yedek→geri yüklemede favori/son kullanılan/bildirim tercihleri **kayboluyordu**, kısmi import, `nova_score` sayaç değeri, su kaydı iki kez, 4506 → 37 istek |
| Hesap hataları | `bmi(70,-180)`, `activity_level` (**TDEE %18,4 eksik**), `Gender.other` 166 kcal, `progress` koruması **HİÇ çağrılmıyordu** |
| Sessiz kayıplar | bildirimler UTC (**TR'de 3 saat kaymış**), ilk açılışta planlamama, tam alarm izni, master anahtar gölgelenmesi, tartılma sıklığı 0, web `try/catch` **hiç çalışmıyordu**, UTC gün kaçıklığı |
| Yeni özellik | hesap silme arayüzü, favoriler, sunucu bildirim tercihleri, gıda silme arayüzü, gece aralığı 21→09 |

**Abartma kontrolü:** her madde `git log` ile eşleştirildi; düzeltmediğimiz
hiçbir şey yazılmadı. `workmanager` kaldırma ve `photo_url` kararı
"do nothing" olduğu için düzeltme gibi yazılmadı.

### README / README_EN — 5 konu eksikti (hepsi eklendi)
| Konu | Durum |
|------|-------|
| Widget | Yalnız 1 satır geçiyordu → özellik tablosuna alındı |
| Hesap silme | **hiç yok** → eklendi (KVKK, iki aşamalı onay) |
| Favoriler / sunucu bildirim tercihleri | **hiç yok** → eklendi |
| **Vault** (`INTERNAL_FUNCTION_TOKEN`) | **hiç yok** → eklendi: neden **iki yere** yazılır, yazılmazsa ne olur |
| **`pg_cron`** job kurulumu | **hiç yok** → eklendi: 5 adım, hangi `SELECT` ne dönmeli, yönetilen uzantı notu |

Her README iddiası **koda karşı doğrulandı**:
`delete_account_dialog.dart`, `add_from_food_dialog.dart`,
`kotlin/com/calorix/calorix/widget/{Daily,Weekly}WidgetProvider.kt`.

---

## Görev 5 — Düzenleyici kökü: **(a) HEPSİ KALSIN** + indeks

45 dosya / 884 KB. Karar: **silme, indeksle**.

**Neden (a):**
1. Raporlar **kanıt zinciridir, günlük değil**. `RAPOR-A4r3` bir iddiayı
   test edip yeşil kaldığını görüp düzeltmeyi **geri aldığını** yazıyor;
   `RAPOR-A2r13` kendi varsayımının yanlış olduğunu kabul ediyor. Bu
   tür kayıtler ancak yazılı kalırsa "bu kararı neden verdik?" cevaplanır.
2. `CHANGELOG.md`'deki her madde bir rapora dayanıyor; rapor silinirse
   changelog'ın "neden" kısmı havada kalır.
3. **Silmek geri alınamaz, taşımak ucuz.**
4. Görevin korunmasını istediği 5 dosya, raporların **atıf yaptığı**
   nesneler.

**Neden "hiç dokunma" da değil:** 45 dosya düz klasörde aranamaz.
`00-INDeks.md` eklendi: kalıcı kayıt ↔ tur günlüğü ayrımı, tur sırasıyla
indeks, ve **13 turda biriken 8 ders** tek yerde (kanıtsız index,
`WITH CHECK` fallback, reçete yazma, tarih sabitlerini testle doğrula,
"yeşilse iddiayı bırak", kanıtsız kural yazma…).

`PROTOKOL.md`, `OZET-tur*.md`, `TRANSFER-defteri.md`, `URUN-KARARLARI.md`,
`DONGULU-DURUM.md` **dokunulmadı**.

---

## ⭐ Negatif ölçüm — "etkin test" kanıtı

| Kapı | Enjeksiyon | Gözlem | Sonuç |
|------|-----------|--------|-------|
| 4f1 | `de settings.deleteAccount.title = en değeri` | `✗ de.json: çevrilmemiş — en.json ile birebir aynı` | ✅ kırmızı |
| 4f3 | `de common.healthDisclaimer` + `\n` | `✗ satır sonu sayısı diller arasında farklı` | ✅ kırmızı |
| 4f4 | `de "Kein (Problem"` | `✗ parantez dengesi bozuk ((×1, )×0)` | ✅ kırmızı |
| 4g | `fr notificationTypes.email = 'Email'` | `✗ aynı metnin bir kopyası çevrilmiş, diğeri çevrilmemiş` | ✅ kırmızı |
| SQL / CASCADE | `foods.created_by` CASCADE → SET NULL | `✗ 3 SQL testi BAŞARISIZ` + `[KALDI] foods.created_by ON DELETE CASCADE (3-A) -- confdeltype=n` | ✅ kırmızı |
| SQL / BOLA | `meal_entries` SELECT → `USING (true)` | **ilk 3 deneme yeşil** → sonra `✗ rls_policies.sql BAŞARISIZ`, `48 test / 1 basarisiz` | ✅ kırmızı (koşu sırası hatası düzeltildikten sonra) |

**Etkin test kanıtı — iki yönlü kontrol:**
- **Pozitif:** `rls_policies.sql` "49 test / 0 başarısız" raporluyor.
- **Negatif:** BOLA enjeksiyonuyla **"48 test / 1 başarısız"** + `[KALDI]
  A yalnizca kendi meal kaydini gorur -- görülen: 2` (elle ve harness ile).
  Yani test gerçekten **çalışıyor** ve hatayı **adıyla** söylüyor.

---

## Doğrulama kapıları (tümü yeşil)

| Komut | Sonuç |
|-------|-------|
| `flutter analyze` | **No issues found!** (5.8 s) |
| `flutter test` | **1156 test geçti** (0:53) — tabanla birebir |
| `node tool/check_i18n.cjs` | ✓ 12 dil · **522** anahtar · ölü **60/60** · uyarı 70 |
| `node tool/check_versions.cjs` | ✓ 1.3.0+4 tutarlı |
| `npm run build` | ✓ built in 16.70 s |
| `npm run lint` | 0 hata, 10 uyarı (eşik 25) |
| `npx tsc -p tsconfig.app.json --noEmit` | **exit 0** |
| `deno check --frozen=true` | 0 hata |
| `deno test --frozen=true` | **164 passed / 0 failed / 1 ignored** |
| `bash tool/run_sql_tests.sh` | **5/5 SQL testi** · 19 mig · full_setup 3× |
| `flutter build apk --debug` | ✓ Built (56 s) |
| Workflow YAML ×3 | ✓ `yaml.safe_load` |
| `paths` kapsam denetimi | ✓ 3/3 tam |

---

## AKTARIM (başka alana)

| Sev | Konu | Alan |
|-----|------|------|
| P2 | `check_i18n` 4f2 için "kırpılmış cümle" kapısı yazılamıyor; 4 denemede 302 FP ölçüldü. Doğru çözüm **dillere özgü** (Locale/CLDR tabanlı) bir sözlük ya da çeviri sürecine teslim. | i18n / A6 sonraki tur |
| P2 | `auth_shim` + `storage_shim` **test koşul sağlayıcısıdır**, GoTrue/Storage değildir. Canlıya doğrulama yapılamaz; Supabase tarafında `auth.admin` davranışı hâlâ test edilmemiş. | supabase |
| P3 | `pg_cron` **gerçek zamanlayıcı tetiklemesi** stock Postgres'te test edilemez; yalnız tanım + gövde doğrulanıyor. | operasyon |
| P3 | `run_sql_tests.sh` harness'ta `pg_cron`/`pg_net` `CREATE EXTENSION` satırları `sed` ile devre dışı bırakılıyor. Gerekçeli ama gizli değil — dosyada ve workflow'ta yazılı. | — |
| P3 | `full_setup.sql` politikaları yeniden yazıyor; yeni politika migration'a eklenirken `full_setup`'e de eklenmezse iki yol ayrışır. A1'ın parite `diff` kontrolü yakalar ama **CI'da yok**. | supabase / A1 |

## Kalan riskler
1. **SQL testleri artık CI'da ama `supabase start` yerine shim kullanıyor.**
   GoTrue/Storage'nin gerçek davranışı (parola, oturum, OAuth) test
   edilmiyor — testlerin konusu RLS ve FK zinciri olduğu için kabul edildi,
   ama bu **bilinçli** bir kapsam sınırı.
2. **`sql` job'ı Docker gerektiriyor.** `ubuntu-latest`'ta mevcut, ancak
   `postgres:16` imajının ~380 MB çekilmesi ilk koşuda ek süre verir.
3. **4f1 istisna listesi (`UNTRANSLATED_OK`) elle bakım gerektiriyor.**
   Yeni bir kognat eklendiğinde kapı sessizce kırmızıya döner — bu
   istenen davranış, ama liste büyürse gürültü olur.
4. **Kognat tespiti gözle yapıldı.** 5 istisnanın her biri ayrı ayrı
   ölçüldü ama "dilbilimci gözü" gerektiriyor; otomatikleştirilmedi.
5. **`full_setup.sql` ↔ migration paritesi CI'da denetlenmiyor.**
   A1'ın yerel `diff` kontrolü var, iş değil.