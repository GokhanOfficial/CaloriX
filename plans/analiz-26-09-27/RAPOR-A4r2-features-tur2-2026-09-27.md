# RAPOR — A4r2 Flutter Features (Tur 2) — 2026-09-27

**Kapsam:** `flutter_app/lib/features/**`, `flutter_app/lib/app.dart`, `flutter_app/lib/shared/**`
**Pusula:** `plans/analiz-26-09-27/PROTOKOL.md` §6
**Commit:** `a4b1e01` — 13 dosya (lib) + 2 yeni test dosyası

---

## Özet (5 madde)

1. **P1 güvenlik:** Zorunlu güncelleme ekranı (`force_update_page.dart`) uzak manifestten gelen `apkUrl`'i **şema doğrulaması olmadan** `url_launcher`'a veriyordu. Ekran artık A3'ün `UpdateManifest.isSafeApkUrl` kapısını kullanıyor; `javascript:` / `intent:` / `file:` / `data:` / `content:` / `market:` / `http:` reddediliyor ve kullanıcı bilgilendiriliyor. 13 yeni widget testi kanal seviyesinde `launchUrl` çağrılmadığını doğruluyor.
2. **P1 veri:** `activity_level` enum uyuşmazlığı **4 yazma/okuma noktasında** düzeltildi. Yazma yönü `ActivityLevel.name` → `activityLevelToDb(...)` (A2'nin `lib/data/activity_level_map.dart` fonksiyonu), okuma yönü ise `ActivityLevel.values.asNameMap()[...]` → `activityLevelFromDb(...)`. Düzeltilmeyen hâliyle `very_active` satırları sessizce `moderate`'a (TDEE 1.55) düşüyordu.
3. **P1 hata tipleri:** A2'nin yeni imzaları features tarafında yakalandı — `ChatException` (chat), `ArgumentError` (kilo/su/4 öğün dialogu). Artık "gönderilemedi" gibi yanlış mesajlar yerine duruma özel metin gösteriliyor. 5 diyalogda `on ArgumentError` bloğu + `AppLog` eklendi.
4. **P2 i18n:** `onboarding_page.dart` (~18 satır), `password_dialog.dart` (4), `analytics_page.dart` tooltip listesi çeviri anahtarına taşındı. **35 yeni anahtar** için 12 dil tablosu aşağıda (JSON'a dokunulmadı — A6 alanı). Analytics makro adları için mevcut `settings.goals.protein/carbs/fat` anahtarları yeniden kullanıldı (yeni anahtar gerekmedi).
5. **P2/P1 kalanlar:** Sohbet geçmişi **200 mesajlık bellek penceresi** ile sınırlandı (+ "Daha eski mesajları yükle" düğmesi, `ListView` kaydırma koruması). `analytics_page` `onRefresh` artık `ref.refresh(...future)` ile yeni verinin gelmesini bekliyor.

---

## Düzeltilenler

| Sev | Dosya | Ne yapıldı | Doğrulama |
|---|---|---|---|
| **P1** | `features/updates/force_update_page.dart:18-45` | `apkUrl` **şema doğrulaması olmadan** `url_launcher`'a veriliyordu. A3'ün `core/updates/update_manifest.dart:58` `isSafeApkUrl` (https + host + userInfo yok + `.apk` uzantısı) süzgeci eklendi. `canLaunchUrl` öncesi kapı; reddedilirse `updates.unsafeUrl` SnackBar'ı + `debugPrint` (şema adı sızdırılmadan). `messenger` await öncesi yakalandı. `core/updates/**`'e **hiç dokunulmadı** (imza: `bool get isApkUrlSafe` ve `static bool isSafeApkUrl(String raw)` — A3'ün mevcut imzası birebir kullanıldı). | `test/features/updates/force_update_page_test.dart` — **13/13 geçti** |
| **P1** | `features/onboarding/onboarding_page.dart:167` | `'activity_level': _activity.name` → `activityLevelToDb(_activity)`. `veryActive` DB CHECK ihlali (`activity_level IN (...,'very_active')`) nedeniyle reddediliyordu. | `test/features/settings/activity_level_map_test.dart` |
| **P1** | `features/settings/widgets/goals_dialog.dart:59-61,135` | Yazma: `activityLevelToDb`. **Okuma:** `ActivityLevel.values.asNameMap()[profile.activityLevel] ?? moderate` → `activityLevelFromDb(...)`. `asNameMap()['very_active']` `null` döndüğü için **her açılışta** aktivite `moderate`'a düşüyordu. | aynı test, "eski hatalı okumanın sessiz kaybı kapatıldı" |
| **P1** | `features/settings/widgets/personal_info_dialog.dart:166` | Okuma yönü: `asNameMap()` → `activityLevelFromDb`. Otomatik makro yeniden hesaplaması 1.9 yerine 1.55 çarpanıyla hesaplanıyordu. | aynı test |
| **P1** | `features/dashboard/widgets/weight_card.dart:72` | Okuma yönü: `asNameMap()` → `activityLevelFromDb`. Kilo güncellemesi sonrası TDEE yanlış çarpanla hesaplanıyordu. | aynı test |
| **P1** | `features/chat/chat_page.dart:189-251` | A2 `invokeAssistant`'ı `null` yerine `ChatException` fırlatıyor. Ekran `catch (_)` ile **her şeyi "Mesaj gönderilemedi"** diye gösteriyordu — kullanıcı mesajı DB'ye yazılmış olmasına rağmen "gönderilemedi" görüyor ve mesajını tekrar yazıyordu. `on ChatException` ayrı bloğu + `chat.errors.assistant` mesajı. `if (assistant != null)` ölü kod kaldırıldı (`assistant!`). | analyze temiz, mevcut testler yeşil |
| **P1** | `features/dashboard/widgets/weight_card.dart:48-66` | `addWeightEntry` artık `ArgumentError` fırlatabiliyor (NaN/Inf/≤0). Genel "Kilo kaydedilemedi" yerine `on ArgumentError` → `dialogs.invalidAmount` + `AppLog.w`. | analyze temiz |
| **P1** | `features/dashboard/widgets/water_tracker.dart:59-73` | `addWaterEntry` `ArgumentError` fırlatıyor (A2 kontrolü `≤0`; hızlı ekleme butonları sabit 250/500 verir, özel giriş `>0` filtreliyor ama savunma-derinliği için gerekli). `on ArgumentError` → `dialogs.invalidAmount`. | analyze temiz |
| **P1** | `features/add/widgets/add_from_food_dialog.dart:113-127` | `addMealEntry` `ArgumentError` → `dialogs.invalidAmount` + `AppLog.w` (`addFood.toasts.error` yerine). | analyze temiz |
| **P1** | `features/add/widgets/add_manual_entry_dialog.dart:93-107` | aynı | analyze temiz |
| **P1** | `features/add/widgets/edit_meal_entry_dialog.dart:152-166` | `updateMealEntry` kısmi güncellemede `amount_g_ml`'yi doğruluyor → `ArgumentError` → `dialogs.invalidAmount`. | analyze temiz |
| **P1** | `features/add/widgets/recognition_confirm_dialog.dart:247-270` | Çoklu kayıt: satır 5'te `ArgumentError` → `dialogs.invalidAmountPartial` (`{count}` = kaydedilen satır sayısı). Kısmi kayıt durumunda "hiçbir şey kaydedilmedi" izlenimi yanlış olurdu. | analyze temiz |
| **P2** | `features/onboarding/onboarding_page.dart:66-97` | **Sabit Türkçe metinler çeviriye** taşındı. Ek olarak **gerçek bir tutarsızlık** bulundu: hata metinleri "Boy 100-250", "Kilo 30-300" derken kontroller 50-250 ve 20-400 idi. Aralıklar `_minHeightCm`/`_maxHeightCm`/`_minWeightKg`/`_maxWeightKg`/`_minAge`/`_maxAge` sabitlerine taşındı, mesajlar `{min}`/`{max}` ile dolduruluyor. | analyze temiz; `errHeightRange`/`errWeightRange` 12 dil tablosunda |
| **P2** | `features/onboarding/onboarding_page.dart:184,194,230,295-543,614` | Kalan 14 sabit metin (`'Profil kaydedilirken…'`, `'Adım $_step / N'`, `'Sizi Tanıyalım'`, `'İsminiz'`, `'Seçiniz'`, `'Boy ve Kilo'`, `'Ne Kadar Aktifsiniz?'`, `'Hedefiniz Nedir?'`, `'Hedefleriniz Hesaplanıyor…'`, `'Hesaplama Başarısız'`, `'Lütfen geri dönüp…'`, `'Hedefleriniz Hazır!'`, `'Yerel Hesaplama'`, `'İleri'`) → `onboarding.*` anahtarları. `_stepHeader(icon, title, subtitle)` imzası artık **çeviri anahtarı** alıyor (`String` değil, `.tr()` burada). | analyze temiz |
| **P2** | `features/settings/widgets/password_dialog.dart:96,99,106,107,122,131,141` | `'Parola Değiştir'`, `'Yeni parolanızı girin'`, `'Yeni Parola'`, `'En az 6 karakter'`, `'Parola Tekrar'`, `'Parolayı tekrar girin'`, `'İptal'`, `'Kaydet'` → `auth.changePassword.*` / `common.cancel` / `common.save`. `İptal`/`Kaydet` için yeni anahtar açılmadı (`common.*` zaten var). Ek: göz düğmesinin `tooltip`'i yoktu (ekran okuyucu boşluğu) → `auth.changePassword.toggleVisibility`. | analyze temiz |
| **P2** | `features/analytics/analytics_page.dart:838-841` | `const names = ['Protein','Karbonhidrat','Yağ']` → `MacroFocus.values[ri].labelKey.tr()`. Mevcut `settings.goals.protein/carbs/fat` anahtarları kullanıldı (EN'de "Protein (g)" vb. — tooltip'te parantezli metin çıkar, kabul edilebilir; **yeni `analytics.macros.*` anahtarı açılmadı** çünkü `analytics` bölümü zaten var ve `MacroFocus.labelKey` tek kaynak olarak bu anahtarları işaret ediyor). | `macro_focus_test.dart` (mevcut, `labelKey` sözleşmesi) yeşil |
| **P2** | `features/analytics/analytics_page.dart:104-112` | `onRefresh: () async => ref.invalidate(...)` → `() => ref.refresh(provider.future)`. `invalidate` Future'ü **anında** tamamlıyordu → `RefreshIndicator` parmak bırakılır bırakılmaz kayboluyor, ekranda hâlâ eski veri varken "yenilendi" izlenimi veriyordu. | analyze temiz |
| **P2** | `features/chat/chat_page.dart:36-200,368-400,513-554` | Sohbet geçmişi **append-only** idi: her `loadMore` başa 10 mesaj ekliyor, `_messages` sınırsız büyüyordu (`ListView.builder` yalnızca görünen balonları kurar ama **gövdeler ve çözülmüş Markdown** tamamen bellekte). `_historyWindow = 200` penceresi eklendi: `_trimToWindow()` en eskiyi atar, `_windowStartBefore` imleci "daha eski yükleme"yi kaldığı yerden sürdürür, `_LoadEarlierHeader` düğmesi (klavye/ekran okuyucu için erişilebilir yedek), yukarı kaydırma korunur. Pencere taşarsa `maxScrollExtent` farkı yanlış olduğu için scroll `0`'a atılır (kullanıcı sıçramasın). | analyze temiz; mevcut testler yeşil |

---

## Bulunurlar (düzeltilmedi, gerekçe)

| Sev | Dosya:satır | Bulgu | Etki | Öneri |
|---|---|---|---|---|
| P2 | `features/settings/widgets/transfer_dialogs.dart:45` | `subject: 'CaloriX backup'` sabit metin | Çok düşük | **Bırakıldı — gerekçelendirildi:** (a) marka adı (`CaloriX`) çeviri kapsamında olmamalı; (b) `subject` bir **e-posta konu satırı**, kullanıcıya gösterilen UI metni değil — `share_plus` bunu varsayılan uygulamanın paylaşım ekranına iletir. Çevirilirse e-posta başlığı hedef alıcının diline göre değişir (paylaşılan içerik Türkçe olmadan), bu da tutarsızlık. Diğer iki konu satırı `settings.*` çevirilerinde zaten sabit; tutarlılık için `CaloriX backup` de sabit kalmalı. |
| P2 | `features/settings/settings_page.dart:287-296` | `_LanguageTile._names` 12 dil adı sabit (`Türkçe`, `Français`, `Русский` …) | Yok | **Bırakıldı — doğru karar:** Bunlar dilin **kendisinin öz adıdır** (endonym), her dilde aynı yazılır. Çevirilirse "Türkçe" seçeneği İngilizce arayüzde "Turkish" olur ve kullanıcı kendi dilini bulamaz. |
| P3 | `features/about/about_page.dart:89` | `'Gökhan Tekyıldırım'` yazar adı sabit | Yok | Bırakıldı — kişi adı, çevirilmemeli. |
| P3 | `features/add/widgets/add_manual_entry_dialog.dart:142` | `'dialogs.example'` için örnek `"Tavuk Göğsü"` sabit | Düşük (ipucu metni) | Bırakıldı — `namedArgs {example}` ile geliyor; çeviri dosyasındaki `dialogs.example` zaten `{example}` placeholder'ı içeriyor. A6 örnek değerleri `example` parametresine göre locale'leyebilir (anahtar zaten mevcut, yeni anahtar gerekmiyor). |
| P3 | `features/add/widgets/in_app_camera_screen.dart:108,133`, `add_with_ai_dialog.dart:156`, `chat_page.dart:113,169,245,268,299`, `meal_section.dart:53,64`, `weight_card.dart:53,59,111`, `water_tracker.dart:62,67` | Sabit Türkçe metinler | Yok | Bırakıldı — **hepsi `AppLog.*` çağrılarında** (Sentry'ye gider, kullanıcıya gösterilmez). Kullanıcıya gösterilen metinler zaten `.tr()` anahtarı. |
| ~~P2~~ | `assets/translations/*.json` | **35 yeni anahtar** kodda `.tr()` ile çağrılıyordu, JSON'da yokdu | Yüksek (12 dilin hepsinde) | ✅ **A6 tur ortasında uyguladı** — 12 dilin tamamında doğrulandı (aşağıdaki §8 tablosu referans; JSON'daki değerlerin bazıları benim taslağımdan daha iyi, ör. `ar` `calcErrorHint`) |
| P2 | `features/updates/force_update_page.dart` | `apkUrl` güvenli olsa bile **`sha256` doğrulanmıyor** — kullanıcı indirdiği APK'yı doğrulayamıyor | Orta | A3r2 görevlendirmesinde "Manifest `sha256` doğrulaması" var; `UpdateManifest.sha256` alanı zaten mevcut. Bu turun kapsamı dışı (indirme + hash doğrulama = native taraf işi). |
| P3 | `features/onboarding/onboarding_page.dart` | `totalSteps` sabit 5, adım içerikleri 5 ayrı `_stepX()` fonksiyonunda | Refactor riski | Tur 3 — düşük değer, mevcut yapı okunabilir. |
| P2 | `features/chat/chat_page.dart` | Bellek penceresi **200 mesaj**; `_pendingFiles` byte'ları **oturum boyunca** bellekte (her seçimde ekleniyor, gönderimde temizleniyor) | Orta | Tur 3: ek sayısına da üst sınır (örn. 5 dosya) + toplam byte sınırı. `_maxAttachmentBytes` tek dosya için, toplam koruması yok. |

---

## Doğrulananlar (görev 5 — A6'nın eklediği 5 anahtar)

| Anahtar | JSON'da var mı? | Çağrı yeri | Değer (tr / en) | Not |
|---|---|---|---|---|
| `common.comingSoon` | ✅ `tr.json:25`, `en.json:25` | `shared/widgets/placeholder_page.dart:30` | `Çok yakında` / `Coming soon` | Doğru |
| `errors.notFound` | ✅ `tr.json:561`, `en.json:561` | `features/not_found/not_found_page.dart:13` | `Sayfa bulunamadı` / `Page not found` | Doğru |
| `dialogs.flash` | ✅ `tr.json:136`, `en.json:136` | `features/add/widgets/in_app_camera_screen.dart:205` | `Flaş` / `Flash` | Doğru |
| `dialogs.photoTooLarge` | ✅ `tr.json:135`, `en.json:135` | `features/add/widgets/add_with_ai_dialog.dart:112` | `Fotoğraf çok büyük` / `Photo is too large` | Doğru — kullanıcı teknik terim görmüyor |
| `dialogs.amountRequired` | ✅ `tr.json:137`, `en.json:137` | `features/add/widgets/recognition_confirm_dialog.dart:521` | `Miktar gerekli` / `Amount is required` | **Uygun**, ancak kullanım yeri biraz farklı: metin `r.amount <= 0` iken (yani alan **dolu ama 0**) gösteriliyor. "Miktar gerekli" 0 için "Miktar 0'dan büyük olmalı" daha isabetli olurdu. Mevcut değer yanlış değil, kaba bir eşleşme — **düzeltilmedi** (JSON benim alanım değil; A6 isterse `tr: "Miktar 0'dan büyük olmalı"` / `en: "Amount must be greater than 0"` olarak günceller). |

> `tr.json` ve `en.json` **433 anahtarın tamamıyla eşleşiyor** (eksik anahtar tespit edilmedi); yukarıdaki 5'i artık ikisinde de mevcut.

---

## AKTARIM (başka alana)

### → A6 (i18n) — **35 yeni anahtar, 12 dil** — ✅ TAMAMLANDI

A6 §8 tablosunu uyguladı; 12 dilin 12'sinde de tüm anahtarlar ve `{min}`/`{max}`/`{step}`/`{total}`/`{count}` placeholder'ları doğrulandı. **`analytics.macros.*` açılmadı** — mevcut `settings.goals.protein/carbs/fat` kullanıldı. Tablo §8'de.

### → A2r2 (veri katmanı) — **`activity_level` entegrasyonu tamam**

- A2'nin `lib/data/activity_level_map.dart`'i tur ortasında (çalışırken) düştü; imzalar benim yazdığım `lib/shared/activity_level_map.dart` ile **birebir aynıydı** (`String activityLevelToDb(ActivityLevel)`, `ActivityLevel activityLevelFromDb(...)`). Ben kendi kopyamı **sildim** ve 4 features dosyasını A2'nin `lib/data/activity_level_map.dart`'ine bağladım. **Tek doğruluk kaynağı = `lib/data/activity_level_map.dart`.**
- A2'nin `fromDb` imzası `String?` yerine **`Object?`** (loglama için) — features tarafı sorunsuz, `String?` argümanları da kabul ediyor.
- A2'nin `fromDb`'si **camelCase toleransı yok** (`'veryActive'` → `moderate`). Bu **kasıtlı ve doğru**: DB CHECK yalnızca snake_case kabul ettiği için camelCase satır DB'de hiçbir zaman oluşamaz; eski `veryActive` satırları yazılamazdı. İçe aktarılan yedeklerde varsa `moderate` fallback'i + `AppLog.w` doğru davranış.
- **A2'ye kalan:** `macro_calculator.dart:68` hâlâ `'activity_level': activityLevel.name` gönderiyor → `calculate-macros` edge function `requireEnum(body.activity_level, ACTIVITY_LEVELS)` ile `veryActive`'ı **400 ile reddediyor**, sessizce yerel fallback'e düşüyor. `MacroCalculator` zaten `lib/data/` altında → A2 alanı, dokunmadım.

### → A3r2 (çekirdek)

- `core/utils/num_parsing.dart:15` — `library` direktifi diğerlerinden sonra geliyor, `flutter analyze` **hata** veriyor (`library_directive_not_first`). Dosya A3'ün alanında; A2r2 oluşturmuş, A3r2 düzeltmeli.
- `core/utils/calculations.dart` → `MacroCalculator.calculate` `bmi`'yi hâlâ `try` dışında çağırıyor (`macro_calculator.dart:56`). A2r2 görevlendirmesinde var; `Calculations.bmi` artık sonlu değer döndürüyor (A3 düzeltmesi) ama **`try` dışında kalması** savunma-derinliği eksiği.

### → Ana ajan

- `test/core/utils/data_write_safety_test.dart` (A2r2, in-flight) **3 test kırık** — `MacroCalculator` negatif kilo → `-26.1` protein, `activity_level` edge function gövdesi boş, `analyticsDataProvider` `AnalyticsAuthRequired` yerine `Supabase.instance` assertion'ı atıyor. Tam koşu `+370 -3` veriyor; **3'ü de A2'nin dosyasında**, benim alanımda 0 kırık.
- `tool/check_i18n.cjs` A6 tarafından genişletilmiş (202 satır) — yeni anahtarlarım için de kontrol edilmeli.

---

## Yeni testler

### `flutter_app/test/features/updates/force_update_page_test.dart` (yeni, **13 test — hepsi geçiyor**)

`url_launcher` platform kanalı (`plugins.flutter.io/url_launcher`) mock'lanır; `launch` çağrıları kaydedilir.

| Test | Kapsam |
|---|---|
| `https GitHub APK adresi kabul edilir ve launch edilir` | `tool/release_android.sh`'in ürettiği gerçek URL → `launchUrl` **çağrılıyor**, argüman `.apk` içeriyor, SnackBar yok |
| 11 × `güvensiz apkUrl — launch edilmez` | `javascript:` / `intent:` / `file:` / `data:` / `content:` / `http:` / `market:` / boş / `::::` format hatalı / `.apk` uzantısı yok / `https://user:pass@host` → **`launches` boş**, kullanıcı bilgilendiriliyor, `takeException()` null |
| `süzgeç saf süzgeçle aynı kararı verir` | Ekranın kapısı ile `UpdateManifest.isSafeApkUrl` sonucu birebir aynı; sapma açık yönlendirme yüzeyini geri açar |

### `flutter_app/test/features/settings/activity_level_map_test.dart` (yeni, **6 test — hepsi geçiyor**)

| Test | Kapsam |
|---|---|
| `5 değerin tamamı DB sütununun kabul ettiği değerler` | `toDb` çıktıları migration'daki CHECK listesiyle birebir |
| `hiçbir enum değeri camelCase sızmıyor (regresyon)` | 5 enum'un tamamı `ActivityLevelMap.dbValueSet` içinde; `veryActive.name != toDb(veryActive)` |
| `snake_case DB değerleri doğru enum'a döner` | 5/5 okuma yönü |
| `null / boş / bilinmeyen → moderate (çökmez)` | Çökmez, `moderate` fallback |
| `eski hatalı okumanın sessiz kaybı kapatıldı` | `asNameMap()['very_active']` **null** → `fromDb('very_active')` **moderate değil** (regresyon kanıtı) |
| `gidiş-dönüş: 5/5 enum için değişmez` | `fromDb(toDb(x)) == x` |

---

## Doğrulama (fiili çıktı)

```
$ cd flutter_app && flutter analyze
3 issues found (hepsi A2r2'nin in-flight dosyalarında).
  → 3/3 başka ajanların **in-flight** dosyalarında:
     • error   ×1  test/core/utils/data_write_safety_test.dart:590  (currentUserProvider undefined)
     • info    ×1  test/core/utils/data_write_safety_test.dart:2    (functions_client bağımlılığı)
     • warning ×1  test/data/activity_level_map_test.dart:2         (num_parsing kullanılmıyor)
  → Benim alanımda (lib/features/**, lib/shared/**, test/features/**):
     **0 sorun**. (P1 sırasında `No issues found!`; A2r2 ilk çalıştırmasında
     `core/utils/num_parsing.dart:15` hata vermişti, sonra düzeltti.)

$ cd flutter_app && flutter test
$ # A2r2'nin data_write_safety_test.dart'i yazılıyorken:
+366: All tests passed!                    ← tam koşu yeşil
+370 -3 / +337 -1: Some tests failed.     ← A2r2 test dosyası in-flight
   Kırık testlerin tamamı test/core/utils/data_write_safety_test.dart (A2 alanı):
     1. derleme: `currentUserProvider` undefined (satır 590)
     2. MacroCalculator negatif kilo → -26.1 protein
     3. activity_level edge function gövdesi boş
     4. analyticsDataProvider AnalyticsAuthRequired yerine Supabase assertion'ı
   A6 çevirileri (12 dil) düştükten sonraki koşu: +337 -1 (sadece yukarıdaki
   derleme hatası). A2r2 commit edince tam koşu yeşile dönecek.

$ # Kendi alanım + komşu çekirdek testler (A2r2'nin in-flight dosyası hariç):
$ flutter test test/features/ test/core/updates/ test/core/utils/calculations_test.dart \
    test/core/utils/calculations_edge_cases_test.dart test/widget_test.dart
+120: All tests passed!
```

---

## Sonraki öneriler (Tur 3)

1. **`macro_calculator.dart:68`** — `activityLevel.name` → `activityLevelToDb(activityLevel)`. `calculate-macros` edge function `veryActive`'ı 400 ile reddedip sessizce yerel fallback'e düşürüyor (A2 alanı, A2r2'ye).
2. **Ekleme toplam byte sınırı** — `_pendingFiles` oturum boyunca bellekte; `_maxAttachmentBytes` tek dosya için. Toplam sınır + dosya sayısı sınırı (`chat_page.dart`).
3. **`sha256` doğrulaması** — manifest'te alan var, indirilen APK doğrulanmıyor (A3r2 alanı; native taraf işi).
4. **`dialogs.amountRequired` değeri** — `r.amount <= 0` durumunda "Miktar 0'dan büyük olmalı" daha isabetli (A6).
5. **`tool/check_i18n.cjs`'e yeni anahtar tablosu** — A6 uyguladıktan sonra `onboarding.*` (24 anahtar) eksiksiz doğrulanmalı.
6. **`onboarding` alan aralıkları** — `20-400 kg` / `50-250 cm` BMI limitleriyle uyumlu ama 20 kg altı çocuk profiline izin veriyor; 13+ yaş doğrulaması var, düşük kilo sınırı tartışmaya açık.

---

## 8. 12 DİL ÇEVİRİ TABLOSU (A6 uygulayacak)

> `assets/translations/*.json` dosyalarına **dokunulmadı** (A6 alanı).
> ✅ **A6 tur ortasında uyguladı** — 12 dilin tamamında placeholder aritmetiği dahil doğrulandı.
> Toplam **35 yeni anahtar** + 5 anahtar yeniden kullanımı.
> `analytics.macros.*` **açılmadı** — mevcut `settings.goals.protein/carbs/fat` kullanılıyor.

### 8.1 `onboarding.*` — 24 yeni anahtar

| Anahtar | tr | en | de | es | fr | it | pt | ru | ar | ja | ko | zh |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `onboarding.step` | Adım {step} / {total} | Step {step} / {total} | Schritt {step} / {total} | Paso {step} / {total} | Étape {step} / {total} | Passaggio {step} / {total} | Etapa {step} / {total} | Шаг {step} / {total} | الخطوة {step} / {total} | ステップ {step} / {total} | {total}단계 중 {step}단계 | 第 {step} 步 / 共 {total} 步 |
| `onboarding.stepPersonalTitle` | Sizi Tanıyalım | Let's Get to Know You | Lernen wir Sie kennen | Conozcámonos | Faisons connaissance | Conosciamoci | Vamos conhecer você | Познакомимся | لنتعرّف عليك | あなたについて教えてください | 우리를 알아가요 | 让我们了解一下你 |
| `onboarding.stepPersonalSubtitle` | Kişisel Bilgiler | Personal Information | Persönliche Daten | Información personal | Informations personnelles | Dati personali | Informações pessoais | Личная информация | المعلومات الشخصية | 基本情報 | 개인정보 | 个人信息 |
| `onboarding.stepBodyTitle` | Boy ve Kilo | Height and Weight | Größe und Gewicht | Altura y peso | Taille et poids | Altezza e peso | Altura e peso | Рост и вес | الطول والوزن | 身長と体重 | 키와 몸무게 | 身高和体重 |
| `onboarding.stepBodySubtitle` | Vücut Ölçüleri | Body Measurements | Körpermaße | Medidas corporales | Mensurations corporelles | Misure corporee | Medições corporais | Замеры тела | قياسات الجسم | 体格の測定 | 신체 측정값 | 身体尺寸 |
| `onboarding.stepActivityTitle` | Ne Kadar Aktifsiniz? | How Active Are You? | Wie aktiv sind Sie? | ¿Qué tan activo eres? | Quel est votre niveau d'activité ? | Quanto sei attivo? | Quão ativo você é? | Насколько вы активны? | ما مدى نشاطك؟ | 活動量はどれくらいですか | 활동량은 어느 정도인가요 | 你的活动量如何？ |
| `onboarding.stepActivitySubtitle` | Aktivite Seviyesi | Activity Level | Aktivitätslevel | Nivel de actividad | Niveau d'activité | Livello di attività | Nível de atividade | Уровень активности | مستوى النشاط | 活動レベル | 활동 수준 | 活动水平 |
| `onboarding.stepGoalTitle` | Hedefiniz Nedir? | What Is Your Goal? | Was ist Ihr Ziel? | ¿Cuál es tu objetivo? | Quel est votre objectif ? | Qual è il tuo obiettivo? | Qual é o seu objetivo? | Какова ваша цель? | ما هو هدفك؟ | 目標は何ですか | 목표는 무엇인가요 | 你的目标是什么？ |
| `onboarding.stepGoalSubtitle` | Hedef Türü | Goal Type | Zieltyp | Tipo de objetivo | Type d'objectif | Tipo di obiettivo | Tipo de objetivo | Тип цели | نوع الهدف | 目標の種類 | 목표 유형 | 目标类型 |
| `onboarding.fieldName` | İsminiz | Your Name | Ihr Name | Tu nombre | Votre nom | Il tuo nome | Seu nome | Ваше имя | اسمك | お名前 | 이름 | 你的姓名 |
| `onboarding.pick` | Seçiniz | Select | Auswählen | Seleccionar | Sélectionner | Seleziona | Selecionar | Выберите | اختر | 選択してください | 선택하세요 | 请选择 |
| `onboarding.next` | İleri | Next | Weiter | Siguiente | Suivant | Avanti | Próximo | Далее | التالي | 次へ | 다음 | 下一步 |
| `onboarding.calculating` | Hedefleriniz Hesaplanıyor… | Calculating Your Goals… | Ihre Ziele werden berechnet… | Calculando tus objetivos… | Calcul de vos objectifs… | Calcolo dei tuoi obiettivi… | Calculando seus objetivos… | Расчёт ваших целей… | جارٍ حساب أهدافك… | 目標を計算しています… | 목표를 계산하는 중… | 正在计算你的目标… |
| `onboarding.calculatingSubtitle` | Bir saniye | Just a moment | Einen Moment | Un momento | Un instant | Un momento | Um momento | Мгновение | لحظة | 少々お待ちください | 잠시만요 | 请稍候 |
| `onboarding.goalsReady` | Hedefleriniz Hazır! | Your Goals Are Ready! | Ihre Ziele sind fertig! | ¡Tus objetivos están listos! | Vos objectifs sont prêts ! | I tuoi obiettivi sono pronti! | Seus objetivos estão prontos! | Ваши цели готовы! | أهدافك جاهزة! | 目標の準備ができました！ | 목표가 준비되었습니다! | 你的目标已准备好！ |
| `onboarding.localCalculation` | Yerel Hesaplama | Local Calculation | Lokale Berechnung | Cálculo local | Calcul local | Calcolo locale | Cálculo local | Локальный расчёт | حساب محلي | ローカル計算 | 로컬 계산 | 本地计算 |
| `onboarding.calcError` | Hesaplama Başarısız | Calculation Failed | Berechnung fehlgeschlagen | Error en el cálculo | Échec du calcul | Calcolo non riuscito | Falha no cálculo | Не удалось рассчитать | فشل الحساب | 計算に失敗しました | 계산에 실패했습니다 | 计算失败 |
| `onboarding.calcErrorHint` | Lütfen geri dönüp tekrar deneyin | Please go back and try again | Bitte gehen Sie zurück und versuchen Sie es erneut | Vuelve atrás e inténtalo de nuevo | Veuillez revenir en arrière et réessayer | Torna indietro e riprova | Volte e tente novamente | Пожалуйста, вернитесь и попробуйте снова | يُرجى العودة والمحاولة مرة أخرى | 戻って、もう一度お試しください | 뒤로 가서 다시 시도해 주세요 | 请返回后重试 |
| `onboarding.saveError` | Profil kaydedilirken bir hata oluştu | An error occurred while saving your profile | Beim Speichern des Profils ist ein Fehler aufgetreten | Error al guardar el perfil | Une erreur s'est produite lors de l'enregistrement du profil | Si è verificato un errore durante il salvataggio del profilo | Erro ao salvar o perfil | Ошибка при сохранении профиля | حدث خطأ أثناء حفظ الملف الشخصي | プロフィールの保存中にエラーが発生しました | 프로필 저장 중 오류가 발생했습니다 | 保存个人资料时出错 |
| `onboarding.errNameShort` | İsim en az 2 karakter olmalı | Name must be at least 2 characters | Name muss mindestens 2 Zeichen haben | El nombre debe tener al menos 2 caracteres | Le nom doit contenir au moins 2 caractères | Il nome deve contenere almeno 2 caratteri | O nome deve ter pelo menos 2 caracteres | Имя должно содержать не менее 2 символов | يجب أن يتكون الاسم من حرفين على الأقل | 名前は2文字以上で入力してください | 이름은 2자 이상이어야 합니다 | 姓名至少需要 2 个字符 |
| `onboarding.errBirthRequired` | Doğum tarihi gerekli | Date of birth is required | Geburtsdatum ist erforderlich | La fecha de nacimiento es obligatoria | La date de naissance est requise | La data di nascita è obbligatoria | A data de nascimento é obrigatória | Дата рождения обязательна | تاريخ الميلاد مطلوب | 生年月日を入力してください | 생년월일이 필요합니다 | 需要填写出生日期 |
| `onboarding.errAgeRange` | Yaş {min}-{max} arasında olmalı | Age must be between {min} and {max} | Alter muss zwischen {min} und {max} liegen | La edad debe estar entre {min} y {max} | L'âge doit être compris entre {min} et {max} | L'età deve essere tra {min} e {max} | A idade deve estar entre {min} e {max} | Возраст должен быть от {min} до {max} | يجب أن يكون العمر بين {min} و{max} | 年齢は{min}〜{max}の範囲で入力してください | 나이는 {min}~{max} 사이여야 합니다 | 年龄必须在 {min} 到 {max} 之间 |
| `onboarding.errHeightRange` | Boy {min}-{max} cm arasında olmalı | Height must be between {min} and {max} cm | Größe muss zwischen {min} und {max} cm liegen | La altura debe estar entre {min} y {max} cm | La taille doit être comprise entre {min} et {max} cm | L'altezza deve essere tra {min} e {max} cm | A altura deve estar entre {min} e {max} cm | Рост должен быть от {min} до {max} см | يجب أن يكون الطول بين {min} و{max} سم | 身長は{min}〜{max}cmの範囲で入力してください | 키는 {min}~{max}cm 사이여야 합니다 | 身高必须在 {min} 到 {max} 厘米之间 |
| `onboarding.errWeightRange` | Kilo {min}-{max} kg arasında olmalı | Weight must be between {min} and {max} kg | Gewicht muss zwischen {min} und {max} kg liegen | El peso debe estar entre {min} y {max} kg | Le poids doit être compris entre {min} et {max} kg | Il peso deve essere tra {min} e {max} kg | O peso deve estar entre {min} e {max} kg | Вес должен быть от {min} до {max} кг | يجب أن يكون الوزن بين {min} و{max} كجم | 体重は{min}〜{max}kgの範囲で入力してください | 몸무게는 {min}~{max}kg 사이여야 합니다 | 体重必须在 {min} 到 {max} 公斤之间 |
| `onboarding.errTargetWeightRange` | Hedef kilo {min}-{max} kg arasında olmalı | Target weight must be between {min} and {max} kg | Zielgewicht muss zwischen {min} und {max} kg liegen | El peso objetivo debe estar entre {min} y {max} kg | Le poids cible doit être compris entre {min} et {max} kg | Il peso obiettivo deve essere tra {min} e {max} kg | O peso-alvo deve estar entre {min} e {max} kg | Целевой вес должен быть от {min} до {max} кг | يجب أن يكون الوزن المستهدف بين {min} و{max} كجم | 目標体重は{min}〜{max}kgの範囲で入力してください | 목표 몸무게는 {min}~{max}kg 사이여야 합니다 | 目标体重必须在 {min} 到 {max} 公斤之间 |

### 8.2 `auth.changePassword.*` — 6 yeni anahtar

| Anahtar | tr | en | de | es | fr | it | pt | ru | ar | ja | ko | zh |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `auth.changePassword.title` | Parola Değiştir | Change Password | Passwort ändern | Cambiar contraseña | Changer le mot de passe | Cambia password | Alterar senha | Изменить пароль | تغيير كلمة المرور | パスワードを変更 | 비밀번호 변경 | 修改密码 |
| `auth.changePassword.subtitle` | Yeni parolanızı girin | Enter your new password | Geben Sie Ihr neues Passwort ein | Introduce tu nueva contraseña | Saisissez votre nouveau mot de passe | Inserisci la tua nuova password | Digite sua nova senha | Введите новый пароль | أدخل كلمة المرور الجديدة | 新しいパスワードを入力してください | 새 비밀번호를 입력하세요 | 输入新密码 |
| `auth.changePassword.newLabel` | Yeni Parola | New Password | Neues Passwort | Nueva contraseña | Nouveau mot de passe | Nuova password | Nova senha | Новый пароль | كلمة المرور الجديدة | 新しいパスワード | 새 비밀번호 | 新密码 |
| `auth.changePassword.confirmLabel` | Parola Tekrar | Confirm Password | Passwort bestätigen | Confirmar contraseña | Confirmer le mot de passe | Conferma password | Confirmar senha | Подтвердите пароль | تأكيد كلمة المرور | パスワードの確認 | 비밀번호 확인 | 确认密码 |
| `auth.changePassword.confirmHint` | Parolayı tekrar girin | Re-enter the password | Passwort erneut eingeben | Vuelve a introducir la contraseña | Saisissez à nouveau le mot de passe | Inserisci di nuovo la password | Digite a senha novamente | Повторите пароль | أعد إدخال كلمة المرور | パスワードをもう一度入力してください | 비밀번호를 다시 입력하세요 | 再次输入密码 |
| `auth.changePassword.toggleVisibility` | Parolayı göster/gizle | Show or hide password | Passwort anzeigen/ausblenden | Mostrar u ocultar contraseña | Afficher ou masquer le mot de passe | Mostra o nascondi password | Mostrar ou ocultar senha | Показать или скрыть пароль | إظهار أو إخفاء كلمة المرور | パスワードを表示/非表示 | 비밀번호 표시/숨기기 | 显示或隐藏密码 |

> `auth.validation.passwordLength` **mevcut** (`Şifre en az 6 karakter olmalıdır`) — "En az 6 karakter" ipucu yerine yeniden kullanıldı, yeni anahtar açılmadı.

### 8.3 `dialogs.invalidAmount*` — 2 yeni anahtar

| Anahtar | tr | en | de | es | fr | it | pt | ru | ar | ja | ko | zh |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `dialogs.invalidAmount` | Geçersiz miktar | Invalid amount | Ungültige Menge | Cantidad no válida | Quantité invalide | Quantità non valida | Quantidade inválida | Недопустимое количество | كمية غير صالحة | 無効な数量です | 잘못된 수량입니다 | 数量无效 |
| `dialogs.invalidAmountPartial` | Geçersiz miktar — {count} yiyecek kaydedildi | Invalid amount — {count} food(s) saved | Ungültige Menge — {count} Lebensmittel gespeichert | Cantidad no válida — se guardaron {count} alimentos | Quantité invalide — {count} aliment(s) enregistré(s) | Quantità non valida — {count} alimenti salvati | Quantidade inválida — {count} alimento(s) salvo(s) | Недопустимое количество — сохранено продуктов: {count} | كمية غير صالحة — تم حفظ {count} من الطعام | 無効な数量です — {count} 件を保存しました | 잘못된 수량 — {count}개 저장됨 | 数量无效 — 已保存 {count} 项 |

### 8.4 `chat.*` — 2 yeni anahtar

| Anahtar | tr | en | de | es | fr | it | pt | ru | ar | ja | ko | zh |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `chat.errors.assistant` | Asistan yanıt vermedi | The assistant could not respond | Der Assistent konnte nicht antworten | El asistente no respondió | L'assistant n'a pas répondu | L'assistente non ha risposto | O assistente não respondeu | Ассистент не ответил | لم يستجب المساعد | アシスタントから応答がありませんでした | 어시스턴트가 응답하지 않았습니다 | 助手未回复 |
| `chat.loadEarlier` | Daha eski mesajları yükle | Load earlier messages | Frühere Nachrichten laden | Cargar mensajes anteriores | Charger les messages précédents | Carica messaggi precedenti | Carregar mensagens anteriores | Загрузить более ранние сообщения | تحميل الرسائل السابقة | 以前のメッセージを読み込む | 이전 메시지 불러오기 | 加载更早的消息 |

### 8.5 `updates.unsafeUrl` — 1 yeni anahtar

| Anahtar | tr | en | de | es | fr | it | pt | ru | ar | ja | ko | zh |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `updates.unsafeUrl` | Güvenli olmayan indirme bağlantısı engellendi | Unsafe download link blocked | Unsicherer Download-Link blockiert | Enlace de descarga inseguro bloqueado | Lien de téléchargement non sécurisé bloqué | Link di download non sicuro bloccato | Link de download inseguro bloqueado | Небезопасная ссылка на загрузку заблокирована | تم حظر رابط تنزيل غير آمن | 安全でないダウンロードリンクをブロックしました | 안전하지 않은 다운로드 링크가 차단되었습니다 | 已阻止不安全的下载链接 |

### 8.6 Yeniden kullanılan mevcut anahtarlar (yeni değer gerekmiyor)

| Kod yeri | Anahtar | tr | en |
|---|---|---|---|
| `password_dialog.dart:130` | `common.cancel` | İptal | Cancel |
| `password_dialog.dart:141` | `common.save` | Kaydet | Save |
| `password_dialog.dart:107` | `auth.validation.passwordLength` | Şifre en az 6 karakter olmalıdır | Password must be at least 6 characters |
| `analytics_page.dart:841` | `settings.goals.protein` / `.carbs` / `.fat` | Protein (g) / Karbonhidrat (g) / Yağ (g) | Protein (g) / Carbs (g) / Fat (g) |
| `onboarding_page.dart:503` | `settings.goals.aiCalculate` | Yapay Zeka ile Hesapla | Calculate with AI |

> **Toplam: 24 + 6 + 2 + 2 + 1 = 35 yeni anahtar.**
> `tool/check_i18n.cjs` A6 tarafından güncellenmiş görünüyor — uygulama sonrası tam koşuyla doğrulanmalı.
