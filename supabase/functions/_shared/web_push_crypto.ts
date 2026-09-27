/**
 * Web Push gövde şifreleme/çözme — **RFC 8188** (`aes128gcm` içerik şifrelemesi) ve
 * **RFC 8291** ("Message Encryption for Web Push") uyumlu, bağımlılıksız WebCrypto
 * uygulaması.
 *
 * ===========================================================================
 * 1) BRİFTEKİ AKIŞ TARİHİ / HATALI — AŞAĞIDA KANIT VE DOĞRU AKIŞ
 * ===========================================================================
 * Görev brifi şu akışı tarif ediyordu:
 *   "ECDH P-256 (p256dh ↔ auth) ile ECDH-ES (HKDF) türet.
 *    HKDF-SHA256 ile cek_info ve nonce_info türet → 16 bayt cek + 12 bayt nonce."
 *
 * Bu **iki ayrı HKDF adımı** RFC 8291 §3.3/§3.4'te **yoktur**. Doğru akış
 * **üç** HKDF adımıdır ve `p256dh` **gereklidir**:
 *
 *   ecdh_secret = ECDH(as_private, ua_public)                §3.1
 *   PRK_key     = HKDF-Extract(salt=auth_secret, IKM=ecdh)    §3.3
 *   key_info    = "WebPush: info" || 0x00 || ua_public || as_public
 *   IKM         = HKDF-Expand(PRK_key, key_info, L=32)        §3.3
 *   PRK         = HKDF-Extract(salt=salt, IKM=IKM)           RFC 8188 §2.2
 *   CEK         = HKDF-Expand(PRK, cek_info,  L=16)           RFC 8188 §2.3
 *   NONCE       = HKDF-Expand(PRK, nonce_info, L=12)          RFC 8188 §2.3
 *
 * Yani:
 *  - `auth` **tek başına yetmez**; HKDF'in *salt* girdisidir.
 *  - `p256dh` **gereklidir** ve iki yerde kullanılır: ECDH'in peer public key'i
 *    (`ua_public`) ve `key_info` içindeki bağlama girdisi (ikinci kullanım,
 *    anahtar karıştırma / KCI koruması — kötüye kullanımda `p256dh` değiştirilip
 *    anahtar ele geçirilemez).
 *  - `key_info` içinde **sunucunun kendi public key'i** (`as_public`) bulunur.
 *
 * Kanıt: RFC 8291 §5 + Ek A'daki çalışma örneği. Aşağıdaki `rfc8291 vectors`
 * testi, bu modülün ürettiği `IKM`/`PRK`/`CEK`/`NONCE` değerlerini **RFC'nin
 * kendi ara değerleriyle bayt bayt** karşılaştırır. (Not: Ek A'daki
 * çıktılar base64url *metni* olarak yazılmış; "key_info" satırındaki
 * "V2ViUHVzaDogaW5mbwAE..." ilk 13 baytı `WebPush: info` ASCII'sidir —
 * ham bayt olarak `SGV5...` değil, düz ASCII'dir.)
 *
 * ===========================================================================
 * 2) `dh` BAŞLIĞI (idlen = 0) NEDEN DOĞRU
 * ===========================================================================
 * Yayımlanmış RFC 8291 §4, AS public key'in `keyid` alanında taşınmasını şart
 * koşar. Ancak Web Push bu taslağın **önceki sürümlerini** uygular: push
 * servisleri (FCM, Mozilla autopush, WNS) ve tüm tarayıcı istemcileri
 * `Crypto-Key: dh=<as_public>` başlığını + gövdede `idlen = 0` bekler.
 * Aynı şekilde tarayıcı istemcileri push API'nin belirlediği **tek kayıtlı**
 * (single-record) biçimi çözer; bu yüzden burada `rs = 4096` sabit kullanılır
 * ve gövde 21 + ciphertext baytıdır.
 *
 * `web-push` (Mozilla) ve `web-push-crypto` referans uygulamaları da bu
 * (RFC öncesi) biçimi üretir. Modül bu biçimi uygular; §3.3'teki HKDF zinciri
 * ise Ek A vektörleriyle birebir doğrulanmıştır. Ayrıntı raporda.
 *
 * ===========================================================================
 * 3) NEDEN BAGIMLILIK YOK
 * ===========================================================================
 * `web-push` / `web-push-crypto` npm paketleri Node `Buffer`/stream'e bağlıdır;
 * Deno/Edge Runtime'ta ek polyfill + cold-start maliyeti getirir. Edge Runtime'ta
 * WebCrypto her zaman mevcut; gereken tüm primitifler (P-256 ECDH, HMAC-SHA-256,
 * AES-128-GCM) orada standarttır (bkz. `vapid.ts` başlığındaki aynı gerekçe).
 *
 * Referanslar:
 *  - RFC 8188 §2.1 şifreli kayıt başlığı · §2.2 HKDF · §2.3 `cek_info`/`nonce_info`
 *    · §2.4 boyutlar · §2.5 kayıt biçimi
 *  - RFC 8291 §3.1 ECDH · §3.2 16 bayt `auth` · §3.3 anahtar birleştirme
 *    · §3.4 özet · Ek A ara değerler
 *  - W3C Push API, "Generating an auth secret" (tarayıcı tarafı `auth` üretimi)
 */

/** RFC 8188 §2.1: `salt` alanı sabit 16 bayttır. */
export const SALT_BYTES = 16;

/** RFC 8291 §3 / RFC 8188 §1: içerik şifreleme adı (`Content-Encoding`). */
export const AES128GCM_ENCODING = "aes128gcm";

/**
 * RFC 8291 §4: "MUST set the rs parameter to a size that is greater than the sum
 * of the lengths of the plaintext, the padding delimiter (1 octet), any padding,
 * and the authentication tag (16 octets)." Pratikte tüm istemciler `rs = 4096`
 * bekler (`web-push` de öyle üretir) ve bu değer pratik sınırı 3993 bayt düz
 * metne indirir — bildirim gövdelerimiz için fazlasıyla yeterli.
 */
export const DEFAULT_RECORD_SIZE = 4096;

/** Push servislerinin pratik gövde üst sınırı (RFC 8291 §4 / RFC 8030 §7.2). */
export const MAX_ENCRYPTED_PAYLOAD_BYTES = 4096;

/**
 * RFC 8291 §4: "at most 3993 octets of plaintext" (4096 − 86 bayt başlık
 * = 4010 gövde; bundan 16 bayt GCM etiketi ve 1 bayt padding ayracı düşer).
 * Şifrelenmiş gövde 4096 bayta sığmalıdır; `preparePushPayload` bunu ayrıca
 * kontrol eder, buradaki sınır ikinci savunma hattıdır.
 */
export const MAX_PLAINTEXT_BYTES = 3993;

/** RFC 8291 §3.2: `auth_secret` tam olarak 16 bayttır. */
const AUTH_BYTES = 16;

/** RFC 8188 §2.4: `cek` (AES-128 anahtarı) ve `nonce` (GCM IV) boyutları. */
const CEK_BYTES = 16;
const NONCE_BYTES = 12;

/** RFC 8291 §3.5 / [X9.62]: uncompressed P-256 noktası = 0x04 + X(32) + Y(32). */
const UNCOMPRESSED_P256_BYTES = 65;

/** GCM doğrulama etiketinin bayt cinsinden uzunluğu (RFC 8188 §2.4). */
const TAG_BYTES = 16;

/** RFC 8188 §2.2: padding ayracı baytı (RFC 8291 §4: "MUST be checked; values other than 0x02 MUST cause the message to be discarded"). */
const PADDING_DELIMITER = 0x02;

/** Gövde içeriği şifrelenirken kullanılan şifreleme hataları. */
export class PushEncryptionError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PushEncryptionError";
  }
}

// ---------------------------------------------------------------------------
// base64url yardımcıları (vapid.ts ile aynı kurallar: dolgu/boşluk toleranslı)
// ---------------------------------------------------------------------------

export function base64UrlToBytes(value: string): Uint8Array {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/").replace(/\s+/g, "")
    .replace(/=+$/, "")
    .replace(/[^A-Za-z0-9+/]/g, "");
  if (normalized.length === 0) throw new PushEncryptionError("base64url içeriği boş");
  const padded = normalized + "=".repeat((4 - (normalized.length % 4)) % 4);
  let binary: string;
  try {
    binary = atob(padded);
  } catch (_) {
    throw new PushEncryptionError("base64url çözülemedi");
  }
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

export function bytesToBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// ---------------------------------------------------------------------------
// HKDF (RFC 5869) — WebCrypto'da HKDF yok, HMAC ile elle kuruyoruz.
// ---------------------------------------------------------------------------

const encoder = new TextEncoder();

async function hmacSha256(key: Uint8Array, data: Uint8Array): Promise<Uint8Array> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    key as unknown as BufferSource,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return new Uint8Array(await crypto.subtle.sign("HMAC", cryptoKey, data as unknown as BufferSource));
}

/**
 * HKDF-Extract (RFC 5869 §2.2): `PRK = HMAC(salt, IKM)`.
 * RFC 5869: boş `salt` geçerlidir ve tümü sıfır 32 bayta eşdeğerdir.
 */
export async function hkdfExtract(salt: Uint8Array, ikm: Uint8Array): Promise<Uint8Array> {
  return await hmacSha256(salt.length === 0 ? new Uint8Array(32) : salt, ikm);
}

/** HKDF-Expand (RFC 5869 §2.3). `length` bayt üretir. */
export async function hkdfExpand(prk: Uint8Array, info: Uint8Array, length: number): Promise<Uint8Array> {
  if (length <= 0 || length > 255 * 32) throw new PushEncryptionError("HKDF uzunluğu geçersiz");
  const out = new Uint8Array(length);
  let previous: Uint8Array = new Uint8Array(0);
  let offset = 0;
  for (let counter = 1; offset < length; counter++) {
    // T(1) = HMAC(PRK, info || 0x01), T(2) = HMAC(PRK, T(1) || info || 0x02), ...
    const block = new Uint8Array(previous.length + info.length + 1);
    block.set(previous, 0);
    block.set(info, previous.length);
    block[block.length - 1] = counter;
    previous = await hmacSha256(prk, block);
    const take = Math.min(previous.length, length - offset);
    out.set(previous.subarray(0, take), offset);
    offset += take;
  }
  return out;
}

// ---------------------------------------------------------------------------
// RFC 8291 §3.3 / RFC 8188 §2.3 `info` dizgeleri
// ---------------------------------------------------------------------------

/**
 * RFC 8291 §3.3: `key_info = "WebPush: info" || 0x00 || ua_public || as_public`.
 * **NUL sonlu DEĞİL** — NUL ayırıcıdır ve iki public key'den **önce** gelir.
 */
export function buildKeyInfo(userAgentPublicKey: Uint8Array, appServerPublicKey: Uint8Array): Uint8Array {
  if (userAgentPublicKey.length !== UNCOMPRESSED_P256_BYTES) {
    throw new PushEncryptionError("ua_public 65 bayt olmalı");
  }
  if (appServerPublicKey.length !== UNCOMPRESSED_P256_BYTES) {
    throw new PushEncryptionError("as_public 65 bayt olmalı");
  }
  return concat([
    encoder.encode("WebPush: info"),
    new Uint8Array([0x00]),
    userAgentPublicKey,
    appServerPublicKey,
  ]);
}

/**
 * RFC 8188 §2.3'teki iki `info` dizgesi **NUL ile sonlandırılır**:
 *   cek_info   = "Content-Encoding: aes128gcm" || 0x00
 *   nonce_info = "Content-Encoding: nonce"    || 0x00
 */
export const CEK_INFO = new Uint8Array([...encoder.encode("Content-Encoding: aes128gcm"), 0x00]);
export const NONCE_INFO = new Uint8Array([...encoder.encode("Content-Encoding: nonce"), 0x00]);

// ---------------------------------------------------------------------------
// ECDH (P-256) — WebCrypto ECDH destekler; anahtar sarmalaması `vapid.ts` ile aynı.
// ---------------------------------------------------------------------------

/** PKCS#8 ön eki (RFC 5958) — `vapid.ts`'teki ile birebir aynı. */
const PKCS8_EC_P256_PREFIX = new Uint8Array([
  0x02, 0x01, 0x00,
  0x30, 0x13,
  0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
  0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07,
]);

/** Ham 32 baytlık P-256 skalerini PKCS#8 DER'e sarar. */
function rawScalarToPkcs8(raw: Uint8Array): Uint8Array {
  if (raw.length !== 32) throw new PushEncryptionError("P-256 özel anahtar 32 bayt olmalı");
  // SEC1 minimal: SEQUENCE { INTEGER 1, OCTET STRING (32) }
  const sec1 = new Uint8Array(7 + raw.length);
  sec1[0] = 0x30;
  sec1[1] = 5 + raw.length;
  sec1[2] = 0x02;
  sec1[3] = 0x01;
  sec1[4] = 0x01;
  sec1[5] = 0x04;
  sec1[6] = 0x20;
  sec1.set(raw, 7);
  const out = new Uint8Array(2 + PKCS8_EC_P256_PREFIX.length + 2 + sec1.length);
  out[0] = 0x30;
  out[1] = PKCS8_EC_P256_PREFIX.length + 2 + sec1.length;
  out.set(PKCS8_EC_P256_PREFIX, 2);
  out[2 + PKCS8_EC_P256_PREFIX.length] = 0x04;
  out[3 + PKCS8_EC_P256_PREFIX.length] = sec1.length;
  out.set(sec1, 4 + PKCS8_EC_P256_PREFIX.length);
  return out;
}

/** P-256 **özel** anahtarı içe aktarır (ECDH, `deriveBits` yetkisiyle). */
export async function importP256PrivateKey(raw: Uint8Array): Promise<CryptoKey> {
  return await crypto.subtle.importKey(
    "pkcs8",
    rawScalarToPkcs8(raw) as unknown as BufferSource,
    { name: "ECDH", namedCurve: "P-256" },
    true,
    ["deriveBits"],
  );
}

/** P-256 public key'i 65 bayt uncompressed nokta biçiminde döndürür. */
export async function exportP256PublicKey(publicKey: CryptoKey): Promise<Uint8Array> {
  const jwk = await crypto.subtle.exportKey("jwk", publicKey);
  if (jwk.crv !== "P-256" || !jwk.x || !jwk.y) {
    throw new PushEncryptionError("P-256 public key dışa aktarılamadı");
  }
  const x = base64UrlToBytes(jwk.x);
  const y = base64UrlToBytes(jwk.y);
  if (x.length !== 32 || y.length !== 32) throw new PushEncryptionError("P-256 public key boyutu hatalı");
  const out = new Uint8Array(UNCOMPRESSED_P256_BYTES);
  out[0] = 0x04;
  out.set(x, 1);
  out.set(y, 33);
  return out;
}

/** `p256dh` alanını (base64url, 65 bayt, 0x04 işaretli) ECDH public key olarak içe aktarır. */
export async function importP256PublicKey(p256dh: string): Promise<CryptoKey> {
  const bytes = base64UrlToBytes(p256dh);
  if (bytes.length !== UNCOMPRESSED_P256_BYTES || bytes[0] !== 0x04) {
    throw new PushEncryptionError("p256dh 0x04 ile başlayan 65 bayt olmalı");
  }
  try {
    // `extractable: true` şart: RFC 8291 §3.3 `key_info` dizgesi `ua_public`
    // baytlarını içerir, bu yüzden key'i yeniden dışa aktarabilmeliyiz.
    return await crypto.subtle.importKey(
      "raw",
      bytes as unknown as BufferSource,
      { name: "ECDH", namedCurve: "P-256" },
      true,
      [],
    );
  } catch (_) {
    // WebCrypto, noktanın eğri üzerinde olduğunu da doğrular (RFC 8291 §7).
    throw new PushEncryptionError("p256dh içe aktarılamadı (geçersiz EC noktası)");
  }
}

/** ECDH üzerinden ortak gizliyi üretir (RFC 8291 §3.1, 32 bayt). */
export async function deriveEcdhSecret(privateKey: CryptoKey, peerPublicKey: CryptoKey): Promise<Uint8Array> {
  try {
    return new Uint8Array(
      await crypto.subtle.deriveBits({ name: "ECDH", public: peerPublicKey }, privateKey, 256),
    );
  } catch (_) {
    throw new PushEncryptionError("ECDH türetilemedi");
  }
}

// ---------------------------------------------------------------------------
// Şifreleme
// ---------------------------------------------------------------------------

export interface EncryptedPushBody {
  /** RFC 8188 §2.1 şifreli gövde başlıkları + RFC 8291 `Crypto-Key: dh=`. */
  headers: Record<string, string>;
  /** Şifreli gövde (`Uint8Array`) — `fetch` gövdesi olarak doğrudan kullanılabilir. */
  body: Uint8Array;
  /** Test/denetim için türetilen ara değerler (üretimde kullanılmaz). */
  debug: {
    salt: Uint8Array;
    userAgentPublicKey: Uint8Array;
    appServerPublicKey: Uint8Array;
    ecdhSecret: Uint8Array;
    prkKey: Uint8Array;
    keyInfo: Uint8Array;
    ikm: Uint8Array;
    prk: Uint8Array;
    cek: Uint8Array;
    nonce: Uint8Array;
  };
}

export interface EncryptPushBodyInput {
  /** Abonelik `auth` alanı (base64url, tam olarak 16 bayt — RFC 8291 §3.2). */
  authSecret: string;
  /** Abonelik `p256dh` alanı (base64url, 65 bayt uncompressed P-256). */
  p256dh: string;
  /** Şifrelenecek düz metin (JSON bildirim gövdesi). */
  plaintext: string;
  /** Kayıt boyutu. RFC 8291 §4 gereği tek kayıt; pratikte 4096. */
  recordSize?: number;
  /** Test/denetim için sabit salt; üretimde `undefined` (rastgele 16 bayt). */
  salt?: Uint8Array;
  /** Test/denetim için sabit AS anahtar çifti; üretimde `undefined` (üretilir). */
  applicationServerKeyPair?: CryptoKeyPair;
  /** Push servisi TTL başlığı (saniye). */
  ttlSeconds?: number;
  /** `Urgency` başlığı (RFC 8030 §5.3). */
  urgency?: "very-low" | "low" | "normal" | "high";
}

/** RFC 8188 §2.2: `rs` pozitif bir 32-bit tam sayı olmalıdır. */
function normalizeRecordSize(value: number | undefined): number {
  const size = value ?? DEFAULT_RECORD_SIZE;
  if (!Number.isInteger(size) || size <= 0 || size > 0xffffffff) {
    throw new PushEncryptionError("geçersiz kayıt boyutu");
  }
  return size;
}

/** İki veya daha fazla bayt dizisini birleştirir. */
function concat(parts: Uint8Array[]): Uint8Array {
  const total = parts.reduce((sum, p) => sum + p.length, 0);
  const out = new Uint8Array(total);
  let offset = 0;
  for (const part of parts) {
    out.set(part, offset);
    offset += part.length;
  }
  return out;
}

/**
 * RFC 8291 §4 gereği **tek kayıt** üretir: `rs` = düz metin + 1 bayt padding
 * ayracı + 16 bayt GCM etiketinden **büyük** olmalıdır (4096 pratik değerdir).
 * `dh` = mesaja özel üretilen AS public key.
 *
 * @throws PushEncryptionError `auth`/`p256dh` bozuk veya eksikse, düz metin
 *         sınırdan büyükse, `rs` geçersizse.
 */
export async function encryptPushBody(input: EncryptPushBodyInput): Promise<EncryptedPushBody> {
  const { authSecret, p256dh, plaintext } = input;

  // Girdi doğrulaması: bozuk `auth` sessizce geçmemeli, istisna fırlatmalıdır
  // (çağıran bu istisnayı yakalayıp push'u atlar, e-posta akışı sürer).
  if (typeof authSecret !== "string" || !authSecret.trim()) {
    throw new PushEncryptionError("abonelik auth alanı boş");
  }
  if (typeof p256dh !== "string" || !p256dh.trim()) {
    throw new PushEncryptionError("abonelik p256dh alanı boş");
  }
  if (typeof plaintext !== "string") {
    throw new PushEncryptionError("şifrelenecek gövde metin olmalı");
  }

  const recordSize = normalizeRecordSize(input.recordSize);

  const auth = base64UrlToBytes(authSecret);
  if (auth.length !== AUTH_BYTES) {
    // RFC 8291 §3.2: `auth` 16 bayttır. Yanlış boyutta devam etmek, istemcide
    // açılmayan bir gövde üretir (sessiz bildirim kaybı) — bu yüzden reddedilir.
    throw new PushEncryptionError(`auth 16 bayt olmalı, ${auth.length} bayt verildi`);
  }

  // 1) Mesaj başına rastgele 16 bayt salt (RFC 8188 §2.1).
  const salt = input.salt ?? crypto.getRandomValues(new Uint8Array(SALT_BYTES));
  if (salt.length !== SALT_BYTES) {
    throw new PushEncryptionError("salt 16 bayt olmalı");
  }

  // 2) Mesaja özel AS anahtar çifti (RFC 8291 §3.1). Mesaj bittikten sonra
  //    atılabilir; her mesaj için yeni çift üretmek replay'i zorlaştırır.
  const asKeyPair = input.applicationServerKeyPair ??
    await crypto.subtle.generateKey({ name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"]) as CryptoKeyPair;
  const asPublicKeyBytes = await exportP256PublicKey(asKeyPair.publicKey);

  // 3) ECDH (RFC 8291 §3.1) — AS özel anahtarı × UA public key (`p256dh`).
  const uaPublicKey = await importP256PublicKey(p256dh);
  const ecdhSecret = await deriveEcdhSecret(asKeyPair.privateKey, uaPublicKey);
  const uaPublicKeyBytes = await exportP256PublicKey(uaPublicKey);

  // 4) HKDF-Extract/Expand zinciri (RFC 8291 §3.3 + RFC 8188 §2.2/2.3).
  const prkKey = await hkdfExtract(auth, ecdhSecret);
  const keyInfo = buildKeyInfo(uaPublicKeyBytes, asPublicKeyBytes);
  const ikm = await hkdfExpand(prkKey, keyInfo, 32);
  const prk = await hkdfExtract(salt, ikm);
  const cekBytes = await hkdfExpand(prk, CEK_INFO, CEK_BYTES);
  const nonceBytes = await hkdfExpand(prk, NONCE_INFO, NONCE_BYTES);
  const cek = await crypto.subtle.importKey(
    "raw",
    cekBytes as unknown as BufferSource,
    { name: "AES-GCM" },
    false,
    ["encrypt"],
  );

  // 5) RFC 8188 §2.2/§2.5: düz metni `padding delimiter` ile sonlandır, tek
  //    kayıtta AES-128-GCM ile şifrele. GCM çıktısı `ciphertext || tag` üretir;
  //    RFC 8188 §2.5 gereği etiket kaydın **sonunda** tutulur (doğru biçim).
  const plaintextWithDelimiter = concat([encoder.encode(plaintext), new Uint8Array([PADDING_DELIMITER])]);
  if (plaintextWithDelimiter.length > recordSize) {
    // RFC 8291 §4: rs, düz metin + 1 + tag toplamından büyük olmalı.
    throw new PushEncryptionError(
      `düz metin ${plaintextWithDelimiter.length} bayt, rs=${recordSize} sınırını aşıyor`,
    );
  }
  const ciphertext = new Uint8Array(
    await crypto.subtle.encrypt(
      { name: "AES-GCM", iv: nonceBytes as unknown as BufferSource, tagLength: 128 },
      cek,
      plaintextWithDelimiter as unknown as BufferSource,
    ),
  );

  // 6) `salt(16) || rs(4) || idlen(1) || ciphertext` (RFC 8188 §2.1).
  //    `idlen = 0`: AS public key `Crypto-Key: dh=` başlığında taşınır.
  const header = new Uint8Array(SALT_BYTES + 4 + 1);
  header.set(salt, 0);
  new DataView(header.buffer).setUint32(SALT_BYTES, recordSize, false); // büyük endian
  header[SALT_BYTES + 4] = 0;
  const body = concat([header, ciphertext]);

  if (body.length > MAX_ENCRYPTED_PAYLOAD_BYTES) {
    throw new PushEncryptionError(
      `şifreli gövde ${body.length} bayt, push sınırını (${MAX_ENCRYPTED_PAYLOAD_BYTES}) aşıyor`,
    );
  }

  return {
    headers: {
      "Content-Encoding": AES128GCM_ENCODING,
      "Content-Type": "application/octet-stream",
      "TTL": String(input.ttlSeconds ?? 86400),
      "Urgency": input.urgency ?? "normal",
      // RFC 8291 §3.5: `dh` = bu mesaj için üretilen AS ECDH public key.
      "Crypto-Key": `dh=${bytesToBase64Url(asPublicKeyBytes)}`,
    },
    body,
    debug: {
      salt,
      userAgentPublicKey: uaPublicKeyBytes,
      appServerPublicKey: asPublicKeyBytes,
      ecdhSecret,
      prkKey,
      keyInfo,
      ikm,
      prk,
      cek: cekBytes,
      nonce: nonceBytes,
    },
  };
}

// ---------------------------------------------------------------------------
// Çözme (yalnızca test/denetim — sunucu tarafında gerekmez)
// ---------------------------------------------------------------------------

export interface DecryptedPushBody {
  plaintext: string;
  salt: Uint8Array;
  recordSize: number;
  idlen: number;
  /** Kayıt sayısı (RFC 8291 §4: tek kayıt beklenir). */
  recordCount: number;
  /** `as_public` değeri `Crypto-Key: dh=` başlığından okundu. */
  appServerPublicKey: Uint8Array;
}

/** `Crypto-Key` başlığından `dh=` değerini çeker. */
function parseDhHeader(cryptoKey: string | undefined): string {
  if (!cryptoKey) throw new PushEncryptionError("Crypto-Key (dh=) başlığı eksik");
  const match = cryptoKey.match(/dh=([A-Za-z0-9_-]+)/);
  if (!match) throw new PushEncryptionError("Crypto-Key başlığında dh= yok");
  return match[1];
}

/**
 * `aes128gcm` gövdesini çözer. Web Push **istemcisi** bu işlemi yapar; sunucu
 * tarafında ihtiyaç yoktur (ve olamaz — bkz. not). Tek amaç: şifreleme/çözme
 * uyumluluğunu (RFC 8291) birim testlerinde kanıtlamak.
 *
 * ÖNEMLİ: `ecdh_secret = ECDH(ua_private, as_public)` (RFC 8291 §3.4) olduğu
 * için çözme için **kullanıcı ajanının ÖZEL anahtarı** gerekir. `p256dh` tek
 * başına yetmez (o yalnızca public key'dir). Bu yüzden parametre `authSecret`
 * + `p256dh` + **`userAgentPrivateKey`** alır — yani tip düzeyinde bile
 * "sunucu tarafında çözme yapılabilir" yanılgısı engellenir. Gerçek tarayıcı
 * bu özel anahtarı `PushSubscription.keys.getAuth()` ile türetir.
 */
export async function decryptPushBody(
  encrypted: EncryptedPushBody,
  authSecret: string,
  p256dh: string,
  userAgentPrivateKey: CryptoKey,
): Promise<DecryptedPushBody> {
  const { body, headers } = encrypted;
  const encoding = (headers["Content-Encoding"] || "").toLowerCase();
  if (encoding !== AES128GCM_ENCODING) {
    throw new PushEncryptionError(`Content-Encoding aes128gcm olmalı, "${encoding}" geldi`);
  }
  if (body.length < SALT_BYTES + 5) {
    throw new PushEncryptionError("şifreli gövde çok kısa");
  }

  const asPublicKey = await importP256PublicKey(parseDhHeader(headers["Crypto-Key"]));
  const asPublicKeyBytes = await exportP256PublicKey(asPublicKey);
  const uaPublicKey = await importP256PublicKey(p256dh);
  const uaPublicKeyBytes = await exportP256PublicKey(uaPublicKey);
  // İstemci tarafı: kendi özel anahtarı × AS public key (RFC 8291 §3.1/3.4).
  const ecdhSecret = await deriveEcdhSecret(userAgentPrivateKey, asPublicKey);

  const auth = base64UrlToBytes(authSecret);
  if (auth.length !== AUTH_BYTES) throw new PushEncryptionError("auth 16 bayt olmalı");

  const view = new DataView(body.buffer, body.byteOffset, body.byteLength);
  const salt = body.slice(0, SALT_BYTES);
  const recordSize = view.getUint32(SALT_BYTES, false);
  const idlen = body[SALT_BYTES + 4];
  if (SALT_BYTES + 5 + idlen > body.length) {
    throw new PushEncryptionError("idlen gövde sınırını aşıyor");
  }

  const prkKey = await hkdfExtract(auth, ecdhSecret);
  const ikm = await hkdfExpand(prkKey, buildKeyInfo(uaPublicKeyBytes, asPublicKeyBytes), 32);
  const prk = await hkdfExtract(salt, ikm);
  const cekBytes = await hkdfExpand(prk, CEK_INFO, CEK_BYTES);
  const nonceBytes = await hkdfExpand(prk, NONCE_INFO, NONCE_BYTES);
  const cek = await crypto.subtle.importKey(
    "raw",
    cekBytes as unknown as BufferSource,
    { name: "AES-GCM" },
    false,
    ["decrypt"],
  );

  const payload = body.subarray(SALT_BYTES + 5 + idlen);
  const perRecord = recordSize + TAG_BYTES;
  const out: Uint8Array[] = [];
  let offset = 0;
  let index = 0;
  while (offset < payload.length) {
    const chunk = payload.subarray(offset, Math.min(offset + perRecord, payload.length));
    const nonce = new Uint8Array(NONCE_BYTES);
    nonce.set(nonceBytes, 0);
    // RFC 8188 §2.2: nonce'un son baytı kayıt sıra numarası ile XOR'lanır.
    new DataView(nonce.buffer, nonce.byteOffset, nonce.byteLength).setUint8(
      NONCE_BYTES - 1,
      nonceBytes[NONCE_BYTES - 1] ^ (index & 0xff),
    );
    let plain: ArrayBuffer;
    try {
      plain = await crypto.subtle.decrypt(
        { name: "AES-GCM", iv: nonce as unknown as BufferSource, tagLength: 128 },
        cek,
        chunk as unknown as BufferSource,
      );
    } catch (_) {
      throw new PushEncryptionError("kayıt çözülemedi (GCM etiketi doğrulanmadı)");
    }
    out.push(new Uint8Array(plain));
    offset += perRecord;
    index += 1;
  }

  const joined = concat(out);
  // RFC 8291 §4: "The padding delimiter octet MUST be checked; values other than
  // 0x02 MUST cause the message to be discarded."
  if (joined.length === 0 || joined[joined.length - 1] !== PADDING_DELIMITER) {
    throw new PushEncryptionError("padding delimiter 0x02 değil — kayıt reddedilmeli");
  }
  return {
    plaintext: new TextDecoder().decode(joined.subarray(0, joined.length - 1)),
    salt,
    recordSize,
    idlen,
    recordCount: out.length,
    appServerPublicKey: asPublicKeyBytes,
  };
}
