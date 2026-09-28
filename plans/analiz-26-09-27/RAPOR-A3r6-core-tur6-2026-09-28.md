# RAPOR — A3r6-flutter-core — 2026-09-28 — Tur 6

Alan: `flutter_app/lib/core/**`, `flutter_app/lib/main.dart`, `flutter_app/test/core/**`
Turun amacı: **yeni özellik değil, önceki 5 turun kodunu denetlemek.**

## Özet (5 madde)

1. **Bulduğum en ciddi hata bir P0'dı ve "widget tazeleme" idi: hiç çalışmıyordu.**
   `HomeWidgetSave.update` metodu `HomeWidget.updateWidget(name: name, androidName: name)`
   ile çağırıyordu. `home_widget` 0.10.0 Android tarafı sınıfı
   `HomeWidgetPlugin.kt:269`'da `qualifiedAndroidName ?: "${context.packageName}.${className}"`
   ile çözüyor ve `name` verildiğinde `com.calorix.app.DailyWidgetProvider` arıyor
   (`applicationId = "com.calorix.app"`, sınıf ise `com.calorix.calorix.widget.*`) →
   `ClassNotFoundException` → `result.error(-3)`. Yani "Güncelle" butonu, ayar
   değişimi, öğün ekleme sonrası tazeleme — **hiçbiri** widget'a ulaşmıyordu.
   Düzeltildi: yalnızca `androidName`.

2. **Bildirim planlama tarafındaki sessiz kayıpları kapattım.** `zonedSchedule`
   bir öğün için patladığında **diğer öğünler de planlanmıyordu** (istisna
   `reschedule`'i yarıda bırakıyordu); `_exactAllowed` yalnızca `init`'te bir kez
   okunduğu için kullanıcı tam alarm iznini kapattığında hatırlatıcılar **sessizce
   hiç gelmiyordu**; `POST_NOTIFICATIONS` reddi hiçbir yerde görünmüyordu;
   saat dilimi çözülemezse UTC'ye düşülüyordu ama `AppLog` release'de Sentry
   DSN boşsa tamamen kayboluyor (`app_logger.dart:36`). Artık
   `NotificationScheduleOutcome` planlanan/planlanamayan sayısını, izin
   durumunu ve "kullanıcıya uyarı gerekiyor mu" bilgisini dışarı veriyor;
   `reschedule` her seferinde `canScheduleExactNotifications()` yeniden okuyor.

3. **`nextDailyOccurrence` saf fonksiyonun sözleşmesi bozuktu ve testleri
   ölçmüyordu.** Sonucu `tz.local` diliminde kuruyordu; `now` farklı bir
   dilimdeyse sessizce kayıyordu (TR'de 08:30 istenip UTC 08:30 dönüyordu).
   Daha kötüsü: `timezone_resolver_test.dart`'deki DST testleri `Europe/Berlin`
   `now` değerleriyle yazılmıştı ama gerçekte `tz.local` (test ortamında **UTC**)
   üzerinde hesap yapıyordu — **hiçbir şey ölçmüyordu**, yeşildi. Artık
   `now.location` kullanılıyor; yeni testler 3 dil × 28 gün × 24 saat × 4 dakika
   parametrik olarak gerçekten ölçüyor.

4. **`downloadVerifyAndOpen` "tek giriş noktası" yorumu fiilen imkânsızdı.**
   Metot `_UpdateGateState` **içinde** `static` idi; Dart'ta `State` sınıfları
   `_` ile gizli olduğu için `ForceUpdatePage` (`lib/features/updates/`, A4 alanı)
   onu **çağıramıyordu**. Zorunlu güncelleme ekranı hâlâ `sha256` doğrulamasını
   **atlayan** ikinci bir `launchUrl(apkUrl)` yolunu kullanıyor (Tur 1'den beri
   raporlanıyordu). Metot `apk_downloader.dart` içine **top-level** taşındı;
   artık A4 gerçekten çağırabilir.

5. **Widget sözleşmesi artık derleyici/test tarafından korunuyor.**
   `test/core/widgets/widget_key_contract_test.dart` Dart `WidgetKeys` ile
   Kotlin `WidgetData.kt`'yi dosyayı metin olarak okuyup **her iki yönde**
   karşılaştırıyor; tip sözleşmesini (`putLong(rawLongBits)` + bayrak,
   `prefs.all` erişimi) ve tazeleme yayınının `androidName` ile yapıldığını da
   kilitliyor. Ayrıca `Calculations`'ı bağımsız olarak doğruladım ve 3 gerçek
   hata buldum (negatif boy geçerli BMI üretiyordu; `progress`/`waterTargetMl`
   NaN'da `UnsupportedError` fırlatıyordu).

## Düzeltilenler

| Sev | Dosya | Ne yapıldı | Doğrulama |
|---|---|---|---|
| **P0** | `widgets/widget_bridge.dart:146-186` | `HomeWidgetSave.update` artık **yalnızca** `androidName` veriyor. `name` verilmesi `"$packageName.$className"` çözümlemesi yapıyor ve sınıf bulunamıyordu (Paket `home_widget` dokümanı da "must match the classname of the AppWidgetProvider" diyor). | `widget_key_contract_test.dart` — kaynak metninde `name: name` **yokluğu** + provider sınıfları `.kt` dosyalarında var + `ACTION_REFRESH` manifest'te kayıtlı |
| **P1** | `widgets/widget_bridge.dart:100-118` | `_refreshAll` toplu `try/catch` yerine provider başına izole: biri çözülemezse diğeri tazeleniyor. | `flutter test test/core/widgets` |
| **P1** | `notifications/notification_service.dart:394-460` | `zonedSchedule` hatası artık `reschedule`'i **yarıda bırakmıyor**; `_scheduleDaily` → `bool`. `NotificationScheduleOutcome` (scheduledCount/failedCount/notificationsAllowed/exactAllowed/`needsUserAttention`) eklendi. | `flutter analyze` temiz |
| **P1** | `notifications/notification_service.dart:230-259` | `_refreshPermissions()` eklendi: `areNotificationsEnabled()` + `canScheduleExactNotifications()` **her `reschedule`'te** yeniden okunuyor. `_exactAllowed` yalnız init'te bir kez okunuyordu — kullanıcı izni kapatınca hatırlatıcılar sessizce hiç gelmiyordu. | `flutter analyze` temiz |
| **P1** | `notifications/notification_service.dart:126-152` | `timeZoneUnresolved` bayrağı: dilim çözülemezse artık **dışarıdan görülebilir** (ayarlar ekranı uyarı gösterebilir). `_tzResolvedOnce` ile yeni servis "çözülmemiş" görünmüyor. | `flutter analyze` temiz |
| **P1** | `notifications/notification_service.dart:426-447` | `snoozeOneHour` planlama hatasını yutuyor (istisna `app.dart`'deki aksiyon işleyicisine kaçıyordu). | `flutter analyze` temiz |
| **P1** | `notifications/timezone_resolver.dart:61-104` | `nextDailyOccurrence` sonucu `tz.local` yerine **`now.location`** ile kuruyor. | `notification_scheduling_test.dart` — 3 dil × 28 gün × 24 saat × 4 dakika parametrik "sonuç daima gelecekte" + konum eşitliği testleri |
| **P1** | `updates/apk_downloader.dart:45-79, 148-215` | `downloadVerifyAndOpen` `_UpdateGateState`'ten **top-level**'a taşındı → `ForceUpdatePage` gerçekten çağırabilir (sha256 atlatma yolu kapatılabilir hale geldi). | `dead_code_test.dart` — imza kilidi + `update_gate.dart`'de ikinci tanım **yok** |
| **P1** | `updates/apk_downloader.dart:121-146, 196-235` | Geçici dosya **sürümlü ad** alıyor (`calorix-update-<code>-<version>.apk`) + `_deleteStaleSiblings` eski sürüm artıklarını temizliyor. Yazma hatasında yarım dosya bırakılmıyor (`ApkDownloadFailure.write`). `versionName` yol enjeksiyonuna karşı süzülüyor. | `apk_integrity_test.dart` — "geçici dosya yönetimi" 3 yeni test |
| **P1** | `updates/update_gate.dart:46-90, 130-160` | `_promptScheduled` bayrağı: durum hızla iki kez değişirse aynı frame'de ikinci `addPostFrameCallback` kuyruğa girmiyordu. `_launchApk` içindeki `_notify`/`mounted` korumaları korundu. | `flutter analyze` temiz |
| **P1** | `utils/calculations.dart` | `bmi`: `heightCm <= 0` → 0 (`hM*hM` negatif boyda **pozitif** olduğu için `bmi(70,-180)` = 21.6 dönüyordu, yani boyu -180 cm olan kayıt geçerli BMI gibi görünüyordu). `progress`: `NaN`/`Infinity` → 0 (`.round()` `UnsupportedError` fırlatıyordu). `waterTargetMl`: `NaN`/`Infinity`/negatif → 0 (`-330 ml` hedefi üretiyordu). `tdee`: alt sınır açık. | `calculations_reference_test.dart` (53 test) + güncellenen `calculations_edge_cases_test.dart` |
| **P2** | `widgets/widget_snapshot.dart:67-113` | `WidgetKeys.stateValues` eklendi — sözleşmedeki 40 anahtarın tek listesi (test sayım için, "yeni anahtar eklendi ama karşı taraf güncellenmedi" yönünü yakalıyor). | `widget_key_contract_test.dart` |
| **P2** | `widgets/widget_bridge.dart:26-47, 400-460` | `stateNoConfig` yorumu düzeltildi (`lib/` içinde **üretilmiyor**; native tarafın kendi varsayılanı). `publishWeekly` ve `shouldSendNudge` "ölü kod" yorumları eklendi (aşağıda). | `flutter analyze` temiz |
| **P2** | `updates/apk_downloader.dart:17-30` | `url_launcher` import'u eklendi (top-level fonksiyon taşındı). | `flutter analyze` temiz |

## Bulunurlar (düzeltilmedi, gerekçe)

| Sev | Dosya:satır | Bulgu | Etki | Öneri |
|---|---|---|---|---|
| **P1** | `features/updates/force_update_page.dart:38-45` | Zorunlu güncelleme ekranı hâlâ `canLaunchUrl(url)` + `launchUrl(apkUrl)` ile **doğrulamasız** APK açıyor; `sha256` zincirini atlıyor. | Manifest ele geçirilirse zorunlu güncellemede bozuk APK kurulabilir | **A4 alanı.** Metot artık erişilebilir (`apk_downloader.downloadVerifyAndOpen`); `_openApk` onu çağırmalı. `dead_code_test.dart` bu bulguyu kırmızıya dönmeye hazır tutuyor |
| **P2** | `core/widgets/widget_bridge.dart:400-460` | `publishWeekly` `lib/` içinden **hiç çağrılmıyor** → `weekly.values`/`weekly.labels` hiç yazılmıyor → `WeeklyWidgetProvider` her zaman boş/bayat gösteriyor (30 dk `updatePeriodMillis` yalnızca mevcut veriyi çizer). | Haftalık widget işlevsiz | Mimari karar: (a) `DiaryRepository`'ye 7 günlük sorgu + `WidgetBridgeScope`'ta çağrı (`lib/data/**` A2 alanı), (b) haftalık widget'ı kaldır. **Silmedim** — eksik özellik, ölü kod değil |
| **P2** | `core/widgets/widget_snapshot.dart:340-380` | `shouldSendNudge` + `WidgetSettings.nudgeEnabled/Hour/Minute` + `WidgetStrings.nudgeTitle/Body` yazılmış ve ayar UI'ında **görünür** ama hiçbir yer bildirim göndermiyor; `nudge*` metinleri `str.*` paketine de girmiyor. | Kullanıcı ayarı açıp hiçbir davranış değişimi görmüyor | Tur 7: ya bağla (arka plan görevi) ya da ayar UI'ından çıkar |
| **P2** | `pubspec.yaml:61` | `workmanager: ^0.10.10` **hiç kullanılmıyor**: `lib/` içinde tek referans yok, `MainActivity.kt` boş, manifest'te `WorkManager` servisi/receiver'ı yok. | APK boyutu + bakım yükü (ağır bağımlılık, kullanılmayan WorkManager servisleri) | A6 alanı (`pubspec`): ya arka plan görevi yaz, ya bağımlılığı kaldır |
| **P2** | `notifications/notification_service.dart:196-205` | `refreshTimeZone()` **hiçbir yerden çağrılmıyor** (0 çağıran). `refreshTimeZone` olmadan saat dilimi değişimi yalnızca yeniden açılışta fark edilir — kullanıcı uçaktan iner inmez 1-2 gün yanlış saatte bildirim alır. | Orta (yanlış saat, sonraki açılışta düzelir) | A4: `app.dart`'de `AppLifecycleListener.onResume` → `refreshTimeZone()`. `refreshTimeZone` hazır ve çalışıyor, geri çağrı zinciri (`addTimezoneWatcher`) bağlı |
| **P3** | `notifications/notification_service.dart:112-121` | iOS hâlâ hiç yapılandırılmıyor (`InitializationSettings(android: …)`); `DarwinInitializationSettings` yok. | iOS'ta plugin initialize edilemez | Tur 1'den beri açık; dokümanlarda "Android-only" denmeli veya uygulanmalı |
| **P3** | `observability/app_logger.dart:36` | `if (kDebugMode || !Sentry.isEnabled) return` — release'de Sentry DSN boşsa **hiçbir şey** loglanmıyor, `debugPrint` de bastırılıyor. Benim eklediğim planlama logları da buraya düşüyor. | Teşhis edilebilirlik | `dart:developer log()` ile logcat'e düşme (A4 düzeltmesi değil, `core` alanı — bilinçli bırakıldı: `_capture` Sentry bütçesiyle ilgili) |
| **P3** | `config/env.dart:112-138` | `assertSafeForClientBuild` **derleme zamanı** guard var (`service_role` gömülürse build kırmızı). `SENTRY_DSN` gömme riski **yok**: Sentry DSN gönderme yetkisi verir, okuma yetkisi değil. `.env` `pubspec.yaml:102`'de `assets` altında paketleniyor ama CI'da **placeholder** üretiliyor. | Düşük | A1 alanı (PROTOKOL §4); dokunmadım. Belgelendi |

## AKTARIM (başka alana)

- **A4-flutter-features** — `lib/features/updates/force_update_page.dart:38-45`:
  `downloadVerifyAndOpen` artık **herkese açık** (`apk_downloader.dart` top-level).
  `_openApk` metodu `ApkDownloader` + `launchUrl(Uri.file(...))` zincirini
  kullanmalı; mevcut `canLaunchUrl(url)` + `launchUrl(apkUrl)` yolu
  `sha256` doğrulamasını atlıyor. 4 satırlık değişiklik.
  `test/core/dead_code_test.dart` bunu kırmızıya dönmeye hazır.
- **A4-flutter-features** — `lib/app.dart:76-82`:
  `NotificationService.refreshTimeZone()` hiç çağrılmıyor. `AppLifecycleListener`
  ile `onResume`'da çağrılırsa uçaktan inen kullanıcının hatırlatıcıları
  anında yeni saat dilimine planlanır. Servis tarafı hazır.
- **A4r6 / ortak** — `flutter analyze` **şu an temiz** (`No issues found!`).
  Tur başında `lib/features/analytics/analytics_*.dart` (yeni dosyalar) ve
  `test/features/chat/chat_page_a4r3_test.dart` (`ChatAttachmentLimits`
  undefined) kırıktı; A4r6 bu sırada düzeltmiş. Ayrıca
  `test/features/chat/chat_accessibility_a4r6_test.dart` transient yükleme
  hatası veriyordu (import eksikliği, A4 alanında) — son koşuda düzelmiş.
- **A6-tests-quality** — `pubspec.yaml:61` `workmanager` bağımlılığı kullanılmıyor
  (kanıt: `lib/` içinde 0 referans, `MainActivity.kt` boş, manifest'te WorkManager
  servisi yok). Ağır bağımlılık, ölü yük.
- **A5-web-legacy** — `src/lib/calculations.ts:24-32` `calculateBMR`:
  `gender === 'male' ? +5 : -161` yani web'de `other` **kadın** formülüne düşüyor.
  Flutter `Gender.other` **erkek** formülünü kullanıyor (166 kcal fark).
  `calculations_reference_test.dart` bu ayrışmayı belgeliyor ve kilitliyor;
  ürün kararı gerekiyor.
- **A1-security** — `core/updates/update_manifest.dart:81` `isSafeApkUrl` yalnızca
  `https` + `.apk` + `userInfo` kontrol ediyor; **host kısıtı yok**. Sunucu ele
  geçirilirse `https://evil.com/x.apk` da kabul edilir. TLS pinning yok
  (Tur 1'de açık). A1 kararı gerekiyor.

## Yeni testler

| Dosya | Test | Kapsam |
|---|---|---|
| `test/core/widgets/widget_key_contract_test.dart` | **7** | Dart `WidgetKeys` ↔ Kotlin `WidgetData.kt` **her iki yönde** karşılaştırma (40 anahtar); tip sözleşmesi (`home_widget.double.` bayrağı, `Double.fromBits`, `prefs.all[key]`); tazeleme yayını (`androidName` ile, `name: name` **yokluğu**, provider `.kt` dosyaları, `ACTION_REFRESH` == manifest); durum değerleri; `buildStateSnapshot`/`buildDailySnapshot` anahtar kümesi tam |
| `test/core/updates/manifest_attack_test.dart` | **34** | `sha256` kaldırıldığında/bozulduğunda/bozuk metin konduğunda sonuç **asla** `verified` değil; 10 düşmanlı `apkUrl` varyantı (`javascript:`, `intent:`, `file:`, `content:`, `market:`, `http:`, `userInfo`, uzantısız, boş host, host yok) → ağa hiç çıkmadan red; `minSupportedVersionCode` manipülasyonu (999 → kilit kurar; alan silinince fail-**ON**, hiçbir build `required` görmez; string/sondur → 1); `versionCode` 7.5/`versionName` eksik/`apkUrl` eksik → manifest geçersiz → `unknown`; zorunlu güncelleme sonsuz döngü riski; `notes` alan tipi |
| `test/core/notifications/notification_scheduling_test.dart` | **18** | `nextDailyOccurrence`: 00:00/23:59/tam an/1 sn kala/ay sonu/şubat sonu/DST ileri-geri/konum sözleşmesi + **3 dil × 28 gün × 24 saat × 4 dakika** parametrik; hatırlatıcı ID çakışması; `_pendingSchedule` biriktirme; migration **bir kez** çalışıyor ve kullanıcı ayarını (9:00) **ezmiyor**; öğün başına bağımsızlık; varsayılan saat geçerliliği |
| `test/core/utils/calculations_reference_test.dart` | **53** | BMR elle hesaplanmış referans (1749/1320), 1 kg→10, 1 cm→6, 1 yıl→5, kadın-erkek farkı 166, `other` ayrışması; TDEE 5 çarpan (2100/2406/2713/3019/3325); hedef 1200 tabanı (tüm amaç×TDEE kombinasyonu); makro %30/40/30, Atwater toplam sapma ≤ 4 kcal, negatif→0; BMI 4 referans + negatif boy + NaN; kategori eşikleri ve renk adları; su `kg×33`; yaş (geçti/geçmedi/bugün/yarın/29 Şubat/maxAge); `progress` 0..100 garantisi |
| `test/core/dead_code_test.dart` | **11** | `downloadVerifyAndOpen` imzası + tek tanım; `UpdateChecker` durum makinesi boşlukları; cache/dismissed anahtar ayrımı; **karar matrisi 3×4×9 = 108 kombinasyon** + tekdüzelik; kaynak dosyası bağımlılıkları (`core` → `features`), `ForceUpdatePage` bulgusunu kırmızıya dönmeye hazır |
| `test/core/updates/apk_integrity_test.dart` (güncellendi) | +3 | Geçici dosya adı/yol enjeksiyonu/eski sürüm temizliği/başarısız indirmede artık |
| `test/core/utils/calculations_edge_cases_test.dart` (güncellendi) | — | Negatif boy ve negatif kilo testleri artık **düzeltilmiş** davranışı kilitliyor (eski yorumlar hatayı "beklenen" diye kaydediyordu) |

`test/core/**` = **441 test** (`flutter test test/core` → `All tests passed!`).
Toplam `flutter test` = **784** (Tur 5'te 629; +155, hepsi geçiyor).

## Değişmeyenler (bilinçli)

- `main.dart` — Sentry `runZonedGuarded` + fallback doğru, dokunmadım.
- `theme/app_theme.dart` — kontrast tablosu ölçülmüş ve testli, yeni renk
  eklemedim; WCAG ölçümü yeniden yapmaya gerek kalmadı.
- `analysis_options.yaml` — `strict-casts`/`strict-inference`/`strict-raw-types`
  zaten açık; `core/` altında ihlal yok (`flutter analyze` temiz). A6 alanı
  olduğu için dosyaya dokunmadım.
- `env.dart` — A1 alanı (PROTOKOL §4).
- `router/app_router.dart` — `_RouteReady(null)` mantığı doğru, sorun yok.

## Sonraki öneriler (tur 7 için)

1. **`ForceUpdatePage` `sha256` zincirine girsin** (A4) — erişim engeli kalktı.
2. **Ayak ölü kod ya da eksik özellik kararı** (A4 + A2): haftalık widget
   (`publishWeekly`), nudge bildirimi (`shouldSendNudge`), `workmanager`.
   Üçü de "kullanıcıya görünür ama işlevsiz" — sessizce kaybolmadan karar
   verilmeli.
3. **`refreshTimeZone` bağlansın** (A4) — `onResume` çağrısı.
4. **İki testi kırmızıya döndürmek** bilinçli yapıldı:
   `dead_code_test.dart` (ForceUpdatePage) ve `update_gate`/`notification`
   izin entegrasyonu. A4 düzeltmelerini CI'da zorlayacak.
5. **`isSafeApkUrl` host kısıtı** (A1) — `github.com/GokhanOfficial/CaloriX`
   allow-list ya da TLS pinning kararı.
6. **Web/Flutter `Gender.other` ayrışması** (A5 + ürün) — 166 kcal fark.
7. `analytics_page.dart` (1239 satır) ve `chat_page.dart` (969 satır) bölme —
   A4'ün alanında, Tur 5'te kalmıştı; A4r6 bölme yapmış görünüyor.
