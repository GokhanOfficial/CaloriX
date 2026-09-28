import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/observability/app_logger.dart';
import '../supabase/supabase_client_provider.dart';

/// Hesap silme (KVKK / Google Play "Hesap Silme" zorunluluğu) — istemci
/// tarafı sarmalayıcı.
///
/// ## Sunucu sözleşmesi (2026-09-28, `supabase/functions/delete-account/`)
///
/// Bu sözleşme **tahminle değil, kaynak koddan okunarak** çıkarıldı
/// (`index.ts` + `helpers.ts` + `_shared/{auth,http,rate_limit,validate}.ts`).
///
/// ### İstek
///
///  - **Yalnızca `POST`.** Diğer her yöntem → `405 "Yalnızca POST desteklenir"`.
///  - Gövde **yalnızca** `{"password": "<string>"}`. `readJsonBody` (4096 bayt)
///    `password` dışındaki alanları **yok sayar**; kullanıcı kapsamı
///    (BOLA) gövdeden **hiçbir şekilde** okunmaz — `requireUserContext`
///    `userId`'yi doğrulanmış JWT'den alır. Bu yüzden gövdeye `userId`
///    eklemek işe yaramaz; sadece gereksiz PII taşır.
///  - `Content-Type` zorunluluğu: `readJsonBody` **yalnızca**
///    `application/json` (veya **hiç** başlık yok) kabul eder. `text/plain`
///    → `415`. `supabase.functions.invoke` gövde verildiğinde başlığı
///    **otomatik** `application/json` yapar; bu yüzden elle `fetch` kullanmak
///    yalnızca 415 riski değil, `Authorization` başlığını (JWT) elle taşıma
///    zorunluluğu yüzünden **token sızıntısı** riski de doğurur. Bu yüzden
///    istemci **her zaman** `functions.invoke` kullanır.
///
/// ### Yanıt
///
///  | Durum | Gövde | Karşılık |
///  |---|---|---|
///  | 200 tam | `{"success":true,"message":"…silindi."}` | [AccountDeletionResult.partial] == false |
///  | 200 kısmi | `{"success":true,"message":"…bir bölümü silinemedi…","retryRecommended":true}` | [AccountDeletionResult.partial] == true |
///  | 401 | `{"error":"Parola hatalı"}` | [AccountDeletionErrorKind.wrongPassword] |
///  | 401 | `{"error":"Yetkisiz"}` | [AccountDeletionErrorKind.unauthorized] |
///  | 429 | `{"error":"Çok fazla deneme yapıldı, lütfen bekleyin"}` + `Retry-After` | [AccountDeletionErrorKind.rateLimited] |
///  | 400 / 405 / 413 / 415 | `{"error":"Eksik veya geçersiz istek"}` vb. | [AccountDeletionErrorKind.invalidRequest] |
///  | 500 | `{"error":"Hesap silinemedi, lütfen daha sonra tekrar deneyin"}` | [AccountDeletionErrorKind.unknown] |
///
/// **Rate limit 2/saat** (`RATE_LIMIT = {windowSeconds: 3600, max: 2}`) ve
/// **kullanıcı bazlıdır** (`delete-account:u:<uuid>`), yani bir kullanıcı
/// başka birinin kotasını tüketmez.
///
/// ### `rolledBack` alanı **yoktur**
///
/// A1r3/A1r4 sürümünde kısmi silme bir **rollback** ile ölçülüyordu; ölçüm
/// sonrası bu model terk edildi. Kısmi silme **yalnızca** `retryRecommended`
/// ile bildirilir ve `auth.admin.deleteUser()` **başarısız** olduğu için
/// gerçekleşir (`deleteAuthUser` istisna fırlatır → `index.ts:145-156`).
/// Yani `partial == true` demek **hesabın hâlâ durduğu** demektir; kullanıcı
/// yeniden denemelidir. `rolledBack` alanı okunmaz çünkü sunucu hiç üretmiyor.
///
/// ### Güvenlik — parola asla loglanmaz
///
/// [AppLog] çağrılarında **yalnızca HTTP durum kodu** raporlanır; parola,
/// hata nesnesi (`FunctionException.details` gövdeden gelir ama yine de
/// denetlenmez) veya sunucu metni **hiçbir koşulda** loglanmaz. Bu bir
/// savunma derinliği katmanıdır: `AppLog.scrubPii` `password:` kalıbını
/// zaten maskeler ama doğru davranış hiç göndermemektir.
class AccountRepository {
  AccountRepository(this._client);

  final SupabaseClient _client;

  /// Edge fonksiyon adı — `supabase/config.toml` ile birebir.
  static const String functionName = 'delete-account';

  /// Sunucunun kabul ettiği **tek** alan.
  static const String passwordField = 'password';

  /// `requireString(body.password, "password", 256)` → sunucu üst sınırı.
  /// Boş göndermek yerine burada reddetmek, kotanın (`2/saat`) boşa
  /// harcanmasını ve kullanıcının neden başarısız olduğunu anlamamasını
  /// engeller. (Sunucu da `requireString` ile reddeder, yani aynı sonuç —
  /// ama 429 kotasını **istemci tarafında** korumak doğrusu.)
  static const int maxPasswordLength = 256;

  /// Sunucunun kısmi silme sinyali (`index.ts:154`).
  static const String retryRecommendedField = 'retryRecommended';

  /// `readJsonBody` gövde üst sınırı (bayt) — `index.ts:91`.
  static const int maxBodyBytes = 4096;

  /// Hesabı ve tüm kişisel verisini kalıcı olarak siler.
  ///
  /// [password] — kullanıcının **mevcut** parolası. Sunucu bunu
  /// `signInWithPassword` ile doğrular; oturum JWT'si tek başına **yetmez**
  /// (XSS ile alınan bir oturum başkasının hesabını silemez).
  ///
  /// Başarılı çağrıda [AccountDeletionResult] döner. Hata durumunda
  /// [AccountDeletionException] fırlatır; arayüz `kind` alanına göre
  /// karar verir.
  Future<AccountDeletionResult> deleteAccount({
    required String password,
  }) async {
    final passwordText = password.trim();
    if (passwordText.isEmpty) {
      // Sunucu `requireString` ile yine reddeder, ama **istemcide** erken
      // reddetmek rate limit kotasını (2/saat) korur.
      throw const AccountDeletionException(
        AccountDeletionErrorKind.invalidRequest,
        status: null,
      );
    }
    if (passwordText.length > maxPasswordLength) {
      throw const AccountDeletionException(
        AccountDeletionErrorKind.invalidRequest,
        status: null,
      );
    }

    FunctionResponse response;
    try {
      response = await _client.functions.invoke(
        functionName,
        // Gövde **yalnızca** `password`. `functions.invoke` `Content-Type:
        // application/json` başlığını ve `Authorization` JWT'sini kendisi
        // ekler (elle `fetch` kullanılmaz — 415 + token sızıntısı riski).
        body: {passwordField: passwordText},
      );
    } on FunctionException catch (e) {
      // `status: 0` → ağ/aktarım hatası (`FunctionsFetchException`),
      // yani sunucuya hiç ulaşılmadı. Diğerleri HTTP durum kodudur.
      final mapped = _mapHttpError(status: e.status, details: e.details);
      // Yalnızca durum kodu loglanır — parola **asla** gönderilmez.
      AppLog.w('Hesap silme isteği başarısız (HTTP ${e.status})');
      throw mapped;
    } catch (e, s) {
      // `FunctionException` dışı (ör. JSON kodlama hatası). Yine de parola
      // burada da loglanmaz: mesaj sabit, `error` nesnesi de atılır.
      AppLog.w('Hesap silme isteği beklenmeyen hata verdi', null, s);
      throw AccountDeletionException(
        AccountDeletionErrorKind.unknown,
        status: null,
        causeType: e.runtimeType.toString(),
      );
    }

    final data = response.data;
    if (data is! Map) {
      // 200 ama haritalanmayan gövde: sunucu sözleşmesi ihlali. Kullanıcıya
      // "silindi" demek **yanlış** olur (KVKK), bu yüzden hata sayılır.
      AppLog.w('Hesap silme yanıtı çözümlenemedi (HTTP ${response.status})');
      throw AccountDeletionException(
        AccountDeletionErrorKind.unknown,
        status: response.status,
      );
    }

    if (data['success'] != true) {
      // 200 + `success` yok/`false`: sözleşme dışı. Sessiz "başarı" demek
      // yerine belirsiz hata olarak yukarı çıkar.
      AppLog.w('Hesap silme yanıtında success alanı yok (HTTP ${response.status})');
      throw AccountDeletionException(
        AccountDeletionErrorKind.unknown,
        status: response.status,
      );
    }

    // Kısmi silme: `retryRecommended === true` ⇒ **hesap hâlâ duruyor**
    // (bkz. sınıf dokümanı, "rolledBack alanı yoktur").
    final partial = data[retryRecommendedField] == true;
    if (partial) {
      AppLog.w('Hesap silme kısmi tamamlandı; yeniden deneme öneriliyor');
    }
    return AccountDeletionResult(
      partial: partial,
      retryRecommended: partial,
    );
  }

  /// HTTP durum kodunu [AccountDeletionErrorKind]'e eşler.
  ///
  /// **Saf ve statik** (test edilebilir): hiçbir ağ/istemci bağımlılığı yok.
  ///
  /// ### 401 ayrımı
  ///
  /// Sunucu 401'i **iki farklı sabit mesajla** döner:
  ///  - `"Parola hatalı"` → [AccountDeletionErrorKind.wrongPassword]
  ///  - `"Yetkisiz"` → [AccountDeletionErrorKind.unauthorized]
  ///
  /// Bu ayrım kullanıcı davranışı açısından şart: oturum geçersizse
  /// "parolanız hatalı" demek kullanıcıyı sonsuz döngüye sokar; doğru
  /// eylem yeniden giriş yapmaktır. Mesaj eşleşmesi **en iyi tahmin**
  /// olsa da sunucu mesajları sabit (`helpers.ts` → `mapPasswordErrorToStatus`,
  /// `index.ts:80,160`), yani bu bir kırılgan bağ değil.
  static AccountDeletionException _mapHttpError({
    required int status,
    Object? details,
  }) {
    final message = _errorMessageFrom(details);
    if (status == 401) {
      final kind = (message != null && message.contains(_unauthorizedMarker))
          ? AccountDeletionErrorKind.unauthorized
          : AccountDeletionErrorKind.wrongPassword;
      return AccountDeletionException(kind, status: status);
    }
    if (status == 429) {
      return const AccountDeletionException(
        AccountDeletionErrorKind.rateLimited,
        status: 429,
      );
    }
    if (status == 400 || status == 405 || status == 413 || status == 415) {
      return AccountDeletionException(
        AccountDeletionErrorKind.invalidRequest,
        status: status,
      );
    }
    return AccountDeletionException(
      status == 0
          ? AccountDeletionErrorKind.network
          : AccountDeletionErrorKind.unknown,
      status: status == 0 ? null : status,
    );
  }

  /// Sunucunun oturum geçersiz mesajı (`index.ts:80,160`).
  static const String _unauthorizedMarker = 'Yetkisiz';

  /// Hata gövdesinden `{error: "..."}` alanını okur.
  ///
  /// Gövde parse edilemezse `null` döner; çağıran bu durumda mesaja **bakmaz**
  /// ve durum koduna göre karar verir (sabit mesaj olmayan bir hata
  /// `wrongPassword` sayılmaz, çünkü varsayılan 401 dalında yalnızca mesaj
  /// eşleşmezse `wrongPassword` seçilir — bu bilinçli bir tercihtir:
  /// 401'in gövdesi tanınmıyorsa en olası açıklama paroladır).
  static String? _errorMessageFrom(Object? details) {
    if (details is Map) {
      final error = details['error'];
      if (error != null) return error.toString();
    }
    if (details is String && details.trim().isNotEmpty) {
      return details.length > 200 ? details.substring(0, 200) : details;
    }
    return null;
  }
}

/// Hesap silme sonucu (yalnızca **başarılı** HTTP yanıtlarında döner).
class AccountDeletionResult {
  const AccountDeletionResult({
    required this.partial,
    required this.retryRecommended,
  });

  /// Sunucu bazı tabloları temizleyemedi (`retryRecommended: true`).
  ///
  /// Bu durumda `auth.admin.deleteUser()` **başarısız** olduğu için hesap
  /// **hâlâ duruyor** ve kullanıcı yeniden denemelidir. Kullanıcıya "başarı"
  /// gibi gösterilmemeli (KVKK eksik silme iddiası olmaz).
  final bool partial;

  /// `partial` ile aynı sinyali taşıyan, sunucunun alan adıyla birebir
  /// eşleşen okunabilir alan. UI ve testler bunu okur.
  final bool retryRecommended;

  /// Tam silme gerçekleşti mi?
  bool get completed => !partial;

  @override
  String toString() =>
      'AccountDeletionResult(partial: $partial, retryRecommended: $retryRecommended)';
}

/// Hesap silme hatası — arayüz `kind` alanına göre karar verir.
///
/// **Güvenlik:** [message] **sabit** bir dize seçilmez; sınıf yalnızca
/// [kind], [status] ve [causeType] taşır. Yani bu istisnanın `toString()`
/// çıktısında parola **matematiksel olarak bulunamaz** (parola bu sınıfa
/// hiç girmez). Bu, `test/data/repositories/account_repository_test.dart`
/// içindeki "parola hiçbir hata mesajında geçmiyor" testinin dayandığı
/// garantidir — test, bir uygulama hatası olsaydı kırmızı olurdu.
class AccountDeletionException implements Exception {
  const AccountDeletionException(
    this.kind, {
    this.status,
    this.causeType,
  });

  /// Hatanın arayüze taşınan anlamı.
  final AccountDeletionErrorKind kind;

  /// Sunucunun HTTP durum kodu (`null` → ağ hatası veya istemci öncesi ret).
  final int? status;

  /// Beklenmeyen hata türü (`FunctionException` dışı) — PII değildir, tip
  /// adıdır. Sentry'de sınıflandırma için kullanılır.
  final String? causeType;

  @override
  String toString() =>
      'AccountDeletionException(kind: ${kind.name}, status: $status, causeType: $causeType)';
}

/// Hesap silme hata türleri — `delete-account` sözleşmesinden türetilir.
enum AccountDeletionErrorKind {
  /// 401 `"Parola hatalı"` — kullanıcı **aynı parolayı** girmeli.
  wrongPassword,

  /// 401 `"Yetkisiz"` — oturum geçersiz; **yeniden giriş** gerekir.
  unauthorized,

  /// 429 — sunucu kotası (2/saat, kullanıcı bazlı). `Retry-After` başlığı
  /// `FunctionException` ile taşınmadığı için saniye bilgisi yoktur.
  rateLimited,

  /// 400 / 405 / 413 / 415 — istek biçimi reddedildi (istemci hatası).
  invalidRequest,

  /// `status: 0` — ağ/aktarım hatası, sunucuya ulaşılamadı.
  network,

  /// 5xx veya eşleşmeyen yanıt şekli.
  unknown,
}

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  return AccountRepository(ref.watch(supabaseClientProvider));
});
