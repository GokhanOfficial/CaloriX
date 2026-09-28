// Hesap silme (KVKK / Google Play "Hesap Silme" zorunluluğu) — **saf** katman.
//
// ## Sunucu sözleşmesi (tahmin değil, kaynaktan okundu)
//
// `supabase/functions/delete-account/index.ts` +
// `supabase/functions/delete-account/helpers.ts` +
// `supabase/functions/_shared/{auth,http,rate_limit,validate}.ts`.
//
// ### İstek
//
//  - **Yalnızca `POST`.** Başka yöntem → `405 "Yalnızca POST desteklenir"`.
//  - Gövde **yalnızca** `{"password": "<string>"}`. `readJsonBody` (4096 bayt)
//    `password` dışındaki alanları yok sayar. Kullanıcı kapsamı (BOLA)
//    gövdeden **hiçbir şekilde** okunmaz — `requireUserContext` `userId`'yi
//    doğrulanmış JWT'den alır.
//  - `Content-Type` **zorunlu**: `readJsonBody` yalnızca `application/json`
//    (ya da hiç başlık yok) kabul eder. `text/plain` → `415`.
//    `supabase.functions.invoke` gövde verildiğinde başlığı otomatik
//    `application/json` yapar ve `Authorization` JWT'sini kendisi ekler —
//    elle `fetch` kullanmak 415 riski **ve** token sızıntısı riski taşır.
//    Bu yüzden istemci daima `functions.invoke` kullanır (bkz.
//    `useAccountDeletion`).
//
// ### Yanıt
//
// | Durum     | Gövde                                        | Karşılık                    |
// |-----------|----------------------------------------------|----------------------------|
// | 200 tam   | `{success:true,message:"…silindi."}`          | `partial: false`           |
// | 200 kısmi | `{success:true,…,retryRecommended:true}`      | `partial: true`            |
// | 401       | `{error:"Parola hatalı"}`                     | `wrongPassword`            |
// | 401       | `{error:"Yetkisiz"}`                          | `unauthorized`             |
// | 429       | `{error:"Çok fazla deneme…"}` + `Retry-After` | `rateLimited`              |
// | 400/405/413/415 | `{error:"Eksik veya geçersiz istek"}` | `invalidRequest`            |
// | 500       | `{error:"Hesap silinemedi…"}`                 | `unknown`                  |
//
// Rate limit **2/saat** ve **kullanıcı bazlıdır** (`delete-account:u:<uuid>`).
//
// ### `rolledBack` alanı **yoktur**
//
// Kısmi silme **yalnızca** `retryRecommended` ile bildirilir ve
// `auth.admin.deleteUser()` **başarısız** olduğu için gerçekleşir
// (`index.ts:145-156`). Yani `partial === true` demek **hesabın hâlâ
// durduğu** demektir; kullanıcı yeniden denemelidir.
//
// ## Flutter ile hizalama
//
// `flutter_app/lib/data/repositories/account_repository.dart` (aynı hata
// türleri, aynı `maxPasswordLength = 256`, aynı "oturum/JWT tek başına
// yetmez" kuralı). Web'de tam UX'in (iki aşamalı diyalog, yerel temizlik)
// gerekmediği görev tanımı "çalışan ve doğru mesajları gösteren bir akış"
// diyor; **hata sınıflandırması** yine de birebir aynıdır.

/** Hesap silme sonucu (yalnızca **başarılı** HTTP yanıtlarında). */
export interface AccountDeletionResult {
  /**
   * Sunucu bazı tabloları temizleyemedi (`retryRecommended: true`).
   *
   * Bu durumda `auth.admin.deleteUser()` **başarısız** olduğu için hesap
   * **hâlâ duruyor** ve kullanıcı yeniden denemelidir. "Başarı" gibi
   * gösterilmemeli (KVKK eksik silme iddiası olmaz).
   */
  partial: boolean;
  /** Sunucunun alan adıyla birebir eşleşen okunabilir sinyal. */
  retryRecommended: boolean;
  /** Tam silme gerçekleşti mi? */
  completed: boolean;
}

/** Hata türleri — `delete-account` sözleşmesinden türetilir. */
export type AccountDeletionErrorKind =
  /** 401 `"Parola hatalı"` — kullanıcı aynı parolayı girmeli. */
  | 'wrongPassword'
  /** 401 `"Yetkisiz"` — oturum geçersiz; yeniden giriş gerekir. */
  | 'unauthorized'
  /** 429 — sunucu kotası (2/saat, kullanıcı bazlı). */
  | 'rateLimited'
  /** 400 / 405 / 413 / 415 — istek biçimi reddedildi. */
  | 'invalidRequest'
  /** Ağ/aktarım hatası, sunucuya ulaşılamadı. */
  | 'network'
  /** 5xx veya eşleşmeyen yanıt şekli. */
  | 'unknown';

/** `requireString(body.password, "password", 256)` → sunucu üst sınırı. */
export const MAX_PASSWORD_LENGTH = 256;

/** `readJsonBody` gövde üst sınırı (bayt) — `index.ts:91`. */
export const MAX_BODY_BYTES = 4096;

/** Sunucunun kısmi silme sinyali (`index.ts:154`). */
export const RETRY_RECOMMENDED_FIELD = 'retryRecommended';

/** Sunucunun oturum geçersiz mesajı (`index.ts:80,160`). */
const UNAUTHORIZED_MARKER = 'Yetkisiz';

/**
 * Hesap silme hatası.
 *
 * ⚠️ **Güvenlik:** `message` **sabit** bir dize seçilmez; bu sınıf yalnızca
 * `kind` ve `status` taşır. Yani `String(error)` çıktısında parola
 * **matematiksel olarak bulunamaz** (parola bu sınıfa hiç girmez). Bu,
 * "parola hiçbir hata mesajında geçmiyor" testinin dayandığı garantidir.
 */
export class AccountDeletionError extends Error {
  readonly kind: AccountDeletionErrorKind;
  readonly status: number | null;

  constructor(kind: AccountDeletionErrorKind, status: number | null = null) {
    // `name` sabit; parola veya sunucu metni **hiçbir koşulda** taşınmaz.
    super(`AccountDeletionError(${kind})`);
    this.name = 'AccountDeletionError';
    this.kind = kind;
    this.status = status;
  }
}

/**
 * Hata gövdesinden `{error: "..."}` alanını okur.
 *
 * Gövde parse edilemezse `null` döner. Tanınmayan bir 401 gövdesi
 * `wrongPassword` sayılır (bilinçli tercih: 401'de en olası açıklama
 * paroladır ve yanlış ayrım kullanıcıyı sonsuz döngüye sokar).
 */
export function errorMessageFrom(body: unknown): string | null {
  if (body && typeof body === 'object' && !Array.isArray(body)) {
    const value = (body as Record<string, unknown>).error;
    if (value != null) return String(value);
  }
  if (typeof body === 'string' && body.trim() !== '') {
    return body.length > 200 ? body.slice(0, 200) : body;
  }
  return null;
}

/**
 * HTTP durum kodunu [AccountDeletionErrorKind]'e eşler.
 *
 * **Saf ve statik** (test edilebilir): hiçbir ağ/istemci bağımlılığı yok.
 */
export function mapHttpError(status: number, body: unknown): AccountDeletionError {
  const message = errorMessageFrom(body);
  if (status === 401) {
    const kind =
      message !== null && message.includes(UNAUTHORIZED_MARKER) ? 'unauthorized' : 'wrongPassword';
    return new AccountDeletionError(kind, status);
  }
  if (status === 429) return new AccountDeletionError('rateLimited', 429);
  if (status === 400 || status === 405 || status === 413 || status === 415) {
    return new AccountDeletionError('invalidRequest', status);
  }
  return new AccountDeletionError(status === 0 ? 'network' : 'unknown', status === 0 ? null : status);
}

/**
 * İstemci öncesi doğrulama — boş/çok uzun parola **gönderilmez**.
 *
 * Sunucu `requireString` ile de reddeder; ama boş isteği göndermek
 * **2/saatlik kotayı harcar** (bir deneme sayılır) ve kullanıcı neden
 * başarısız olduğunu anlamaz. Doğrulama burada yapılır.
 */
export function validatePassword(password: string): AccountDeletionError | null {
  const text = typeof password === 'string' ? password.trim() : '';
  if (text === '' || text.length > MAX_PASSWORD_LENGTH) {
    return new AccountDeletionError('invalidRequest', null);
  }
  return null;
}

/**
 * Başarılı (200) yanıt gövdesini doğrular.
 *
 * 200 ama haritalanmayan / `success !== true` gövde → sözleşme ihlali.
 * Kullanıcıya "silindi" demek **yanlış** olur (KVKK), bu yüzden hata.
 */
export function parseSuccessResponse(body: unknown): AccountDeletionResult {
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    throw new AccountDeletionError('unknown', 200);
  }
  const record = body as Record<string, unknown>;
  if (record.success !== true) {
    throw new AccountDeletionError('unknown', 200);
  }
  const partial = record[RETRY_RECOMMENDED_FIELD] === true;
  return { partial, retryRecommended: partial, completed: !partial };
}
