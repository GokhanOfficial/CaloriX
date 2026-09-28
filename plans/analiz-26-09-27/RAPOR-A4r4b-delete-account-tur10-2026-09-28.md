# RAPOR — A4r4b: Hesap Silme Arayüzü (P0), Tur 10

**Tarih:** 2026-09-28 · **Ajan:** A4r4b · **Commit:** `1042a29` (tek commit)
**Kapsam:** `flutter-features` / `feat`

---

## 1. Edge function sözleşmesinin GERÇEK doğrulaması

Varsayım **yok**; `supabase/functions/delete-account/{index.ts,helpers.ts}` ve
`_shared/{auth,http,rate_limit,validate}.ts` satır satır okundu.

### İstek

| Konu | Gerçek durum | Kaynak |
|---|---|---|
| Yöntem | **Yalnızca `POST`**; diğer her şey → `405 "Yalnızca POST desteklenir"` | `index.ts:74` |
| Gövde | **Yalnızca `{"password": string}`**. `readJsonBody` 4096 bayt sınır | `index.ts:91-92` |
| `userId` gövdeden alınır mı? | **Hayır — hiçbir şekilde.** BOLA koruması; `requireUserContext` id'yi doğrulanmış JWT'den alır | `_shared/auth.ts:44-86` |
| Parola sınırı | `requireString(…, 256)` → trim, boş olamaz, ≤ 256 karakter | `_shared/validate.ts:18-24` |
| `Content-Type` | Zorunlu **ve istemci tarafından sağlanmalı**: `readJsonBody` yalnızca `application/json` (veya **hiç** başlık) kabul eder; `text/plain` → **415** | `_shared/auth.ts:108-112` |
| Gövde limiti | `content-length` veya ham gövde > 4096 → **413** | `_shared/auth.ts:113-118` |
| Geçersiz JSON / diz / null | **400** | `_shared/auth.ts:119-127` |

> ⭐ **Bu 415 satırı görev tanımının uyarısını doğruluyor:** `Content-Type`
> **zorunludur**. Elle `fetch` yazmak hem 415 riski hem de JWT'yi elle taşıma
> zorunluluğu yüzünden **token sızıntısı** riskidir. `supabase.functions.invoke`
> (`functions_client-2.7.1`) başlığı **kendisi** koyar — test bunu ölçüyor.

### Rate limit — **2/saat, kullanıcı bazlı**

```
RATE_LIMIT = { windowSeconds: 3600, max: 2 }          // index.ts:67
rateLimitKey("delete-account", req, userId)
  → "delete-account:u:<uuid>"                        // _shared/rate_limit.ts:311
```
Anahtar **kullanıcı** bazlıdır ⇒ bir kullanıcı başkasının kotasını tüketmez.
Yanıt `429` + `Retry-After` başlığı. İki kaynak: DB sayaç (`rate_limit_hit` RPC)
ve bellek içi yedek.

### Yanıt — durum kodu → mesaj → istemci tipi

| HTTP | Gövde | İstemci `kind` |
|---|---|---|
| **200** | `{"success":true,"message":"Hesabınız ve tüm verileriniz kalıcı olarak silindi."}` | tam silme (`partial:false`) |
| **200** | `{"success":true,"message":"…bir bölümü silinemedi…","retryRecommended":true}` | **kısmi silme** (`partial:true`) |
| **401** | `{"error":"Parola hatalı"}` | `wrongPassword` |
| **401** | `{"error":"Yetkisiz"}` | `unauthorized` |
| **400/413/415** | `{"error":"Eksik veya geçersiz istek"}` | `invalidRequest` |
| **405** | `{"error":"Yalnızca POST desteklenir"}` | `invalidRequest` |
| **429** | `{"error":"Çok fazla deneme yapıldı, lütfen bekleyin"}` | `rateLimited` |
| **500** | `{"error":"Hesap silinemedi, lütfen daha sonra tekrar deneyin"}` | `unknown` |

### ⭐ Kısmi silme — alan adları (soru doğrudan yanıtlandı)

- **`rolledBack` alanı `YOKTUR`.** `grep` ile `index.ts` ve `helpers.ts`
  taranmış: hiçbir yerde üretilmiyor. Bu alan A1r3'ün modeliydi; **A1r4**
  ölçüm sonrası **terk etti** (`helpers.ts:145-152`).
- **`DELETION_PARTIAL_MESSAGE`** bir sabit metin sabitidir
  (`helpers.ts:289-290`), JSON alanı **değildir**; `message` içinde döner.
- **`retryRecommended: true`** — tek ve resmî sinyal (`index.ts:154`).
- Bu dal **yalnızca** `auth.admin.deleteUser()` **başarısız** olduğunda
  çalışır (`deleteAuthUser` istisna fırlatır → `index.ts:138,145-156`).
  Yani `partial == true` ⇒ **hesap hâlâ duruyor**. Kullanıcı yeniden
  denemelidir.

### Diğer doğrulamalar

- `DATA_TABLES` = 12 tablo; `profiles` **her zaman son sırada**
  (`helpers.ts:44-60`, `assertSafeDeletionOrder`).
- `foods` listede **değil**: `created_by` CASCADE ile temizlenir, seed
  gıdalar korunur (URUN-KARARLARI 3-A).
- Hatalarda **`console.error` sunucu loguna**, sabit mesaj istemciye
  (`_shared/http.ts:73-76`). Tablo/kolon adı sızmaz.

---

## 2. Veri katmanı — `data/repositories/account_repository.dart` (yeni, 323 satır)

`ChatException` / `RecognitionException` kalıbına uygun.

```dart
enum AccountDeletionErrorKind {
  wrongPassword,   // 401 "Parola hatalı"
  unauthorized,    // 401 "Yetkisiz"   ← eklenen ayrım
  rateLimited,     // 429
  invalidRequest,  // 400 / 405 / 413 / 415
  network,         // status 0
  unknown,         // 5xx / sözleşme ihlali
}
class AccountDeletionException implements Exception {
  final AccountDeletionErrorKind kind; final int? status; final String? causeType;
}
class AccountDeletionResult { final bool partial, retryRecommended; bool get completed; }
```

**Kararlar ve gerekçeleri**

1. **401 ikiye ayrıldı.** Sunucu 401'i iki farklı sabit mesajla döner
   (`index.ts:80` ve `:160`). Ayrım olmazsa oturum geçersizken kullanıcıya
   "parolanız hatalı" denir ve kullanıcı **sonsuz döngüye** girer; doğru
   eylem yeniden giriş.
2. **200 + `success` yoksa hata.** Sessiz "silindi" demek, sunucu sözleşmeyi
   ihlal etse bile KVKK eksik silme iddiası olurdu.
3. **Boş/aşırı-uzun parola istemcide reddedildi.** Sunucu zaten reddediyor
   (`requireString`) ama istemcide erken ret **2/saatlik kotayı** koruyor.
4. **Parola hiçbir yerde.** `AccountDeletionException` yalnızca `kind`,
   `status`, `causeType` taşır → parola sınıfa **hiç girmez**, `toString()`
   çıktısında matematiksel olarak bulunamaz. `AppLog` çağrılarında **yalnızca
   HTTP durum kodu** var (`AppLog.w('… (HTTP ${e.status})')`), hata nesnesi
   bile geçirilmiyor. İkinci katman `AppLog.scrubPii` (`password`/`parola`
   kalıbı) — varlığı **testle ölçüldü**.
5. `functions.invoke` kullanıldı; `maxPasswordLength=256`, `maxBodyBytes=4096`,
   `retryRecommendedField='retryRecommended'` sabitleri sözleşmeyi belgeler.

---

## 3. Arayüz akışı (adım adım)

**Giriş noktası** — `settings_page.dart`, listenin **en altında**; "Hakkında"
ve sağlık uyarısı kartından **sonra**. `Çıkış Yap`'ın yanına **konmadı**:
biri veri kalır, diğeri gider → farklı risk seviyesi, görsel olarak ayrışmalı.
A4r7b'nin bölümlerine dokunulmadı (yalnız import + 20 satır eklendi).

1. **Uyari diyaloğu** (`AlertDialog`, `barrierDismissible: false`)
   - Başlık + **7 veri kategorisi** madde madde: öğün/yemek, su, kilo, sohbet,
     favoriler+son kullanılanlar, profil/hedefler/ayarlar, bildirimler/hatırlatıcılar
   - **"Geri alınamaz"** kırmızı zeminli kutu
   - Kırmızı: `theme.colorScheme.errorContainer` + `onErrorContainer`
     (WCAG AA garantili). `AppColors.destructive` **kullanılmadı** —
     açık temada metin için 4.30:1, eşiğin altında (`app_theme.dart:103-108`).
2. **Parola** — `TextFormField` + `AutofillGroup`
   - `autofillHints: [AutofillHints.password]` — `auth_page.dart:314` ile **birebir**
   - `obscureText`, `enableSuggestions:false`, `autocorrect:false`,
     `textInputAction: done`, görünürlük düğmesi (`tooltip` WCAG 4.1.2)
3. **Gönderim**
   - Boşsa **hiç gönderilmez**, alan temizlenir + odak döner (kota koruma)
   - `_submitting` ile **çift gönderim engeli**; butonda spinner, iptal pasif
   - Hata anında `setState(_submitting=false)` ⇒ diyalog **kilitlemez**
4. **Sonuç**
   - **Tam silme** → `signOut()` → `AccountLocalCleanup.run()` → `router.go('/auth')`
   - **Parola hatalı (401)** → yalnız o mesaj + alan temizlenir + odak
   - **Rate limit (429)** → "çok fazla deneme, biraz sonra tekrar dene"
   - **Kısmi silme** → "bazı veriler silinemedi… hesabınız hâlâ duruyor";
     düğme **yeniden etkinleşir**, `signOut` **çağrılmaz**
   - **Sunucunun ham Türkçe metni gösterilmez** (12 dil + şema sızıntısı)
5. `use_build_context_synchronously`: her `await` sonrası
   `if (!mounted) return;` — 5 nokta.

---

## 4. Yerel temizlik — hangi state, gerçek fonksiyon adlarıyla

`features/settings/account_local_cleanup.dart` (yeni, 251 satır).

| Temizlenen | **Gerçek çağrılan** | Kaynak |
|---|---|---|
| Öğün hatırlatıcıları (kalıcı) | `prefs.remove('reminder_<meal>_enabled/_hour/_minute')` × 4 öğün + 3 legacy | `reminder_settings.dart:32-38` |
| **Planlı bildirimler** (Android/iOS) | **`NotificationService.instance.reschedule(const {})`** | `notification_service.dart:274-290` |
| Widget ayarları | `WidgetSettingsKeys.*` (9 anahtar) | `widget_settings.dart:75-84` |
| Tema | `'theme'` | `app_theme.dart:235` |
| Kamera tercihi | `'camera_preference'` | `camera_preference.dart:28` |
| Güncelleme önbelleği/susturma | `'update_manifest_cache'`, `'update_dismissed_code'` | `update_checker.dart:67,150` |
| **Ana ekran widget'ı** | **`WidgetBridge.publishState(state: WidgetBridge.stateSignedOut, …)`** | `widget_bridge.dart:119-132` |
| Riverpod state (10 provider) | `ref.invalidate(...)` | aşağıda |

**Riverpod** (`accountScopedProviders`): `profileProvider`,
`dailyDataProvider`, `selectedDateProvider`, `activeChatThreadIdProvider`,
`favoriteFoodsProvider`, `favoriteIdsProvider`, `frequentFoodsProvider`,
`recentFoodsProvider`, `widgetSettingsProvider`, `reminderSettingsProvider`.

> **`reschedule({})` neden?** Serviste genel bir "iptal et" API'si **yok**.
> `reschedule` `MealType.values` için `cancel(mealReminderId)` +
> `cancel(snoozeReminderId)` çağırır, sonra **yalnızca `enabled` olanları**
> yeniden planlar. Boş harita ⇒ hepsi iptal, hiçbiri planlanmaz.
> `snoozeOneHour` ise yalnız `snack`'i etkiler — **yetersiz** kalırdı.

### ⭐ Ölçülen bulgu: `SharedPreferences.clear()` **kullanılmaz**

`supabase_flutter-2.17.2` → `lib/src/supabase.dart:130-134`:
```dart
localStorage: SharedPreferencesLocalStorage(
    persistSessionKey: "sb-${Uri.parse(url).host.split(".").first}-auth-token")
```
Oturum `shared_preferences`'ın **aynı deposunda** tutuluyor (+ PKCE için
`SharedPreferencesGotrueAsyncStorage`). `prefs.clear()` çağırsak **oturum da
silinirdi** — `signOut()` yolu görünmezce devre dışı kalır ve yarı uygulanmış
bir oturumda kalırdı. Bu yüzden yalnız uygulama anahtarları tek tek silinir;
**test bunu doğruluyor** (`sb-test-auth-token` temizlikten sonra duruyor).

Hiçbir adım istisna fırlatmaz; `AccountLocalCleanupResult` dört bayrağı
raporlar, arayüz tamamlanmayan temizliği kullanıcıya uyarı olarak gösterir
(ama yine de `/auth`'a gider).

---

## 5. Çeviriler — 12 dil

`settings.deleteAccount.*` · 513 anahtar · `check_i18n.cjs` **yeşil**,
boş string yok.

| Dil | `entry` | `messages.partial` (kısmi silme) |
|---|---|---|
| tr | Hesabımı Sil | Bazı veriler silinemedi. Hesabınız hâlâ duruyor; … |
| en | Delete My Account | Some data could not be deleted. Your account still exists; … |
| de | Mein Konto löschen | Einige Daten konnten nicht gelöscht werden. … |
| es | Eliminar mi cuenta | No se pudieron eliminar algunos datos. Tu cuenta sigue existiendo; … |
| fr | Supprimer mon compte | Certaines données n'ont pas pu être supprimées. … |
| it | Elimina il mio account | Alcuni dati non sono stati eliminati. … |
| pt | Excluir minha conta | Alguns dados não puderam ser excluídos. … |
| ru | Удалить аккаунт | Часть данных удалить не удалось. … |
| ar | حذف حسابي | تعذّر حذف بعض البيانات. لا يزال حسابك موجودًا؛ … |
| ja | アカウントを削除 | 一部のデータを削除できませんでした。アカウントは残っています。… |
| ko | 계정 삭제 | 일부 데이터를 삭제하지 못했습니다. 계정이 아직 남아 있으니 … |
| zh | 删除我的账户 | 部分数据未能删除，账户仍然存在，请几分钟后再试。 |

Anahtar grupları: `entry`, `entryDesc`, `title`, `warning`, `data.{7}`,
`irreversible`, `passwordLabel`, `passwordRequired`, `confirm`, `deleting`,
`messages.{8}`.

> Arapça metinlerde ASCII cümle noktası **yok** (RTL denetleyicisi 61
> kasıntı uyarının tamamı için zaten uyarı üretiyor; yeni anahtarlar temiz).
> `ja.network` içindeki nöbetçi İngilizce kelime ("retry") üretim öncesi
> düzeltildi.

---

## 6. Testler — 56 yeni, gerçek assertion'lı

| Dosya | Test | Kapsam |
|---|---|---|
| `test/data/repositories/account_repository_test.dart` | **26** | 401/401-yetkisiz/429/400/405/413/415/500/ağ(0)/200-sonuçsuz/200-success:false; boş + 256+ karakter istemcide; gövde **yalnız** `password`; `Content-Type` otomatik; başlıklarda parola yok; 5 yolda parola sızıntısı taraması |
| `test/features/settings/delete_account_dialog_a4r4b_test.dart` | **23** | kapsam listesi + geri alınamaz; `EditableText` üzerinde `obscureText`/`enableSuggestions`/`autocorrect`/`autofillHints`; boş parola gitmez; 401 mesaj+odak+oturum düşmez; 429; **kısmi silme (3 test)**; tam silme `/auth`; temizlik başarısız olsa da `/auth`; çift gönderim; diğer 4 hata tipi; parola hiçbir `Text`'te görünmez |
| `test/features/settings/account_local_cleanup_a4r4b_test.dart` | **7** | anahtar listesi (15 hatırlatıcı + tema/kamera/güncelleme/9 widget); oturum anahtarı listede **değil**; 25 anahtar silinir; oturum **kalır**; 4 adım başarılı; **idempotent**; provider kapsamı |

**Platform kanalı mock'u**: `TestDefaultBinaryMessenger` + `setMockMethodCallHandler`.
Kanal adları **paket kaynaklarından** okundu:
`home_widget-0.10.0/lib/src/home_widget.dart:15` → `'home_widget'`
(ilk denemede yanlış ad kullanıldı, testte 3 dakika asılı kaldı ve düzeltildi),
`dexterous.com/flutter/local_notifications`.

### Toplam doğrulama

| Kapı | Sonuç |
|---|---|
| `flutter analyze` | ✅ **No issues found!** |
| `flutter test` | ✅ **995 passed** (taban 910 → +56 benim, +29 diğer ajan) |
| `node tool/check_i18n.cjs` | ✅ 12 dil, 513 anahtar, ölü orphan 63/63 (ratchet dokunulmadı) |
| `node tool/check_versions.cjs` | ✅ 1.3.0+4 tutarlı |
| Testler `/tmp` dışında | ✅ (`/tmp/opencode` yalnız **yedek** için, sonra silindi) |

### ⭐ Negatif test ölçümü (2 kez, kırmızı görüldü)

| Geri alınan düzeltme | Sonuç |
|---|---|
| `account_repository.dart`: 401 `unauthorized`/`wrongPassword` ayrımı kaldırıldı | 🔴 **1 kırmızı** — *"401 'Yetkisiz' → unauthorized"* |
| `delete_account_dialog.dart`: kısmi silmede çıkış kapısı `if (false && result.partial)` yapıldı | 🔴 **3 kırmızı** — *"kısmi silme mesajı / oturum düşürülmez / düğme yeniden etkinleşir"* |

Her ikisi de geri kondu → 56/56 yeşil doğrulandı.

---

## 7. Commit

| Hash | Stat |
|---|---|
| `1042a29` | `7 files changed, 2083 insertions(+)` |

Dosyalar: `account_repository.dart`, `account_local_cleanup.dart`,
`delete_account_dialog.dart`, `settings_page.dart` (+20) ve 3 test dosyası.

> ⚠️ **Çeviriler ayrı commit'te değil.** 12 dil JSON'u paralel çalışan
> A4r7b ajanının `9d2e75e` commit'ine **sürüklenmiş** (dosyalar çalışma
> ağacımda değişmişti, ajan `git add` ile hepsini aldı). Anahtarlar HEAD'de
> **eksiksiz** doğrulandı (12/12 `OK`) ve `check_i18n.cjs` yeşil; ancak
> **sahiplik** açısından bu commit'te görünmüyor. Düzeltme önerisi: sonraki
> turda `assets/translations/*.json` içindeki `settings.deleteAccount.*`
> bloklarının `deleteAccount` geçmişini not etmek.

---

## 8. Kalan riskler

1. **Çeviri commit sahipliği (yukarıda).** Kod sağlam, izlek kayıp.
2. **`Retry-After` saniyesi taşınamıyor.** `FunctionException` yanıt
   **başlıklarını** taşımıyor (`functions_client-2.7.1/lib/src/types.dart:35-40`
   → yalnız `status`, `details`, `reasonPhrase`). 429'da "biraz sonra"
   genel mesajı gösteriliyor, **saniye** yok. Sunucu kotaları doğru
   gönderiyor; SDK kanalı darboğaz. Çözüm SDK değişikliği gerektirir.
3. **`reschedule({})` erişim izni isteyebilir.** `_refreshPermissions` her
   `reschedule`'te izin okur (`notification_service.dart:233-245`) — planlama
   yapmadan okuma güvenli, ama Android 12+ `canScheduleExactNotifications`
   çağrısı native tarafta **sekme açabilir** (yalnız `init`'te istenen
   `requestExactAlarmsPermission` değil; `reschedule` **okur**). Düşük risk,
   izlenmeye değer.
4. **Rate limit 2/saat kullanıcıyı kilitleyebilir.** Yanlış parola denemesi
   kotayı tüketir; kullanıcı doğru parolayı bilse bile 1 saat bekler. A1r5'in
   **bilinçli** kararı (yıkıcı işlem, parola zaten biliniyor olmalı). UX
   olarak kabul edilebilir, ama Google Play'de "hesabımı silemiyorum" şikâyeti
   gelirse ilk bakılacak yer burasıdır. Sunucu tarafı (A1) alanı.
5. **Deprem testi yapılmadı.** Edge function çalışırken uçak moduna geçme,
   uygulama arka planda öldürme gibi senaryolar ölçülmedi.
6. **`delete-account` web PWA'da yok.** `src/**` React istemcisi aynı sunucu
   fonksiyonunu çağırabilir ama ayarlar ekranına giriş noktası konmadı
   (alan sahipliği: `src/**` bana ait değil). Play zorunluluğu Android/Flutter
   tarafını karşılıyor; web PWA'da KVKK "sil" talebi **hâlâ elle** yürütülüyor.
7. **`ref.invalidate` container'ı yok etmez.** Bellekteki referanslar düşer,
   ama oturum düşüşü zaten `currentUserProvider`'ı tetiklediği için gerçek
   sızıntı beklenmiyor; yine de **ölçülmedi** (bellek profili).
