# CaloriX Flutter — İlerleme Takibi

> Master plan: `flutter-plan-master.md`
> **Not:** Supabase veritabanı şu an deaktif — canlı backend testleri tüm fazlar bittikten sonra kullanıcı tarafından yapılacak.

---

## ✅ Faz 0 — İskelet & Altyapı (tamamlandı: 2026-08-15)

### Yapıldı
- [x] `flutter create --org com.calorix --project-name calorix --platforms=android,web,linux flutter_app`
- [x] `pubspec.yaml` — tüm bağımlılıklar (supabase_flutter, riverpod, go_router, easy_localization, fl_chart, mobile_scanner, **camera**, image_picker, flutter_dotenv, flutter_markdown, share_plus, flutter_local_notifications...)
- [x] `.env.example` şablonu + `.env` gitignore'a eklendi (gerçek değerler test aşamasında kullanıcı tarafından girilecek)
- [x] `lib/core/config/env.dart` — dart-define > .env öncelikli okuma
- [x] `lib/data/supabase/supabase_client_provider.dart` — `initSupabase()` (env eksikse sessizce atlar, uygulama yine açılır)
- [x] `lib/core/theme/app_theme.dart` — Material 3, **dark varsayılan**, `shared_preferences` kalıcılığı (`theme` anahtarı — web ile aynı), `ThemeModeNotifier`
- [x] `lib/core/router/app_router.dart` — 9 route (web path'leriyle birebir), placeholder sayfalar; auth redirect TODO (Faz 1)
- [x] `lib/app.dart` + `lib/main.dart` — EasyLocalization + ProviderScope + MaterialApp.router
- [x] **i18n:** `tool/convert_locales.cjs` — i18next `{{var}}` → easy_localization `{var}` dönüştürücü; **12 dilin tamamı** `assets/translations/` altında (Faz 3'ten öne çekildi)
- [x] `assets/images/logo.png` web'den kopyalandı
- [x] Android: `applicationId com.calorix.app`, `minSdk 23`, manifest izinleri (INTERNET, CAMERA, POST_NOTIFICATIONS), `android:label="CaloriX"`
- [x] Android build düzeltmeleri:
  - `isCoreLibraryDesugaringEnabled = true` + `desugar_jdk_libs:2.1.4` (flutter_local_notifications)
  - `android/build.gradle.kts` subprojects hook: `camera_android_camerax`'e `androidx.concurrent:concurrent-futures:1.2.0` (CameraX 1.5.3 jspecify derleme hatası çözümü)

### Doğrulama sonuçları
- [x] `flutter analyze` — **0 sorun**
- [x] `flutter test` — **1/1 geçti** (PlaceholderPage widget testi)
- [x] `flutter build web --release` — **✓ Built build/web**
- [x] `flutter build apk --debug` — **✓ Built app-debug.apk**

### Kalan / notlar
- Emulator'de görsel smoke test yapılmadı (gerek yok — placeholder sayfalar)
- Chrome yok → web sadece build edildi, tarayıcı testi yapılmadı
- `proguard-rules.pro` placeholder olarak eklendi (Faz 5'te doldurulacak)
- Flutter doctor: adb çoğaltması uyarısı var (zararsız), Chrome eksik (web run için `CHROME_EXECUTABLE` ayarlanabilir)

---

## ✅ Faz 1 — Auth + Onboarding + Profil (tamamlandı: 2026-08-15)

**Plan:** `flutter-plan-phase1-auth.md`

### Yapıldı
- [x] `AuthRepository` (signUp/signIn/signOut/resetPassword/resendVerificationEmail/updatePassword) — hata biçimi web ile aynı: nullable `AuthException?`; e-posta redirect'leri platforma göre (web: `Uri.base.origin`, mobil: `io.supabase.calorix://reset-callback`)
- [x] Router auth redirect — `_routeDecisionProvider` (sealed: loading/ready): oturum yok→`/auth`, PASSWORD_RECOVERY→`/auth`, profil hatası veya `onboarding_completed=false`→`/onboarding`; `refreshListenable` ile otomatik yeniden yönlendirme
- [x] AuthPage UI — 4 görünüm: auth (Giriş/Kayıt TabBar), forgotPassword, pendingVerification (yeniden gönder + farklı hesap), resetPassword; PASSWORD_RECOVERY eventi otomatik reset görünümüne geçirir; hata mesajları web ile aynı string eşleşmeleri
- [x] Deep link: `io.supabase.calorix://reset-callback` intent-filter AndroidManifest'e eklendi
- [x] OnboardingPage — 5 adımlı sihirbaz (kişisel → boy/kilo [canlı BMI rozeti] → aktivite → hedef → özet); son adımda `MacroCalculator` (önce `calculate-macros` Edge Function, hata/eksikte yerel Mifflin-St Jeor fallback); kayıt `ProfileRepository.update` + `profileProvider` invalidate
- [x] `Profile` modeli (json_serializable, `isOnboardingComplete` getter) + `ProfileRepository` (fetch `.maybeSingle()`, update `updated_at` damgalı) + `profileProvider`
- [x] `UserSetting` modeli + `UserSettingsRepository` (fetchAll→Map, upsert `onConflict: 'user_id,key'`) + `userSettingsProvider`
- [x] `AppConstants` + enum'lar: ActivityLevel (çarpanlar), Goal (kalori modifikatörleri), Gender, MealType (Faz 2 için)
- [x] `Calculations` — BMR/TDEE/hedef kalori/makro (30/40/30)/BMI/su (kg×33)/yaş/ilerleme; web `calculations.ts` parity
- [x] Unit testler (mocktail): **34 test, tamamı geçiyor**
  - `test/data/repositories/auth_repository_test.dart` — 12 test (tüm metotlar + redirect URL + display_name fallback)
  - `test/data/repositories/macro_calculator_test.dart` — 6 test (AI başarı / fallback 3 senaryo / istek gövdesi parity)
  - `test/core/utils/calculations_test.dart` — web parity hesap testleri

### Doğrulama sonuçları
- [x] `flutter analyze` — **0 sorun**
- [x] `flutter test` — **34/34 geçti**
- [x] `flutter build web --release` — **✓ Built build/web**
- [x] `flutter build apk --debug` — **✓ Built app-debug.apk**

### Kalan / notlar
- `json_annotation` ^4.12.0'a yükseltildi (build_runner uyarısı)
- Canlı Supabase testi yapılmadı (DB deaktif) — kullanıcı tüm fazlar bitince test edecek
- iOS deep link yapılandırması yapılmadı (proje android+web+linux hedefli; gerekirse Faz 5'te)

---

## ✅ Faz 2 — Günlük + Yemek Ekleme (tamamlandı: 2026-08-15)

**Plan:** `flutter-plan-phase2-diary.md`

### Yapıldı
- [x] **Modeller** (json_serializable): `Food` + `FoodNutrition` (1:1 join — PostgREST'in Map/List döndürme belirsizliği `_firstNutrition` ile çözüldü), `MealEntry` (tüm meal_entries kolonları), `WaterEntry`, `WeightEntry`; `FoodItem` (arama/favori/son-yenilenler için 100g-normalize birleşik tip, `forAmount()` hesabı web parity)
- [x] **FoodRepository** — `search()` (foods ilike + food_nutrition join, popularity desc, limit 10 + custom meal_entries ilike limit 50 → dedup lowercase name → DB önce stable sort → take 15; web `useFoodSearch` birebir), `favorites()` (son 200 meal_entry, frekansa göre top 10; web `useFavoriteFoods`), `recents()` (son 50, unique, 10; web `useRecentFoods`)
- [x] **DiaryRepository** — `fetchDaily` (3 paralel sorgu: meals created_at asc / water entry_time asc / son kilo **tarih filtresiz** entry_date desc limit 1; web `useDailyData` parity), `addMealEntry`/`updateMealEntry` (updated_at damgalı)/`deleteMealEntry` (soft), `addWaterEntry`/`deleteWaterEntry` (soft), `addWeightEntry`; `DailyData` value class (`mealsByType`, `totals`, `totalWater`)
- [x] **Provider'lar** — `selectedDateProvider` (bugün, gece yarısı), `dailyDataProvider` (user+date watch; invalidate ile tazelenir), `foodSearchProvider` (autoDispose.family, min 2 karakter), `favoriteFoodsProvider`, `recentFoodsProvider`
- [x] **Dashboard** (`Index.tsx` karşılığı) — `DateSelector` (chevron + takvim + "bugün" dönüşü, dün/yarın etiketleri), `CalorieRing` (kalan merkezli, aşımda hata rengi), `MacroCards` (P/K/Y — etiketler `settings.goals.*`), `WaterTracker` (ilerleme + hızlı +250/+500 + özel dialog), `WeightCard` (hızlı giriş + `auto_recalculate_macros` açıksa `calculate-macros` çağrısı — web `handleWeightSubmit` parity: yaş `floor(gün/365.25)` varsayılan 30, previous_macros/previous_weight_kg gönderimi, başarısızlıkta sessiz geçiş), `MealSections` (4 öğün kartı, Dismissible ile soft-delete), pull-to-refresh, FAB → /add
- [x] **Yemek Ekleme** (`AddPage.tsx` karşılığı) — öğün seçici (varsayılan `lunch`), AI placeholder kartı (Faz 4), **arama** (300ms `Timer` debounce, min 2 karakter, sonuç satırları `100g • X kcal` + P/K/Y), **Son Eklenenler** + **En Çok Yenenler** bölümleri (arama aktifken gizlenir — web davranışı), barkod kartı (placeholder), manuel giriş kartı
- [x] **Dialoglar** — `AddFromFoodDialog` (bottom-sheet: miktar [varsayılan serving ?? 100g] + öğün + canlı makro önizleme; custom ise `food_id: null` + `custom_name`), `AddManualEntryDialog` (isim/öğün/miktar/kcal/P/K/Y — web `AddMealDialog` parity, `parseFloat || 0`)
- [x] **Navigasyon** — `AppShell` (Material 3 `NavigationBar`, 5 sekme) `ShellRoute` ile router'a bağlandı; dashboard FAB ve meal-card "ekle" butonları `/add`'e gider
- [x] `MacroCalculator.calculate` — `previousMacros`/`previousWeightKg` opsiyonel parametreleri eklendi (kilo güncelleme akışı); Edge function null'ları güvenle yok sayıyor
- [x] `MealType` enum'a `emoji` alanı (web `MEAL_TYPES.icon`) — dashboard ve add sayfası tek kaynaktan kullanıyor

### Doğrulama sonuçları
- [x] `flutter analyze` — **0 sorun**
- [x] `flutter test` — **46/46 geçti** (34 eski + 12 yeni: `diary_repository_test.dart` — formatEntryDate / mealsByType / totals / totalWater / forAmount web-parity hesapları)
- [x] `flutter build web --release` — **✓ Built build/web**
- [x] `flutter build apk --debug` — **✓ Built app-debug.apk**

### Kalan / notlar
- Canlı Supabase testi yapılmadı (DB deaktif) — planın "web ile senkron / aynı hesap" kriterleri kullanıcının tüm fazlar sonrası testine kaldı
- Favori **ekleme/çıkarma** (yıldız toggle) web'de ayrı bir özellik olarak yok — web `useFavoriteFoods` sadece kullanım frekansından türetiyor; Flutter da aynısını yapıyor (ayrı favoriler tablosu kullanılmıyor)
- AI/barkod butonları bilinçli placeholder (Faz 4)
- Su kaydı silme UI'ı yok (web'de de yok — sadece repository metodu var)

---

## ✅ Faz 3 — Analitik + Ayarlar (tamamlandı: 2026-08-15)

**Plan:** `flutter-plan-phase3-analytics-settings.md`

### Yapıldı
- [x] **AnalyticsRepository** — `AnalyticsPeriod` enum (week/month/threeMonths), `DailyStats`/`WeightPoint`/`AverageStats`/`AnalyticsData` value sınıfları; test edilebilir static metotlar (`dateRange`, `buildDays`, `aggregateDaily`, `computeAverages`, `buildWeightTrend`) + `fetch()` (3 paralel Supabase sorgusu); `analyticsRepositoryProvider`, `analyticsPeriodProvider` (StateProvider), `analyticsDataProvider` (FutureProvider.family<AnalyticsData,String>) — web `useAnalyticsData` parity
- [x] **AnalyticsPage** (`analytics_page.dart`) — dönem SegmentedButton (hafta/ay/3ay); `_Targets.fromProfile` (eksikte AppConstants varsayılanları); `_StatGrid` (4 kart: ortalama kalori/su/protein + kilo değişimi — web renk kuralları); `_CaloriesChartCard` (fl_chart LineChart, hedefin %'si, %100 kesik çizgi); `_MacrosChartCard` (BarChart P/K/Y gruplu + %100 kesik çizgi + lejant); `_MacroAveragesCard` (LinearProgressIndicator satırları); `_WeightTrendCard` (LineChart + ilk/değişim/son); `_SummaryCard` (verili gün/toplam gün)
- [x] **SettingsPage** (`settings_page.dart`) — AppBar `settings.title`; tema SwitchListTile (dark toggle → themeModeProvider); 5 bölüm (Profil/Uygulama/Veri/Hesap/Hakkında) `_SectionHeader` + Card `_Tile` satırları; `_LanguageTile` (12 dil DropdownButton → context.setLocale); `_CameraTile` (SegmentedButton in_app/native → cameraPreferenceProvider); sağlık sorumluluk reddi kartı
- [x] **Ayarlar dialogları** (`lib/features/settings/widgets/`):
  - `personal_info_dialog.dart` — ad/boy/kilo/hedef kilo kontrolleri, Gender RadioGroup, doğum tarihi (showDatePicker), canlı BMI rozeti (Calculations.bmi + bmi_category rengi); kayıt: autoRecalculateMacros && kilo değişti && doğum tarihi var → macroCalculatorProvider.calculate (previousMacros/previousWeightKg) ile bmr/tdee/hedefler eklenir
  - `goals_dialog.dart` — kalori/su/protein/karb/faz kontrolleri, ActivityLevel + Goal RadioGroup; `_aiCalculate` macroCalculatorProvider.calculate ile 5 kontrolü doldurur; kayıt: activity_level/goal.name + 5 hedef
  - `notifications_dialog.dart` — push/email bool (varsayılan true), tartılma sıklığı (varsayılan 7), autoRecalc bool; kayıt: push_notifications_enabled/email_notifications_enabled/weigh_in_frequency_days/auto_recalculate_macros (per-type notification_preferences tablo CRUD → Faz 5)
  - `password_dialog.dart` — hardcoded TR string'ler (web parity); uzunluk <6 → auth.validation.passwordLength, uyuşmaz → auth.validation.passwordMismatch, else authRepositoryProvider.updatePassword
- [x] **Veri aktarımı** — `DataTransferRepository` (exportData: 8 paralel sorgu → JsonEncoder.withIndent; importData: doğrulama + food dedup name+created_by, food_nutrition remap, meal/water/weight dedup, Map<String,int> sayım döndürür; _stripIds) + `dataTransferRepositoryProvider`
- [x] **TransferDialogs** (`transfer_dialogs.dart`) — export: exportData → getTemporaryDirectory → `calorix-backup-{yyyy-MM-dd}.json` → Share.shareXFiles; import: FilePicker.platform.pickFiles (json, withData) → importData → SnackBar; FormatException → settings.import.fileNote
- [x] **AboutPage** (`about_page.dart`) — uygulama bilgi kartı (logo + CaloriX + about.subtitle + versiyon rozeti `about.version.tr(namedArgs:{'version':appVersion})`), özellikler kartı (AI/barkod/takip/analitik/bildirim madde satırları), geliştirici kartı (Gökhan Tekyıldırım + rol + mailto InkWell → url_launcher), powered-by kartı (Pollinations AI), footer kartı (madeWith + Heart(destructive) + inTurkey + copyright)
- [x] **CameraPreference** (`lib/core/config/camera_preference.dart`) — `enum CameraPreference { inApp('in_app'), native('native'); fromValue }` + `CameraPreferenceNotifier` (shared_preferences `camera_preference` anahtarı, varsayılan inApp) + `cameraPreferenceProvider` — Faz 4'te tüketilecek
- [x] **url_launcher** ^6.3.1 pubspec'e eklendi (mailto için); 6.3.2 çözümlendi
- [x] **Android build — compileSdk 36 çakışması çözümü:** file_picker 8.x ve image_picker_android transitif olarak `flutter_plugin_android_lifecycle` çeker; 2.0.35'in yayınlanmış AAR'i `minCompileSdk=36` gerektiriyor, ancak AGP 9.1 + Flutter 3.47'de `flutter.compileSdkVersion=34` ve AGP 9 compileSdk değerini değerlendirme sırasında erken sonlandırdığı için plugin modüllerinin compileSdk değerini 36'ya yükseltmek zamanlama hatası veriyor ("too late to set compileSdk"). Çözüm: `dependency_overrides` ile `flutter_plugin_android_lifecycle: 2.0.24` (compileSdk 34 ile yayınlanan son sürüm) sabitlendi — AAR metadata kontrolü artık geçiyor. Not: Faz 5'te Flutter/AGP yükseltildiğinde override kaldırılabilir.

### Doğrulama sonuçları
- [x] `flutter analyze` — **0 sorun**
- [x] `flutter test` — **61/61 geçti** (46 eski + 15 yeni: `analytics_repository_test.dart` — dateRange [hafta/ay/3ay/şubat28/saat-sıfır] / buildDays [hafta kırpma, ay etiketleri, başlangıç>bugün boş] / aggregateDaily [yuvarlama kuralları, boş] / computeAverages [tipe göre bölen, boş, 1 ondalık] / buildWeightTrend [sıralı, boş])
- [x] `flutter build web --release` — **✓ Built build/web**
- [x] `flutter build apk --debug` — **✓ Built app-debug.apk** (117.7s)

### Kalan / notlar
- Canlı Supabase testi yapılmadı (DB deaktif) — kullanıcı tüm fazlar bitince test edecek
- Bildirim tercihleri per-type (`notification_preferences` tablo CRUD) Faz 5'e ertelendi
- `camera_preference` ayarı oluşturuldu ama henüz tüketilmiyor — Faz 4 (in-app kamera) ile bağlanacak
- `flutter_plugin_android_lifecycle` 2.0.24 pin'i geçici — Faz 5'te Flutter/AGP yükseltince kaldırılacak

---

## ✅ Faz 4 — AI + Kamera + Barkod (tamamlandı: 2026-08-16)

**Plan:** `flutter-plan-phase4-ai.md`

### Yapıldı

#### 4a — AI Chat (`ChatPage.tsx` karşılığı)
- [x] `ChatMessage` + `ChatAttachment` modelleri (json_serializable) — `chat_messages.attachments` JSONB içindeki tek ek; `isUser`/`isAssistant` ayrımı `sender` alanından
- [x] `ChatRepository` — `ensureThread` (aktif/arşivlenmemiş thread bul/oluştur), `fetchMessages` (son PAGE_SIZE, eskiden-yeniye DB → UI'ye ters çevir), `sendMessage` (kullanıcı mesajını ÖNCE `chat_messages`'a insert, sonra `ai-chat` invoke; gövde `{mode, threadId, locale, language, timeZone, currentDate}` — edge fonksiyonu son 50 mesajı DB'den okur, kullanıcı metni gönderilmez), `archiveThread`, `uploadAttachment` (storage `chat-attachments` bucket → imzalı URL `attachments`'a); **tek invoke, stream/poll yok** (web parity); `localDateOnly` (web `toLocaleDateString("en-CA")`)
- [x] `ChatPage` — thread listesi + mesaj ekranı; markdown render (`flutter_markdown`); "Temizle" → thread arşivle + yeni thread; image_picker ile ek (attachment) seçimi → storage yükleme; gönder + asistan cevabı bekleme durumu
- [x] Unit test: `chat_repository_test.dart` — 10 test (`localDateOnly` formatı, gövde alanları, attachment parse)

#### 4b — Kamera + Foto/Metin Tanıma
- [x] **Kamera mimarisi** (Faz 4 planı §1) — üç giriş yolu: uygulama içi kamera (`camera`, barkod-tarayıcı benzeri tam ekran) / telefon kamerası (`image_picker` camera) / galeri (`image_picker` gallery). `camera_preference` ayarı tüketildi (Faz 3'ten): `in_app` → InAppCameraScreen önce, izin reddinde native'e düşer; `native` → doğrudan ImagePicker.camera. maxWidth 1600, imageQuality 85
- [x] `InAppCameraScreen` — `CameraController` (arka kamera, `ResolutionPreset.high`, flash toggle), çekim butonu + galeriye geçiş + kapat, çekim sonrası önizleme ("Yeniden Çek" / "Kullan"), sonuç `XFile`; `static Future<XFile?> show(BuildContext)`; izin reddedilirse null döner (çağıran native'e düşer)
- [x] `RecognizedFood` modeli — `recognize-food`/`recognize-food-text` yanıtındaki `foods[]` öğesi; 100g/ml başına normalize; `amount_g_ml` AI porsiyon tahmini; yeni (`calories_per_100g` …) ve eski (`calories`, `protein_g` …) alan adlarını ikisi de tolere eder (web parity); `forAmount()` (kcal yuvarla, makrolar 1 ondalık), `toItem()` (FoodItem'a dönüştür). `RecognitionResult.fromJson({foods, description})`
- [x] `RecognitionRepository` — `recognizeFood(XFile, {additionalText})` (byte'ları oku → base64 **data URL** → `recognize-food` gövde `{image_base64, additional_text?}`, depolama yükleme YOK), `recognizeFoodText(text)` (`recognize-food-text` gövde `{text}`); `recognitionRepositoryProvider`
- [x] `AddWithAiDialog` — giriş adımı (web `UnifiedFoodDialog`): foto çek (kamera tercihine göre), galeriden seç, metin gir → "AI ile analiz et"; yükleniyor durumu → `recognize-food`/`recognize-food-text` → sonuçlar `RecognitionConfirmDialog`'a
- [x] `RecognitionConfirmDialog` — onay ekranı (web "results" adımı): tüm tanınan yemekler tek kaydırılabilir listede, ortak öğün seçici; her yemek düzenlenebilir (ad, miktar g/ml, 100g başına kcal/P/K/Y), canlı toplam; checkbox ile seçim kaldırılır. Kayıt (web `handleSave` parity): SEÇİLİ her yemek için AYRI `meal_entries` INSERT, `custom_name`, `source` photo/text, `food_id: null`; invalidate dailyDataProvider/recentFoodsProvider/favoriteFoodsProvider + SnackBar
- [x] Unit test: `recognized_food_test.dart` — 16 test (fromJson yeni/eski alan önceliği, defaultlar, genişletilmiş besin + nova/nutri, forAmount yuvarlama, toItem)

#### 4c — Barkod Tarama (web `BarcodeScanDialog.tsx` parity)
- [x] `BarcodeFood` modeli — web `FoodData` karşılığı; hem DB'den (`fromDb: true`) hem AI'den (`fromDb: false`) tek ürün; 100g başına değerler; **düzenlenebilir alanlar** (result adımında değişebilir — web `foodData` gibi), `final` kalan: barcode/confidence/fromDb/foodId; `fromAiFood` (Map, yeni/eski alan önceliği), `fromDbRow` (PostgREST 1:1 join Map/List → `_firstNutrition`; **`sugar_g` tekil — DB sütunuyla doğru**), `fromRecognizedFood` (AI tanıma → BarcodeFood), `forAmount`, `displayName` (`name + (brand? " ($brand)" : "")`)
- [x] `BarcodeRepository` — `lookupByBarcode(code)` (`foods` + `food_nutrition` join, `.eq('barcode', code).maybeSingle()`; row null veya tüm makrolar 0 → null, web `food && food.nutrition` parity), `createFoodWithNutrition({userId, food, source})` (önce `foods` {name, brand, barcode, serving_size_g, source, created_by} → select id; sonra `food_nutrition` {food_id, kcal, protein_g, carbs_g, fat_g, fiber_g, **sugar_g tekil**, salt_g, saturated_fat_g, trans_fat_g, nova_score, nutri_score}; food_id döndürür)
- [x] `BarcodeScanDialog` — 4 adımlı bottom-sheet (web ile aynı: scan → analyzing → notFound / result):
  - **scan**: `MobileScanner` (mobile_scanner 5.2.3) canlı barkod tarama (native, `DetectionSpeed.noDuplicates`, `CameraFacing.back`) + `errorBuilder` (`errorDetails.message`); web'de `kIsWeb` guard → placeholder + manuel giriş; manuel barkod numarası alanı (yalnızca rakam) + "Ara" butonu
  - **analyzing**: DB arama ("Veritabanında aranıyor...") veya AI analizi ("AI Analiz ediliyor...")
  - **notFound**: ürün bulunamadı; foto çek (kamera tercihi) / galeri / ek detay → "AI ile analiz et" (`recognize-food` foto ile, `recognize-food-text` metinle; prompt `additionalText || "Barkod: {barcode}"`); boş ek+foto yoksa `aiPromptRequired` uyarısı
  - **result**: DB'den bulundu rozeti ("Veritabanında bulundu") veya AI güven skoru; barkod etiketi; öğün seçici; düzenlenebilir ad/marka; miktar + porsiyon boyutu; "100g başına" ipucu; 4 ana makro + açılır-kapanır genişletilmiş besin (doymuş/trans yağ, şeker, lif, tuz, NOVA, Nutri-Score); canlı hesaplanan önizleme; "Tekrar tara" + "Kaydet"
  - **kayıt** (web `handleSave` parity): source = foto? "photo" : "barcode"; `fromDb` değilse + barkod varsa `createFoodWithNutrition` → finalFoodId; `food.forAmount(amount)` → `addMealEntry` (mealType, amountGMl, calculated*, source, foodId: finalFoodId, customName: displayName); invalidate + SnackBar
- [x] **Wiring** — `AddPage._BarcodeCard` artık `BarcodeScanDialog.show(context, defaultMealType: _selectedMeal)` açıyor (placeholder `_phase4Placeholder` kaldırıldı)
- [x] **Çeviriler** — 21 yeni `dialogs.barcode.*` anahtarı (scanDesc, manualPlaceholder, search, cameraError, searching, productNotFoundDesc, aiPrompt, aiPromptRequired, aiTextPrompt {0}, barcodeLabel {0}, foundInDb, reScan, brand, servingSize, extendedNutrition, saturatedFat, transFat, sugars, salt, novaScore, nutriScore) + `dialogs.fiberG` tüm **12 dilde** (ar/de/en/es/fr/it/ja/ko/pt/ru/tr/zh) eklendi
- [x] Unit test: `barcode_food_test.dart` — 14 test (fromAiFood 6, fromDbRow 3, forAmount 2, displayName 3)

### Doğrulama sonuçları
- [x] `flutter analyze` — **0 sorun** (test'teki kullanılmayan `food_item` import'u temizlendi)
- [x] `flutter test` — **101/101 geçti** (61 eski + 40 yeni: chat 10 + recognized_food 16 + barcode_food 14)
- [x] `flutter build web --release` — **✓ Built build/web** (67.9s)
- [x] `flutter build apk --release` — **✓ Built app-release.apk (79.2MB, 341.3s)**

### Kalan / notlar
- Canlı Supabase / edge fonksiyonu testi yapılmadı (DB deaktif) — kullanıcı tüm fazlar bitince test edecek
- mobile_scanner web plugin'i var ama plan web'de manuel giriş (kIsWeb guard) kullanıyor — canlı kamera web'de test edilmedi
- **Bilinen web latent bug'u (mirasmadı):** web `BarcodeScanDialog.tsx` kaydı sırasında `food_nutrition`'a `sugars_g` (çoğul) insert ediyor, ancak DB sütunu `sugar_g` (tekil) — web'de bu sütun sessizce düşer. Flutter `BarcodeFood.fromDbRow` ve `BarcodeRepository.createFoodWithNutrition` **doğru `sugar_g` (tekil)** kullanıyor; web tarafındaki bu tutarsızlık ayrıca giderilmeli
- InAppCameraScreen widget testi (mock CameraController) eklenmedi — `camera` plugin'i mock'lanması zor; canlı cihaz/emülatör testi kullanıcıya kaldı
- Gradle KGP uyarısı (camera_android_camerax/mobile_scanner/share_plus Built-in Kotlin geçişi) — bilgi amaçlı, build'i engellemiyor; Faz 5'te plugin güncellemeleri ile ele alınabilir

---

## ✅ Faz 5 — Web Build, CI/CD ve Yayınlama (tamamlandı: 2026-08-16)
Plan: `flutter-plan-phase5-release.md`

### 5a — CI (GitHub Actions)
- `.github/workflows/flutter.yml`: `flutter_app/**` (ve workflow'un kendisi)
  path filter'lı; push (main + feature/**) ve PR tetikleyici.
- `concurrency` ile aynı branch için eski çalışma iptal.
- `check` job: JDK 17 + Flutter 3.47.0 setup → `flutter pub get` →
  `build_runner build --delete-conflicting-outputs` → `flutter analyze` →
  `flutter test`. `.env` gitignore'da ama pubspec asset'i olduğundan CI
  placeholder `.env` sentezler (`cp .env.example .env`).
- `build` job (yalnızca main): web release + appbundle, gerçek Supabase
  değerleri `--dart-define` ile (Env dart-define'a öncelik verir). Build
  artifact'leri upload-artifact ile kaydedilir.

### 5b — Android release imzalama + R8
- `android/key.properties.example` (Play Console upload keystore için
  şablon; gerçek dosya gitignore'da).
- `android/app/build.gradle.kts`: `key.properties` mevcutsa release
  signingConfig (keyAlias/keyPassword/storeFile/storePassword), yoksa
  debug anahtarına düşer — CI pipeline yeşil kalır, Play Console'a
  gerçek keystore ile imzalanmış AAB yüklenir.
- R8: `isMinifyEnabled` + `isShrinkResources` açık; keep kuralları
  `proguard-rules.pro`'da (Flutter/Supabase/CaloriX model sınıfları/
  riverpod/easy_localization/mobile_scoring + Play Core `-dontwarn` +
  enum/Serializable + stack-trace attribute'ları).
- AAB build ✓ (70.9MB, R8 sonrası APK'tan küçük; debug imza fallback).

### 5c — Uygulama ikonu + açılış ekranı
- `flutter_launcher_icons ^0.14.3` + `flutter_native_splash ^2.4.6`
  dev_dependencies'e eklendi; pubspec'te config blokları (kaynak
  `assets/images/logo.png` 1024×1024, arka plan CaloriX teal #00C7B7).
- **İkon üretildi** (`dart run flutter_launcher_icons`):
  - Android default mipmap PNG'leri (mdpi…xxxhdpi) Flutter logosu yerine
    CaloriX logosu ile değişti (442→2879, …1443→24885 byte — içerik
    tamamen yenilendi).
  - Android adaptive icon: `mipmap-anydpi-v26/ic_launcher.xml` + foreground
    drawables (drawable-*dpi/ic_launcher_foreground.png, 108…432dp) +
    `values/colors.xml` (`ic_launcher_background #00C7B7`).
  - Web: `favicon.png`, `icons/Icon-{192,512,maskable-192,maskable-512}.png`
    logo ile üretildi; `manifest.json` tema/arka plan rengi `#0175C2`→
    `#00C7B7` (Flutter mavisi → CaloriX teal).
  - iOS üretimi devre dışı (`ios: false`) — projede iOS Runner klasörü yok
    (Android/web odaklı); iOS hedeflenirse `ios: true` + `flutter create
    --platforms ios` ile Runner şablonu eklenmeli.
  - Debug APK build ✓ — ikonlar APK içine gömüldü doğrulandı
    (mipmap + adaptive XML + foreground drawables byte-boyut uyumlu).
- **Açılış ekranı (splash) üretimi hâlâ bekliyor** (config hazır):
  `dart run flutter_native_splash:create` (kullanıcı çalıştıracak).

### 5d — CHANGELOG + sürüm
- `CHANGELOG.md`'ye "Flutter App" bölümü eklendi (EN + TR), pubspec
  sürümü `1.0.0+1` (web `1.1.0`'dan bağımsız).
- `flutter-plan-phase5-release.md`: `--web-renderer` bayrağı artık yok
  (canvaskit Flutter 3.x'te varsayılan) — plan düzeltildi.

### Doğrulama
- `flutter analyze` → 0 sorun
- `flutter test` → 101/101 geçti
- `flutter build web --release` → ✓ (66.0s derleme; canvaskit varsayılan)
- `flutter build appbundle --release` → ✓ 70.9MB (R8 açık)

### Kalan / kullanıcı tarafından yapılacak (operasyonel)
- Keystore üretimi + `key.properties` doldurma (Play Console upload)
- Supabase Dashboard → Authentication URL Configuration: Redirect URLs'e
  `io.supabase.calorix://reset-callback` (Android) + Flutter web URL'i
- GitHub Secrets: `FLUTTER_SUPABASE_URL`, `FLUTTER_SUPABASE_ANON_KEY`
- Hosting kararı (ayrı Vercel projesi / subdomain / React yanında paralel)
- Play Store listeleme metinleri/görselleri (TR + EN)
- İkon üretildi (5c); splash üretim komutunu çalıştırma:
  `dart run flutter_native_splash:create`
- iOS (opsiyonel): Apple Developer hesabı + macOS build ortamı gerekir
- Tüm fazlar bitince canlı DB uçtan uca test (kullanıcı)

### Notlar
- Canlı Supabase / edge fonksiyonu testi yapılmadı (DB deaktif)
- CI imzalama yok (debug fallback) — Play Console yüklemesi elle imzalanır
- Gradle KGP uyarısı (camera_android_camerax/mobile_scanner/share_plus)
  bilgi amaçlı; plugin Built-in Kotlin geçişi sonraki güncellemelerde

---

## UI/UX Redesign (feature/flutter-app üstünde, 3 faz)

Kullanıcı arayüzü olgun/modern bulmadığını bildirdi ve 6 somut sorun verdi:
AI ekle tuşu çirkin; öğün "+" sonradan öğle seçiyor; ekle menüsü kullanışsız;
ring/makro tıklanmıyor (istatistik eksik hissi); kaydırınca anında siliniyor
(undo/edit yok); AI tanıma onayda gram editlerken her tuşta cursor odağı
kayboluyor + satır görünümü çirkin. Plan `plans/flutter-redesign-master.md`
+ 3 faz dosyasında. Backend/Supabase değişikliği YOK, yeni ağır bağımlılık
YOK (mevcut `fl_chart` yeterli).

### Faz 1 — Odak kaybı fix + tanıma satırı görsel + M3 tema cila ✓
- `recognition_confirm_dialog.dart`: satır tile `_FoodRowTile`
  `ConsumerStatefulWidget`'a taşındı; 6稳定 controller `initState`'te seed,
  `addListener` ile row alanı günceller, `dispose`'da bırakır. ListView
  item'larına `ValueKey`. → her tuşta cursor sabit, çok satırda bağımsız.
- `_NumField`/`_MiniNum` controller-param versiyonuna geçti;
  `lib/shared/widgets/number_fields.dart` shared helper (barkod dialogu da
  import eder). `barcode_scan_dialog.dart` sonuç adımı aynı desenle fix.
- Tanıma satırı `Card` içine alındı; 4 per-100g makro tek satırda kompakt.
- `app_theme.dart`: `cardTheme`/`appBarTheme`/`navigationBarTheme`/
  `inputDecorationTheme(filled)` M3 cilası; `AppColors.macro*` korundu.

### Faz 2 — /add hub + meal preselection + SegmentedButton ✓
- `meal_selector.dart` (yeni): `MealSegmentedButton` (SegmentedButton<
  MealType>, 4 segment emoji + i18n etiket).
- `MealType.defaultForNow()`: saat eşikli varsayılan öğün
  (`<11` breakfast, `<16` lunch, `<21` dinner, else snack).
- FAB + öğün kartı "+" → `AddWithAiDialog.show(defaultMealType:)` doğrudan
  (meal pre-set); `/add` builder `state.extra is MealType ?` okur.
- `/add` hub: `_AiCard` tek tıkla AI dialogu (iç içe Card/Buton kaldırıldı).
- 4 dialog DropdownButtonFormField → `MealSegmentedButton`.

### Faz 3 — Tıklanabilir ring/makro + per-macro analitik + öğün satırı ✓
- `macro_focus.dart` (yeni): `MacroFocus` enum (protein/carbs/fat) +
  `fromName`, `labelKey`, `color`, `percentOfTarget` (test edilebilir çekirdek).
- `app_router.dart`: `/analytics?macro=` → `MacroFocus.fromName` →
  `AnalyticsPage(focusedMacro:)`. `analytics_page.dart` StatefulWidget'a
  çevrildi; `_FocusedMacroChartCard` (fl_chart LineChart, `dailyStats`
  P/C/F → hedef yüzdesi, 100% dashed `success` çizgisi, `%X (Yg)` tooltip,
  `Scrollable.ensureVisible` ile scroll-vurgu).
- `calorie_ring.dart` + `macro_cards.dart` tıklanabilir (InkWell + Semantics);
  dashboard → `/analytics` / `/analytics?macro=`. `macro_cards`
  `Colors.redAccent/amber/lightBlue` → `AppColors.macro*`.
- `meal_section.dart`: `Dismissible.confirmDismiss` false döner (kart yerinde
  kalır) + "Geri Al" SnackBar (`restoreMealEntry`); ListTile trailing
  edit + delete IconButtons; onTap düzenle dialogu.
- `diary_repository.dart`: `restoreMealEntry(id)` (`deleted_at=null` +
  `updated_at`), `updateMealEntry` `updated_at` damgalı.
- `edit_meal_entry_dialog.dart` (yeni): `MealEntry` calculated_* toplamından
  per-100g geri hesaplar; 6稳定 controller (odak kaybı yok).
- i18n: `common.undo`, `dashboard.edit/delete`, `analytics.charts.macroFocus.title`,
  `analytics.goToCalories` (en + tr; diğer 10 dil en fallback).

### Doğrulama
- `flutter analyze` → 0 sorun
- `flutter test` → 117/117 (101 + 16 yeni: `macro_focus_test.dart`
  10, `meal_type_test.dart` 6 — `MacroFocus.fromName/labelKey/color/
  percentOfTarget`, `MealType.defaultMealForHour` eşikleri)
- `flutter build apk --debug` → ✓

### Kalan / kullanıcı tarafından yapılacak
- Canlı DB uçtan uça test (DB deaktif): ring tıkla → analitik; makro kartı
  tıkla → per-macro grafik; öğün satırı kaydır → Geri Al; edit ikonu →
  dialog kaydet; AI tanıma gram edit → cursor sabit.
- Tema cilası light tema okunaklı; manuel görsel onay.
