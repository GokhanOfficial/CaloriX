/**
 * Web Push (RFC 8030) + VAPID (RFC 8292) yardımcıları — harici bağımlılık yok.
 *
 * Neden elle? `npm:web-push` Node'a (Buffer/stream) bağımlıdır ve Deno/Edge
 * Runtime'da ek polyfill gerektirir. Edge Runtime'ta WebCrypto her zaman var;
 * VAPID imzası yalnızca bir ECDSA P-256 (ES256) JWT imzasıdır, dolayısıyla elle
 * üretmek hem daha küçük hem de bağımlılıksızdır.
 *
 * Referanslar:
 *  - RFC 8292 (VAPID): `Authorization: vapid t=<jwt>, k=<applicationServerKey>`
 *  - RFC 7515/7519 (JWT), RFC 7518 (JWS) — ES256 = ECDSA P-256 + SHA-256,
 *    imza **ham (raw) R||S** (64 bayt) olmalı, DER değil.
 *  - RFC 8291 (aes128gcm) — bu modül **şifreleme yapmaz** (aşağıdaki not).
 */

/** Push servislerinin gövde olarak kabul ettiği pratik üst sınır (4096 bayt). */
export const MAX_PUSH_PAYLOAD_BYTES = 4096;

/** Push bildiriminde gövde metni için pratik üst sınır (kesilir). */
export const MAX_PUSH_BODY_CHARS = 200;

/**
 * EC P-256 özel anahtarın PKCS#8 DER düzeni (RFC 5958):
 *
 *   SEQUENCE {
 *     INTEGER 0                                        -- version
 *     SEQUENCE { OID 1.2.840.10045.2.1, OID 1.2.840.10045.3.1.7 }
 *     OCTET STRING { OCTET STRING <32 bayt skaler> }
 *   }
 *
 * Uzunluk baytları hesaplanarak üretilir (sabit `0x41`/`0x27` yazmak kolanlıkla
 * yanlış DER üretir ve içe aktarma sessizce başarısız olur).
 */
const PKCS8_EC_P256_PREFIX = new Uint8Array([
  0x02, 0x01, 0x00, // INTEGER 0 (version)
  0x30, 0x13, // SEQUENCE (AlgorithmIdentifier), len 19
  0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, // OID 1.2.840.10045.2.1 (id-ecPublicKey)
  0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, // OID 1.2.840.10045.3.1.7 (prime256v1)
]);
/** SEC1 `ECPrivateKey` öneki: INTEGER 1 + OCTET STRING başlığı (5 bayt). */
const SEC1_HEADER = new Uint8Array([0x02, 0x01, 0x01, 0x04, 0x20]);

/** Not: `crypto.subtle.sign` ES256'da ham (P1363) imza üretir; bazı runtime'lar DER döndürebilir. */
const ECDSA_PARAMS = { name: "ECDSA", hash: "SHA-256" } as unknown as AlgorithmIdentifier;

export class VapidError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "VapidError";
  }
}

// ---------------------------------------------------------------------------
// base64url yardımcıları (atob/btoa: Deno ve Edge Runtime'da mevcut)
// ---------------------------------------------------------------------------

export function base64UrlToBytes(value: string): Uint8Array {
  // Sondaki dolgu (padding) önce atılır: fazladan `=` `atob`'u hata verdirir.
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/").replace(/\s+/g, "")
    .replace(/=+$/, "")
    .replace(/[^A-Za-z0-9+/]/g, "");
  if (normalized.length === 0) throw new VapidError("base64url içeriği boş");
  const padded = normalized + "=".repeat((4 - (normalized.length % 4)) % 4);
  let binary: string;
  try {
    binary = atob(padded);
  } catch (_) {
    throw new VapidError("base64url çözülemedi");
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
// PEM / DER yardımcıları
// ---------------------------------------------------------------------------

export interface ParsedPem {
  label: string;
  der: Uint8Array;
}

/** PEM metnini DER'e çevirir. `-----BEGIN X-----` ... `-----END X-----` aralığını alır. */
export function parsePem(text: string): ParsedPem {
  const begin = text.match(/-----BEGIN ([A-Z0-9 ]+)-----/);
  const end = text.match(/-----END [A-Z0-9 ]+-----/);
  if (!begin || !end) throw new VapidError("PEM başlıkları eksik");
  const start = text.indexOf(begin[0]) + begin[0].length;
  const stop = text.indexOf(end[0]);
  if (stop <= start) throw new VapidError("PEM gövdesi boş");
  const body = text.slice(start, stop).replace(/[^A-Za-z0-9+/=\s]/g, "").replace(/\s+/g, "");
  if (!body) throw new VapidError("PEM gövdesi boş");
  return { label: begin[1].trim(), der: base64UrlToBytes(body) };
}

/**
 * Ham 32 baytlık P-256 skalerini PKCS#8 DER'e sarar.
 *
 * Not: `crypto.subtle.importKey('pkcs8', ...)` bir **RFC 5915** gövdesi bekler
 * (`PrivateKeyInfo.privateKey = OCTET STRING { ECPrivateKey SEQUENCE }`) ve
 * `ECPrivateKey` içindeki isteğe bağlı `[0] parameters` / `[1] publicKey`
 * alanlarını kabul etmez. openssl'in tam SEC1 çıktısı bu yüzden
 * `minimalSec1()` ile sadeleştirilerek kullanılır.
 */
export function rawScalarToPkcs8(raw: Uint8Array): Uint8Array {
  if (raw.length !== 32) throw new VapidError("P-256 özel anahtarı 32 bayt olmalı");
  return sec1ToPkcs8(minimalSec1(raw));
}

/**
 * SEC1 (`EC PRIVATE KEY`) DER'i PKCS#8 `PrivateKeyInfo` DER'ine çevirir.
 * Uzunluk baytları hesaplanır; P-256 girdileri tek baytlık uzunluk alanına sığar.
 */
export function sec1ToPkcs8(sec1: Uint8Array): Uint8Array {
  if (sec1.length < 8 || sec1.length > 127) {
    throw new VapidError(`SEC1 anahtar boyutu beklenmeyen: ${sec1.length} bayt`);
  }
  const out = new Uint8Array(2 + PKCS8_EC_P256_PREFIX.length + 2 + sec1.length);
  out[0] = 0x30; // SEQUENCE
  out[1] = PKCS8_EC_P256_PREFIX.length + 2 + sec1.length; // içerik uzunluğu
  out.set(PKCS8_EC_P256_PREFIX, 2);
  out[2 + PKCS8_EC_P256_PREFIX.length] = 0x04; // OCTET STRING
  out[3 + PKCS8_EC_P256_PREFIX.length] = sec1.length;
  out.set(sec1, 4 + PKCS8_EC_P256_PREFIX.length);
  return out;
}

// ---------------------------------------------------------------------------
// Anahtar içe/dışa aktarma
// ---------------------------------------------------------------------------

/**
 * SEC1 `ECPrivateKey` DER'inden özel skaler baytlarını çıkarır.
 * `ECPrivateKey ::= SEQUENCE { version INTEGER, privateKey OCTET STRING, [0] parameters, [1] publicKey }`
 *
 * Not: openssl'in ürettiği tam SEC1 yapısı (opsiyonel `[1] publicKey` içeren)
 * Deno'nun PKCS#8 çözücüsü tarafından kabul edilmez. Bu yüzden `minimalSec1()`
 * ile gereksiz alanlar atılıp yalnızca `version + privateKey` kalacak şekilde
 * yeniden kurulur.
 */
export function sec1PrivateScalar(der: Uint8Array): Uint8Array {
  if (der.length < 8 || der[0] !== 0x30) throw new VapidError("SEC1 yapısı geçersiz");
  let offset = 2;
  if ((der[1] & 0x80) !== 0) offset = 3; // uzun form uzunluk (P-256'da olmaz)
  if (der[offset] !== 0x02) throw new VapidError("SEC1 version alanı eksik");
  const versionLen = der[offset + 1];
  offset += 2 + versionLen;
  if (der[offset] !== 0x04) throw new VapidError("SEC1 privateKey alanı eksik");
  const scalarLen = der[offset + 1];
  const start = offset + 2;
  if (scalarLen < 1 || start + scalarLen > der.length) throw new VapidError("SEC1 privateKey uzunluğu geçersiz");
  return der.slice(start, start + scalarLen);
}

/** Yalnızca `version + privateKey` içeren minimal SEC1 DER üretir (RFC 5915 uyumlu). */
export function minimalSec1(scalar: Uint8Array): Uint8Array {
  if (scalar.length < 1 || scalar.length > 32) throw new VapidError("SEC1 skaler uzunluğu geçersiz");
  const body = new Uint8Array(SEC1_HEADER.length + scalar.length);
  body.set(SEC1_HEADER, 0);
  body.set(scalar, SEC1_HEADER.length);
  const out = new Uint8Array(2 + body.length);
  out[0] = 0x30;
  out[1] = body.length;
  out.set(body, 2);
  return out;
}

/**
 * Verilen metni P-256 özel anahtara çevirir. Desteklenen biçimler:
 *  (a) base64url ham 32 bayt (VAPID üreticilerinin verdiği tipik biçim),
 *  (b) `-----BEGIN PRIVATE KEY-----` (PKCS#8),
 *  (c) `-----BEGIN EC PRIVATE KEY-----` (SEC1).
 *
 * `extractable = true`: public key türetmek için JWK dışa aktarımı gerekir
 * (WebCrypto'de EC public key'i başka yolla elde edilemez).
 */
export async function importVapidPrivateKey(raw: string): Promise<CryptoKey> {
  const text = raw.trim();
  if (!text) throw new VapidError("VAPID_PRIVATE_KEY boş");

  let expectedScalar: Uint8Array | null = null;
  let pkcs8: Uint8Array | null = null;
  let key: CryptoKey | null = null;

  if (/-----BEGIN/.test(text)) {
    const { label, der } = parsePem(text);
    if (label === "EC PRIVATE KEY") {
      // openssl'in tam SEC1 çıktısı (opsiyonel alanlar içerir) Deno tarafından
      // kabul edilmez; yalnızca version + privateKey kalan minimal biçim kullanılır.
      expectedScalar = sec1PrivateScalar(der);
      pkcs8 = sec1ToPkcs8(minimalSec1(expectedScalar));
    } else if (label === "PRIVATE KEY" || label === "PRIVATE KEY (PKCS8)") {
      pkcs8 = der;
    } else if (label === "PUBLIC KEY" || label === "CERTIFICATE") {
      throw new VapidError("VAPID_PRIVATE_KEY bir public key/PEM sertifikası; özel anahtar gerekli");
    } else {
      throw new VapidError(`Desteklenmeyen PEM etiketi: ${label}`);
    }
  } else {
    const compact = text.replace(/\s+/g, "");
    if (!/^[A-Za-z0-9+/_-]{40,200}=*$/.test(compact)) {
      throw new VapidError("VAPID_PRIVATE_KEY PEM ya da base64url olmalı");
    }
    const bytes = base64UrlToBytes(compact);
    if (bytes.length === 32) {
      // (a) VAPID üreticilerinin verdiği tipik biçim: ham skaler.
      expectedScalar = bytes;
      pkcs8 = rawScalarToPkcs8(bytes);
    } else if (bytes.length === 65 && bytes[0] === 0x04) {
      // Yanlışlıkla public key konmuş: skaler buradan çıkarılamaz.
      throw new VapidError("VAPID_PRIVATE_KEY bir public key gibi görünüyor (65 bayt)");
    } else if (bytes[0] === 0x30) {
      // (b) base64url kodlanmış PKCS#8 ya da SEC1 DER (openssl `pkey -outform DER`).
      // PKCS#8'i doğrudan deneriz; başarısız olursa SEC1 sanıp sadeleştiririz.
      try {
        key = await importPkcs8(bytes);
      } catch (_) {
        expectedScalar = sec1PrivateScalar(bytes);
        pkcs8 = sec1ToPkcs8(minimalSec1(expectedScalar));
      }
    } else {
      throw new VapidError(`Beklenmeyen anahtar uzunluğu: ${bytes.length} bayt`);
    }
  }

  if (!key) {
    if (!pkcs8) throw new VapidError("P-256 özel anahtar içe aktarılamadı");
    try {
      key = await crypto.subtle.importKey(
        "pkcs8",
        pkcs8 as unknown as BufferSource,
        { name: "ECDSA", namedCurve: "P-256" },
        true,
        ["sign"],
      );
    } catch (_) {
      throw new VapidError("P-256 özel anahtar içe aktarılamadı");
    }
  }

  // Kötü DER/kötü base64 girdinin sessizce geçmesini engelle: içe aktarılan
  // anahtarın skaleri, beklenen baytlarla (sağa hizalı) aynı olmalı.
  if (expectedScalar) {
    const jwk = await crypto.subtle.exportKey("jwk", key);
    if (!jwk.d) throw new VapidError("JWK skaler alanı yok");
    const actual = base64UrlToBytes(jwk.d);
    const expected = expectedScalar.length >= 32
      ? expectedScalar.slice(expectedScalar.length - 32)
      : expectedScalar;
    if (actual.length > 32) {
      throw new VapidError("P-256 dışı bir anahtar verildi");
    }
    for (let i = 0; i < 32; i++) {
      if (actual[i] !== (expected[i] ?? 0)) {
        throw new VapidError("PEM/SEC1 içeriği beklenmeyen biçimde");
      }
    }
  }
  return key;
}

/** PKCS#8 DER'den imzalama anahtarı üretir (doğrulama amacı yok). */
async function importPkcs8(der: Uint8Array): Promise<CryptoKey> {
  return await crypto.subtle.importKey(
    "pkcs8",
    der as unknown as BufferSource,
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign"],
  );
}

/** P-256 private key'ten uncompressed (65 bayt) public key üretir → base64url. */
export async function deriveVapidPublicKey(privateKey: CryptoKey): Promise<string> {
  const jwk = await crypto.subtle.exportKey("jwk", privateKey);
  if (jwk.crv !== "P-256" || !jwk.x || !jwk.y) throw new VapidError("P-256 public key türetilemedi");
  const x = base64UrlToBytes(jwk.x);
  const y = base64UrlToBytes(jwk.y);
  if (x.length !== 32 || y.length !== 32) throw new VapidError("P-256 public key boyutu hatalı");
  const out = new Uint8Array(65);
  out[0] = 0x04;
  out.set(x, 1);
  out.set(y, 33);
  return bytesToBase64Url(out);
}

// ---------------------------------------------------------------------------
// İmza normalizasyonu
// ---------------------------------------------------------------------------

/**
 * WebCrypto çoğu runtime'da ECDSA imzasını ham (IEEE P1363, R||S) üretir; bazı
 * implementasyonlar DER (SEQUENCE) döndürebilir. JWS ES256 **her zaman** ham
 * R||S ister, bu yüzden DER girdiyi burada güvenle çeviririz.
 */
export function normalizeEcdsaSignature(signature: Uint8Array): Uint8Array {
  if (signature.length === 64) return signature;
  if (signature.length > 2 && signature[0] === 0x30) {
    const readInteger = (offset: number): { value: Uint8Array; next: number } => {
      if (signature[offset] !== 0x02) throw new VapidError("ECDSA imza (DER) çözülemedi");
      let len = signature[offset + 1];
      let start = offset + 2;
      if (len & 0x80) {
        const count = len & 0x7f;
        // P-256'da tek baytlık uzunluk yeterli; daha uzun süreç reddedilir.
        if (count !== 1 || start + count > signature.length) {
          throw new VapidError("ECDSA imza (DER) çözülemedi");
        }
        len = signature[start];
        start += 1;
      }
      if (start + len > signature.length) throw new VapidError("ECDSA imza (DER) çözülemedi");
      // DER INTEGER: negatif ise başta 0x00 vardır, at.
      let value = signature.slice(start, start + len);
      let i = 0;
      while (i < value.length - 1 && value[i] === 0x00) i++;
      value = value.slice(i);
      return { value, next: start + len };
    };

    const r = readInteger(2);
    const s = readInteger(r.next);
    if (r.value.length === 0 || s.value.length === 0 || r.value.length > 32 || s.value.length > 32) {
      throw new VapidError("ECDSA imza (DER) çözülemedi");
    }
    const out = new Uint8Array(64);
    out.set(r.value, 32 - r.value.length);
    out.set(s.value, 64 - s.value.length);
    return out;
  }
  throw new VapidError(`Beklenmeyen ECDSA imza uzunluğu: ${signature.length}`);
}

// ---------------------------------------------------------------------------
// VAPID JWT
// ---------------------------------------------------------------------------

/** RFC 8292: `sub` ya `mailto:` ya da `https://` olmalı. */
export function isValidVapidSubject(subject: string): boolean {
  const value = subject.trim();
  if (!value) return false;
  if (/^mailto:[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)) return true;
  try {
    const url = new URL(value);
    return url.protocol === "https:" && !!url.host;
  } catch (_) {
    return false;
  }
}

export interface VapidHeaderInput {
  /** Audit (`sub`): `mailto:` veya `https://` imzalı origin. */
  subject: string;
  /** Push endpoint'inin origin'i, ör. `https://fcm.googleapis.com`. */
  audience: string;
  privateKey: CryptoKey;
  /** Test/denetim için; üretimde `Date.now()` kullanılır. */
  nowMs?: number;
  /** Token ömrü (saniye). RFC 8292: 24 saatten kısa olmalı. */
  ttlSeconds?: number;
}

/** VAPID için imzalı ES256 JWT üretir (RFC 8292 §2). */
export async function buildVapidJwt(input: VapidHeaderInput): Promise<string> {
  const { subject, audience, privateKey } = input;
  if (!isValidVapidSubject(subject)) {
    throw new VapidError("VAPID_SUBJECT 'mailto:' veya 'https://' formatında olmalı");
  }
  let aud: string;
  try {
    const url = new URL(audience);
    if (url.protocol !== "https:") throw new Error("https gerekli");
    aud = url.origin;
  } catch (_) {
    throw new VapidError("VAPID audience (push endpoint origin) geçersiz");
  }

  const now = Math.floor((input.nowMs ?? Date.now()) / 1000);
  const ttl = Math.min(Math.max(input.ttlSeconds ?? 12 * 3600, 60), 24 * 3600 - 1);

  const headerB64 = bytesToBase64Url(new TextEncoder().encode(JSON.stringify({ typ: "JWT", alg: "ES256" })));
  const payloadB64 = bytesToBase64Url(new TextEncoder().encode(JSON.stringify({ aud, exp: now + ttl, sub: subject.trim() })));
  const signingInput = new TextEncoder().encode(`${headerB64}.${payloadB64}`);

  let raw: Uint8Array;
  try {
    raw = new Uint8Array(
      await crypto.subtle.sign(
        ECDSA_PARAMS,
        privateKey,
        signingInput as unknown as BufferSource,
      ),
    );
  } catch (_) {
    throw new VapidError("ECDSA imzası üretilemedi");
  }
  return `${headerB64}.${payloadB64}.${bytesToBase64Url(normalizeEcdsaSignature(raw))}`;
}

/** `Authorization: vapid t=<jwt>, k=<publicKey>` başlığını üretir. */
export async function buildVapidAuthorization(
  input: Omit<VapidHeaderInput, "privateKey"> & { privateKey: CryptoKey; publicKey: string },
): Promise<string> {
  const jwt = await buildVapidJwt(input);
  return `vapid t=${jwt}, k=${input.publicKey}`;
}

/** Test/doğrulama amaçlı JWT segment çözücü. */
export function decodeJwtSegment<T = Record<string, unknown>>(segment: string): T {
  return JSON.parse(new TextDecoder().decode(base64UrlToBytes(segment))) as T;
}

// ---------------------------------------------------------------------------
// Push gövdesi (payload) doğrulama
// ---------------------------------------------------------------------------

export interface PushPayloadInput {
  title: string;
  body: string;
  data?: Record<string, unknown>;
}

export interface PreparedPushPayload {
  payload: PushPayloadInput;
  body: string;
}

/**
 * Gönderilecek JSON'u doğrular ve boyut sınırına getirir.
 * - `title`/`body` tip ve uzunluk kontrolü
 * - `data` yalnızca düz JSON değerleri (derin/ döngüsel yapı reddedilir)
 * - 4096 baytı aşarsa önce `data` düşürülür, gerekirse `body` kırpılır.
 */
export function preparePushPayload(input: PushPayloadInput): PreparedPushPayload {
  if (!input || typeof input !== "object") throw new VapidError("push payload zorunlu");
  if (typeof input.title !== "string" || !input.title.trim()) throw new VapidError("push title zorunlu metin olmalı");
  if (typeof input.body !== "string") throw new VapidError("push body metin olmalı");
  if (input.title.length > 120) throw new VapidError("push title en fazla 120 karakter olabilir");

  const payload: PushPayloadInput = {
    title: input.title.trim(),
    body: input.body.trim().slice(0, MAX_PUSH_BODY_CHARS),
  };

  if (input.data !== undefined && input.data !== null) {
    if (typeof input.data !== "object" || Array.isArray(input.data)) {
      throw new VapidError("push data nesne olmalı");
    }
    // Derinlik sınırlı düz kopya: yalnızca JSON-uyumlu temel tipler.
    const flat: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(input.data as Record<string, unknown>).slice(0, 20)) {
      if (typeof value === "string") flat[key.slice(0, 40)] = value.slice(0, 200);
      else if (typeof value === "number" && Number.isFinite(value)) flat[key.slice(0, 40)] = value;
      else if (typeof value === "boolean") flat[key.slice(0, 40)] = value;
      else if (value === null) flat[key.slice(0, 40)] = null;
      // nesne/dizi/NaN: bilinçli olarak düşürülür
    }
    if (Object.keys(flat).length > 0) payload.data = flat;
  }

  let body = JSON.stringify(payload);
  if (body.length > MAX_PUSH_PAYLOAD_BYTES && payload.data) {
    delete payload.data;
    body = JSON.stringify(payload);
  }
  if (body.length > MAX_PUSH_PAYLOAD_BYTES) {
    const overflow = body.length - MAX_PUSH_PAYLOAD_BYTES;
    payload.body = payload.body.slice(0, Math.max(0, payload.body.length - overflow - 3));
    body = JSON.stringify(payload);
  }
  if (body.length > MAX_PUSH_PAYLOAD_BYTES) throw new VapidError("push payload çok büyük");
  return { payload, body };
}
