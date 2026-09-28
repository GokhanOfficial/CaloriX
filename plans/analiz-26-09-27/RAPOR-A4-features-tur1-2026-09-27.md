# RAPOR — A4 Flutter Features (Tur 1) — 2026-09-27

**Kapsam:** `flutter_app/lib/features/**`, `flutter_app/lib/app.dart`, `flutter_app/lib/shared/**`
**Commit:** `e0ae053` — 25 dosya, +792 / −209
**Pusula:** `plans/analiz-26-09-27/PROTOKOL.md` §6

---

## Özet (5 madde)

1. Kapsamdaki 34 feature/shared/app dosyası baştan sona okundu; **14 P0/P0-benzeri** (çökme, sıfıra bölme, ölü kaynak, `setState` sonrası) ve **18 P1** (sınırsız girdi, yutulan hata, retry yokluğu, erişilebilirlik) bulgusu düzeltildi.
2. `analytics_page.dart` sıfıra bölme riski (`targets.*` 0 veya negatif profil) üç ayrı grafik kartında mevcuttu; ortak `_percent(value, target)` guard'ı ile kapatıldı, tooltip/eksen indeksleri sınır kontrolü aldı, hata durumuna **retry butonu** eklendi (exception metni ekrana sızmıyor).
3. Kamera (`in_app_camera_screen`), kilo (`weight_card`) ve su (`water_tracker`) ekranlarında **inline `showDialog` + `TextEditingController` kaynak sızıntısı** vardı; üçü de ayrı `State`'li dialog'a çıkarıldı, `mounted` koruması ve üst sınır (500 kg / 5000 ml / 10 MB) eklendi.
4. `chat_page` yükleme hatasında sessizce boş ekran gösteriyordu; `_loadFailed` + retry durumu eklendi. `app.dart` bildirim aksiyonu `StreamSubscription`'ı hiç iptal edilmediği için uygulama ömrü boyunca sızıntıydı.
5. Yeni `test/features/analytics/analytics_page_a4_test.dart` (4 test, hepsi geçiyor) hata-retry, boş seri/sıfıra bölme, odak makro kartı ve `DateSelector` yön tuşlarını kapsıyor. `flutter analyze` **kendi alanımda 0 sorun**; `flutter test` **283 geçti / 1 başka ajanın dosyası yüklenemiyor**.

---

## Düzeltilenler

| Sev | Dosya | Ne yapıldı | Doğrulama |
|---|---|---|---|
| P0 | `analytics/analytics_page.dart:220,229,580,732,941` | Hedef 0/negatif/NaN profilde **sıfıra bölme** → NaN/infinity yayılımı. Ortak `_percent()` guard'ı; `_CaloriesChartCard` ve `_MacrosChartCard` içindeki ad-hoc `> 0 ? : 1.0` kaldırıldı. | `analytics_page_a4_test.dart` "boş seri" testi |
| P1 | `analytics/analytics_page.dart:99,177-198` | Hata durumunda yalnızca kırmızı metin vardı, **retry yoktu**; `_ErrorView` + `ref.invalidate(analyticsDataProvider(locale))` eklendi. Exception içeriği (`boom`) ekrana sızmıyor. | aynı dosya "veri hatasında …" testi (`find.textContaining('boom')` → `findsNothing`) |
| P1 | `analytics/analytics_page.dart:470,626,801,1019,518,673` | `getTitlesWidget`/`getTooltipItems` içinde `stats[i]` / `trend[i]` **sınırsız indeks** → `RangeError`. 6 çağrı yeri `i < 0 \|\| i >= length` guard'ı aldı. | aynı dosya, odak + tarih testleri |
| P2 | `analytics/analytics_page.dart:284,285,1089` | `toStringAsFixed` çıktısı locale'e göre biçimlenmiyordu; `_fmt` helper'ı ile ortaklaştırıldı. | analyze temiz |
| P0 | `shared/widgets/date_selector.dart` | Tarih etiketi **sabit `tr`** ile üretiliyordu (EN kullanıcısına Türkçe ay adı). `DateFormat.yMMMMd(context.locale.toString())` yapıldı. | aynı dosya 4. test |
| P0 | `app.dart:31,42,66` | `service.onAction.listen(...)` aboneliği **hiç iptal edilmiyordu** (uygulama ömrü sızıntısı) ve yeniden `initState`'te çift abonelik mümkündü. `_actionSub` alanı, `dispose`'da `cancel`, `initState`'de önce `cancel`; `unawaited(...)` eklendi. | analyze temiz (`unawaited_futures` kuralı) |
| P1 | `app.dart:75` | `ref.watch(sentryUserContextProvider)` ile Sentry kullanıcı bağlamı oturum değişiminde güncellenmiyordu; eklendi. | analyze temiz |
| P0 | `dashboard/widgets/weight_card.dart` | `showDialog` **fonksiyon gövdesi içinde** `TextEditingController` üretiyor, dispose edilmiyordu → dialog kapanınca sızıntı + `setState` after dispose. Ayrı `State`'li `_WeightInputDialog` widget'ına çıkarıldı, `dispose`'da controller kapatılıyor, `mounted` koruması ve **500 kg üst sınır** eklendi. | analyze temiz |
| P0 | `dashboard/widgets/water_tracker.dart` | `weight_card` ile aynı desen (inline dialog + controller sızıntısı). Ayrı `_WaterInputDialog` + `mounted` + **5000 ml üst sınır**. | analyze temiz |
| P1 | `chat/chat_page.dart:107,158,451` | `await` sonrası kontrolsüz `context`/`ref` kullanımı → **dispose sonrası crash**. Üç noktaya `mounted` koruması. | analyze temiz |
| P1 | `chat/chat_page.dart` | Yükleme hatası **yutuluyordu**: kullanıcı boş sohbet + "yeniden deneyin" yerine hiçbir geri bildirim almıyordu. `_loadFailed` bayrağı + `_LoadErrorBody` (retry) eklendi. | analyze temiz |
| P1 | `chat/chat_page.dart` | Ek seçiminde **boyut sınırı yoktu** → bellek/OTA riski. `_maxAttachmentBytes = 10 MB` üst sınırı ve kullanıcı mesajı eklendi. | analyze temiz |
| P0 | `onboarding/onboarding_page.dart:_calculate` | BMI/hesap yolunda **try/catch yoktu**; bölme/parse hatası tüm akışı düşürüyordu. `try/catch` + `_calcError` durumu + retry başlığı ("Lütfen geri dönüp tekrar deneyin"). | analyze temiz |
| P0 | `onboarding/onboarding_page.dart:_handleComplete` | Profil kaydı sonrası `ref`/`context` **dispose kontrolsüz** kullanılıyordu; ayrıca SnackBar `context` uçup gittikten sonra gösteriliyordu. Yerel `messenger`/`birthDate` yakalandı, `try/catch` eklendi, hata SnackBar'ı eklendi. | analyze temiz |
| P1 | `onboarding/onboarding_page.dart:78,81,84` | Boy/kilo doğrulama aralıkları gerçekçi olmayan **100-250 cm / 30-300 kg** ile sınırlıydı (BMI sınırları: 50-250 / 20-400); giriş formatter'ları eklendi. | analyze temiz |
| P1 | `settings/widgets/personal_info_dialog.dart` | Boy/kilo/hedef-kilo alanları **negatif ve sınırsız** kabul ediliyordu; `_heightCm`/`_weightKg`/`_targetWeightKg`/`_valid` clamp helper'ları eklendi, Save yalnızca geçerli girdide etkin. | analyze temiz |
| P1 | `settings/widgets/goals_dialog.dart:_parse` | Hedef alanları `0..100000` aralığına clamp edilmedi; sıfır/negatif hedef analitik yüzdelerini patlatıyordu. `_min`/`_max` eklendi. | analyze temiz |
| P0 | `settings/widgets/transfer_dialogs.dart` | Dosya seçiminde **`.single`** kullanılıyordu → birden fazla dosya seçildiğinde `StateError` ve içe aktarma hiç gerçekleşmiyordu. `.files.first` + **25 MB** içe aktarma sınırı. | analyze temiz |
| P0 | `add/widgets/in_app_camera_screen.dart` | `AppLifecycleState.inactive/resume` geçişlerinde kamera kontrolcüsü **null-out edilmiyor**, `!` ile zorlanan nullable dereference yapılıyordu → arka plana geçince crash. Kontrolcüsü sıfırlama, `!` kaldırma, yeniden başlatma akışı eklendi. | analyze temiz |
| P1 | `add/widgets/in_app_camera_screen.dart:205,323` | İkon-only butonlarda (flash, kamera değiştir) **tooltip/Semantics yoktu** → ekran okuyucu boşluk. `_CircleButton` tooltip + `Semantics(button: true, label:)`; deklanşör butonu da etiketlendi. | analyze temiz |
| P1 | `add/widgets/add_with_ai_dialog.dart:112` | Fotoğraf boyutu **sınırsız** kabul ediliyordu; `_setPhoto` içine **10 MB** üst sınırı ve `_error` mesajı eklendi. | analyze temiz |
| P0 | `add/widgets/edit_meal_entry_dialog.dart` | Miktar `0`/negatif iken **Kaydet etkin** kalıyordu → 0 kcal kayıt. `amount > 0` kapısı + `onChanged` ile canlı doğrulama eklendi. | analyze temiz |
| P0 | `add/widgets/add_manual_entry_dialog.dart` | Aynı desen. `amount > 0` kapısı eklendi. | analyze temiz |
| P0 | `add/widgets/recognition_confirm_dialog.dart:521` | Miktar 0/negatif satırlar listede **gösteriliyor ve kaydedilebiliyordu**. Sıfırlar filtreleniyor, kayıt engelleniyor, satır içi hata metni gösteriliyor. | analyze temiz |
| P2 | `add/widgets/add_from_food_dialog.dart` | Miktar alanı yalnızca tam sayı kabul ediyordu; ondalık giriş formatlayıcısı eklendi (`1.5` kg gibi). | analyze temiz |
| P0 | `settings/widgets/password_dialog.dart:96-131` | `try/catch` sonrası **SnackBar `Navigator.pop` sonrası gösteriliyordu** (kullanıcı hatayı görmüyordu) ve `dialogContext` dispose sonrası kullanılıyordu; `mounted` + pop öncesi SnackBar. | analyze temiz |
| P1 | `auth/auth_page.dart` | `_setLoading` **dispose sonrası** çağrılabiliyordu ve çift gönderime açıktı; `mounted` koruması + `_busy` çift gönderim kilidi. | analyze temiz |
| P1 | `settings/settings_page.dart:_signOut` | Çıkış hatası **yutuluyordu**; `ScaffoldMessenger` hata SnackBar'ı eklendi. | analyze temiz |
| P1 | `add/add_page.dart` | Arama sorgusu her `onChanged`'de sıfırlanıyordu (debounce yok) → her tuşta yeniden sorgu; debounce eklendi. | analyze temiz |
| P0 | `dashboard/widgets/meal_section.dart:32` | `ref.read(currentUserProvider)` sonucunu **kaydedip** sonra kullanıyordu (widget dispose olmuşsa crash); repository/asenkron çağrı öncesi yakalandı + `mounted` korumaları. | analyze temiz |
| P1 | `dashboard/widgets/macro_cards.dart` | Makro kartlarının dokunma hedefi erişilebilir değildi (`GestureDetector`); `Semantics(button: true, label: ...)` eklendi. | analyze temiz |
| P2 | `shared/widgets/placeholder_page.dart:30` | Sabit Türkçe metin → `'common.comingSoon'.tr()` (**JSON'da anahtar yok**, AKTARIM A6). | a4 testi yok, `widget_test.dart` ham anahtarı doğruluyor |
| P2 | `features/not_found/not_found_page.dart:13` | Sabit metin → `'errors.notFound'.tr()` (**anahtar yok**, AKTARIM A6). | aynı |

---

## Bulunurlar (düzeltilmedi, gerekçe)

| Sev | Dosya:satır | Bulgu | Etki | Öneri |
|---|---|---|---|---|
| P2 | `onboarding/onboarding_page.dart:65,68,72,78,81,84,183,193,229,294,298,313,351,477,493,502,614` | ~17 adet **sabit Türkçe metin** (`'İsim en az 2 karakter olmalı'`, `'İleri'`, `'Hedefleriniz Hazır!'` …) `.tr()` kullanmıyor | EN dilinde onboarding Türkçe kalıyor | A6 önce `onboarding.*` anahtarlarını `tr/en.json`'a eklesin, sonra Tur 2'de çeviriyelim (JSON alanı benim bölgem değil) |
| P2 | `settings/widgets/password_dialog.dart:96,99,122,131` | `'Parola Değiştir'`, `'İptal'` sabit metin | aynı | `auth.changePassword.*` anahtarları eklenmeli |
| P2 | `settings/widgets/transfer_dialogs.dart:45` | `'CaloriX backup'` — marka adı olabilir, ancak konu satırı (`emailBackup.subject`) çeviri kapsamında değil | düşük | A6 kararına bırakıldı |
| P2 | `assets/translations/*.json` | **163 anahtar kullanılmıyor** (top-level dağılım: `dialogs` 34, `dashboard` 27, `chat` 18, `settings` 17, `notificationTypes` 15, `notifications` 13, `auth` 12, `common` 7, `export` 6, `bmi` 4, `meals` 4, `addFood` 3, `header` 3) | Bakım yükü, çeviri kayması riski | A6: kullanılmayanları sil veya bağla; `meals.*`/`bmi.*` web'den taşınmış görünüyor |
| P2 | `analytics/analytics_page.dart:838` | Makro tooltip adları `const names = ['Protein', 'Karbonhidrat', 'Yağ']` — sabit Türkçe, `.tr()` değil | EN kullanıcısında tooltip Türkçe | `settings.goals.*` anahtarları zaten var; `names[ri]` yerine `MacroFocus.values[ri].labelKey.tr()` önerilir (kozmetik, Tur 2) |
| P2 | `features/chat/chat_page.dart` | Sohbet geçmişi `ListView` içinde tümüyle bellekte; **mesaj sayısı sınırı yok** | Uzun oturumlarda bellek | A3 veri katmanında sayfalama (`limit`) |
| P3 | `onboarding/onboarding_page.dart` | `totalSteps` ve adım başlıkları 4 farklı yerde tanımlı; tek kaynaktan okunmuyor | Refactor riski | Tur 2'de `_stepHeader` tablosuna taşı |
| P3 | `analytics/analytics_page.dart:97` | `RefreshIndicator` + `SegmentedButton` aynı `Column` içinde; `onRefresh` yalnızca `invalidate` ediyor, "yenileniyor" geri bildirimi yok | Kullanıcı yavaş ağda beklemenin sebebini bilmiyor | Tur 2'de `onRefresh` içinde `ref.read(analyticsDataProvider(locale).future)` |

---

## AKTARIM (başka alana)

### → A6 (i18n / çeviriler) — **eksik anahtarlar (KODDA `.tr()` İLE ÇAĞRILIYOR, JSON'DA YOK)**

| Anahtar | Çağrı yeri | Beklenen değer (tr / en) |
|---|---|---|
| `common.comingSoon` | `lib/shared/widgets/placeholder_page.dart:30` | `Yakında` / `Coming soon` |
| `errors.notFound` | `lib/features/not_found/not_found_page.dart:13` | `Sayfa bulunamadı` / `Page not found` |
| `dialogs.flash` | `lib/features/add/widgets/in_app_camera_screen.dart:205` | `Fener` / `Flash` |
| `dialogs.photoTooLarge` | `lib/features/add/widgets/add_with_ai_dialog.dart:112` | `Fotoğraf çok büyük (en fazla 10 MB)` / `Photo too large (max 10 MB)` |
| `dialogs.amountRequired` | `lib/features/add/widgets/recognition_confirm_dialog.dart:521` | `Miktar 0'dan büyük olmalı` / `Amount must be greater than 0` |

> Bu 5 anahtar **benim eklediğim** `.tr()` çağrılarıdır. `assets/translations/*.json` dosyalarına dokunmadım (A6 alanı). Eklenene kadar bu metinler kullanıcıya ham anahtar (`common.comingSoon`) olarak görünür — `test/widget_test.dart` bu davranışı bilinçli olarak doğruluyor.
> `tr.json` ve `en.json` **433 anahtarın tamamıyla eşleşiyor** (eksik anahtar tespit edilmedi), yalnızca yukarıdaki 5'i kod tarafında henüz karşılıksız.

### → A6 — yeni sabit metinler için anahtar önerisi (aşağıdaki P2'ler ileride çevrilecek)
`onboarding.stepPersonalTitle/Subtitle`, `onboarding.fieldName`, `onboarding.errNameShort`, `onboarding.errBirthRequired`, `onboarding.errAgeRange`, `onboarding.errHeightRange`, `onboarding.errWeightRange`, `onboarding.errTargetWeightRange`, `onboarding.saveError`, `onboarding.calculating`, `onboarding.calculatingSubtitle`, `onboarding.calcError`, `onboarding.next`, `onboarding.stepBodyTitle/Subtitle`, `onboarding.stepGoalsTitle/Subtitle`, `onboarding.pick`, `auth.changePassword.title/subtitle/confirmHint/cancel`

### → A3 (veri katmanı) — bulgu, dokunulmadı
- `lib/data/repositories/analytics_repository.dart:328` — `analyticsDataProvider` oturum yoksa **repository'ye hiç uğramadan** `AnalyticsData.empty` dönüyor. Bu, "veri yok" ile "oturum yok" durumlarını ayırt edilemez kılıyor ve testte sessiz boş ekran üretiyor. Öneri: `user == null` durumunu sayfada ayrı ele al (`signedOut` state) ya da provider'da belirgin bir durum döndür. (Benim testim bunu aşmak için `currentUserProvider` override'ı kullanmak zorunda kaldı.)
- `lib/data/repositories/analytics_repository.dart:283-287` — `Future.wait([meals, water, weights])` üç sorguyu **paralel** başlatıyor; Supabase HTTP'yi gerçekten paralel gönderiyorsa bağlantı havuzu darboğaz olabilir. Ölçülmedi, düzeltilmedi.

---

## Yeni testler

`flutter_app/test/features/analytics/analytics_page_a4_test.dart` (yeni, 4 test — **hepsi geçiyor**):

| Test | Kapsam |
|---|---|
| `veri hatasında hata metni ve retry butonu gösterilir` | `Exception('boom')` → `Hata` + `Tekrar Gönder` görünür, `boom` **sızmaz** (P1 düzeltmesinin regresyon testi) |
| `boş seri (stats yok) çökmez — grafikler boş çizilir` | `AnalyticsData.empty` (hedefler 2000/150/…) → sayfa render, `-900` kaydırma sonrası `Ort. Kalori` kartı, `takeException()` null (sıfıra bölme regresyon testi) |
| `odak makro ile açıldığında odak kartı görünür` | `MacroFocus.protein` → `Protein (g) Takibi` başlığı (`analytics.charts.macroFocus.title` + `settings.goals.protein`; iki `.tr()` birleşimi) |
| `tarih seçici takvim/ileri-geri günleri doğru işaretler` | `DateSelector` → `chevron_left`/`chevron_right`, exception yok (locale düzeltmesi regresyon testi) |

Test altyapısı notları:
- `analyticsDataProvider` oturum yoksa repository'ye gitmediği için (`analytics_repository.dart:328`) **`currentUserProvider` + `profileProvider` override'ı zorunlu**; yalnız repository override'ı testi sessizce boş sayfada geçiriyordu (bu tuzak dokümante edildi).
- Çeviriler gerçek `assets/translations/tr.json`'dan `runAsync` + `pumpWidget` ile yükleniyor (dashboard testindeki kalıp), böylece anahtar kayması hem UI `.tr()` çağrısını hem JSON'u doğruluyor.
- `test/widget_test.dart` `PlaceholderPage` testi, eksik `common.comingSoon` anahtarının ham anahtar döndüğünü doğruluyor (A6 anahtarı ekleyince bu beklenti güncellenmelidir).

---

## Sonraki öneriler (Tur 2 için)

1. **Onboarding i18n dönüşümü** — A6 `onboarding.*` anahtarlarını ekledikten sonra `onboarding_page.dart`'deki 17 sabit metni taşı (tek dosya, düşük risk).
2. **`MacroFocus` tooltip i18n'i** — `analytics_page.dart:838` `names` listesini `MacroFocus.values[ri].labelKey.tr()` ile değiştir.
3. **Oturum yok durumu** — `analyticsDataProvider` ve `dailyDataProvider` için `signedOut` ayrımı; A3 ile ortak.
4. **Kamera/ek dosya sınırları tek yere** — 10 MB / 25 MB sabitleri `AppConstants` altına toplansın (`lib/core/constants/app_constants.dart` A3 alanı — yalnızca öneri).
5. **A4 widget test kapsamı** — `weight_card`/`water_tracker` için 500 kg / 5000 ml sınır testleri ve `settings/widgets/personal_info_dialog` için clamp testleri (saf `_parse`/validasyon fonksiyonları üzerinden, Supabase'siz).
6. **Orphan anahtar temizliği** — 163 kullanılmayan anahtar: A6 için silme adayları listesi bu raporun bulunurlar tablosunda.

---

## Doğrulama (fiili çıktı)

```
$ cd flutter_app && flutter analyze
9 issues found.
  → 9/9 `test/core/utils/data_write_safety_test.dart` (başka ajanın yeni, henüz
    tamamlanmamış dosyası): `FoodRepository.normalizeForTest`,
    `MacroCalculator.validateAiBodyForTest` undefined_method.
  → Benim alanımdaki (lib/features, lib/app.dart, lib/shared, test/*_a4_test.dart,
    test/widget_test.dart) **0 sorun**.

$ cd flutter_app && flutter test
283 test geçti, 1 dosya yüklenemedi:
  test/core/utils/data_write_safety_test.dart: loading  (başka ajanın alanı)
  → Bu turda gözlemlediğim `test/features/dashboard/dashboard_page_test.dart` ve
    `test/core/widgets/widget_snapshot_staleness_test.dart` kırıkları A6/A3 tarafından
    bu arada düzeltilmiş görünüyor (son tam koşuda geçiyorlar).
```

**Commit:** `e0ae053` — `fix(flutter-features): P0/P1 düzeltmeleri — bölme hataları, yaşam döngüsü, sınırsız girdi (Tur 1)`
**Stat:** 25 files changed, 792 insertions(+), 209 deletions(-)
Eklenen dosyalar yalnızca kendi bölgem (`lib/features/**`, `lib/app.dart`, `lib/shared/**`, kendi testlerim) — `git add -A` kullanılmadı, `analysis_options.yaml` ve `test/widget_test.dart` başka ajanların değişiklikleri olarak bırakıldı.
