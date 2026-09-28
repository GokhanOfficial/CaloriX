# RAPOR — A4r8 · Sunucu bildirim tercihleri arayüzü (Tur 10)

**Tarih:** 2026-09-28 · **Ürün kararı:** `URUN-KARARLARI.md` #2 (A seçeneği onaylandı)
**Commit:** `de7ab90` · 17 dosya, +591 / −71

---

## 0. Başlangıç durumu (alan sahipliği)

Görev başlarken A4r7'nin (ve A4r7b'nin) **commit edilmemiş** çalışması
diskte duruyordu. Görev sırasında A4r7 `9d2e75e` ile commit etti; ben o
commit'in üstüne **devam ettim**. Kendi alanım dışındaki dosyalara
(`widget_settings_dialog.dart`, `favorite_button.dart`, `food_repository.dart`,
öğün hatırlatıcısı kısmı) **dokunmadım**.

---

## 1. Şema doğrulaması (varsayım değil, okundu)

`notification_preferences` — kaynak: `supabase/full_setup.sql:523-537`
(aynen `migrations/20260111075621_*.sql:2-18` ile aynı).

| Kolon | Tip | Varsayılan | Not |
|---|---|---|---|
| `id` | `uuid` | `gen_random_uuid()` | PK |
| `user_id` | `uuid NOT NULL` | — | `auth.users(id) ON DELETE CASCADE` |
| `notification_type` | `text NOT NULL` | — | allow-list CHECK |
| `push_enabled` | `boolean` | `true` | |
| `email_enabled` | `boolean` | `true` | |
| `start_hour` | `integer` | `9` | |
| `end_hour` | `integer` | `21` | |
| `interval_hours` | `integer` | `3` | ⭐ CHECK **1..24** |
| `summary_day` | `integer` | `1` | ⭐ 0=Pazar |
| `summary_hour` | `integer` | `9` | |
| `created_at` / `updated_at` | `timestamptz` | `now()` | `updated_at` trigger |

**CHECK'ler** (`full_setup.sql:822-831`):

- `notification_preferences_type_allowlist` — `IN ('weigh_in','daily_log',
  'water','goal_achieved','weekly_summary')` (5 tip)
- `notification_preferences_hours_range` — `start/end/summary_hour 0..23`
  **AND `interval_hours BETWEEN 1 AND 24`** `AND summary_day 0..6`

**Unique constraint:** `UNIQUE(user_id, notification_type)` → `upsert` için
`onConflict: 'user_id,notification_type'` **tahmin edilmedi, şemadan okundu**
(`.sql:536`).

### ⭐ `summary_day` indeksi doğrulandı (0 = Pazar)

Migration yorumu "0=Sunday, 1=Monday" diyor. Bunu **üç yerden** teyit ettim:

1. `check-reminders/index.ts:261` — "`summary_day` (0=Pazar..6=Cumartesi) ile
   `weekday` aynı dizindir"
2. `check-reminders/helpers.ts:70-78` — `WEEKDAY_INDEX = {Sun:0, Mon:1, …, Sat:6}`
   ve `getZonedParts` bu dizini döndürüyor
3. `index.ts:484` — `dayOfWeek === summaryDay` **doğrudan** karşılaştırma

→ **A1r8'in tespiti doğru.** Dart'ın `DateTime.weekday` dizini (1=Pzt) ile
**ters yönde** olduğu için arayüzde `(i + 1) % 7` eşlemesi kullanılıyor ve bu
**iki yönde de** (değer→etiket, etiket→değer) test ediliyor.

### `check-reminders`'ın okuduğu tipler ve açma koşulları

| Tip | Koşul | Zamanlama |
|---|---|---|
| `weigh_in` | `push \|\| email \|\| (!pref && profile.weigh_in_frequency_days)` | `hour === 9` **sabit** |
| `water` | `pref.push \|\| pref.email` | `start ≤ h ≤ end`, `interval_hours` |
| `daily_log` | `pref.push \|\| pref.email` | `hour === 18` **sabit** |
| `weekly_summary` | `pref.push \|\| pref.email` | `weekday === summary_day && hour === summary_hour` |

⭐ **Sorun teyidi:** `weight`/`daily_log`/`weekly_summary` için
`pref?.push_enabled` **satır yoksa `undefined`** → koşul `false` → **sessizce
kapalı**. A4r7'nin "her tip için satır yaz" davranışı bu sorunu çözdü.

---

## 2. ⭐ `interval_hours: 0` çakışması — Flutter tarafında kapandı

**Karar: `NULL` değil → `1`** (gerekçe kodda `toRow` yorumunda da yazılı).

- `NULL`, SQL üç değerli mantığıyla CHECK'i geçerdi ama
  `check-reminders/index.ts:354` `interval_hours ?? 3` dediği için sunucu
  sessizce `3` kullanırdı → "kapalı" değil, **"yazılmamış"** anlamı. Kullanıcı
  5 saatte bir açtığını sanır, sunucu 3 saatte bir gönderir.
- `1` CHECK'i karşılar **ve** anlamlıdır: `interval_hours` yalnız `water`'da
  okunur; `weigh_in`/`daily_log` zaten sabit saat denetimi yapar
  (`=== 9`, `=== 18`). Tek seferlik tiplerde `1` = "en fazla saatte bir kez".

**Canlı Postgres kanıtı** (`postgres:16-alpine`, konteyner `a4r8-pg`):

```
== WEB: interval_hours = 0 (useNotifications.ts:30) ==
ERROR: new row for relation "np" violates check constraint
       "notification_preferences_hours_range"
== FLUTTER: interval_hours = 1 ==
INSERT 0 1
```

Flutter `toRow` çıktısı **5 tipin tamamı** gerçek CHECK'lere yazıldı — `INSERT 0 5`:

| tip | start | end | interval | summary_day |
|---|---|---|---|---|
| `weigh_in` | 9 | 9 | **1** | 1 |
| `water` | 9 | 21 | **3** | 1 |
| `daily_log` | 21 | 23 | **1** | 1 |
| `goal_achieved` | 0 | 23 | **24** | 1 |
| `weekly_summary` | 9 | 9 | **1** | 0 |

→ **Hiçbiri 0 değil.** `summary_day 0` (Pazar) ve `6` (Cmt) kabul, `7` reddedildi.

---

## 3. ⭐ Bulunan ve düzeltilen 2 hata (A4r7'nin çalışan kodu)

### P1 — Profil master anahtarları ölmüş haldeydi

`send-notification/index.ts:423-424`:

```ts
const pushEnabled = preference?.push_enabled ?? profile.push_notifications_enabled ?? true;
```

`??` **yalnız `NULL` üstüne düşer.** `notification_preferences`'a yazan ilk
istemci olmak, `push_enabled`'ın artık **dolu** olması demektir → profil master
anahtarı **hiç okunmaz**. A4r7'nin "her tip için satır yaz" davranışı
(`check-reminders`'in sessiz-kapalı sorununu düzeltmesi) bu ayrımı kırdı.

**Ölçülen sonuç:** master `push` = `false`, varsayılan tip değeri `true` →
yazılan satır **`push_enabled: true`**. Kullanıcı üstteki anahtarı kapatıyor,
bildirimler yine gidiyor, hata yok.

**Düzeltme:** `NotificationPreferencesRepository.applyMasterSwitches` — bileşim
**AND**. Tek yerde uygulanır, `_save`'a bağlıdır, UI'da `channelNote` metniyle
söylenir.

### P1 — `start_hour > end_hour` sessizce hiç göndermiyordu

`check-reminders/index.ts:356` → `normalizedHour >= startHour && <= endHour`.
DB CHECK'i iki saati de 0..23 olduğu için `start=21, end=6`'ya **izin verir**;
ama koşul **hiçbir saatte** sağlanmaz → `water` hatırlatması sessizce hiç gitmez.

**Düzeltme:** `toRow` `end < start` durumunda `end`'i `23`'e çeker. Gece aralığı
desteklenmiyor (arayüzde de belgeli).

### Ek: derlenmeyen test satırı

A4r7'nin bıraktığı `row['end_hour']! as int >= row['start_hour']! as int`
ifadesi, `analysis_options.yaml`'deki `strict-casts` altında **derlenmiyordu**
(`argument_type_not_assignable`). Düzeltildi.

---

## 4. Cihaz/sunucu öncelik kararı

**Karar: Sunucu yalnız push/e-posta kanallarını yönetir; öğün
hatırlatıcıları cihazda kalır.** A4r7'nin kararı doğru bulundu ve **nedeni
ayrıntılılandırıldı**:

- `check-reminders` (cron) yalnız **push/e-posta** üretir; web'de bu tek
  çalışan kanaldır. Tercih satırı olmayan kullanıcıda 3 tip **sessiz kapalı**dır.
- Öğün hatırlatıcıları **cihazda** `zonedSchedule` ile zamanlanır; PWA'da
  cihaz zamanlayıcısı yok, mobilde push aboneliği gerekir. Sunucuya taşımak
  mevcut mimariyi bozar.
- Dolayısıyla iki kaynak **birbirinin yerine geçmez**: sunucu → push/e-posta,
  cihaz → yerel zamanlama.

**UI'da metinle belirtildi** (`serverScope`, 12 dil): *"Hesabınızdan gönderildikleri
için bu hatırlatıcılar, cihazınız kapalıyken veya değişse de gelmeye devam
eder. Sonraki bölümdeki öğün hatırlatıcıları yalnızca bu cihazda kalır."*

⭐ **Çakışma senaryosu:** kullanıcı öğün hatırlatıcısını cihazda kapatır,
sunucu tarafı açık kalırsa **çakışma yoktur** — iki ayrı kanal, iki ayrı kapsam.

---

## 5. Arayüz

`notifications_dialog.dart`'a **gömüldü** (ayrı ekran yok). Bölüm sırası:
profil anahtarları → **Sunucu Hatırlatıcıları** → Öğün Hatırlatıcıları.

Kontroller (bölüm bileşeninde):
- **4 tip kartı**: `water` · `daily_log` · `weekly_summary` · `goal_achieved`
- Her kartta: **push** ve **e-posta** `FilterChip` (kanal seçimi)
- `water`: başlangıç saati · bitiş saati · **aralık (1/2/3/4/6/8/12/24 saat)**
- `weekly_summary`: **haftanın günü** (0=Pazar…6=Cmt) + **saat**
- `daily_log` / `goal_achieved` için saat alanı **gösterilmiyor**: sunucu
  `=== 18` ve zamanlamasız gönderiyor; alan göstermek yanlış bir vaat olurdu.
- Yükleme: `_prefsLoaded` kapısı (yükleme bitmeden "Kaydet" pasif) +
  `loadFailed` uyarısı · Kaydetme: tek "Kaydet" → profil + 5 tip birlikte

---

## 6. Çeviriler (12 dil, hepsi dolu)

`settings.notifications.server` altına **14 anahtar**, 12 dilin hepsinde
dolu string, boş string yok (programatik doğrulandı).

| anahtar | tr | en | de | fr | es | it | pt | ru | ar | zh | ja | ko |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `title` | Sunucu Hatırlatıcıları | Server Reminders | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `desc` | hesabınızdan gönderilen… | sent from your account… | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `serverScope` ⭐ | cihaz değişse de gelir | keeps arriving… | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `channelNote` ⭐ | yukarıdaki anahtarlar uygulanır | switches at top apply… | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `loadFailed` | yüklenemedi | could not be loaded | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `water` | Su İçme | Water Reminder | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `dailyLog` | Günlük Kayıt | Daily Log | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `weeklySummary` | Haftalık Özet | Weekly Summary | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `goalAchieved` | Hedef Başarısı | Goal Achievement | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `startHour` / `endHour` | Başlangıç/Bitiş saati | Start/End hour | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `intervalHours` | Aralık (saat) | Interval (hours) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `summaryDay` / `summaryHour` | Gün / Saat | Day / Hour | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

⭐ **`desc` düzeltmesi:** metin *"meal reminders **above** stay on your
device"* diyordu; oysa sunucu bölümü öğün hatırlatıcılarından **aşağıda**.
12 dilin hepsinde konum doğru yazıldı.
⭐ **`days`/`hours` silindi:** A4r7 eklemiş ama **hiç bağlanmamış** → ölü
ratchet 63 → **62** (azaldı).

---

## 7. ⭐ Negatif test ölçümü

| # | Geri alınan düzeltme | Sonuç |
|---|---|---|
| 1 | `applyMasterSwitches` → `_serverPrefs` | `Expected: false, Actual: <true>` — **kırmızı** |
| 2 | `_clamp(intervalHours, 1, 24, 3)` → `intervalHours` | 2 test kırmızı: `Expected: not <0>, Actual: <0>` + `does not contain <-1>` |

İkisi de geri kondu → **8/8 yeşil**.

---

## 8. Doğrulama çıktıları

```
flutter analyze  → No issues found! (ran in 5.1s)
flutter test     → 1004/1004 All tests passed!   (önce 995, +9 yeni)
node tool/check_i18n.cjs     → ✓ temiz · 12 dil, 513 anahtar · ölü 62/63 · exit 0
node tool/check_versions.cjs → ✓ tutarlı: 1.3.0+4 · exit 0
```

---

## 9. Kalan riskler / aktarımlar

| Sev | Konu | Durum |
|---|---|---|
| **P1 · AKTARIM** | **Web istemcisi hâlâ `interval_hours: 0` yazıyor** (`src/hooks/useNotifications.ts:30-33`, 3 tip) → web'de bildirim tercihi kaydetme **400** ile başarısız. Flutter tarafı temiz; `src/**` benim alanım değil | A5r8'e |
| **P1 · AKTARIM** | Web'de de **aynı master gölgelenmesi** var: `updatePreference` satır yazdığı anda profil master anahtarı okunmaz. Aynı AND mantığı gerekir | A5r8'e |
| **P2** | `goal_achieved`'ı **kimse göndermiyor**: `check-reminders` işlemez, `send-notification`'ı çağıran başka fonksiyon yok (`invoke('send-notification')` → boş). Tip CHECK allow-list'inde ve arayüzde var ama tetikleyici yok — **A4r7'nin notu doğru** | Ürün kararı |
| **P2** | `cron.schedule` hiçbir migration'da yok → `check-reminders` **elle** tetikleniyor. Arayüz doğru tercih yazsa da gönderim olmaz | A1r3'ten kalan, A6 |
| **P2** | Gece aralığı (21→09) desteklenmiyor; `toRow` `end`'i 23'e çekiyor. Desteklenmesi istenirse sunucu `wrap` mantığı gerekir | Ürün kararı |
| **P2** | `upsertAll` satır satır yazıyor (5 istek). Hata hangi tipte olduğunu net göstermesi için bilinçli; toplu tek çağrıya çevrilebilir | — |
