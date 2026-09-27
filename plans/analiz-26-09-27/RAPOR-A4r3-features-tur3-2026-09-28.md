# RAPOR — A4r3 (flutter-features) — 2026-09-28 — Tur 3

## Özet (5 madde)

1. **P0 bulundu ve düzeltildi:** sohbet mesaj listesi (`chat_page.dart`) `_hasMore` doğru olduğunda
   **her seferinde çöküyordu**. A4r2'nin Tur 2'de eklediği 200 mesajlık pencerenin `itemBuilder`
   indeks eşlemesinde işaret hatası vardı (`+` yerine `-` olmalıydı) → `visible[i]` `RangeError`.
   Widget testi yazıldı: **düzeltme öncesi kırmızıydı** (`RangeError: Not in inclusive range 0..2: 3`).
2. **`AnalyticsAuthRequired` UI'da karşılıksızdı** (madde 1 görevi) → `_SignInRequiredView` eklendi
   (`context.go(AppRoutes.auth)`), genel `_ErrorView`'den ayrıldı. 4 test.
3. **Aktivite seviyesi okuma tarafı (madde 2) zaten A4r2 tarafından düzeltilmişti**; kapsamlı tarama
   yapıldı, `activityLevelFromDb` 4 noktada doğru kullanılıyor, **kalan `asNameMap` kullanımları
   `goal`/`gender` için ve bunlar camelCase olduğu için doğru**. TDEE etkisi ölçüldü (aşağıda).
4. **Chat eki toplam boyut sınırı eklendi** (madde 4): 25 MB, saf `ChatAttachmentLimits.canAccept`
   fonksiyonu + 9 test. Ayrıca "daha eski mesajları yükle" başlığı, `dispose` kontrolü, tembel liste
   ve indeks eşlemesi doğrulandı (madde 5) — **çökme bulundu, düzeltildi**.
5. **Kendi hata avı:** 3 yeni P1 (`await` sonrası `ref`/`setState`) + 1 P2 (tooltip) + 1 latent
   P1 (Kaydet kilidi) bulundu ve düzeltildi. **Bir "bulgu" yanlış çıktı ve geri alındı** (aşağıda).

---

## Düzeltilenler

| Sev | Dosya | Ne yapıldı | Doğrulama |
|---|---|---|---|
| **P0** | `lib/features/chat/chat_page.dart:396-408` | `itemBuilder` indeks eşlemesinde `+ (_hasMore?1:0)` → `- headerLen` (başlık satırı **çıkarılır**). `_hasMore` `true` iken `visible[i]` `RangeError` fırlatıyordu | 3 widget testi; **düzeltme öncesi kırmızı** (`RangeError: Not in inclusive range 0..2: 3`), sonra yeşil |
| **P1** | `lib/features/analytics/analytics_page.dart:99-108, 218-268` | `error:` dalında `e is AnalyticsAuthRequired` ayrımı → yeni `_SignInRequiredView` (kilit ikonu + mesaj + `FilledButton.icon` → `AppRoutes.auth`). `_ErrorView`'den ayrı | 4 test: giriş butonu var, `Hata`/`Tekrar Gönder` yok, boş grafik yok, buton `/auth`'a yönlendiriyor |
| **P1** | `lib/features/chat/chat_page.dart:37-51, 78-84, 322-337` | Toplam eki boyut sınırı (25 MB) + saf `ChatAttachmentLimits.canAccept` | 9 test (tek dosya 10 MB, toplam 25 MB, eşitlik sınıra dahil, negatif savunma, kısmi ekleme yok) |
| **P1** | `lib/features/chat/chat_page.dart:285-299` | `_clearVisibleChat`: `await archiveThread` sonrası `mounted` kontrolü | 1 test (dispose senaryosu). **Kanıt**: düzeltme geri alınınca `setState() called after dispose(): _ChatPageState (lifecycle state: defunct)` loglandı |
| **P1** | `lib/shared/widgets/date_selector.dart:40-48` | `_pickDate`: `await showDatePicker` sonrası `context.mounted` (eskiden yalnız `picked == null`) | 3 test |
| **P1** | `lib/features/settings/widgets/widget_settings_dialog.dart:85` | `_pickTime`: `await showTimePicker` sonrası `context.mounted` | koda bakışla doğrulandı (dialog test altyapısı gerektiriyor) |
| **P1** | `lib/features/settings/widgets/goals_dialog.dart:110-111` | `await calculate(...)` sonrasındaki `setState`'e `mounted` (`finally`'deki koruma `setState`'ten sonra geliyordu, işe yaramıyordu) | `flutter analyze` temiz |
| **P1 (latent)** | `lib/features/add/widgets/recognition_confirm_dialog.dart:196-210` | `_save`: seçim kontrolü `setState(() => _saving = true)` **öncesine** alındı. Aksi halde `selected.isEmpty` erken dönüşü `_saving`'i `true` bırakıp Kaydet butonunu kalıcı kilitliyordu. **Şu an erişilemez** (iki koşul aynı predicate) ama ayrışırsa ekran kilitlenir | `flutter analyze` temiz |
| **P2** | `lib/features/auth/auth_page.dart:316-320` | Şifre göster/gizle ikon butonuna `tooltip` (WCAG 4.1.2). Karşı taraftaki `password_dialog.dart` aynı anahtarı (`auth.changePassword.toggleVisibility`) kullanıyor — 12 dilde **mevcut**, yeni çeviri gerekmedi | `flutter analyze` temiz |
| — | `lib/features/chat/chat_page.dart:285-292` | `archiveThread(user.id, ...)` — A2 imzayı `userId` ile sıkılaştırdı (thread artık kullanıcıya bağlı) | 1 test `verify(() => repo.archiveThread('u1','t1'))` |

**Toplam: 3 commit, 8 dosya (4 kaynak + 3 test + 1 kaynak), 21 yeni test.**

---

## Görev maddelerinin durumu

### 1. `AnalyticsAuthRequired` (P1) — ✅ Düzeltildi
Ayrıntı yukarıdaki tabloda. **Ek not:** `analytics.signInRequired` çeviri anahtarı 12 dil
dosyasında **yok**. `assets/translations/**` A6r3'ün alanı olduğu için dokunulmadı; bunun yerine
`easy_localization` çeviri bulunamazsa **ham anahtarı** (`analytics.signInRequired`) ekrana bastığı
için `_signInRequiredText` getter'ı Türkçe metne düşüyor ve bunu test ediyorum
(ham anahtar asla ekranda görünmüyor). Anahtar eklendiğinde otomatik olarak çeviriye geçer.

### 2. Aktivite seviyesi okuma (P1) — ✅ Zaten düzeltilmiş (A4r2, `501cfb1`)
Kapsamlı tarama: `grep -rn "activityLevel\|asNameMap" lib/features lib/shared lib/app.dart`.
`activityLevelFromDb` **4 noktada** doğru kullanılıyor:
- `onboarding_page.dart:187` → `activityLevelToDb(_activity)` (yazma)
- `goals_dialog.dart:137` → `activityLevelToDb(_activity)` (yazma)
- `goals_dialog.dart:63` → `activityLevelFromDb(widget.profile?.activityLevel)` (okuma)
- `weight_card.dart:83` + `personal_info_dialog.dart:168` → `activityLevelFromDb(p.activityLevel)` (okuma)

**Kalan `asNameMap` kullanımları `goal` ve `gender` için** (`Goal.values.asNameMap()`,
`Gender.values.asNameMap()`). Bunlar **camelCase/snake_case uyuşmazlığı taşımıyor**: DB CHECK'i
`('cut','bulk','maintain')` ve `('male','female','other')` — enum adlarıyla birebir aynı.
Bu yüzden **düzeltme gerektirmiyor**; yanlış "ikinci bir sessiz veri hatası" raporlamamak için
migration'dan doğruladım.

#### TDEE etkisi (somut sayı)
`asNameMap()['very_active']` → `null` → `?? ActivityLevel.moderate` → **TDEE çarpanı 1.55**,
`veryActive` ise **1.90**. `MacroCalculator` TDEE = BMR × çarpan.

Örnek (30 y, erkek, 175 cm, 80 kg → Mifflin BMR ≈ 1780 kcal):

| activity_level (DB) | Çözümlenen enum | TDEE çarpanı | TDEE (kcal) | Günlük hedef (maintain) |
|---|---|---|---|---|
| `very_active` | `moderate` (**yanlış**) | 1.55 | 2759 | ~2759 |
| `very_active` | `veryActive` (**doğru**) | 1.90 | 3382 | ~3382 |

**Sapma: −623 kcal/gün** (≈ %18,4 eksik). Kilo kaydı/görünüm değişikliği `auto_recalculate_macros`
açıksa bu fark **profilin `tdee` ve `daily_calorie_target` alanlarına yazılıyordu** — yani
kullanıcının tüm günlük hedefi (ve makro oranları) kalıcı olarak yanlış hesaplanmış oluyordu.
Bu düzeltme `501cfb1` ile yapıldı; testler `test/data/activity_level_map_test.dart` +
`test/data/macro_calculator_test.dart` tarafından korunuyor.

### 3. `dialogs.amountRequired` metni yanlış (P2) — ⏳ Raporlandı, çeviri dosyalarına dokunulmadı

`recognition_confirm_dialog.dart:567` — bu anahtar `if (r.amount <= 0)` koşulunda gösteriliyor.
"Yeterli miktar girin" anlamına geliyor, oysa durum **"miktar 0'dan büyük olmalı"**. Kullanıcı alanı
boş bıraktığında uyarı "Miktar gerekli" der — ama alan zaten görünür ve odaktayken içinde
varsayılan değer var; mesaj yanlış yönlendiriyor (alanı doldurması gerektiğini ima eder).

**Öneri:** `dialogs.invalidAmount` ("Geçerli bir miktar girin") zaten **doğru durumu** ifade ediyor
ve 12 dilde mevcut. İki seçenek:

- **(a) Kod değişikliği (önerilen, 0 çeviri işi):** `r.amount <= 0` dalında
  `dialogs.invalidAmount`'ı kullan (miktar alanı boşsa `dialogs.amountRequired` kalsın).
- **(b) Metin düzeltmesi:** `amountRequired`'ı "Miktar 0'dan büyük olmalı" anlamına getir — aşağıdaki tablo.

Tabloda `amountRequired` **mevcut** → **önerilen** metin:

| Dil | Mevcut (`dialogs.amountRequired`) | Önerilen |
|---|---|---|
| tr | Miktar gerekli | Miktar 0'dan büyük olmalı |
| en | Amount is required | Amount must be greater than 0 |
| de | Menge ist erforderlich | Menge muss größer als 0 sein |
| fr | Quantité requise | La quantité doit être supérieure à 0 |
| es | Se requiere la cantidad | La cantidad debe ser mayor que 0 |
| it | Quantità richiesta | La quantità deve essere maggiore di 0 |
| ru | Требуется количество | Количество должно быть больше 0 |
| ar | الكمية مطلوبة | يجب أن تكون الكمية أكبر من 0 |
| zh | 请输入数量 | 数量必须大于 0 |
| ja | 量を入力してください | 量は 0 より大きい必要があります |
| ko | 양을 입력하세요 | 양은 0보다 커야 합니다 |
| pt | Quantidade obrigatória | A quantidade deve ser maior que 0 |

### 4. Sohbet eki boyut sınırı (P1) — ✅ Düzeltildi
`_maxAttachmentBytes` (10 MB) yalnızca **tek dosya** için geçerliydi; `_pendingFiles` sınırsız
dosya tutuyordu. Üstelik **her dosya zaten 10 MB'a küçültülüyor** (`maxWidth: 1600,
imageQuality: 85`), yani pratikte kullanıcı 2-3 fotoğraftan sonra belleğe ~25-30 MB ham byte
yazıyor, `insertUserMessage` hepsini base64'e çevirince (~1.33×) ~35-40 MB gövde oluşuyor.
25 MB toplam sınır eklendi; aşılırsa **ek eklenmiyor** (mevcut seçim bozulmuyor, kullanıcı
bir dosyayı silmeli) ve `dialogs.photoTooLarge` (12 dilde mevcut) + `(toplam max. 25 MB)` gösteriliyor.

### 5. Chat mesaj listesi performansı (P2) — ✅ Doğrulandı, **çökme bulundu**
- `ListView.builder` + `itemBuilder`/`itemCount` → **tembel, doğru.**
- `reverse: true` **kullanılmıyor** → `reverse` + `itemCount - index - 1` karıştırma tuzağı
  **yok**. Ama bunun yerine **daha kötü bir hata vardı**: başlık/gösterge satırlarının indeks
  ofseti işaret hatasıyla hesaplanıyordu (P0, yukarıda).
- `dispose`: `_scrollController` (listener kaldırılıp dispose), `_inputController` → **temiz.**
  Subscription yok (yok gereksinim). A4r2'nin `app.dart`'daki `StreamSubscription` sızıntısı
  zaten düzeltilmişti.
- Ek: `ListView.builder` `itemCount`'u `_sending`/`_loadingMore`/`_hasMore` değiştiğinde
  değişiyor — `setState` çağrıları mevcut (`setState(() {})` satır 159/110). Doğru.

---

## Yeni avlanan hatalar (kendi hata avı, madde listesi dışında)

| Sev | Dosya:satır | Bulgu | Etki | Düzeltildi |
|---|---|---|---|---|
| **P0** | `features/chat/chat_page.dart:408` | `itemBuilder` indeks ofseti `+` (başlık ekleniyor) | `_hasMore` true iken **her sohbet listesi çöküyor** (`RangeError`) | ✅ `489d6ea` |
| **P1** | `features/chat/chat_page.dart:294` | `await archiveThread` sonrası `setState` (mounted yok) | Dispose sonrası çökme; hata `catch`'e düşüp **başarılı arşivlemeyi "temizlenemedi" diye** gösteriyor | ✅ `0523740` |
| **P1** | `shared/widgets/date_selector.dart:40` | `await showDatePicker` sonrası `WidgetRef` kullanımı (mounted yok) | Takvim açıkken ekran değişimi → "Bad state: Cannot use ref after the widget was disposed" | ✅ `85dae8c` |
| **P1** | `features/settings/widgets/widget_settings_dialog.dart:85` | `await showTimePicker` sonrası `WidgetRef` (mounted yok) | Aynı desen | ✅ `85dae8c` |
| **P1** | `features/settings/widgets/goals_dialog.dart:111` | `await calculate` sonrası `setState` (mounted yok); `finally` koruması `setState`'ten sonra geliyordu | Dialog kapatılırsa çökme | ✅ `0523740` |
| **P1 (latent)** | `features/add/widgets/recognition_confirm_dialog.dart:209` | `setState(_saving=true)` sonrası erken `return` → buton kalıcı kilit | Şu an erişilemez; predicate ayrışırsa ekran kilitlenir | ✅ `0523740` |
| **P2** | `features/auth/auth_page.dart:316` | İkon-only butonda `tooltip` yok (WCAG 4.1.2) | Ekran okuyucu butonu tanımlayamıyor | ✅ `85dae8c` |

### Turda taranan ve **temiz çıkan** desenler (güvenilirlik notu)
- `int.parse`/`double.parse`/`DateTime.parse`: features/shared'da **tek** `DateTime.parse`
  (`chat_page.dart:785`) ve `try/catch` ile koralı. Geri kalanı `tryParse`.
- `.first`/`.single`/`elementAt`: tümü ya boşluk kontrollü ya da tek eleman garanti eden
  `SegmentedButton` `s.first` kalıpları. `analytics_page.dart:1067` `trend.first` çağrı yeri
  `if (data.weightTrend.isNotEmpty)` ile koralı.
- `fl_chart` indeks erişimleri (`stats[i]`, `trend[i]`): 8 noktada, hepsi
  `if (i < 0 || i >= stats.length) return SizedBox.shrink()` ile koralı (A4r2'ın işi).
- Tüm `IconButton`/`PopupMenuButton` örneklerinde `tooltip` kontrol edildi; 10 `IconButton`'ın
  9'unda vardı, eksik olan `auth_page.dart`'deki **tek** örnek düzeltildi.
- `await` + `ScaffoldMessenger.of(context)` kalıplarının tamamı `messenger` değişkeniyle
  `await` öncesi yakalanmış (A4r2'nin işi) — `use_build_context_synchronously` ihlali yok.
- `setState`/`ref` içeren 25 dosyanın tamamı tarandı; yukarıdaki 4 gerçek ihlal dışında temiz.

### ⛔ Geri alınan "bulgu" (dürüstlük kaydı)
`recognition_confirm_dialog` satır kartındaki canlı önizleme protein/karbonhidrat/yağı
`/10` ile ölçekliyordu (`kcal` `/100` idi) → ilk bakışta **"10 kat şişirilmiş önizleme"**
gibi görünüyordu. Test yazıp kanıtlamaya çalıştığımda test **yeşil** kaldı; nedenini araştırınca
buldum:

```
(x/10).round()/10   ≡   round(x/100 * 10)/10     (matematiksel olarak ÖZDEŞ)
```

Bu, "1 ondalık basamağa yuvarlama"nın **eşdeğer bir yazımı**, hata değil. Rastgele
200 000 `(porsiyon, miktar)` çiftiyle doğruladım: **0 uyuşmazlık**. Değişikliği
`git checkout` ile geri aldım ve yazdığım testi sildim — **bulgu raporlanmadı, düzeltilmedi.**
(Ders: "farklı görünen iki ifade" her zaman farklı hesap demek değil; mutlaka sayısal olarak
doğrulanmalı.)

---

## AKTARIM (başka alana)

### → A6r3 (i18n / test kalitesi) — `assets/translations/**` + CI
| Sev | Konu | Dosya | Not |
|---|---|---|---|
| **P2** | Yeni anahtar `analytics.signInRequired` **yok** (12 dil). Şimdilik kod içinde Türkçe fallback var, ham anahtar ekrana basılmıyor (test edildi) | `lib/features/analytics/analytics_page.dart:246` | Tablo raporun 3. bölümünde. Eklenince fallback otomatik devre dışı kalır |
| **P2** | `dialogs.amountRequired` metni durumu yanlış tarif ediyor (aşağıdaki 12 dil tablosu) | 12 dil dosyası | Seçenek (a) önerildi: koddan `dialogs.invalidAmount`'a geçiş → 0 çeviri işi |
| **P2** | `test/core/widgets/widget_bridge_scope_test.dart` **4 test kırık + 10 dk timeout** (`flutter test` tamamında). A3r2'nin commit'ine bağlı | `test/core/widgets/widget_bridge_scope_test.dart` | Benim alanım değil, dokunmadım. `flutter test`'in 477 geçmesini engelliyor |

### → A2r2 (veri katmanı) — bilgi
- `ChatRepository.archiveThread(String userId, String threadId)` imzası değişti; benim
  çağrı yerim güncellendi (`features/chat/chat_page.dart:293`). Teşekkürler — bu, başka birinin
  thread'ini arşivlemeyi de engelliyor, doğru bir sertleştirme.

### → A3r2 (çekirdek)
- `update_manifest` / `update_apk_url` testleri (3) + `widget_bridge_scope` testleri (4) kırık.
  Bunlar benim alanım dışında; `flutter test` tamamını kırmızı bırakıyor.

---

## Yeni testler

| Dosya | Test sayısı | Kapsam |
|---|---|---|
| `test/features/chat/chat_page_a4r3_test.dart` | 14 | 3 indeks/`RangeError` · 1 sohbet temizleme · 1 dispose senaryosu · 9 `ChatAttachmentLimits` |
| `test/features/analytics/analytics_auth_required_a4r3_test.dart` | 4 | "Giriş yap" görünür · `Hata`/`Tekrar Gönder` yok · boş grafik yok · buton `/auth`'a gider · ham anahtar yok |
| `test/features/shared/date_selector_mounted_a4r3_test.dart` | 3 | takvim aç/kapat · seçici kaldırılınca çökme yok · "Dün" etiketi |

**21 yeni test.** Zorluk notu: chat'in indeks testi **düzeltme öncesi kırmızıydı**
(`RangeError` stack trace'i ile doğrulandı) — sahte yeşil değil.

---

## Doğrulama

```
$ cd flutter_app && flutter analyze lib/features lib/shared lib/app.dart test/features
Analyzing 4 items...
No issues found! (ran in 4.4s)

$ cd flutter_app && flutter test test/features/
00:07 +56: All tests passed!

$ cd flutter_app && flutter test            # tam paket
10:13 +477 -4: Some tests failed.
  → 4 hata: test/core/widgets/widget_bridge_scope_test.dart (A3r2 alanı, benim commit'ime bağlı değil)
  → 1 timeout: aynı dosya
```

---

## Sonraki öneriler (Tur 4 için)

1. **A6r3:** `analytics.signInRequired` 12 dile eklensin; `dialogs.amountRequired` ya metin
   düzeltilsin ya da koddan `invalidAmount`'a geçsin.
2. **A3r2:** `widget_bridge_scope_test.dart`'daki 4 kırık test + timeout çözülmeli;
   `flutter test` tam paketi ancak bundan sonra yeşile döner.
3. **Mimari (ana ajan):** `analytics_page.dart` **1239 satır**, `chat_page.dart` **969 satır**,
   `onboarding_page.dart` **651 satır**. A4r2 turları boyunca bu dosyalara 4 ayrı commit
   düştü ve her seferinde "hangi satır bozuldu" avı gerektirdi. Bölme (grafik kartları /
   chat balonları / onboarding adımları ayrı dosya) **P3 seviyesinde temizlik** ama
   iki ajanın aynı dosyaya dokunma riskini gerçekten azaltır.
4. **Test altyapısı:** `showDatePicker`/`showTimePicker` gibi `Navigator` route'u açan
   fonksiyonları `flutter_test`'te doğrudan sürüklemek mümkün değil. `mounted` koruması
   için **strict** regresyon testi yazılamıyor (ateş yakma testi ancak konsol logu seviyesinde
   kalmak zorunda). Alternatif: bu tür çağrıları ince bir injectable fonksiyonun arkasına
   alıp testte sahte implementasyon döndürmek.
5. **Ortalama `build` boyutu:** `chat_page._ChatPageState.build` ~180 satır, 3 ayrı `if/else`
   bloğu ile iç içe. Okunabilirlik için `_buildMessageList` / `_buildComposer` /
   `_buildPendingAttachments` ayrımı düşünülebilir.
