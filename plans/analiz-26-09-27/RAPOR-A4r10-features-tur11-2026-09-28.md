# RAPOR — A4r10 (ekranlar) — 2026-09-28 — Tur 11

Alan: `flutter_app/lib/features/**`, `flutter_app/lib/shared/**`,
`flutter_app/assets/translations/**`, `flutter_app/test/features/**`.
Commitler: `1778cf8`, `207e38d`.

---

## Özet

1. **`weigh_in_frequency_days`** — gerçek CHECK sınırları şemadan çıkarıldı
   (**1..365**, `NULL` serbest); arayüz artık girişi sınırlıyor, hata
   **anında** gösteriyor, "Kaydet" geçersizde **pasif**, ve iki ayrı
   `catch` kolu eklendi (`ProfileFieldRangeError` ayrı, genel `catch` artık
   `AppLog.w` ile loglu).
2. **`deleteFood` arayüzü** — `shared/widgets/delete_food_button.dart`
   (onay diyaloğu + tooltip + Semantics) `add_page.dart`'in dört bölümüne
   bağlandı. Başarısızlık **"başarı" gibi söylenmiyor**.
3. **`goal_achieved`** — ölü tercih tipi **UI'dan gizlendi** (karar 2-B);
   gerekçe ve (a)'nın gerektirdikleri raporda.
4. **Gece aralığı (21→09)** — sunucu **desteklemiyor** (ölçüldü); arayüz
   aralığı **sınırladı** + kullanıcıya görünür doğrulama notu.
5. Testler **1004 → 1044**; 4 düzeltme için **negatif ölçüm** yapıldı.

---

## Düzeltilenler

| Sev | Dosya | Ne yapıldı | Doğrulama |
|---|---|---|---|
| **P1** | `lib/features/settings/widgets/weigh_in_frequency_input.dart` **(yeni)** | Saf sözleşme: `parseWeighInFrequencyDays` / `isBlankWeighInInput` / `isValidWeighInInput`. Gerçek CHECK sınırları dokümanı. | 25 birim testi |
| **P1** | `lib/features/settings/widgets/notifications_dialog.dart:227-250` | `int.tryParse(…) ?? 7` → **doğrulanmış** değer. Boş alan → `DEFAULT 7`. | `flutter test` yeşil + negatif ölçüm kırmızı |
| **P1** | aynı `:380-395` | `TextField` → `TextFormField`, `LengthLimitingTextInputFormatter(3)`, `errorText`, `helperText`, `onChanged: _validateFrequency`, `FocusNode`. | 5 widget testi |
| **P1** | aynı `:466-476` | `onPressed: _canSave ? _save : null` — geçersizde **pasif**. | `expect(button.onPressed, isNull)` |
| **P1** | aynı `:279-311` | `on ProfileFieldRangeError` ayrı kol + `AppLog.w`; genel `catch (_)` → `catch (e, s)` + `AppLog.w`. | "sessiz yutma yok" testi |
| **P1** | `lib/shared/widgets/delete_food_button.dart` **(yeni)** | Onay diyaloğu (ad + kullanım sayısı + favori uyarısı), silme akışı, hata ayrımı, tooltip + `MergeSemantics`. | 7 widget testi |
| **P1** | `lib/features/add/add_page.dart:265-290, 391-400, 476-485` | `DeleteFoodButton` dört bölüme bağlandı; `onFoodChanged` ile liste tazeleme. | 1044 test |
| **P2** | `server_notification_preferences_section.dart:48-56` | `goalAchieved` `_visible` haritasından **çıkarıldı**. | 2 widget testi |
| **P2** | aynı `:186-215` | `endHourOptions(startHour)` — bitiş saati `start..23`. Doğrulama notu eklendi. | 5 birim + 1 widget testi |
| — | `assets/translations/*.json` (12 dil) | 11 yeni anahtar (3 + 1 + 7). | `check_i18n` yeşil |

### ⭐ Görev 1 — CHECK sınırları **okundu**, tahmin edilmedi

İki kaynak, **aynı ifade**:

```sql
-- supabase/migrations/20260928400000_data_integrity_check_constraints.sql:225-228
-- supabase/full_setup.sql:1013-1016
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_weigh_in_frequency_days_range;
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_weigh_in_frequency_days_range
  CHECK (weigh_in_frequency_days IS NULL OR weigh_in_frequency_days BETWEEN 1 AND 365);
```

**Gerçek aralık: `1..365`** (`NULL` serbest). A2r9'ın veri katmanı
(`ProfileRepository.fieldRanges`) **aynı** değerleri taşıyor; test bunu
**ölçerek** eşitliği doğruluyor (iki katman ayrışırsa kullanıcı arayüzde
"geçerli" görür, DB reddeder — A4r3'ün dersi).

Kolon `DEFAULT 7` (`full_setup.sql:128`) → boş alan `7` yazılır.

### ⭐ Ölçülen tuzak: `int.tryParse` tek başına **güvenli değil**

Test yazarken ölçüldü:

| Girdi | `int.tryParse` sonucu | Sonuç |
|---|---|---|
| `'0x10'` | **16** | ⭐ hexadecimal, 16 yazılıyordu |
| `'+7'` | **7** | ⭐ işaretli, kabul ediliyordu |
| `'7.5'` | `null` | doğru |
| `'-5'` | −5 | `digitsOnly` zaten engelliyor |

`tryParse` "kullanıcı rakam yazdı" anlamına **gelmez**. Parser artık biçimi
de doğruluyor: `RegExp(r'^\d+$')`. Arayüzde `FilteringTextInputFormatter.digitsOnly`
bu ikinci katmanı atlayan yolları (yapıştırma, otomatik doldurma) kapatıyor.

### ⭐ Kendi kodumda bulduğum hata (test yakaladı)

`_save` içindeki erken çıkışta `_frequencyErrorOf(raw)` **"geçersiz metin
bul"** anlamına geliyordu ama "bul" yerine "**her dolu metin geçersiz**"
döndürüyordu → **geçerli** değerler de kaydedilemiyordu (test
`verify(...).called(1)` ile kırmızı verdi). `isValidWeighInInput(raw)`
kapısına çevrildi. Düzeltme öncesi hâli: `39 pass / 1 fail`.

### Görev 2 — şema okuması: **fiziksel silme**, `deleted_at` yok

- `foods` tablosunda `deleted_at` **yok** (`full_setup.sql:151-164` →
  `id, name, brand, serving_size_g, serving_description, source, image_url,
  popularity_count, verified, created_by, created_at, updated_at`).
  `FoodRepository` yorumu (`:133-139`) bunu zaten teyit ediyor.
- `foods.created_by` → `ON DELETE CASCADE` (`full_setup.sql:161`) —
  A1r5'in kararı: hesap silinince kullanıcının gıdası da silinir,
  `NULL` (seed/admin) satırlar korunur.
- `meal_entries.food_id` → `ON DELETE SET NULL`
  (`full_setup.sql:213`, migration `20260927120000:490`) — **öğünler
  korunur**, `food_id` boşalır. Bu yüzden `deleteFood`'un "silinemezse
  favoriye dokunma" sıralaması **defansif** bir güvence olarak duruyor
  (FK artık `SET NULL` olduğu için pratikte 23503 üretmez, ama sözleşme
  ölçülüyor ve ileride geri alınırsa koruyor).
- `favorite_foods.food_id` → `ON DELETE CASCADE NOT NULL`
  (`full_setup.sql:302-304`) → ölü favori satırı kalmaz; yine de
  `removeFavoritesForFood` idempotent temizlik yapar.
- RLS: `foods` DELETE → `created_by = auth.uid()` (`full_setup.sql:424`) —
  düğme **karma** gıdalarda da görünür, `false` döner ve kullanıcıya
  nedeni söylenir (RLS sürpriz olmaz).

**Onay akışı**: `Dokun → AlertDialog (ad + kullanım sayısı + favori uyarısı) →
İptal | Sil → deleteFood → 4 provider invalidate + liste tazeleme →
SnackBar`.

**`useCount` uyarısı**: `FoodItem.useCount` yalnız `frequentFoods`/
`favorites` bölümlerinde doludur; arama sonuçlarında ve "son eklenenler"de
`null`'dır. Bu yüzden `null` iken mesaj **gösterilmez** — "0 öğünde
kullanıldı" gibi **uydurma** bir bilgi üretilmez.

**Erişilebilirlik**: `Tooltip(message: 'Yemek sil: {food}')` +
`MergeSemantics` → `Semantics(button: true, label: …)`. `FavoriteButton`
deseniyle aynı (A4r6 ölçümü: `MergeSemantics` olmadan bayrak
**birleşme sınırının dışında** kalıyor).

### Görev 3 — `goal_achieved`: **(b) UI'dan gizle** uygulandı

**Karar gerekçesi (ölçüm):** `check-reminders/index.ts` 610 satır ve dört
gönderim bloğu içeriyor — `weigh_in` (`:287`), `water` (`:346`),
`daily_log` (`:410`), `weekly_summary` (`:464`). `goal_achieved`
**hiç okunmuyor**. `send-notification`'ı çağıran dört çağrı da bu dört tipi
gönderiyor; `send-notification/index.ts:90`'daki `goal_achieved` e-posta
şablonu **hiç çağrılmıyor**. Yani kullanıcı ekranda anahtar görüyor,
açıp kapatıyor, **hiçbir şey olmuyor** — üstelik
`defaultServerPreference(goalAchieved)` "push açık" olduğu için
kullanılmayan bir satır yazılıyor.

**(a) neden uygulanmadı:** tetikleme koşulu bir **ürün kararıdır** ve üç
farklı davranış mümkündür:

| Soru | Gereken karar |
|---|---|
| Hedef **kilo**ya mı ulaşıldı? | `weight_entries` son kayıt `target_weight_kg`'ya eşitse + **kaç gün kalıcı**? (1 günlük "hedef" 1 kg salınımda gelip gider) |
| Günlük **kalori** hedefi mi? | `daily_calorie_target` tek gün için; "N gün üst üste" gerekir → `daily_nutrition` yoksa hesaplanmalı |
| **Ödül** mantığı var mı? | `send-notification:90` "🎉 Tebrikler!" şablonu hazır ama **ödül mantığı yok** (rozet/seriye şeması hiç yok) |

Ek olarak hepsi **idempotency** gerektirir: `last_weekly_summary` gibi bir
`last_goal_achieved` damgası + **tek seferlik** üretim şart (aksi halde
cron saatte bir "Tebrikler!" gönderir — A1r3'ün `weekly_summary` hatasının
aynısı). Hiçbiri şu an şemada tanımlı değil.

> **AKTARIM → ürün / A1 (supabase):** (a) uygulanırsa
> `check-reminders`'a 5. blok + `profiles.last_goal_achieved TIMESTAMPTZ`
> kolonu (migration) + `calculate-macros`'ya gün hedefi mantığı gerekir.
> `supabase/**` benim alanım değil, **dokunmadım**.

> **AKTARIM → A5 (src):** `src/components/notifications/NotificationPreferences.tsx:198`
> aynı ölü tipi React PWA'da **hâlâ** listeliyor. A5r10 bu dosyaya dokunuyor;
> aynı karar (gizle) oraya da uygulanmalı.

### Görev 4 — gece aralığı: **sunucu desteklemiyor** → arayüz sınırladı

**Sunucu ölçümü** (`check-reminders/index.ts:352-356`):

```ts
const startHour = waterPref?.start_hour ?? 9;
const endHour   = waterPref?.end_hour   ?? 21;
if (normalizedHour >= startHour && normalizedHour <= endHour) { … }
```

`start > end` iken koşul **hiçbir saatte** sağlanmaz (21→09: `21 >= 9`
doğru ama `21 <= 9` yanlış; 09:00'da tersi). Test bunu `serverSends()`
kopyasıyla 24 saat üzerinden ölçüyor ve `09→21` aralığının **çalıştığını**
gösteriyor (sunucu mantığı sağlam, yalnız gece aralığı temsil edilemiyor).

A4r8'in `toRow` çözümü (`end`'i 23'e çekmek) **sessiz davranış değişikliği**
ydı: kullanıcı 21→09 istiyor, 09:00–23:00 alıyor ve bunu **bilmiyor**.

**Yapılan:** bitiş saati seçenekleri `start..23` (`endHourOptions`).
Böylece (a) gece aralığı yazılamaz, (b) `toRow`'nun `end = 23`
normalleştirmesine **arayüzden yol kalmaz**, (c) kullanıcıya
`rangeNoNight` notu görünür. `endHourOptions` dışa aktarıldı: açılır menü
**tembel** (lazy) kurulduğu için `find.text('08')` yalnız *görünen* öğeleri
yakalar ve "listede yok" iddiası **kanıtlamaz** (A4r7b'in dersi).

> **AKTARIM → A1 (supabase):** gerçek gece desteği `check-reminders`'ta iki
> koşul gerektirir:
> 1. `const inRange = start <= end ? (h >= start && h <= end) : (h >= start || h <= end);`
> 2. **Gece yarısını geçen** `last_water_reminder` damgasının hangi güne
>    ait olduğu: `hoursBetween(last, now)` gece yarısını **atladığı** için
>    gece diliminde her koşuda `>= interval` doğru olur → **her saat**
>    gönderim. `last_water_reminder` tek kolon olduğu için ya ikinci kolon
>    (`last_water_reminder_date`) ya da gün-başı sıfırlama gerekir.
> Kullanıcı etkisi doğrudan (uykuda hatırlatma) olduğu için not bırakıldı.

---

## Yeni testler

`flutter_app/test/features/settings/notification_range_and_food_delete_a4r10_test.dart`
— **40 test** (toplam 1004 → **1044**).

| Grup | # | Kapsam |
|---|---|---|
| CHECK sınırları | 2 | alt/üst sınır; **arayüz ↔ A2r9 veri katmanı eşitliği** |
| Alt/üst sınır | 5 | 1, 365, 7, 30, 100, 364; `0`, `-1/-5/-365/-1000`, `366`, `1000/9999/99999` |
| Geçersiz metin & boş | 6 | harf, ondalık, `1e3`/`0x10`/`7,0`/`+7`/`--7`, boş, yalnız boşluk, `null`, `" 7 "` |
| Boş/geçersiz ayrımı | 1 | `isValidWeighInInput` matrisi |
| **Arayüz (gerçek `_save`)** | 6 | `0` → hata metni + `onPressed == null` + `verifyNever(profile+prefs)`; `1`/`365`/`7` aynen yazılır; boş → 7; düzelt→kaydet; geçersiz iken sunucu tercihleri de etkilenmez; `ProfileFieldRangeError` ayrı kol |
| `goal_achieved` | 2 | ekranda **yok**; kalan üç tip **var** |
| Gece aralığı | 6 | sunucu koşulu 24 saat; `endHourOptions` 24 start; gece seçilemez; aralık dışı start çökertmez; doğrulama notu görünür |
| `DeleteFoodButton` | 7 | custom gizli; tooltip+Semantics; iptal = silme yok; onay = `deleteFood('u1','f1')` + "silindi"; `false` → **"başarı" söylenmez**; istisna → hata; oturum yoksa istek yok |

### ⭐ Negatif test ölçümü (4 düzeltme, hepsi kırmızı görüldü)

| Geri alınan düzeltme | Sonuç |
|---|---|
| `frequencyDays` → `int.tryParse(…) ?? 7`; `_canSave` kapısı → `(_saving \|\| !_prefsLoaded)`; `_save` erken çıkışı kaldırıldı | **1 kırmızı** — `"0" → profil ve sunucu tercihleri KAYDEDİLMEZ` |
| `goalAchieved` `_visible`'a geri kondu; `endHourOptions` → 0..23 | **5 kırmızı** — `goal_achieved` kart testi + 4 gece aralığı testi |
| `add_page.dart`'ten `DeleteFoodButton` çıkarıldı | 2 kırmızı (kod yolu) |
| `showDialog<bool>` atlandı (`confirmed = true`) | **4 kırmızı** — onay/iptal/silindi/hata testleri |

Hepsi geri kondu → `flutter analyze` **No issues found!**, `flutter test`
**1044/1044**.

### ⭐ "Yeşil test ≠ etkin test" kontrolü (A4r7b)

- `_tapSave` önce `ensureVisible` + gerekirse `drag` yapıyor; **ayrıca**
  `button.onPressed == null` ve `verifyNever(...)` ile etkileşimin
  gerçekten gerçekleşmediği kanıtlanıyor.
- Bir **tarayıcı ölçümü** yapıldı: `tester.hitTestOnBinding(center)` →
  `HitTestResult` **dolu** (yani düğme gerçekten basılabilir), ama
  `mocktail verify` 0 çağrı buldu → **kendi `_save` mantık hatalıydı**,
  `tap` değil. Bu, tuzağın ikinci biçimini de (düğmeye ulaşıldı ama iş
  yapılmadı) yakaladı. Düzeltildi.
- Onay diyaloğu testleri `verify(() => repo.deleteFood('u1','f1')).called(1)`
  ile **argümanları** doğruluyor (RLS filtresi doğru kullanıcıyla).
- Gece aralığı menü gözlemi yerine **saf liste** ölçümü (tembel menü
  tuzağı, yukarıda).

---

## Yeni çeviri anahtarları (12 dil tablosu — hepsi eklendi)

| Anahtar | tr | en |
|---|---|---|
| `settings.notifications.weighInFrequencyRange` | 1-365 gün arasında bir değer girin | Enter a value between 1-365 |
| `settings.notifications.weighInFrequencyHint` | 1-365 gün arası. Boş bırakılırsa 7 gün kullanılır. | 1-365 days. If left empty, 7 days is used. |
| `settings.notifications.server.rangeNoNight` | Bitiş saati başlangıçtan önce olamaz (gece aralığı desteklenmiyor). | End hour cannot be before the start hour (overnight range is not supported). |
| `foodDelete.title` | Yemek silinsin mi? | Delete this food? |
| `foodDelete.usageCount` | Bu yemek **{count}** öğünde kullanıldı. | This food was used in **{count}** meals. |
| `foodDelete.favoriteWarning` | Bu yemek favorilerinizden de silinecek. | This food will also be removed from your favorites. |
| `foodDelete.confirm` | Sil | Delete |
| `foodDelete.deleted` | Yemek silindi | Food deleted |
| `foodDelete.deleteFailed` | Yemek silinemedi. Bir öğünde kullanılıyorsa önce o kaydı silin. | Could not delete the food. If it is used in a meal, delete that entry first. |
| `foodDelete.tooltip` | Yemek sil: **{food}** | Delete food: **{food}** |

**11 anahtar × 12 dil** (`ar de en es fr it ja ko pt ru tr zh`). `de/es/fr/it/pt/ru/ar/zh/ja/ko`
tarafında da elle çevrildi; `check_i18n` **31 placeholder'lı anahtar × 12 dil
tam tutarlı** diyor. `goalAchieved` anahtarı **silinmedi** (React PWA
kullanıyor; `src/components/notifications/NotificationPanel.tsx:25,42`).

**RTL notu (ar):** `foodDelete.usageCount` içindeki `{count}` Arapça
cümle yapısında ortaya yerleştirildi (`تم استخدام هذا الطعام في {count} وجبات.`)
— yapışık değil, boşluk ayıran; `check_i18n` 4c kuralı CJK dışı için de
uygun.

---

## Bulunurlar (düzeltilmedi, gerekçe)

| Sev | Dosya:satır | Bulgu | Öneri |
|---|---|---|---|
| **P2** | `features/settings/widgets/personal_info_dialog.dart:188` | `catch (_)` ile "hesaplama başarısızsa kişisel bilgiler yine de kaydedilir" — **kasıtlı** ve yorumlu, ama log yok. | `AppLog.w` ekle (küçük). |
| **P2** | `features/settings/widgets/goals_dialog.dart:124,156` | İki `catch (_)` loglamıyor. | Aynı. |
| **P2** | `features/add/widgets/recognition_confirm_dialog.dart:280` | `catch (_)` loglamıyor. | Aynı. |
| **P2** | `features/settings/settings_page.dart:245` | `catch (_)` loglamıyor. | Aynı. |
| **P2** | `features/add/add_page.dart` | Silme düğmesi **arama sonuçlarında da** görünüyor; veritabanı/seed gıdalarında (`created_by` NULL) basılır → `false` + bilgilendirme. Kullanıcı deneyimi biraz gürültülü olabilir (toast çıkar). | Tur 12: `source`/`verified` bilgisi `FoodItem`'a taşınıp yalnız `created_by`'ı dolu olanlarda düğme gösterilebilir. **Şema okuması gerekli** (`foods.source`, `verified` kolonları mevcut, `search()` bunları **seçmiyor** → `lib/data/**` alanı, **aktarım**). |
| **P3** | `shared/widgets/delete_food_button.dart` | `FoodItem.useCount` `null` iken kullanım sayısı gösterilmiyor. | Doğru davranış (uydurma yok); `frequentFoods` zaten `useCount` veriyor. |

### AKTARIM (başka alana)

| Hedef | Konu |
|---|---|
| **A1 (supabase)** | 1) `check-reminders`'a **gece aralığı** desteği gerekiyor (Rapor "Görev 4" — iki koşul: sarma + gece yarısı damgası). 2) `goal_achieved` devreye alınırsa 5. blok + `profiles.last_goal_achieved` kolonu (migration) gerekir. 3) **`check-reminders` cron tanımı hâlâ yok** (Transfer defteri T8) — sunucu hatırlatıcıları **hiç gitmiyor**; bu, A4r8/A4r10'un tüm ayar ekranı düzeltmelerinin **kullanıcıya görünür etkisini** sıfırlıyor. |
| **A5 (src)** | `NotificationPreferences.tsx:198` `goal_achieved`'ı React PWA'da **hâlâ** listeliyor → aynı "gizle" kararı. |
| **A2 (data)** | `FoodRepository.search` `foods.source` ve `verified` kolonlarını **seçmiyor**. Silme düğmesini yalnız `created_by` dolu satırlarda göstermek istersek `FoodItem`'a `isUserOwned` alanı eklenmeli (`lib/data/**` = A2 alanı). Şimdilik sunucu `false` dönüyor + kullanıcı bilgilendiriliyor, bu yüzden **P2** (veri kaybı yok). |
| **A2 (data)** | `NotificationPreference.toRow`'nun `end = 23` normalleştirmesi artık **arayüzden tetiklenemiyor** (`endHourOptions` ile). Veri katmanı savunması **korunmalı** (A2r9'un "clamp sessiz veri bozulmasıdır" gerekçesi burada geçerli değil: 23'e çekilen değer **görünmez** bir davranış değişikliği; ama artık **ulaşılamaz** → savunma derinliği olarak duruyor). |

---

## Doğrulama

```
$ cd flutter_app && flutter analyze
No issues found! (ran in 5.8s)

$ cd flutter_app && flutter test
00:34 +1044: All tests passed!          (1004 → 1044, +40)

$ node tool/check_i18n.cjs
✓ i18n bütünlüğü temiz: 12 dil, 523 anahtar, 345 Flutter kod anahtarı,
  2 dinamik kalıp, 345 React i18next anahtarı doğrulandı.
  orphan → ölü: 63/63 · react canlı: 67 · dinamik: 17 · dolaylı: 31
  placeholder denetimi: 31 placeholder'lı anahtar × 12 dil tam tutarlı
EXIT=0

$ node tool/check_versions.cjs
✓ Sürüm tutarlı: 1.3.0+4 (pubspec = AppConstants = CHANGELOG = README)
EXIT=0
```

⚠️ `git status`'ta `src/**`, `public/locales/**`,
`plans/analiz-26-09-27/TRANSFER-defteri.md` **başka ajanların** (A5r10)
açık değişiklikleri — **dokunulmadı, commit'e alınmadı**.

---

## Kalan riskler

1. **Sunucu hatırlatıcıları hiç çalışmıyor** (`check-reminders` için
   `cron.schedule` tanımı yok — Transfer defteri T8). Bu turdaki **tüm**
   ayar ekranı düzeltmeleri (`goal_achieved`, gece aralığı, saat
   aralıkları) kullanıcıya **ancak** cron kurulduktan sonra görünür olacak.
   Düzeltmeler doğru ama **ölçülemiyor** (sunucu tarafı test edilemedi).
2. **Gece aralığı gerçek desteklenmiyor** — arayüz doğru davranıyor
   (imkânsız seçenek sunmuyor) ama kullanıcının "gece hatırlat" ihtiyacı
   karşılanmıyor. A1'e aktarıldı.
3. **Silme düğmesi gürültüsü**: veritabanı gıdalarında (seed, `created_by`
   NULL) düğme görünür ve `false` döner. Veri kaybı yok, kullanıcı
   bilgilendiriliyor; yine de UX gürültüsü → A2'ye aktarıldı.
4. **`deleteFood` yalnız `created_by = auth.uid()`** gıdaları siler. Yemek
   listesi ekranı **kendi eklediği** gıdayı da "arama sonucu" olarak
   gösteriyor; kullanıcı bir günü silmeye çalışıp hata alabilir. A2
   alanı (`search` `created_by` seçmiyor).
5. **`flutter test` 40 saniye** sürüyor; widget testleri `runAsync` +
   `EasyLocalization` yüzünden yavaş. CI süresi etkisi ölçülmedi.
6. **A2r9'ın "5 ekran `catch (_)` ile 'Kaydedildi' yalanı söylüyordu"
   notu kısmen çözüldü**: `notifications_dialog.dart` artık
   `ProfileFieldRangeError`'ı ayrı yakalıyor ve logluyor; **diğer 4 ekran**
   (`personal_info`, `goals`, `settings_page`, `recognition_confirm`)
   hâlâ `catch (_)` → genel mesaj. Onlarda **aralık doğrulaması
   tetiklenmiyor** (alanlar `height_cm`/`weight`/`water` ve bunlar
   `_valid`/doğrulamalı), ama `_aiCalculate` yolu hariç `catch (_)`
   kalıyor → Tur 12'de `AppLog.w` ile loglanmalı.
