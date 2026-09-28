# RAPOR — A5r10 (web bildirim tercihleri) — 2026-09-28 — Tur 11

Alan: `src/**` · `tool/**` · `public/locales/**` · `CHANGELOG.md` · `package.json`
Dokunulmadı: `flutter_app/**` (yalnızca **okundu**), `supabase/**` (yalnızca okundu), `.github/**`, `plans/**`

## Özet

1. **P1-1 kanıtlandı ve düzeltildi.** `useNotifications` `interval_hours: 0`
   yazıyordu → DB CHECK reddi → web'de sunucu bildirim tercihi **kaydedilemiyordu**.
2. **P1-2 düzeltildi (istemci tarafı AND).** `saveNotifications` **ölü koddu** —
   hiçbir yerden çağrılmıyordu, yani profil master anahtarları hiç yazılmıyordu ve
   "her tip için satır yaz" davranışı hiç tetiklenmiyordu.
3. **P3 kapandı.** Web PWA'da hesap silme giriş noktası eklendi (KVKK/Play).
4. ⭐ **Negatif ölçüm ilk test yazımımda bir "yanlış yeşil" buldu** ve düzeltildi
   (A4r7b tuzağıyla aynı sınıf).
5. Tüm kapılar yeşil: build ✓ · lint **0 hata** · tsc exit 0 · **113 → 142 test** ·
   `check_i18n` ✓ · `check_versions` ✓.

---

## P1-1 — `interval_hours` kaydı düzeltildi

### Kanıt zinciri

| Kaynak | Değer |
|---|---|
| `src/hooks/useNotifications.ts:30-33` (eski) | `interval_hours: 0` (3 tipte) |
| `supabase/full_setup.sql:828-831` | `interval_hours BETWEEN 1 AND 24` |
| `migrations/20260927120000_...sql:418-422` | aynı CHECK (migration'da doğrulandı) |

Test bunu **migration dosyasını okuyarak** sabitler: CHECK metni kaybolursa
kapsam sabitleri güncellenmek zorunda kalır (sabit yanlış kalıp testlerin
boşa yeşil kalması engellenir).

### Flutter ile birebir hizalama

Kaynak: `flutter_app/lib/data/repositories/notification_preferences_repository.dart`

| Flutter | Web karşılığı |
|---|---|
| `_clamp` (:208-209) | `clampInt` |
| `toRow` (:179-206) | `buildPreferenceRow` / `normalizePreference` |
| `applyMasterSwitches` (:320-332) | `applyMasterSwitches` |
| `_asInt` (:220-228) | `clampInt` (`Number(value)` — metin de kabul) |
| `defaultServerPreference` (:72-123) | `NOTIFICATION_DEFAULTS` |

Varsayılan tablosu beş tip için **sayı sayı** eşitliğiyle testte sabitlendi
(`P1-1: Flutter varsayılanlarıyla birebir`).

### ⭐ Ölçüm sırasında bulunan yanlış beklentim

İlk test yazımımda `interval_hours: 0 → 1` bekliyordum ("aralık tabanına
çek"). Test **kırmızı** döndü ve doğrusu şu çıktı: Flutter'ın `_clamp(v,1,24,3)`
değeri `3`'e düşer (fallback), `1` değil. Yani *varsayılan tablosundaki* `1`
değerleri korunur, *kullanıcının 0 girdisi* ise `3`'e normalize edilir.
İki kavram karıştırılmış; beklenti düzeltildi ve gerekçe teste yazıldı.

### `start > end`

A4r4b'nin Flutter'da bulduğu ikinci hata web'de de vardı:
`check-reminders/index.ts:356` koşulu `start <= hour <= end`; `start > end`
**hiçbir saatte** sağlanmaz → hatırlatma sessizce hiç gönderilmez. `normalizePreference`
`end`'i 23'e çeker. 24×24 = 576 kombinasyonluk fuzz testi eklendi.

### Okuma tarafı

`fetchPreferences` artık `existing` satırı **normalize** ederek gösteriyor
(kolonlar nullable, `null` = "sunucu varsayılanı"). Yedek içe aktarım
(`useDataExport`) da aynı katmanı kullanıyor.

---

## `summary_day` 0 = Pazar — üç yerden teyit

| Kaynak | Kanıt |
|---|---|
| `check-reminders/helpers.ts:70-78` `WEEKDAY_INDEX` | `{Sun:0, Mon:1, …, Sat:6}` |
| `check-reminders/index.ts:484` | `dayOfWeek === summaryDay` |
| `full_setup.sql:831` | `summary_day BETWEEN 0 AND 6` |

**Web'de hafta günü üretilmiyor** — `grep` ölçümü: `summary_day` yalnızca
`NotificationPreferences.tsx:140/143/161` (kullanıcı seçimi) ve tip
tanımında geçiyor; `Date#getDay()`/`toISOString` deseni **yok**.

Yine de iki kapı koydum:
1. `WEEKDAY_OPTIONS` değerleri `[0..6]`, ilk etiket `Pazar` — sunucu diziniyle birebir.
2. `weekdayIndexFor` yardımcısı JS `getDay()` ile sunucu `WEEKDAY_INDEX`'ini
   **gerçek tarihlerle** karşılaştırır (7 gün, `Intl` `en-US` kısaltmaları).
   `2024-01-07` = Pazar (0), `2024-01-08` = Pazartesi (1) — A4r7b'nin
   gözle seçip **bir gün kaydırdığı** ve düzelttiği tarihler.

---

## P1-2 — master anahtar gölgelenmesi

### ⭐ Ek bulgu: `saveNotifications` **ölü koddu**

`grep saveNotifications src/` → yalnızca **tanım** (`SettingsPage.tsx:303`).
Hiçbir yerden çağrılmıyordu. Bu, P1-2'nin web tarafındaki asıl nedenidir:

- `pushEnabled` / `emailEnabled` state'leri **okunuyor ama hiç gösterilmiyordu**
  ve hiçbir yere yazılmıyordu → `profiles.push_notifications_enabled` DB'de
  `DEFAULT true` kalıyordu.
- "Her tip için satır yaz" davranışı hiç tetiklenmiyordu; `NotificationPreferences`
  her anahtarı ayrı `updatePreference` ile yazıyordu, yani
  `notification_preferences`'ta **hiç** satırı olmayan
  `water`/`daily_log`/`weekly_summary` için `check-reminders`'ın sessiz-kapalı
  davranışı hiç değişmiyordu.

### Düzeltme

1. Diyaloga iki master anahtarı eklendi (Push / E-posta) + "Kaydet" düğmesi.
2. `saveNotifications` artık **çağrılıyor**: profil yazar **ve**
   `saveAllPreferences` ile beş tipin de satırını yazar.
3. `saveAllPreferences` `applyMasterSwitches` uygular → **master `false` iken
   hiçbir satır `true` yazamaz** (AND). `updatePreference`'a da isteğe bağlı
   `master` parametresi eklendi.
4. `applyMasterSwitches` girdiyi **mutasyona uğratmaz** (kopya döner) —
   testte sabitlendi.

### ⭐ Aktarım (sunucu alanı — dokunulmadı)

`supabase/functions/send-notification/index.ts:423-424` hâlâ `??` okuyor.
İstemci AND'i doğru davranışı garanti eder, ama **sunucu tarafı savunmasız**:
başka bir istemci (ya da elle yazılmış bir satır) master'ı gölgeleyebilir.
`applyMasterSwitches` mantığı `send-notification`'a da eklenmeli
(A1/A2 alanı). Test, sunucu satırının değiştiğini izleyip
"istemci AND'i gereksizse güncelle" diye uyarır.

---

## P3 — Hesap silme giriş noktası

| Katman | Dosya |
|---|---|
| Saf sözleşme (hata sınıflandırması) | `src/lib/accountDeletion.ts` |
| Edge function çağrısı | `src/hooks/useAccountDeletion.ts` |
| Arayüz | `src/components/account/DeleteAccountDialog.tsx` |
| Giriş noktası | `src/pages/SettingsPage.tsx` — Hesap bölümü, Çıkış'ın altında |

Flutter `AccountRepository` ile birebir hizalama:
`wrongPassword` / `unauthorized` / `rateLimited` / `invalidRequest` / `network` /
`unknown`, `maxPasswordLength = 256`, `partial ≠ başarı`, 401'in iki sabit
mesajı (`"Parola hatalı"` vs `"Yetkisiz"`), boş parola **gönderilmez** (2/saat
kotası), hatalı parolada alan temizlenir.

**Güvenlik testi:** `AccountDeletionError` parolayı **hiçbir koşulda**
taşımıyor (`message` sabit). Test `String(err)` + `JSON.stringify` + `stack`
içinde parola arıyor — bir sınıf hatası olsaydı kırmızı olurdu.

⚠️ **Elle `fetch` kullanılmadı**: `readJsonBody` yalnızca `application/json`
kabul ediyor (`text/plain` → 415) ve `Authorization` JWT'sini elle taşımak
token sızıntısı riski. `functions.invoke` ikisini de kendisi ekliyor.
Non-2xx'te `FunctionsHttpError` **fırlatmaz**; `{error, response}` döner ve
gövde `response.json()`'dan okunur (ağ hatasında `status: 0` → `network`).

---

## ⭐ Negatif test ölçümü — "yeşil test ≠ etkin test"

A4r7b'nin `tester.tap` tuzağı (etkileşim gerçekleşmiyor, test hiçbir şey
ölçmüyor) web testlerinde de yakalandı:

| # | Geri alınan düzeltme | Sonuç |
|---|---|---|
| 1 | `NOTIFICATION_DEFAULTS` → `interval_hours: 0` (eski hata) | İlk yazımda **yeşil kaldı** ⭐ |
| 2 | `applyMasterSwitches` çağrısı kaldırıldı | 🔴 `saveAllPreferences içinde applyMasterSwitches çağrısı yok` |
| 3 | `setDeleteAccountOpen(true)` giriş noktası kaldırıldı | 🔴 `hesap silme girdi noktası bağlı değil` |
| 1' | (düzeltilmiş haliyle tekrar) | 🔴 `weigh_in varsayılan interval_hours=0 → CHECK'i reddeder` |

**#1'in anatomisi:** İlk test, varsayılanları `buildPreferenceRow`'dan geçirip
**sonucu** denetliyordu. `buildPreferenceRow` `0`'ı `3`'e çevirdiği için
`interval_hours: 0` yazan tabloyla bile yeşildi — **test hatanın kendisini
gizleyen katmandan geçiriyordu**. Düzeltme: **ham (normalize edilmemiş)**
sayı doğrudan denetleniyor + normalize sürümüyle **aynı olması** da
ayrıca doğrulanıyor (geçerli bir varsayılan sessizce dönüştürülmemeli).

### "Etkin test" için ek kanıtlar

- Varsayılan tablosu testte **kopyalanmıyor**, `useNotifications.ts`
  dosyasından **okunup ayrıştırılıyor** → iki kopyanın ayrışması kırmızı.
- Ölü import tuzağına karşı: import satırı değil, `applyMasterSwitches(...)`
  **çağrısının** ikinci argümanı (`master`) ve sonucun `upsert`'e akması aranıyor.
- Ölü kod tuzağına karşı: `onClick={saveNotifications}` **ve**
  `setDeleteAccountOpen(true)` **ve** `<DeleteAccountDialog open=…>` varlığı
  ayrı ayrı doğrulanıyor (turda bulduğum `saveNotifications` ölü kod hatası
  bu kapı sayesinde kalıcı).
- Etkileşim ölçümü: hook/DB katmanı jsdom gerektiriyor (A5r8'in kalan riski
  aynen geçerli), bu yüzden "etkinlik" **kaynak denetimi** ve
  **saf-katman** üzerinden ölçülüyor; iki etkileşim noktası da kırmızıya
  döndüğü ölçüldü (yukarıda #2, #3).

---

## Yeni testler — `tool/test_notification_preferences.mjs` (29 test)

| Blok | Test |
|---|---|
| Denetim (4) | varsayılan tablosu kaynaktan okunur · CHECK aralıkları migration'dan · `WEEKDAY_INDEX` sunucuyla aynı · `weekdayIndexFor` 7 gün ölçümü |
| P1-1 (5) | `0 → 3` · tüm tiplerde `0` asla çıkmaz · `normalizePreference` de üretmiyor · **ham** varsayılan tablosu · Flutter paritesi |
| P1-2 (5) | master `false` → hiçbir satır `true` değil · master `true` tip bazlı kapatmayı korur · kanal izolasyonu · mutasyon yok · **kaynak denetimi** (ölü import koruması) |
| Saat aralığı (2) | `start > end → 23` · 576 kombinasyonluk fuzz |
| `clampInt` (1) | aralık içi/dışı/`NaN`/metin/tam sayı |
| P3 (6) | 401 iki mesaj · 429/4xx/5xx/ağ · **parola sızıntısı yok** · boş/uzun parola · `partial ≠ başarı` · sözleşme dışı 200 · `errorMessageFrom` |
| Bağlantı (3) | giriş noktası bağlı · oturum düşürme · 27 i18n anahtarı iki istemcide senkron |
| Etkinlik (1) | eski hata yeniden üretilirse kırmızı |

Toplam: **113 → 142 test, 142 geçiyor.**

---

## Çeviri etkisi

- **`public/locales/**` 12 dosya** güncellendi (+27 anahtar).
  `settings.notifications.{push,email}`, `.server.channelNote`,
  `settings.deleteAccount.*` Flutter tarafında **zaten vardı** (A4r4b/A4r7);
  web tarafında yoktu → i18next `fallbackLng: 'en'` ile sessizce İngilizce
  dönerdi.
- **`flutter_app/assets/translations/**` dokunulmadı** (alan sahipliği):
  27 anahtar orada zaten tamdı → senkron **korunuyor**.
- Kaynak: `tool/sync_locales_once.cjs` (idempotent, yalnızca eksik anahtarı
  kopyalar, hiçbir şey silmez). `convert_locales.cjs`'in **ters yönlü**
  çalıştığını (Flutter'ın 152 ek anahtarını sessizce sildiğini) not düştüm;
  o yüzden kullanılmadı. `--dry-run` ile doğrulandı.
- 12 dilin tamamında aynı metin kopyalandı (test `en` üzerinden metin
  eşitliğini doğruluyor).
- `check_i18n` ✓ — 523 anahtar, ölü orphan 63/63 (baseline aynı), React
  canlı 67 → **69** (yeni `t('settings.deleteAccount.*')` çağrıları).

---

## Kapı çıktıları

| Kapı | Sonuç |
|---|---|
| `npm run build` | ✓ built in 14.23s |
| `npm run lint` | **0 hata**, 10 uyarı (hepsi mevcut `react-refresh`; yeni dosyalar uyarı üretmiyor) |
| `npx tsc -p tsconfig.app.json --noEmit` | **exit 0** |
| `npm test` | **142/142** (113 → +29) |
| `node tool/check_i18n.cjs` | ✓ 12 dil, 523 anahtar |
| `node tool/check_versions.cjs` | ✓ |
| Negatif ölçüm | 3/3 kırmızı (biri ⭐ kendi testimde bulunan yanlış yeşil) |

**Commit:** `6f411f9` `fix(web): …` (tek commit; iki konu birbirine bağlı —
ölü `saveNotifications` P1-2'nin kökü, hesap silme aynı dosyada).

---

## Değiştirilen dosyalar

```
src/lib/notificationPreferences.ts          (yeni)  saf normalize + master bileşimi
src/lib/accountDeletion.ts                  (yeni)  saf hata sınıflandırması
src/hooks/useNotifications.ts               (düzen) normalize yazma, saveAllPreferences
src/hooks/useAccountDeletion.ts             (yeni)  edge function çağrısı
src/components/account/DeleteAccountDialog.tsx (yeni) iki aşamalı diyalog
src/pages/SettingsPage.tsx                  (düzen) master anahtarlar + Kaydet + giriş noktası
tool/test_notification_preferences.mjs      (yeni) 29 test
tool/sync_locales_once.cjs                  (yeni) idempotent i18n eşitleyici
public/locales/*/translation.json           ×12
package.json · CHANGELOG.md
```

## AKTARIM (başka alana — dokunulmadı)

1. **`supabase/functions/send-notification/index.ts:423-424`** → A1/A2.
   `preference?.push_enabled ?? profile.push_notifications_enabled` hâlâ
   sunucu tarafında savunmasız. İstemci AND'i doğru davranışı garanti eder
   ama sunucu tarafında `applyMasterSwitches` uygulanırsa ikinci savunma
   katmanı olur.
2. **`supabase/functions/send-notification`** "her tip için satır yaz"
   davranışı hâlâ sunucuya bırakılmış; web artık beş tipin de satırını
   yazıyor → `goal_achieved` (T10'daki "kimse göndermiyor" P2) hâlâ ölü.
3. **`useDataExport` / `backupRestore`** bildirim tercihlerini geri
   yüklerken normalize katmanı kullanmıyor; yedekte `interval_hours: 0`
   varsa aynı CHECK reddi oradan da gelir. Tur 12'de bakılabilir.

## Kalan riskler

- **Etkileşim ölçülmedi.** Hook katmanı (supabase çağrıları, `Switch` tıklaması)
  jsdom gerektiriyor; depoda test koşucusu/çevrimdışı DOM yok. Kanıt
  zinciri: saf katman testleri + kaynak denetimleri (her ikisi de negatif
  ölçümle doğrulandı). React ekranında **manuel** doğrulama önerilir.
- **`interval_hours: 0` → `3` normalizasyonu kullanıcıya görünmüyor.**
  Arayüzde "0" bir değer olarak sunulmuyor (Input `min=1`), dolayısıyla bu
  yol yalnızca bozuk/elle veriden oluşur. Yine de "3 saatte bir" sürprizi
  mümkün; Flutter'ın birebir davranışı olduğu için **parite** adına korundu.
- **`NotificationPreferences` hâlâ her anahtarı anında kaydediyor.** Diyalogdaki
  "Kaydet" beş tipi de yazıyor; iki yol çakışmaz (aynı değerler) ama
  Flutter'daki tek "Kaydet" modeliyle UX farkı var. Web'in anında kaydetme
  modeli korundu (geri almak P3 kapsamı dışı).
- **Web'de cihaz temizliği yok.** `localStorage` yalnızca `theme` ve i18n
  tutuyor (ölçüldü), oturum `supabase-js` tarafından yönetiliyor ve
  `signOut` ile düşüyor → Flutter'ın `AccountLocalCleanup`'ına gerek kalmadı.
  `messages.localCleanup` anahtarı yine de eklendi (çeviri senkronu için).
- **Hafta günü etiketleri Türkçe sabit.** `WEEKDAY_OPTIONS` etiketleri
  çeviri değil; 12 dilde yanlış gün gösterimi riski **yok** (değer doğru),
  ama etiket başka dilde Türkçe kalır. P3, ayrı iş.
- **Gece aralığı (21→09) desteklenmiyor** — Flutter ile aynı bilinçli
  karar; `start > end` 23'e çekiliyor. Ürün kararı gerekiyorsa iki istemci
  birlikte değişmeli.
