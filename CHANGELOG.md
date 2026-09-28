# Changelog

All notable changes to CaloriX are documented in this file.

---

## [Unreleased] - 2026-09-28

Denetim döngüsü Tur 3 (`plans/analiz-26-09-27/RAPOR-A6r3-quality-tur3-2026-09-28.md`).
Sürüm **yükseltilmedi**: aşağıdakiler zaten yayımlanmış 1.3.0+4'ün üzerine
gelen düzeltmeler; `pubspec.yaml`'da hâlâ `1.3.0+4`.

### Fixed — React PWA (`src/**`)
- **Sunucu bildirim tercihi kaydedilemiyordu (P1).**
  `useNotifications` `interval_hours: 0` yazıyordu; DB CHECK'i
  `notification_preferences_hours_range` (`interval_hours BETWEEN 1 AND 24`)
  bu değeri reddediyordu → web PWA'da kullanıcı **hiçbir** sunucu bildirim
  tercihini kaydedemiyordu. Varsayılanlar Flutter'ın `toRow` mantığıyla
  birebir hizalandı (tek seferlik tiplerde `1`, `goal_achieved` için `24`)
  ve **her** yazma yeni `src/lib/notificationPreferences.ts` normalize
  katmanından geçiyor. `start > end` de 23'e çekiliyor (sessizce hiç
  gönderilmeme sorunu).
- **Bildirim master anahtarı ölüydü (P1).**
  `send-notification:423` `preference?.push_enabled ??
  profile.push_notifications_enabled` okuyor ve `??` **yalnız `NULL`** üstüne
  düştüğü için, `notification_preferences`'a satır yazıldığı anda profil
  master anahtarı hiç okunmuyordu. Flutter'ın `applyMasterSwitches` (AND)
  davranışı web'e de uygulandı: master `false` iken hiçbir tip satırı
  `true` yazamaz. Ayrıca `SettingsPage.saveNotifications` **ölü koddu**
  (hiçbir yerden çağrılmıyordu, profil master anahtarları hiç yazılmıyordu
  ve "her tip için satır yaz" davranışı hiç tetiklenmiyordu); artık diyalogdaki
  "Kaydet" düğmesi beş tipin de satırını yazar.
- **Hesap silme giriş noktası yoktu (P3, KVKK / Google Play).**
  Web PWA'da kullanıcı hesabını **elle** silmek zorundaydı. Ayarlar →
  Hesap bölümüne giriş noktası, iki aşamalı onay ve parola doğrulamalı
  diyalog eklendi; tam silme sonrası oturum düşürülüp `/auth`'a yönlendirilir.
  Kısmi silme (`retryRecommended`) "başarı" gibi gösterilmez.


- **`activity_level` 400 hatası (P1).** `SettingsPage.recalculateMacros`
  UI anahtarını (`veryActive`) doğrudan edge function'a gönderiyordu;
  `calculate-macros` yalnızca DB CHECK kısıtıyla birebir aynı snake_case
  değerleri kabul ediyor. "Çok Aktif" seçili profilde **yeniden hesapla**
  her zaman hata veriyordu. `Index.tsx`'te de aynı hata vardı ve orada
  profil DB'den okunduğu için `activityLevelFromDb` →
  `activityLevelToDb` çift dönüşümü gerekiyordu.
- **Vergi dilimi kayması (P1).** `useAnalyticsData` kilo eğrisi
  etiketlerinde `parseISO(entry_date)` kullanılıyordu; `entry_date` bir
  `DATE` kolonu olduğu için `parseISO` UTC gece yarısı üretiyor ve
  `format()` yerel saatte yazdırıyordu — UTC+03:00'te 1 Mart gösterilirken
  28 Şubat'a kayıyordu. Artık takvim günü doğrudan ayrıştırılıyor.
- **`RangeError` (P1).** `eachDayOfInterval` ters aralıkta fırlatıyordu;
  `period` geçersiz olduğunda tüm analitik ekranı patlıyordu. Aralık
  bugüne kırpılıyor ve `start > end` durumu boş seriye düşüyor.
- **Ölçü kabulü (P1).** `AddMealDialog` / `EditMealDialog` /
  `AddWeightDialog` / `CustomWaterDialog` `parseFloat`/`parseInt`
  sonucunu doğrulamadan kaydediyordu: `NaN`/negatif miktar `amount_g_ml = 0`
  olarak yazılıp günlük toplamları sessizce bozuyordu. Su için üst sınır
  da yoktu (tek kayıtla 1.000.000 ml mümkündü).
- **Eksik `user_id` filtresi (P1).** `useDailyData.updateMealEntry` ve
  `deleteMealEntry` yalnızca `id` ile güncelliyordu; RLS'e ek savunma
  katmanı eklendi (`useNotifications.markAsRead` zaten yapıyordu).
- **BMI bölme hatası (P1).** `calculateBMI(70, 0)` `Infinity` dönüyor ve
  `getBMICategory` bunu "obez" olarak sınıflıyordu — fiziksel olarak imkânsız
  bir kayıt yanlış sağlık uyarısı üretiyordu. `calculateProgress` da negatif
  hedefte `-%400` dönüyordu.
- **`DEFAULT_GOALS.fat` 65 → 67 (P1).** Flutter tarafı A3'ün `be8158a`
  commit'iyle 67'ye düzeltildi (`2000 × 0.30 ÷ 9 = 67`); React tarafı 65'te
  kaldı. Profil kaydı olmayan kullanıcı PWA'da yanlış yağ hedefi görüyordu.
- **Oturum yarışı (P1).** `AuthContext` içindeki `getSession()` sözü,
  süresi dolmuş oturum için token yenilerken yayınlanan
  `TOKEN_REFRESHED` sonucunu **eziyordu**. Ayrıca `getSession` reddederse
  `loading` hiç düşmüyor ve uygulama sonsuza dek splash ekranında kalıyordu.
- **Profil yarışı (P1).** `ProfileContext` kullanıcı değiştiğinde eski
  profil bir kare kalıyor ve eski istek geç çözülürse yeni veriyi eziyordu.
- **Sessiz `signOut` hatası (P1).** `signOut` hatası yutuluyordu; başarısız
  olsa bile kullanıcı çıkış yaptığını sanıyordu. `signingOut` bayrağı eklendi.
- **Hata mesajında veri sızıntısı (P1).** `useDataExport.importData`
  `error.message` metnini kullanıcıya gösteriyordu: `JSON.parse` hatası
  dosya yolunu sızdırıyor, Supabase hataları tablo/kısıt adlarını içeriyordu.
- **Yaş hesabı (P2).** `Index.tsx` yaşı `365.25` günlük ortalama ile
  hesaplıyordu (duvar saati farkına duyarlı, 29 Şubat doğumlularda yılda bir
  gün kaydırıyor). Diğer iki ekran zaten `calculateAge` kullanıyordu; üçü
  de aynı takvim yılı hesabına bağlandı.
- **Tarih belirsizliği (P2).** `ChatPage` `currentDate`'i
  `toLocaleDateString("en-CA")` ile üretiyordu; bu her tarayıcıda
  `yyyy-mm-dd` garantisi vermiyor ve sunucu prompt'a düz metin koyduğu için
  AI'a belirsiz gün/ay sırası bırakıyordu.

### Added
- `src/integrations/supabase/functions.ts`: `functions.invoke` için zaman
  aşımı sarmalayıcısı (60 sn). Önceden `ai-chat` (AI + 3 tablo) veya
  `calculate-macros` yavaşladığında buton "bekliyor" durumunda kalıyor ve
  kullanıcı işlemi iptal edemiyordu. Altı çağrı noktası bu sarmalayıcıya
  taşındı. **JWT davranışı değiştirilmedi** — bkz. sarmalayıcının başındaki
  kanıt zinciri.
- `.github/workflows/*.yml`: tüm eylemler **40 haneli commit SHA'sına**
  pinlendi (`@v4` etiketi hareketli bir referanstır; `# v4.2.2` yorumu
  Dependabot güncellemeleri için korundu) ve her işe `timeout-minutes`
  eklendi (flutter check 35, build 45, react check 20). Ağ takılmasında CI
  6 saatlik runner varsayılanını beklemek yerine kesiliyor.
- `tool/check_i18n.cjs`: dört yeni kontrol —
  **placeholder ayracı** (boşluk ayıran dillerde `{min}до` yapışıklığı),
  **Dart interpolasyonu sızıntısı** (`${...}` çeviri içinde),
  **RTL sızıntısı** (Arapçada kalan İngilizce cümle / ASCII satır sonu
  noktalaması) ve **tarih-sayı biçimi** (`DateFormat`/`NumberFormat`
  locale'siz ya da sabit dile bağlı).
- `tool/check_versions.cjs` kapsamı genişletildi: `DEFAULT_GOALS`
  (web) ↔ `AppConstants` (Flutter), makro oranları, atwater Sabitleri,
  aktivite çarpanları, hedef modifikatörleri, minimum kalori tabanı,
  `APP_VERSION` ↔ `package.json`, `local.properties` sürüm bayatlığı ve
  README yayın talimatı ↔ `pubspec`. Aynı sınıf sapmalar (sabitler ve
  hesap oranları arasında) artık **hiçbir araçla** yakalanmıyordu.
- `flutter_app/lib/core/utils/calculations.dart`: makro oranları ve atwater
  değerleri **tek kaynaktan** (`proteinRatio` vb. sabitler) okunuyor; iki
  istemci karşılaştırması bu sabitlere bakıyor.

### Docs
- `README.md` / `README_EN.md`: "Bu depoda iki istemci" tablosuna sürümler
  eklendi (Flutter 1.3.0 / React 1.1.0), özellik listelerinin hangi istemciye
  ait olduğu belirtildi, `INTERNAL_FUNCTION_TOKEN` / `VAPID_SUBJECT` gibi
  **edge function secret'ları** kurulum tablosuna eklendi (bunlar `.env`'e
  değil Supabase projesine tanımlanır).
- `.env.example`: sunucu tarafı secret'lar (`INTERNAL_FUNCTION_TOKEN`,
  `VAPID_SUBJECT`) gerekçeleriyle birlikte belgelendi.

### i18n
- `fr.json`'da 4 eksik anahtar (`updates.unverified`, `integrityFailed`,
  `tooLarge`, `downloadFailed`) gerçek Fransızca çevirilerle eklendi. Bu
  anahtarlar A3'ün `apk_integrity.dart`/`apk_downloader.dart` işinden
  gelmişti; 11 dilde vardı, Fransızca'da yoktu.
- `ar.json` `dashboard.remaining`: `"kcal متبقية"` (İngilizce "remaining kcal"
  kalıbı harf harfine bırakılmış) → `"متبقٍّ (kcal)"`.

---

## [Unreleased — Tur 6-13] - 2026-09-28

Denetim döngüsünün **Tur 6-13** düzeltmeleri. Tur 3-5 için yukarıdaki
`[Unreleased]` bölümüne bakın. Sürüm **yükseltilmedi** (`pubspec.yaml`'da
hâlâ `1.3.0+4`); aşağıdakiler 1.3.0+4 üzerine gelen düzeltmelerdir.

### ⭐ Güvenlik
- **Widget tazeleme hiç çalışmıyordu (P0, kendi kodumuz).**
  `HomeWidget.updateWidget(name: name, androidName: name)` çağrılıyordu;
  `home_widget` 0.10.0 sınıfı `qualifiedAndroidName ?: "$packageName.$className"`
  ile çözüyor → `applicationId` = `com.calorix.app` olduğu için
  `com.calorix.app.DailyWidgetProvider` arıyor → `ClassNotFoundException`.
  **Öğün ekleme, ayar değişimi ve "Güncelle" hiçbiri widget'a ulaşmıyordu.**
  Derleme ve testler yeşildi. Düzeltme: yalnız `androidName`.
- **Push gövdesi gerçekten şifrelenmiyordu (P1).** RFC 8188 `aes128gcm`
  şifreleme eklendi; VAPID imzası bozulmadan. Testler modülün
  `ecdh_secret`/`PRK`/`CEK`/`NONCE` değerlerini **RFC 8291 Ek A'nın
  yayımlanmış değerleriyle** karşılaştırıyor.
- **Push `MAX_PLAINTEXT_BYTES` off-by-one (P1).** Başlık 21 + GCM 16 +
  delimiter 1 çıkarılmamıştı: 3993-4058 baytlık pencerede uzun HTML'li
  `weekly_summary` **push'u sessizce kaybediyordu** (e-posta + DB kaydı
  yazıldığı için görünmüyordu). `rs=32` + 40 bayt da RFC §4 ihlaliydi.
- **RLS UPDATE politikalarında `WITH CHECK` yazıldı (15 tablo).** Düzeltmenin
  kendisi P0'ı **yanlış buldu**: Postgres'te `WITH CHECK` yoksa `USING`
  fallback olarak yeniden değerlendirilir, yani açık zaten kapalıydı.
  Açıkça yazıldı (savunma derinliği), `tests/rls_policies.sql` ile doğrulandı.
- **`chat_threads`/`chat_messages` politikaları `TO public` idi** →
  `TO authenticated`. 5 `SECURITY DEFINER` fonksiyonda `search_path=''`.
- **`full_setup.sql` yeni kurulumları zayıf korumalı bırakıyordu (P1).**
  Migration yoluyla **parite**ye getirildi (FK / CHECK / kolon / index /
  politika `diff`'i boş) ve **idempotent** yapıldı (2. ve 3. çalıştırmada
  0 gerçek hata).
- **13 veri bütünlüğü `CHECK` kısıtı** eklendi (negatif kalori, negatif
  miktar, geçersiz saat aralığı vb.). Canlı veri doğrulanamadığı için
  ihlalde `RAISE EXCEPTION` veren, **satır değiştirmeyen** tasarım seçildi.
- **Silme sonrası veri sızıntısı (P1).** `foods.created_by` FK'si
  `ON DELETE SET NULL` idi → hesap silinince kullanıcının eklediği gıdalar
  **kalıyordu** (KVKK "silme hakkı"). `ON DELETE CASCADE` yapıldı;
  topluluk verisi (`created_by IS NULL`) korunuyor. `tests/foods_cascade.sql`
  4 davranışı kanıtlıyor.
- **Hesap silme 200 "başarı" dönüyordu kısmi silmede (P1).** Tablo silme
  hatası `continue` ile yutuluyordu → KVKK gereği eksik silme başarı gibi
  görünüyordu. `{deleted, failed}` + `retryRecommended` eklendi.
- **Rate limit kalıcı tablo + atomik RPC'ye taşındı.** 10 paralel istek
  testinde tam olarak 5 izin. `delete-account` limiti 5/saat → **2/saat**
  (parola doğrulandığı için 5 gereksizdi; işlem yıkıcı ve geri alınamaz).
- **4 edge function'da `ValidationError` mesajı istemciye sızıyordu.**
- **VAPID imzası hiç üretilmiyordu** → web push bildirimleri fiilen hiç
  gitmiyordu.

### ⭐ Çalışmayan özellikler
- **`recognize-food*` derlenmiyordu.** Edge function'daki bir tip/sözdizimi
  hatası yüzünden tanıma hiç çalışmıyordu.
- **VAPID imzası yoktu** (yukarıda) → web push ölüydü.
- **Widget'ın native tarafı hiç yazılmamıştı.** `home_widget` +
  `workmanager` bağımlılıkları vardı, `lib/core/widgets/**` (~700 satır)
  yalnız testlerden çağrılıyordu. Karar: **widget gerçekten uygulandı**
  (Kotlin `DailyWidgetProvider` + `WidgetData.kt`), tazeleme köprüsü düzeltildi.
  `workmanager` (0 referans) kaldırıldı.
- **`publishWeekly` ve `shouldSendNudge` görünür ama işlevsizdi.**
  Haftalık widget hep boş; ayar UI'da görünür ama bildirim hiç gitmiyor.
  İzole edilip işaretlendi (ürün kararı bekliyor).
- **`cron.schedule` hiçbir yerde yoktu (P0, Tur 1'den beri).**
  `check-reminders` elle tetikleniyor, **sunucu hatırlatıcıları hiç gitmiyordu.**
  `pg_cron` job'ı eklendi (`7-59 * * * *`), Vault'tan okunan
  `x-calorix-internal-token` ile yetkilendiriliyor.

### ⭐ Veri bozulması
- **Yedek → geri yüklemede favoriler, son kullanılanlar ve bildirim
  tercihleri kayboluyordu (P1).** `importData` bu üç tabloyu **hiç
  okumuyordu**. Üçü de içe aktarıma eklendi (`food_id` **ad** üzerinden;
  eşleşmeyen kayıt atla+raporla, ölümcül değil).
- **Kısmi import imkânsız hale getirildi (P0/P1).** Üç faz: önce doğrula
  (ağ yok) → varlık kontrolü → telafili yazma. Tek ölümcül ihlalde hiçbir
  istek atılmaz; yazma hatasında o turda yazanlar `id` ile silinir.
- **Eski "güvenli" dönüştürmeler aslında ölümcüldü (P1).** Geçersiz
  `amount_ml`/`weight_kg` `0`'a yazılıyordu → DB CHECK 400 → **tüm import
  öğünler yazıldıktan sonra** düşüyordu. Besin satırında sayı olmayan
  zorunlu alanın `0`'a çevrilmesi = sessiz yanlış besin değeri.
- **`food_nutrition.nova_score` geçersizde sayaç değeri alıyordu (P1).**
  `1`/`2`/`3` yazılıyordu; "1 = işlenmemiş" olurdu. 42 test kaçırmıştı.
- **Su kaydı iki kez ekleniyordu (P1).** Dedup dizeden epoch
  mikrosaniyeye çevrildi (`+00:00` ↔ `Z` aynı kaydı iki kez ekliyordu).
- **Topluluk gıdaları "v1.2.0'dan beri Bilinmeyen" görünüyordu (P1).**
  `fetchDaily` `foods(name)` embed'ini almıyordu. `foods` INSERT yolu ve
  ölçüsüz öğün düzenlemesi eklendi.
- **Silinen gıdanın öğünü "Bilinmeyen" oluyordu (P1).**
- **`exportData` 6 hassas tabloyu sorgulamıyordu.**
- **2000 istek ölçüldü ve çözüldü: 4506 → 37 istek** (POST 4480 → 9).
  `importBatchSize = 500` (Postgres parametre tavanı 65535'e karşı 7000
  = %11).
- **Kayıp güncelleme (race) kapatıldı.** `updateMealEntry(expectedUpdatedAt:)`
  + `MealEntryConflictError`; başka cihazda güncellenmişse kullanıcı bilgilendirilir.

### ⭐ Hesap hataları
- **`bmi(70, -180) = 24.2` (P1).** Kare pozitif olduğu için **imkânsız kayıt
  geçerli** görünüyordu.
- **`activity_level` enum uyuşmazlığı (P1).** Flutter `ActivityLevel.name` =
  `"veryActive"` (camelCase), DB CHECK'i ve edge function `very_active`
  (snake_case) bekliyordu. "Çok Aktif" seçilince profil yazımı
  **başarısız** oluyor, hedefler kaydedilmiyordu. Ölçülen etki: TDEE
  **%18,4 eksik** (30y/erkek/175cm/80kg → 2759 yerine **3382 kcal/gün**).
- **`Gender.other` iki istemcide farklı hesaplıyordu (P1).** Web `other`/`null`'ı
  **kadın** formülüne düşürüyordu (BMR 1583↔1749, TDEE 2454↔2711 → günde
  257 kcal fark), profil kalıcı yazılıyordu. Karar: **erkek (`+5`)**.
- **`progress` koruması 3 katmanı vardı ama HİÇ çağrılmıyordu.**
- **`waterTargetMl` NaN'da `UnsupportedError`** → ekran düşüyordu.
- **`Calculations.bmi` boy 0'da `Infinity.round()` → `UnsupportedError`.**
- **Sapma (ölçüldü):** `web` `getBMICategory` BMI 0'ı "obez" sayıyordu.

### ⭐ Sessiz kayıplar
- **Bildirimler sessizce UTC'de planlanıyordu (P1).**
  `notification_service.dart:50-57` `FlutterTimezone` hatasını `catch (_)`
  ile yutuyordu; `tz.local` `initializeTimeZones()` sonrası UTC. TR'de
  hatırlatıcılar **3 saat kaymış** çalışıyordu.
- **Hatırlatıcılar ilk açılışta hiç planlanmıyordu (P1).**
  `reschedule()` `!_initialized`'da isteği düşürüyor, kalıcı ayarları
  sessizce kaybediyordu.
- **Tam alarm izni kapatılınca hatırlatıcılar sessizce hiç gelmiyordu (P1).**
  `_exactAllowed` yalnız init'te bir kez okunuyordu.
- **Bir öğünde `zonedSchedule` patlayınca diğerleri de planlanmıyordu.**
  `NotificationScheduleOutcome` eklendi.
- **Bildirim izni reddi hiçbir yerde görünmüyordu.**
- **Gece saat aralığı (21→09) sessizce yazılıyordu (P1).** Flutter'da
  `end < start` **seçilemiyordu**, sunucu da desteklemiyordu → kullanıcı
  seçimi sessizce değişiyordu.
- **`start_hour > end_hour` sunucuda sessizce hiç göndermiyordu (P1).**
  `index.ts:356` koşulu hiçbir saatte sağlanmaz; DB CHECK'i iki saati de
  0..23 olduğu için izin veriyor.
- **Master anahtar gölgelenmesi (P1).** `preference?.push_enabled ??
  profile.push_notifications_enabled` — `??` yalnız NULL'a düştüğü için,
  `notification_preferences`'a satır yazılınca profil master anahtarı
  **hiç okunmuyordu**. `applyMasterSwitches` (AND) ile kapatıldı
  (Flutter **ve** web).
- **Tartılma sıklığı aralık denetimi yoktu (P1).** `0` yazılırsa CHECK
  reddediyor → profil + sunucu tercihleri **birlikte** düşüyordu.
- **Yedek içe aktarımında sessiz `catch (_)`** iki farklı hata sınıfını
  (doğrulama / yazma) birbirine karıştırıyordu.
- **`try/catch` gerçekten hiç çalışmıyordu (web).** "eklendi" toast'u hiçbir
  kayıt yazılmadan; `addMealEntry`'de miktar sınırı yoktu; 3 yarış koşulu
  (kullanıcı B'nin ekranında A'nın verisi); "en son kilo" belirsiz sıralama.
- **UTC gün kaçıklığı: 4 gerçik desen / 8 çağrı noktası (web).**
  `toISOString().split("T")[0]` (TR'de onboarding `max` = **yarın**),
  `new Date("2000-01-15")` (**yaş 1 gün önce** ×3), `Math.floor(/864e5)`
  (uyarı **1 gün geç**).
- **`SentryFlutter.init` fırlatırsa `runApp` hiç çağrılmıyordu** → beyaz ekran.
- **Zorunlu güncelleme ekranı `isApkUrlSafe` süzgecini kullanmıyordu** →
  açık yönlendirme yüzeyi (13 test `launchUrl` **çağrılmadığını** kanıtlıyor).

### ⭐ Yeni özellikler
- **Hesap silme arayüzü (KVKK / Google Play giriş noktası).**
  Edge function hazırdı ama kullanıcıya **hiçbir giriş noktası yoktu** —
  ölü bir özellik. İki aşamalı onay + parola doğrulamalı diyalog, iki
  istemcide de. Silme sonrası oturum düşürülür.
- **Favorilere ekleme/çıkarma arayüzü (ürün kararı 1-A).**
  `favorite_foods` tablosu şemada vardı ama **hiçbir istemci yazmıyordu**;
  favoriler son 200 öğünden hesaplıyordu. Favori yıldız arayüzü eklendi.
- **Sunucu bildirim tercihleri arayüzü (ürün kararı 2-A).**
  `notification_preferences` tablosu vardı ama **kimse yazmıyordu**; sunucu
  satır yoksa `water`/`daily_log`/`weekly_summary` bildirimlerini **sessizce
  kapalı** tutuyordu. Arayüz eklendi, beş tipin satırı yazılıyor.
- **Gıda silme arayüzü** (yemek tarifindeki beslenme bilgisi düzenleme).
- **Tartılma sıklığı** tercih tipi.
- **Ana ekran widget'ları gerçekten uygulandı** (yukarıda).
- **Gece saat aralığı (21→09)** Flutter'da **ve** sunucuda açıldı.

### i18n
- **Tur 13 (A6r13) — çeviri *değeri* kapıları.** `check_i18n.cjs`'e 3 yeni
  hata kapısı: **çevrilmemiş kopya**, **satır sonu sayısı tutarlılığı**,
  **ayraç (parantez/braçet) dengesi**; artı "aynı metnin bir kopyası
  çevrilmiş, diğeri çevrilmemişse" kapısı. Bulunan **gerçek** hatalar:
  `it`/`ru` `notificationTypes.email` çevrilmemişti, `ja`/`ko`
  `about.footer.copyright` İngilizce kalmıştı.
  ⭐ "Kırpılmış cümle" kapısı **4 tasarım denendi ve dördü de elendi**
  (302 yanlış pozitif) — gerekçe kodda belgeli, kapı yazılmadı.
- **Orphan ratchet 63 → 60.** 3 kanıtlanmış ölü anahtar 12 dilden silindi
  (`settings.notifications.server.goalAchieved` kodda **açıkça** dışlanmıştı,
  `serverScope` `channelNote` ile aynı cümleyi söylüyordu,
  `dialogs.fiberG` hiçbir ekranda gösterilmiyordu). 525 → 522 anahtar.
- **Ölü anahtar kazandı:** `settings.notifications.server.rangeNoNight`
  (gece aralığı açıldığında artık kullanılmıyordu) 12 dilden **silindi**.

### CI
- ⭐ **`supabase/tests/*.sql` artık CI'da** (A1r5/A1r8/A1r10'un üç kez
  raporladığı boşluk). "supabase start gerekiyor" gerekçesi **ölçümle
  çürütüldü**: ihtiyaç olan yüzey iki şema (`auth.*`, `storage.*`) + üç rol.
  `tests/auth_shim.sql` + `tests/storage_shim.sql` + `tool/run_sql_tests.sh`
  ile stock `postgres:16` üzerinde 19 migration, `full_setup.sql` (3×
  idempotans) ve 5 SQL regresyon testi çalışıyor.
  Negatif ölçüm: `foods.created_by` FK'si `CASCADE` → `SET NULL` yapıldığında
  **3 test kırmızıya döndü** ve hatayı adıyla bildirdi.
- **P0 — `paths:` kapsam denetimi.** 3 workflow'un **kendi girdileri**
  `paths` listeleriyle karşılaştırıldı:
  - `.env.example` **hiçbir** workflow'te tetiklemiyordu ama `flutter.yml`
    `cp .env.example .env` ile asset paketlemesi yapıyor → bozulunca **her
    iki** Flutter işi kırılıyor, PR'da görünmüyordu.
  - `README.md` / `README_EN.md` `check_versions.cjs` tarafından okunuyor
    ama `flutter.yml`'de yoktu.
  - `public/locales/**` `react.yml`'de vardı, `flutter.yml`'de yoktu.
  - `tool/run_sql_tests.sh` `supabase.yml`'e eklendi.
- **React CI işi** (Node 20, `cache: npm`, `npm ci`, tsc + lint + build).
- **Android derleme kapısı** `flutter build apk --debug` (~56 sn soğuk,
  ~33 sn warm). Ölçüm: `./gradlew :app:compileDebugKotlin` 62 sn **ve
  BAŞARISIZ** → APK build seçildi.
- **Tüm eylemler 40 haneli commit SHA'sına pinlendi**; `permissions: contents: read`,
  her işe `timeout-minutes`; `deno check`/`deno test` `--frozen=true`.
- **`deno.lock` yolu düzeltildi** (`supabase/deno.lock` takipte; kökteki
  `deno.lock` hiçbir `deno` komutu tarafından okunmuyordu).

### Tests
- Flutter test paketi **143 → 1156** test. Supabase edge testleri **19 → 124**.
- **Widget sözleşme testi** (`widget_key_contract_test.dart`): Kotlin
  `WidgetData.kt` dosyasını metin olarak okuyup 40 sabiti **iki yönde**
  karşılaştırıyor — Dart↔Kotlin ayrışması build'de yakalanmıyordu.
- **Yedek round-trip testi** (19 test): tam veri seti → export → import →
  ikinci export → alan alan karşılaştırma. Sahte DB `RETURNING id` +
  NOT NULL/FK/UNIQUE/CHECK + `timestamptz` biçimini taklit ediyor.
- **Kısmi import testleri** (42) ve **telafi sırası** kilidi.
- **SQL regresyon testleri**: RLS 49/49 · şema sözleşmesi 10/10 ·
  CHECK 58 deneme · `foods_cascade` 4/4 · `account_deletion` 6/6.
- **DST testleri hiçbir şey ölçmüyordu** (test ortamında `tz.local` = UTC) →
  yanlış güven üretiyordu; `now.location` ile saf fonksiyon sözleşmesine çevrildi.
- **13 turda 7 kez "yeşil test ≠ etkin test"** yakalandı. Bu turun
  bulguları: 4 tasarım denemesi **elendi** (302 yanlış pozitif), SQL
  testlerinde **izolasyon** hatası (bir testin bıraktığı tablo diğerini
  kırmızıya düşürüyordu), ve ⭐ **koşu sırası hatası**: `full_setup.sql`
  politikaları `DROP POLICY` + `CREATE POLICY` ile **yeniden yazdığı** için
  harness'te şablon üzerinde 3× çalıştırıldığında migration yolundaki
  **bir politika regresyonu sessizce onarılıyordu** — BOLA enjeksiyonu
  (`USING (true)`) iki denemede **yeşil** kaldı, elle koşulunca
  "48 test / 1 başarısız" verdi. İdempotans doğrulaması ayrı veritabanına
  taşındı; sonra aynı enjeksiyon kırmızı verdi. **Hata testte değil, testi
  çalıştıran koddaydı.**

### Fixed — Yedek içe/dışa aktarma (React PWA, `src/lib/import/**`)
Web tarafı, Flutter'da Tur 4'te düzeltilen **aynı** yedek hatalarını
taşıyordu. Bu turda akış baştan yazıldı: `src/lib/import/backupImport.ts`
(saf katman: doğrulama + plan) ve `src/lib/import/backupRestore.ts`
(ağ katmanı: varlık kontrolü + yazma + telafi).

- **Kısmi import (P1).** `importData` satır satır yazıyordu; bir CHECK
  ihlalinde `foods` + besin + o ana kadarki tüm öğünler **yazılmış** kalıyor,
  kullanıcı "hata" görüyor, hangi kayıtların geldiğini öğrenemiyordu.
  Artık üç faz: **ön-uçu doğrulama (ağ yok) → varlık kontrolü (yalnız GET) →
  toplu + telafili yazma**. Tek bir ölümcül ihlalde **hiçbir istek
  atılmaz**; yazma hatasında o turda yazılanlar `id` ile fiziksel olarak
  silinir ve `counts` **her zaman** dolu döner.
- **Sessiz yanlış besin değeri (P1).** `Number(nutrition.kcal) || 0`
  ifadesi, sayı olmayan zorunlu bir alanı `0`'a çevirip **yanlış besin
  değeri** kaydediyordu. Artık ölümcül ihlal: "hiçbir kayıt eklenmedi".
- **`amount_ml`/`weight_kg` geçersizde `0` (P1).** DB
  `water_entries_amount_positive` / `weight_entries_weight_range` CHECK'leri
  400 döndürüyor ve import **tüm öğünler yazıldıktan sonra** ölüyordu.
  Artık ön-uçu doğrulamada ölümcül; küsüratlı `amount_ml` yuvarlanıp
  `coerced` ile bildiriliyor.
- **Ölümcül olmayan enum düzeltmeleri görünür.** Geçersiz `meal_type`
  (`'brunch'`) DB CHECK'i patlatıp **tüm import'u** düşürüyordu; artık
  `'snack'`'a çekiliyor ve `coerced` sayacıyla "N satırda brunch → snack
  yapıldı" bilgisi kullanıcıya gösteriliyor.
- **Yumuşak silinen kayıtlar canlanmıyor (P1).** Yedekte `deleted_at` dolu
  satırlar **dışa aktarılmaz**; elle düzenlenmiş bir yedekte varsa içe
  aktarımda yok sayılır. Önceden kullanıcının sildiği öğün yeni `id` ile
  geri geliyordu.
- **Su dedup'ı artık epoch üzerinden.** `+00:00` ↔ `Z` aynı kayıt sayılıyor
  (dize karşılaştırması aynı su kaydını iki kez ekliyordu). `entry_time`
  yoksa gün başlangıcı türetilir ve bu türetme **sayılır** (sessiz veri
  kaybı yok).
- **`favorite_foods`/`recent_foods` artık içe aktarılıyor (P1).** Dışa
  aktarılıyordu ama içe aktarılmıyordu → yedek→geri yüklemede favoriler
  kayboluyordu. `UNIQUE(user_id, food_id)` üzerinden `upsert`
  (`ignoreDuplicates`) ile yazılıyor; gıda eşlemesi **ad** üzerinden yapılıyor
  (yedekteki eski `id` başka kullanıcıya ait bir UUID'dir, `food_id` olarak
  yazılırsa FK ihlali olurdu).
- **Ölçek: 4506 → 37 istek (P1).** Satır satır yazım yerine 500'lük
  toplu `insert` (`PGRST102` anahtar kümesi sözleşmesi korunur) ve 100'lük
  dilimlenmiş `in` sorguları (2000 kayıtta tek `in` listesi ~78 KB → 414).
- **`created_at` yedeğin damgasıyla taşınıyor.** Toplu yazımda satır
  sırası `created_at`'i taşımadığı için tüm öğünler aynı `now()`'u alıyordu
  ve "ekleme sırası" koruması kayboluyordu. Gerçekçi olmayan damgalar
  (2000 öncesi, gelecek) yok sayılır.
- **Hata mesajı kullanıcıya ne olduğunu söylüyor.** Üç ayrı kol:
  biçim hatası / doğrulama hatası ("hiçbir kayıt eklenmedi") / yazma
  hatası ("N kayıt eklenmişti, geri alındı | geri alınamadı"). Sunucu
  hata metni (tablo/kolon/kısıt adı) yalnızca konsola gider.
- **Dışa aktarma hataları yutulmuyor.** 8 paralel sorgudan biri hata
  verirse kullanıcıya "Dışa Aktarma Eksik — şu bölümler okunamadı"
  uyarısı gösteriliyor; eskiden `|| []` ile boş liste dönüp eksiksiz bir
  yedekmiş gibi görünüyordu.

### Fixed — Bildirimler (`useNotifications`, P2)
- **Sessiz hata (A6r3 aktarımı).** `fetchPreferences` / `fetchNotifications` /
  `subscribeToPush` hata halinde `console.error` + `return` yapıyordu:
  ekranda **eski veri kalıyor**, kullanıcı hatayı göremiyor, push
  aboneliği sessizce başarısız oluyordu. Artık `error`
  (`operation` + görünür mesaj + konsola ayrıntı) ve `retry` durumu var;
  ayar ekranı ile bildirim paneli hata + "Tekrar Dene" gösteriyor.
- **VAPID anahtarı yoksa `console.warn` + `return`.** "Push Bildirimlerini
  Etkinleştir" düğmesi basılı kalıyor, hiçbir şey olmuyordu. Artık
  "Push bildirimleri için VAPID anahtarı tanımlı değil" görünür hatası.
- **İzin alındı ama abonelik kurulamadıysa `true` dönüyordu.**
  `requestPushPermission` artık gerçek sonucu döndürüyor.
- **Kullanıcı değişince eski tercihler ekranda kalıyordu.** Oturum
  kapandığında tercihler/bildirimler/okunmamış sayısı sıfırlanıyor.
- **Ayarlar kaydedilemeyince "başarılı" izlenimi.** `updatePreference`
  artık `boolean` döndürüyor ve hata halinde `error` durumunu güncelliyor.

### Fixed — CI ve denetleyiciler
- **Web testleri CI'da koşmuyordu.** Yeni `npm test` (Node'un yerleşik
  `node:test` + `--experimental-strip-types`, **yeni bağımlılık yok**)
  40 mantık testi çalıştırır; `react.yml`'a eklendi. `check_versions.cjs`
  de React CI'a girdi.
- **`deno.lock` takip ediliyor (P3 kararı).** Edge function'ların
  bağımlılıkları kısmen sürümsüz (`esm.sh/@supabase/supabase-js@2` →
  2.117.2'ye yönlendiriliyor, `deno.land/std@0.168.0` sabit). Repo kökündeki
  `deno.lock` bu çözümlemeyi **sabitler**. Ölçüldü: `deno.lock` yokken
  `esm.sh` en son sürüme (`@2.180.x`) yönlendiriyordu, varken **2.117.2**
  kullanılıyor — CI'nın sürüm sürgüsü görünmez hâle geldi ve
  `setup-deno`'nun `cache: true` anahtarı (`**/deno.lock`) ilk çalışmadan
  itibaren anlamlı.
- **`supabase/deno.json` eklendi.** `nodeModulesDir: "none"` + `lock`
  yönlendirmesi: kökteki `deno.lock` içine React'ın **70 npm
  bağımlılığı** karışıyordu (web paketinin toplamı 8382 → edge için 3285
  bayt). `deno` çalışma dizini `supabase/` olduğu için lock artık yalnız
  edge grafiğini içeriyor.
- **`flutter.yml` / `supabase.yml` / `react.yml` `push` tetiklemesi tüm
  branch'lere açıldı.** Önceden `[main, "feature/**"]` idi: bir `fix/...`
  branch'ine yapılan push denetim çalıştırmıyordu, kırık kod PR açılana
  kadar birikiyordu. `paths` filtresi korunuyor (konfigürasyon değişikliği
  tetiklemez), `concurrency` art arda push'ları iptal ediyor.
- **`react.yml` `tool/**` + `CHANGELOG.md` yollarını izliyor** —
  `check_versions.cjs` bu dosyaları okuyor.

### Docs
- **README.md / README_EN.md**: `VITE_VAPID_PUBLIC_KEY` (istemci tarafı,
  edge function değil) kurulum tablosuna eklendi ve "push açık ama bildirim
  gelmiyor" durumunun artık görünür hata verdiği belirtildi.
- **README.md / README_EN.md — güvenlik notu:** React PWA oturum token'ını
  `localStorage`'da tutuyor (`storage: localStorage`). CSR mimarisinde
  kaçınılmaz olduğu, XSS etkisi, RLS/JWT azaltıcıları ve SSR/BFF yol
  haritası belgelendi. Flutter tarafı token'ı Keychain/Keystore'ta tutar.
- **`.env.example`**: `VITE_VAPID_PUBLIC_KEY` gerekçesiyle eklendi
  (tanımlanmazsa abonelik oluşmuyor, sessiz hata → artık görünür).
- **`flutter_app/android/.../values/strings.xml`**: 5 widget etiketi için
  `values-<lang>/` çeviri dosyaları **kasıtlı olarak eklenmedi**. Gerekçe
  dosyanın başına yazıldı: (a) yalnız launcher etiketleri ve
  `contentDescription` referansı, (b) uygulama metinleri `str.*` anahtarlarıyla
  Dart tarafından geliyor, (c) çevrilebilir widget metni
  `weekly.labels` 12 dilde zaten çevrili. **Kanıt:** `AndroidManifest.xml`
  2 widget etiketi, 2 info XML'de 2 `description`, 1 layout'ta 1
  `contentDescription` referansı — toplam 5, hepsi `@string/…` ve hepsi
  `values/strings.xml`'de tanımlı. 11 yeni çeviri dosyası eklemek yalnız
  widget adını başka dile çevirirdi, içeriği çevirmezdi (yanlış çözüm).

### Tests
- `tool/test_backup_import.mjs` — 40 test: yedek içe aktarımının saf
  katmanı. Doğrulama hatasında hiç yazma olmaması, ölümcül sayısal
  sözleşme, `deleted_at` canlanmaması, epoch dedup, `PGRST102` anahtar
  kümesi, `created_at` taşınması, beyaz liste (kullanıcı/sistem alanları
  kopyalanmaz), favoriler/son kullanılanlar, 8 KB `in` URL tavanı, 2000
  öğün ölçeği, bozuk girdi dayanıklılığı. `npm test` ile koşar.

---

# Flutter App

The Flutter app (`flutter_app/`) carries its own version independent of the
React web app. Versions below track `pubspec.yaml` version only.

## [flutter 1.3.0+4] - 2026-09-27

### Added — React (PWA) CI kapısı
- `.github/workflows/react.yml`: `npm ci` → `npx tsc -p tsconfig.app.json
  --noEmit` → `npm run lint` → `npm run build`. Daha önce React tarafında
  **hiç** CI işi yoktu; bu yüzden `tsconfig.app.json` içindeki
  `"ignoreDeprecations": "6.0"` değerinin TypeScript 5.8.3'te verdiği
  `TS5103` hatası (derlemenin hiç çalışmaması) fark edilemiyordu.
  `permissions: contents: read`, `setup-node` ile sabit Node major'ı ve
  `cache: npm`.

### Added — Android derleme doğrulaması
- CI'ın `check` işine `flutter build apk --debug` eklendi. `flutter analyze`
  ve `flutter test` yalnızca Dart kodunu doğrular; ana ekran widget'larının
  Kotlin/XML tarafı (`kotlin/com/calorix/calorix/widget/`,
  `res/layout/widget_*.xml`, `res/xml/widget_*_info.xml`) bu iki komutta
  hiç kontrol edilmiyordu.
- Ek adım: tüm Android resource XML'lerindeki `@string/...` referanslarının
  `res/values/strings.xml`'de tanımlı olduğunu doğrular (aapt2'den erken,
  okunabilir hata).

### Added — CI kapılarının sıkılaştırılması
- `flutter analyze` artık `--fatal-infos --fatal-warnings` ile çalışıyor:
  lint uyarıları da CI'ı kırar (mevcut taban temiz).
- `FLUTTER_VERSION` `3.47.0` → `3.47.5` (stable kanalındaki güncel patch;
  3.47.0 yayımlanmıştı, CI kırılmıyordu ama 5 patch gerideydi).
- `tool/check_versions.cjs` artık `AppConstants.defaultFat/Protein/Carbs`
  ile `Calculations.macros(2000)` çıktısını karşılaştırır. `defaultFat = 65`
  sapması ancak bu kapıyla yakalanabiliyordu (A3 alanında düzeltiliyor).

### Added — i18n
- 24 yeni çeviri anahtarı (`onboarding.*`, `auth.changePassword.*`,
  `chat.errors.assistant`, `chat.loadEarlier`, `dialogs.invalidAmount*`,
  `updates.unsafeUrl`) 12 dile de eklendi. Bu anahtarlar koddan `.tr()` ile
  çağrılıyordu ama hiçbir dil dosyasında yoktu — ilgili ekranlar ham anahtar
  metni gösteriyordu. 12 dil, 457 anahtar, 0 hata.

### Fixed
- `tool/check_i18n.cjs` yanlış negatifleri gideriyordu: çok satırlı zincirleme
  `.tr()` çağrıları (`'k'\n  .tr()`) ve dolaylı anahtarlar
  (`bmi.*`, `settings.goals.activity.*`, `meals.*`, `notifications.*Title`)
  taranmıyordu; 20 anahtar yanlışlıkla "orphan" sayılıyordu. Orphan raporu
  dört sınıfa ayrıldı: **ölü** (iki istemcide de yok), **react** (`src/**`
  içinde canlı), **dinamik** (interpolasyonlu kalıp kapsamında), **dolaylı**
  (literal geçiyor, `.tr()` değil).
- `tool/check_versions.cjs` `CHANGELOG` başlığı yoksa hata yerine uyarı
  basıyordu ama `warnings` fonksiyonu tanımından **sonra** çağrılıyordu;
  zamanlamanın kendisi sorun değildi ancak fonksiyon kaldırıldı/ düzeltilerek
  hata listesine alındı.

### Docs
- `README.md` / `README_EN.md`: "Frontend | React 18" satırı, depoda iki
  istemci bulunduğu gerçeğiyle çelişiyordu. Teknoloji tablosu iki istemciye
  ayrılmış, Flutter birincil olarak işaretlenmiştir. Yayınlama talimatındaki
  bayat `1.2.0+3` örneği `1.3.0+4` olarak güncellendi.
- `tool/convert_locales.cjs`: kullanım yorumu `.js` → `.cjs`; ayrıca
  script'in `flutter_app/assets/translations/*.json` üzerine yazıp 97
  Flutter-only anahtarı sileceği uyarısı eklendi.

### Added — i18n orphan ratchet'i
- `check_i18n.cjs` artık **ölü** orphan sayısı 63'ü aşarsa CI'ı kırar.
  Silme yapılmadı: 63 ölünün 61'i `public/locales` altındaki React çeviri
  dosyalarında hâlâ yer alıyor (PWA'nın çalışma zamanı kaynağı) ve
  `flutter_app/assets/translations/*.json` bu dosyaların üst kümesidir —
  silmek iki istemciden birini kırardı. Gerekçe ve ölçüm `tool/check_i18n.cjs`
  içindeki `ORPHAN_BASELINE` yorumunda kayıtlıdır.

### Added — Ana ekran widget'ları (Android)
- Günlük ve haftalık özet widget'ları: hedefe göre kalan kalori, makro satırı,
  su takımı, kilo satırı, 7 günlük kalori grafiği, haftalık ortalama ve
  "hedefteki gün" sayısı. Veriler cihazda `HomeWidget` üzerinden
  paylaşılan bir anahtar sözleşmesiyle (`daily.*`, `weekly.*`, `str.*`)
  saklanır; widget ayarları cihaza lokal olarak kalıcıdır.
- "Bugün hiç öğün eklemedin" günlük hatırlatıcısı (nudge): seçilen saatte
  bir kez gönderilir, gün içinde öğün eklenirse gönderilmez.
- Boş günlerde sabah/öğleden sonra/akşam teşvik metinleri (11:00'dan
  önce gösterilmez).
- İmza değişikliği sonrası widget yenilemede kullanıcı kilitlenmesini
  önlemek için `signedOut` / `noConfig` durumları.

### Added — Gözlemlenebilirlik
- Merkezi `AppLog` katmanı (`lib/core/observability/`): hatalar ve
  uyarılar tek noktadan loglanır, Sentry'ye bağlanır. Daha önce sessizce
  yutulan `catch (_)` blokları artık bağlamsal log üretir.

### Fixed
- i18n: `common.undo`, `dashboard.edit`, `dashboard.delete`,
  `analytics.goToCalories` ve `analytics.charts.macroFocus.title`
  anahtarları 10 dilde hiç yoktu — bu dillerde ilgili düğmeler ham
  anahtar metni gösteriyordu. 12 dilde tamamlandı.
- Dashboard render testleri gerçek çeviri metinlerini doğruluyor.

### Tests
- Manifest karar mantığı, öğün hatırlatıcısı göçü, widget veri bayatlama,
  hesaplama kenar durumları ve dashboard render için birim testleri.

## [flutter 1.2.1+3] - 2026-08-22

### Changed — Öğün bazlı hatırlatıcılar
- Tekil "sabah hatırlatıcısı" yerine her ana öğün (kahvaltı / öğle / akşam)
  için ayrı açılıp kapanabilen hatırlatıcı ve saat (varsayılan 08:30 /
  12:30 / 19:00). Mevcut kullanıcıların sabah ayarı göçle kesintisiz
  kahvaltı slotuna taşınır.
- Android bildirimleri ve web in-app banner'ı öğün bazlı; "1 saat ertele" /
  "öğünü atla" aksiyonları tıklanan öğünün bildirimi üzerinde çalışır
  (bildirim ID'leri 1001–1003, erteleme 1101–1103).
- Fixed: bildirimler var olmayan `notif.*` çeviri anahtarlarını kullanıyordu
  (ham anahtar metni gösteriliyordu) — `notifications.*` anahtarlarına
  düzeltildi.
- Translations: `notifications.lunch*/dinner*` anahtarları ve güncellenen
  `settings.notifications.reminder*` metinleri 12 dilde.

## [flutter 1.2.0+2] - 2026-08-22

### Added — Zamanlanmış hatırlatıcılar
- Android: günlük sabah kalori/kahvaltı hatırlatıcısı — aç/kapa + saat
  ayarı (Bildirim Ayarları diyaloğu), bildirim aksiyon tuşları
  ("Kahvaltı yapmayacağım", "1 saat ertele"), reboot sonrası plan korunumu.
- Web: uygulama açıkken gösterilen in-app hatırlatma banner'ı (aynı ayarlar).

### Removed — Barkod özelliği tamamen kaldırıldı
- Flutter ve React uygulamalarından tarayıcı/barkod akışı, `mobile_scanner`
  ve `@zxing/library` bağımlılıkları çıkarıldı; `foods.barcode` kolonu ve
  `food_source` enum'undaki 'barcode' değeri düşürüldü
  (`20260822000000_remove_barcode.sql` — mevcut satırlar 'manual'a taşındı).

### Added — Android zorunlu güncelleme mekanizması
- Launch-time update check against the GitHub Releases manifest
  (`releases/latest/download/latest.json`): builds below
  `minSupportedVersionCode` are blocked with a full-screen "Update Required"
  page (browser APK download); older-but-supported builds get a dismissible
  optional-update dialog; offline check falls back to the cached manifest and
  finally opens with a one-time warning.
- `tool/release_android.sh`: builds the release APK, generates `latest.json`
  (versionName/versionCode/minSupportedVersionCode/apkUrl/sha256/notes) and
  publishes both to GitHub Releases; `--min-code` sets the forced-update
  cutoff for breaking changes (e.g. DB migrations).
- Translations: `updates.*` keys in all 12 locales.

## [flutter 1.0.0+1] - 2026-08-16

### Added — Phase foundation (Faz 0–1)
- Flutter project scaffold on `feature/flutter-app` (supabase_flutter PKCE,
  flutter_riverpod, go_router, easy_localization for 12 locales).
- AuthRepository (signUp/signIn/signOut/resetPassword/resend/updatePassword),
  router auth redirect incl. PASSWORD_RECOVERY + onboarding gate.
- AuthPage (auth / forgot / pendingVerification / reset), OnboardingPage
  (5-step wizard, live BMI, Mifflin-St Jeor fallback for calculate-macros).
- Calculations (BMR/TDEE/macros/BMI/water parity with web).

### Added — Daily tracking (Faz 2)
- Food/FoodNutrition, MealEntry, WaterEntry, WeightEntry, FoodItem
  (100g-normalized, forAmount parity) models.
- FoodRepository (search / favorites / recent), DiaryRepository
  (fetchDaily + meal/water/weight CRUD, soft delete).
- Dashboard (DateSelector, CalorieRing, MacroCards, WaterTracker,
  WeightCard, MealSections), AddPage (300ms debounce search), AppShell.

### Added — Analytics + Settings (Faz 3)
- AnalyticsRepository + analytics_page (period selector, stat cards,
  fl_chart calorie/macro charts, weight trend).
- Settings (theme, 5 sections, 12-language picker, camera preference,
  health disclaimer), 4 dialogs (personal info / goals / notifications /
  password), JSON export/import via DataTransferRepository.

### Added — AI + Camera + Barcode (Faz 4)
- AI Chat (ChatMessage, ChatRepository, ChatPage with markdown).
- In-app camera (barcode-scanner style) + native camera + gallery via
  `camera_preference` (in_app|native, default in_app).
- RecognizedFood + RecognitionRepository (photo + text), AddWithAiDialog,
  RecognitionConfirmDialog (web handleSave parity).
- BarcodeFood + BarcodeRepository + BarcodeScanDialog (4-step scan flow;
  uses DB `sugar_g` singular — web `sugars_g` latent bug NOT inherited).
- mobile_scanner 5.2.3 with `kIsWeb` guard (manual entry on web).

### Added — Release pipeline (Faz 5)
- GitHub Actions CI (`flutter.yml`): path-filtered on `flutter_app/**`;
  pub get → build_runner → analyze → test; on main merge build web + AAB.
  Synthesizes a placeholder `.env` so the gitignored asset bundles.
- Android release signing: `key.properties`-driven signingConfig with
  debug-key fallback; R8 minify+shrink with proguard-rules.pro keep rules
  (models / supabase / riverpod / Play Core dontwarn).
- App icon + native splash config (flutter_launcher_icons,
  flutter_native_splash; CaloriX teal #00C7B7). Generators run manually.
- `applicationId com.calorix.app`; pubspec version `1.0.0+1`.

### Notes
- No live Supabase / Edge Function testing was performed (DB deactivated);
  the user will run end-to-end tests after all phases. Validation was
  `flutter analyze` (0 issues), `flutter test` (101/101), web build, and
  `flutter build appbundle --release` (R8 on, 70.9MB).
- Web `BarcodeScanDialog.tsx` inserts `sugars_g` (plural) into
  `food_nutrition`, but the DB column is `sugar_g` (singular) — that column
  silently drops on web. The Flutter app uses the correct singular name.

---

## [1.1.0] - 2026-05-18

### Added
- Added AI Chat nutrition assistant for conversational support around daily food logs, goals, and nutrition decisions.
- Added Supabase Edge Function support for AI chat responses.
- Added database migration support for storing AI chat conversations and messages.

### Changed
- Updated documentation to describe the AI Chat feature and the 1.1.0 release.
- Updated package metadata from 0.0.0 to 1.1.0.

### Removed
- Removed the offline sync feature because it was buggy and caused reliability/data consistency issues.
- Removed offline sync database artifacts via migration.

---

# Değişiklik Günlüğü

CaloriX için dikkat çeken tüm değişiklikler bu dosyada belgelenir.

---

# Flutter Uygulaması

Flutter uygulaması (`flutter_app/`) React web uygulamasından bağımsız kendi
sürümünü taşır. Aşağıdaki sürümler yalnızca `pubspec.yaml` sürümünü izler.

## [flutter 1.0.0+1] - 2026-08-16

### Eklendi — Faz altyapısı (Faz 0–1)
- `feature/flutter-app` branch'inde Flutter projesi iskeleti
  (supabase_flutter PKCE, flutter_riverpod, go_router, 12 dil için
  easy_localization).
- AuthRepository (signUp/signIn/signOut/resetPassword/resend/updatePassword),
  router auth yönlendirmesi (PASSWORD_RECOVERY + onboarding geçidi dahil).
- AuthPage (auth / forgot / pendingVerification / reset), OnboardingPage
  (5 adımlı sihirbaz, canlı BMI, calculate-macros için Mifflin-St Jeor
  fallback'i).
- Calculations (BMR/TDEE/makro/BMI/su — web parity).

### Eklendi — Günlük takip (Faz 2)
- Food/FoodNutrition, MealEntry, WaterEntry, WeightEntry, FoodItem
  (100g-normalize, forAmount parity) modelleri.
- FoodRepository (arama / favoriler / son yenilenler), DiaryRepository
  (fetchDaily + meal/water/weight CRUD, soft delete).
- Dashboard (DateSelector, CalorieRing, MacroCards, WaterTracker,
  WeightCard, MealSections), AddPage (300ms debounce arama), AppShell.

### Eklendi — Analitik + Ayarlar (Faz 3)
- AnalyticsRepository + analytics_page (dönem seçici, istatistik kartları,
  fl_chart kalori/makro grafikleri, kilo trendi).
- Ayarlar (tema, 5 bölüm, 12 dil seçici, kamera tercihi, sağlık reddi),
  4 diyalog (kişisel bilgi / hedefler / bildirimler / şifre), JSON
  export/import (DataTransferRepository).

### Eklendi — AI + Kamera + Barkod (Faz 4)
- AI Chat (ChatMessage, ChatRepository, markdown destekli ChatPage).
- Ekran içi kamera (barkod-tarayıcı stili) + yerel kamera + galeri
  (`camera_preference`: in_app|native, varsayılan in_app).
- RecognizedFood + RecognitionRepository (foto + metin), AddWithAiDialog,
  RecognitionConfirmDialog (web handleSave parity).
- BarcodeFood + BarcodeRepository + BarcodeScanDialog (4 adımlı tarama;
  DB `sugar_g` tekil kullanılır — web `sugars_g` latent bug'u MİRAS
  ALINMADI).
- mobile_scanner 5.2.3, `kIsWeb` guard'ı ile (web'de manuel giriş).

### Eklendi — Yayın pipeline'ı (Faz 5)
- GitHub Actions CI (`flutter.yml`): `flutter_app/**` path filter'lı;
  pub get → build_runner → analyze → test; main merge'de web + AAB build.
  Asset paketlemesi için placeholder `.env` sentezler.
- Android release imzalama: `key.properties` odaklı signingConfig (debug
  fallback'li); R8 minify+shrink + proguard-rules.pro keep kuralları
  (modeller / supabase / riverpod / Play Core dontwarn).
- Uygulama ikonu + açılış ekranı yapılandırması (flutter_launcher_icons,
  flutter_native_splash; CaloriX teal #00C7B7). Üretim elle çalıştırılır.
- `applicationId com.calorix.app`; pubspec sürüm `1.0.0+1`.

### Notlar
- Canlı Supabase / Edge Function testi yapılmadı (DB deaktif); kullanıcı
  tüm fazlar bitince uçtan uca test edecek. Doğrulama `flutter analyze`
  (0 sorun), `flutter test` (101/101), web build ve `flutter build
  appbundle --release` (R8 açık, 70.9MB) ile yapıldı.
- Web `BarcodeScanDialog.tsx` kaydı sırasında `food_nutrition`'a
  `sugars_g` (çoğul) insert ediyor, ancak DB sütunu `sugar_g` (tekil) —
  web'de bu sütun sessizce düşer. Flutter uygulaması doğru tekil adı
  kullanır.

---

## [1.1.0] - 2026-05-18

### Eklendi
- Günlük yemek kayıtları, hedefler ve beslenme kararları hakkında sohbet ederek destek almayı sağlayan AI Chat beslenme asistanı eklendi.
- AI chat yanıtları için Supabase Edge Function desteği eklendi.
- AI chat konuşmaları ve mesajlarını saklamak için veritabanı migration desteği eklendi.

### Değiştirildi
- Dokümantasyon AI Chat özelliği ve 1.1.0 sürümüyle güncellendi.
- Paket metadata sürümü 0.0.0 değerinden 1.1.0 değerine yükseltildi.

### Kaldırıldı
- Hatalı çalıştığı ve güvenilirlik/veri tutarlılığı sorunlarına neden olduğu için offline sync özelliği kaldırıldı.
- Offline sync veritabanı kalıntıları migration ile kaldırıldı.
