# RAPOR — A4r7b (kurtarma ajanı) · favoriler + sunucu bildirimleri · Tur 10

**Tarih:** 2026-09-28 · **Önceki:** A4r7 (iptal edildi, yarım & commitlenmemiş)
**Kapsam:** `URUN-KARARLARI.md` 1-A (favoriler) + 2-A (sunucu bildirimleri)

---

## 1. `flutter analyze` hatası nasıl çözüldü

**Sürüm:** `Flutter 3.47.1 stable` · Dart 3.13.1 · Engine 11d7965… (6 hafta önce)

Hata: `SemanticsFlags.checked` ve `CheckedState` **yok**.

**Gerçek API araştırması** (tahmin değil, kaynak okundu):

| Kaynak | Gerçek |
|---|---|
| `sky_engine/lib/ui/semantics.dart:1217-1250` | `class SemanticsFlags extends NativeFieldWrapperClass1 { SemanticsFlags({this.isChecked = CheckedState.none, …}) }` → durum **`isChecked` alanı**nda, tipi `CheckedState` |
| `sky_engine/lib/ui/semantics.dart:1078-1089` | `enum CheckedState { none(0), isTrue(1), isFalse(2), mixed(3) }` — `dart:ui`'de |
| `flutter/lib/semantics.dart` | Yalnız `export 'dart:ui' show LocaleStringAttribute, SpellOutStringAttribute;` → **`CheckedState` dışa aktarılmıyor** |
| `flutter_test/lib/src/matchers.dart:3298` | Flutter'ın **kendi** testleri `flagsCollection.isChecked != ui.CheckedState.none` yazıyor — yani doğru kullanım `dart:ui show CheckedState` |
| `flutter/lib/src/widgets/semantics_debugger.dart:6` | `import 'dart:ui' show CheckedState;` — aynı desen |

**Çözüm (testte):** `import 'dart:ui' show CheckedState;` + `data.flagsCollection.isChecked`
(eskiden `.checked`). `package:flutter/semantics.dart` import'u **kullanılmadığı**
için kaldırıldı (analyze `unused_import` veriyordu).

⚠️ **Sürüm tuzağı:** 3.47'de `SemanticsFlags` bit-maskesinden `NativeFieldWrapperClass1`
alan sarmalayıcısına geçmiş. `<3.32` sürümlerde `isChecked` **bool**'du
(`data.hasFlag(SemanticsFlag.isChecked)`); `.isChecked` **bugün** `CheckedState`
döndürür. Testi zorlamadım, sürümün gerçek API'sini kullandım.

---

## 2. Commit'ler

```
d5d116f  feat(flutter-features): favori yıldız arayüzü + sohbet liste indeksi tek yerde
         5 dosya · +1140 −53
9d2e75e  fix(flutter-features): sunucu bildirim tercihleri — hafta günü hizası,
         tip güvenliği, yarım kayıt kapısı
         20 dosya · +2686 −98
```

Üçüncü commit gerekmedi: son test hizası, eşzamanlı çalışan A4r8'in commitine
girdi (dosya commitlenmeden benim `git add`'im çalışma ağacındaydı). İçeriği
korundu — `git show HEAD:…notification_preferences_a4r7_test.dart` içinde.

**Dokunulmayanlar (brief'e uygun):** `lib/core/**`, `lib/data/**` (izin verilen 2 dosya),
`supabase/**`, `src/**`, `tool/**`, `.github/**`, `plans/**`,
`account_repository.dart`, `delete_account_dialog.dart`.

---

## 3. Favori arayüzü denetimi — **çalışıyor, 1 eksik vardı**

`shared/widgets/favorite_button.dart` + `add_page.dart` + `add_from_food_dialog.dart`

| Ölçüm | Sonuç |
|---|---|
| Optimistic UI | ✅ `setState` ile ikon **anında** değişiyor (yazma beklemeden) |
| Hata geri alma | ✅ `catch` → `_optimistic = wasFavorite` + `SnackBar` (`favorites.toasts.addFailed`/`removeFailed`) |
| Yemek silinince favori | ✅ `deleteFood` **önce** gıdayı siler (`meal_entries.food_id` FK `NO ACTION` → 23503), **sonra** favoriyi temizler; silinemezse favorilere dokunulmaz |
| `foodId == null` | ✅ Düğme gizlenir (`favorite_foods.food_id NOT NULL`; custom/manuel gıda favori olamaz) |
| Oturum yok | ✅ `user == null` → hiçbir yazma denemesi (RLS `auth.uid()` 400 dönerdi) |
| N+1 | ✅ `favoriteIdsProvider` tek sorguda küme döner; satır başına `isFavorite` yok |
| Aynı yemek iki kez ekleme | ✅ `ignoreDuplicates: true` → `Prefer: resolution=ignore-duplicates` **(ölçüldü, mock istek başlığı)** |
| Silme idempotliği | ✅ `DELETE` 0 satır dönse de hata fırlatmaz |

**Eksik bulunan (benim eklediklerim):** §5'teki iki test düzeltmesi (semantik API)
+ `analysis_options.yaml` **bana ait değil** (bkz. §8, commitlenmedi).

**Kalıcı kalan risk:** `deleteFood`'un **hiçbir UI çağıranı yok**
(`grep -rn deleteFood lib/` → yalnız tanım). Yemek silme ekranı A4r6'da
`features/**`'te yok; bu yüzden "silinen yemek favoriyi temizler" sözleşmesi
**yalnız veri katmanında** ölçülüyor.

---

## 4. Bildirim tercihleri — A1r8'in `interval_hours: 0` çakışması

**Sorun:** `notification_preferences_hours_range` CHECK'i `interval_hours
BETWEEN 1 AND 24` istiyor; web (`useNotifications.ts:30-33`) `0` yazıyor
→ canlı Postgres'te reddedildi (A1r8).

**Flutter tarafında çakışma YOK — ölçtüm:**

| Nokta | Değer |
|---|---|
| `toRow` | `_clamp(intervalHours, 1, 24, 3)` → `0` **asla** çıkmaz |
| Varsayılanlar | `weigh_in/daily_log/weekly_summary = 1`, `water = 3`, `goal_achieved = 24` |
| CHECK ile uyum | ✅ saatler 0..23, `summary_day` 0..6, tip allow-list'i 5 tip ile birebir |
| `created_at` gönderiliyor mu | ❌ (A2r5'in hatası tekrarlanmıyor) |
| `user_id` her satırda | ✅ (RLS `auth.uid() = user_id`) |
| `check-reminders` SELECT'i | `index.ts:275` ile **aynı 8 kolon** |

**Çakışmanın doğru çözümü web'de** (`src/hooks/useNotifications.ts:30-33` →
`interval_hours: 0` → `1`). `src/**` benim alanım değil; A1r8 zaten A5r8'e
aktarmış. Flutter'da `NULL` seçeneği de değerlendirildi ve **reddedildi**:
`check-reminders/index.ts:354` `interval_hours ?? 3` dediği için `NULL`
"her saat" değil "sunucu 3 saatte bir" anlamına gelirdi — kullanıcı 5 saat
seçtiğini sanar, sunucu 3 uygulardı.

### ⭐ Hafta günü hizası — **en kirletici hata, bulundu ve düzeltildi**

`server_notification_preferences_section.dart`, `DateTime(2024, 1, 7)`
referansını kullanıyordu ve yorumu *"2024-01-07 = Pazartesi (weekday 1)"*
diye yazıyordu.

**Ölçüm:** `DateTime(2024, 1, 7).weekday == 7` → **PAZAR**.

Sonuç: liste `Cmt → Paz` sırasını gösteriyordu. Kullanıcı ekranda "Pzt" gördüğü
halde `summary_day = 0` yazılıyordu → sunucu özeti **Pazar** gününe gönderiyordu
(ve tersi). Kullanıcı **hiçbir zaman** istediği güne kaydedemiyordu.

**Düzeltme:** `_monday = DateTime(2024, 1, 8)` + `value = (i + 1) % 7`
(Pzt=1 … Cmt=6, Paz=0) = `WEEKDAY_INDEX` ile birebir.

⚠️ **İlk denemem de yanlıştı** — `2024-01-14` seçmiştim, test kırmızı döndü
(`Paz`), 12 dilde ölçtüm: `2024-01-08` doğru. Düzeltmeyi **teste güvenerek**
değil **ölçerek** seçtim.

### ⭐ `fromRow` tip güvenliği — ikinci hata

`as int?` yerine `_asInt()`: PostgREST `numeric`/`bigint` kolonu metin döndürürse
`as int?` **`TypeError`** fırlatır ve `fetch` **tüm ayar ekranını** çökertirdi.
Reponun geri kalanı aynı tuzağa karşı `as num?` kullanıyordu
(`food_repository.dart:347`, `profile.dart:146`); buradaki `as int?` tek istisnaydı.

### ⭐ Yarım kayıt — üçüncü hata

`_loadServerPrefs` `Future.microtask` ile koşuyor; **yükleme bitmeden** "Kaydet"
basılırsa `_serverPrefs` `{}` → `upsertAll` **hiçbir şey yazmıyor**, kullanıcı
"Ayarlar güncellendi" görüyor ama `check-reminders`'ın sessiz-kapalı davranışı
**hiç değişmemiş** oluyordu.

- `onPressed: (_saving || !_prefsLoaded) ? null : _save`
- `fetch` hatası yutulmuyor: ekran çökmez, `server.loadFailed` uyarısı çıkar
  (12 dil), kaydetme varsayılanlarla çalışır.

---

## 5. Sohbet listesi taşıma — **tamam**

A4r3'ün P0'ının kaynağı `chat_page.dart:452-476` `itemBuilder` içindeki elle
indeks hesabıydı; `+ (_hasMore ? 1 : 0)` işareti ters olduğu için
`visible[3]` → **`RangeError`**, yani "daha eski mesajlar" düğmesi görünen
**her** sohbet liste çöküyordu.

`features/chat/message_list.dart`:
- **`MessageListLayout`** (saf sınıf): `itemCount` ve `messageIndexAt` **aynı**
  üç sayıdan türer → ayrışamaz. Sınır dışı/alt bilgi indeksi `null` döner,
  `RangeError` **fırlatmaz** (ölçüldü: `ListView` kaydırmada geçici olarak
  `itemCount`'tan büyük indeks isteyebiliyor → `try/catch` değil **aralık
  denetimi** doğru çözüm).
- **`ChatListHeader`** enum'u: bayrak listesi tek yerde.
- `chat_page.dart` yalnız bayrakları veriyor; elle indeks hesabı yok.
- 32 test: 4 başlık varyantı × 4 mesaj sayısı × 2 alt bilgi, hepsi widget
  ağacı kurmadan.

---

## 6. Çeviriler — **12 dil dolu, `check_i18n` yeşil**

`assets/translations/*.json` — 12 dilin **hepsi**:
- `settings.notifications.server.*` — 14 anahtar (benim eklediğim `loadFailed` dahil)
- `favorites.add/remove/toasts.addFailed/removeFailed` — 4 anahtar (`{food}` placeholder'ı)
- `addFood.favorites.*` + `addFood.frequent.*` — 4 anahtar

`check_i18n.cjs`: ✓ 12 dil, 513 anahtar, 335 Flutter kodu anahtarı doğrulandı,
27 placeholder'lı anahtar × 12 dil tam tutarlı.

⚠️ `settings.notifications.server.days`/`hours` A4r7'in eklediği **kullanılmayan**
anahtarlar — `orphan → ölü` listesinde, zararsız ama ölü. Silmedim (A4r7'in
alanı, i18n denetimi de ölü anahtarı kabul ediyor).

---

## 7. Negatif test ölçümü (3 düzeltme, hepsi ölçüldü)

| # | Geri alınan | Kırmızı çıktısı |
|---|---|---|
| 1 | `value: (i+1)%7` → `value: i` | `Expected: 'Pzt' Actual: 'Sal'` — **1 kırmızı** |
| 2 | `_asInt(...)` → `as int?` (5 satır) | **3 kırmızı** (String / num / bozuk değer testleri) |
| 3 | `(_saving \|\| !_prefsLoaded) ? null : _save` → `_saving ? null : _save` | **1 kırmızı** (yarım kayıt testi) |

Hepsi geri kondu, `flutter analyze` + ilgili dosyalar yeniden yeşil.

Ek ölçüm (test kırmızıya **düşmeyen** ama gerçek olan bulgu):
`tester.tap(find.text('Kaydet'))` **sessizce hiçbir şey yapmıyordu** —
`HitTestResult: Offset(713.7, 1140.0) is outside the bounds of the root … Size(800, 600)`.
`verify(profile.update)` çağrı sayısı **0** idi; yani 3 test "yeşil" görünürken
**hiçbir şey ölçmüyordu**. `ensureVisible` yetmiyordu (`end` hizalı `Row`).
`tapSave` artık gerekirse `drag` ile kaydırıyor → uyarı yok, gerçek yol ölçülüyor.

---

## 8. Doğrulama çıktıları

```
flutter analyze        → No issues found! (4.4s)
flutter test           → 00:34 +1004: All tests passed!   (910 → 1004, −0)
node tool/check_i18n   → ✓ 12 dil, 513 anahtar, 335 Flutter kodu anahtarı
node tool/check_versions → ✓ 1.3.0+4 (pubspec = AppConstants = CHANGELOG = README)
```

**Test sayısı 910 → 1004** (A4r7'nin 3 yeni dosyası: favorite_button 22,
message_list 32, notification_preferences 31 = +85; hesap silme ajanının
testleri de aynı koşuda sayıma girdi).

**Eşzamanlı ajan notu:** Ara koşuda 3 hata
(`account_local_cleanup_a4r4b_test.dart`, 3 × `TimeoutException after 0:10:00`)
göründü — bu dosya **hesap silme ajanının** alanında, benim testim değil; onlar
düzeltince final koşusu tamamen yeşil oldu. Aynı sırada onların
`toRow` saat-aralığı düzeltmesi (`start > end` → 23) geldiği için
`notification_preferences_a4r7_test.dart` bir tur kırmızıydı; testi **davranışı**
ölçecek şekilde hizaladım (§2 3. parça) ve 31/31 yeşil.

---

## 9. ⭐ A4r7'in bıraktığı ve **benim commitlemediğim** değişiklik

`flutter_app/analysis_options.yaml` çalışma ağacında **değişmiş** durumda ve
A4r7'ye ait:

```yaml
language: {strict-casts, strict-inference, strict-raw-types: true}   # Faz 1
linter: {always_declare_return_types, prefer_single_quotes, unawaited_futures}
```

- Bunlar A4r7'nin brifinde **yok**; A6 kalite ajanının "Faz 1" işi.
- `strict-raw-types` **mevcut kod tabanını** etkiler (`flutter test` yeşil
  olduğu için şu an patlama yok, ama 1 uyarı var: `test/data/.../new_write_paths_a2r9_test.dart:31`).
- Benim iki `lib/**` dosyam bu ayarlar altında temiz.
- **Commit etmedim** — alan sahipliği ihlali olurdu. A6'ya aktarım.

---

## 10. Kalan riskler

| Sev | Risk | Gerekçe / öneri |
|---|---|---|
| **P1** | `src/hooks/useNotifications.ts:30-33` `interval_hours: 0` yazıyor → web'de bildirim tercihi **kaydedilemiyor** (CHECK reddi) | `src/**` benim alanım değil. A1r8 A5r8'e aktardı. **Hâlâ duruyor.** |
| **P1** | `weigh_in_frequency_days` aralık denetimi yok: `_frequency` metin kutusuna `0` yazılabilir → `profiles_weigh_in_frequency_days_range` CHECK (1..365) reddeder → **profil kaydının tamamı** düşer (sunucu tercihleri de yazılmaz, `_save` tek `try` içinde) | A1r8 bulgusu, `_save` içinde `clamp(1, 365)` öneriyor. **Düzeltmedim** — metin alanı + hata mesajı ürün kararı; ayrıca `_frequency` **pre-existing** kod. |
| **P1** | `deleteFood`ın **hiç UI çağıranı yok** | "Silinen yemek favoriyi temizler" sözleşmesi yalnız veri katmanında ölçülüyor; yemek silme ekranı `features/**`'te hiç yok |
| **P2** | `weight <= 1000` / `amount <= 10000` CHECK'leri: UI'da üst sınır yok | `_save` tek `try` → bir CHECK reddi **profil + sunucu** kaydının ikisini de düşürür, kullanıcı yalnız "Hata" görür |
| **P2** | `server.days` / `server.hours` ölü çeviri anahtarı | `orphan → ölü`; zararsız, silinebilir |
| **P2** | `_summary_day` gece/gündüz saat aralığı (21→09) **desteklenmiyor**; `toRow` 23'e çekiyor | Sunucu `start <= end` bekliyor; gece aralığı isteyen kullanıcı yanlış davranış alıyor. Bilinçli karar, yorumda belgeli |
| **P2** | Eşzamanlı ajanlarla **aynı dosyalara** yazma (`notification_preferences_repository.dart`, `notification_preferences_a4r7_test.dart`) | Bu turda iki kez oldu; son hâl üstte kalan değil, tesadüf. Alan sahipliği ihlali riski |
| **P3** | `analysis_options.yaml` A4r7'den kalan, commitlenmemiş "Faz 1" sıkılaştırması | §9 |
