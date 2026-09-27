/**
 * VAPID/Web Push yardımcıları için Deno testleri.
 *
 * Çalıştırma:
 *   deno test --allow-env supabase/functions/_shared/vapid_test.ts
 *
 * Test anahtarı: bilinen/deterministik bir P-256 çifti. Skaler 0x01..0x20'dir,
 * dolayısıyla public key `deriveVapidPublicKey()` ile **gerçekten** türetilir ve
 * JWT imzası `crypto.subtle.verify()` ile doğrulanır. Anahtar üretiminde yanlış
 * bir değer yazılırsa test anında düşer (sabit bir base64 string "yapıştırmak"
 * yerine türetilmiş değer kullanılır).
 */

import {
  base64UrlToBytes,
  buildVapidAuthorization,
  buildVapidJwt,
  bytesToBase64Url,
  decodeJwtSegment,
  deriveVapidPublicKey,
  importVapidPrivateKey,
  isValidVapidSubject,
  MAX_PUSH_PAYLOAD_BYTES,
  minimalSec1,
  normalizeEcdsaSignature,
  preparePushPayload,
  rawScalarToPkcs8,
  sec1ToPkcs8,
  VapidError,
} from "./vapid.ts";

/** Bilinen test skaler'i: 0x01, 0x02, ... 0x20 (32 bayt). */
const TEST_SCALAR = new Uint8Array(32);
for (let i = 0; i < 32; i++) TEST_SCALAR[i] = i + 1;
const TEST_SCALAR_B64URL = bytesToBase64Url(TEST_SCALAR);

const FIXED_NOW_MS = 1_757_000_000_000; // 2025-09-27T00:53:20Z
const AUDIENCE = "https://fcm.googleapis.com";
const SUBJECT = "mailto:ops@calorix.app";

function toPem(label: string, der: Uint8Array): string {
  const std = bytesToBase64Url(der).replace(/-/g, "+").replace(/_/g, "/");
  const padded = std + "=".repeat((4 - (std.length % 4)) % 4);
  return `-----BEGIN ${label}-----\n${padded.replace(/(.{64})/g, "$1\n")}\n-----END ${label}-----\n`;
}

async function publicKeyOf(privateKey: CryptoKey): Promise<CryptoKey> {
  const jwk = await crypto.subtle.exportKey("jwk", privateKey);
  return await crypto.subtle.importKey(
    "jwk",
    { kty: "EC", crv: jwk.crv!, x: jwk.x!, y: jwk.y! },
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["verify"],
  );
}

// Deno, `verify(alg, key, signature, data, extraAlg)` 5 argümanlı WebCrypto
// imzasını destekler (tip tanımı 4 argüman bildirdiği için daraltma).
const ECDSA_PARAMS = { name: "ECDSA", hash: "SHA-256" } as unknown as AlgorithmIdentifier;

function verify(
  key: CryptoKey,
  signingInput: Uint8Array,
  signature: Uint8Array,
): Promise<boolean> {
  return (
    crypto.subtle.verify as unknown as (
      algorithm: AlgorithmIdentifier,
      key: CryptoKey,
      signature: BufferSource,
      data: BufferSource,
      extra?: AlgorithmIdentifier,
    ) => Promise<boolean>
  )(
    ECDSA_PARAMS,
    key,
    signature as unknown as BufferSource,
    signingInput as unknown as BufferSource,
    ECDSA_PARAMS,
  );
}

function assert(condition: unknown, message = "assertion başarısız"): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals<T>(actual: T, expected: T, message?: string): void {
  const a = JSON.stringify(actual);
  const b = JSON.stringify(expected);
  if (a !== b) throw new Error(message ?? `beklenen ${b}, alınan ${a}`);
}

function assertBytes(actual: Uint8Array, expected: Uint8Array, message?: string): void {
  if (actual.length !== expected.length) {
    throw new Error(message ?? `beklenen ${expected.length} bayt, alınan ${actual.length}`);
  }
  for (let i = 0; i < actual.length; i++) {
    if (actual[i] !== expected[i]) throw new Error(message ?? `bayt ${i} farklı: ${actual[i]} != ${expected[i]}`);
  }
}

function assertThrows(fn: () => unknown, ctor: new (...args: never[]) => Error): void {
  try {
    fn();
  } catch (error) {
    assert(error instanceof ctor, `beklenen ${ctor.name}, alınan ${(error as Error).name}`);
    return;
  }
  throw new Error(`${ctor.name} bekleniyordu, istisna atılmadı`);
}

async function assertRejects(fn: () => Promise<unknown>, ctor: new (...args: never[]) => Error): Promise<void> {
  try {
    await fn();
  } catch (error) {
    assert(error instanceof ctor, `beklenen ${ctor.name}, alınan ${(error as Error).name}`);
    return;
  }
  throw new Error(`${ctor.name} bekleniyordu, istisna atılmadı`);
}

// ---------------------------------------------------------------------------

Deno.test("base64url gidiş-dönüş (dolgu/boşluk toleranslı)", () => {
  const bytes = new Uint8Array([0, 1, 250, 251, 252, 253, 254, 255]);
  const b64 = bytesToBase64Url(bytes);
  assert(!b64.includes("=") && !b64.includes("+") && !b64.includes("/"), "base64url karakter kümesi");
  assertBytes(base64UrlToBytes(b64), bytes);
  assertBytes(base64UrlToBytes(`  ${b64}\n`), bytes);
  assertBytes(base64UrlToBytes(`${b64}==`), bytes);
});

Deno.test("PKCS#8 sarmalayıcı doğru yapı üretir", () => {
  const der = rawScalarToPkcs8(TEST_SCALAR);
  assertEquals(der[0], 0x30, "dış SEQUENCE");
  assertEquals(der[1], der.length - 2, "SEQUENCE uzunluk baytı içerik uzunluğu olmalı");
  // PrivateKeyInfo = version(3) + AlgorithmIdentifier(21) + OCTET STRING{ SEC1 }
  // PrivateKeyInfo = version(3) + AlgorithmIdentifier(21) + OCTET STRING{ SEC1 }
  assertEquals(der[26], 0x04, "privateKey OCTET STRING olmalı");
  assertEquals(der[27], der.length - 28, "OCTET STRING uzunluğu");
  // iç içe SEC1: SEQUENCE { INTEGER 1, OCTET STRING(32) skaler }
  assertEquals(der[28], 0x30);
  assertEquals(der[29], der.length - 30, "SEC1 SEQUENCE uzunluğu");
  assertEquals(Array.from(der.slice(30, 35)), [0x02, 0x01, 0x01, 0x04, 0x20]);
  assertBytes(der.slice(der.length - 32), TEST_SCALAR, "skaler DER'in son 32 baytında olmalı");
  assertThrows(() => rawScalarToPkcs8(new Uint8Array(31)), VapidError);
});

Deno.test("base64url 32 bayt özel anahtar içe aktarılır ve public key türetilir", async () => {
  const key = await importVapidPrivateKey(TEST_SCALAR_B64URL);
  assertEquals(key.type, "private");
  assertEquals(key.algorithm.name, "ECDSA");
  const pub = await deriveVapidPublicKey(key);
  const pubBytes = base64UrlToBytes(pub);
  assertEquals(pubBytes.length, 65, "uncompressed P-256 noktası 65 bayt olmalı");
  assertEquals(pubBytes[0], 0x04, "0x04 (uncompressed) işareti olmalı");
  // Deterministik: aynı skaler her zaman aynı public key'i verir.
  assertEquals(pub, await deriveVapidPublicKey(await importVapidPrivateKey(TEST_SCALAR_B64URL)));
});

Deno.test("PKCS#8 PEM özel anahtar içe aktarılır", async () => {
  const fromPem = await importVapidPrivateKey(toPem("PRIVATE KEY", rawScalarToPkcs8(TEST_SCALAR)));
  const fromRaw = await importVapidPrivateKey(TEST_SCALAR_B64URL);
  assertEquals(await deriveVapidPublicKey(fromPem), await deriveVapidPublicKey(fromRaw));
});

/** `openssl ecparam -name prime256v1 -genkey` çıktısının DER yapısını üretir. */
function opensslStyleSec1(scalar: Uint8Array): Uint8Array {
  // SEQUENCE { INTEGER 1, OCTET STRING scalar, [0] parameters, [1] publicKey }
  const chunks: number[][] = [
    [0x02, 0x01, 0x01], // INTEGER 1
    [0x04, scalar.length, ...scalar], // OCTET STRING
    [0xa0, 0x0a, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07], // [0] parameters
    // [1] publicKey — kasıtlı olarak **geçersiz** nokta (skalerle uyumsuz)
    [0xa1, 0x44, 0x03, 0x42, 0x00, ...Array.from({ length: 65 }, (_, i) => (i * 7) % 251)],
  ];
  const body = chunks.flat();
  const der = new Uint8Array(2 + body.length);
  der[0] = 0x30;
  der[1] = body.length;
  der.set(body, 2);
  return der;
}

Deno.test("SEC1 (EC PRIVATE KEY) PEM içe aktarılır", async () => {
  // openssl biçiminde tam SEC1 (opsiyonel [0]/[1] alanları dahil)
  const sec1 = opensslStyleSec1(TEST_SCALAR);
  const key = await importVapidPrivateKey(toPem("EC PRIVATE KEY", sec1));
  const expected = await importVapidPrivateKey(TEST_SCALAR_B64URL);
  assertEquals(await deriveVapidPublicKey(key), await deriveVapidPublicKey(expected));
  // openssl'in [1] alanındaki public key'i **kullanılmaz**: skaler doğrudan kullanılır.
  const minimal = minimalSec1(TEST_SCALAR);
  assertEquals(sec1ToPkcs8(minimal).length, rawScalarToPkcs8(TEST_SCALAR).length);
  assertEquals(await deriveVapidPublicKey(await importVapidPrivateKey(toPem("EC PRIVATE KEY", minimal))),
    await deriveVapidPublicKey(expected));
});

Deno.test("SEC1: [1] alanındaki yanlış public key skalerin önüne geçmez", async () => {
  // openssl'in yaptığı gibi SEQUENCE'un son 32 baytını skaler sanılan bir
  // uygulama yanlış anahtar üretirdi; doğru davranış skaler alanını okumaktır.
  const sec1 = opensslStyleSec1(TEST_SCALAR);
  const wrong = await importVapidPrivateKey(toPem("EC PRIVATE KEY", sec1));
  const correct = await importVapidPrivateKey(TEST_SCALAR_B64URL);
  const wrongIfLast32 = await importVapidPrivateKey(
    toPem("EC PRIVATE KEY", sec1.slice(0, sec1.length - 65)),
  );
  assertEquals(await deriveVapidPublicKey(wrong), await deriveVapidPublicKey(correct));
  assertEquals(
    await deriveVapidPublicKey(wrongIfLast32),
    await deriveVapidPublicKey(correct),
    "kırpılmış SEC1 de aynı skalerden türemeli",
  );
  // Sanılan "yanlış" skaler gerçekten farklı bir anahtar üretir: testin
  // anlamlı olması için iki değerin aynı olmadığını da doğrularız.
  const fake = await deriveVapidPublicKey(
    await importVapidPrivateKey(bytesToBase64Url(sec1.slice(sec1.length - 32))),
  );
  assert(
    fake !== (await deriveVapidPublicKey(correct)),
    "SEC1 son 32 baytı ([1] publicKey) skalerden farklı olmalı",
  );
});

Deno.test("bozuk/hatalı anahtar girdileri sessizce geçmez", async () => {
  await assertRejects(() => importVapidPrivateKey(""), VapidError);
  await assertRejects(() => importVapidPrivateKey("    "), VapidError);
  // 65 baytlık public key özel anahtar olarak verilmiş.
  const pubOnly = await deriveVapidPublicKey(await importVapidPrivateKey(TEST_SCALAR_B64URL));
  await assertRejects(() => importVapidPrivateKey(pubOnly), VapidError);
  // Public key PEM'i (SubjectPublicKeyInfo)
  await assertRejects(() => importVapidPrivateKey(toPem("PUBLIC KEY", derFromPoint(pubOnly))), VapidError);
  // Rastgele metin / yanlış uzunluk
  await assertRejects(() => importVapidPrivateKey("not-a-key"), VapidError);
  await assertRejects(() => importVapidPrivateKey(bytesToBase64Url(new Uint8Array(16))), VapidError);
  // Yarım PEM
  await assertRejects(() => importVapidPrivateKey("-----BEGIN PRIVATE KEY-----\nAAAA"), VapidError);
});

/** base64url 65 baytlık noktadan (yalnızca test yardımcısı) SubjectPublicKeyInfo DER üretir. */
function derFromPoint(pointB64Url: string): Uint8Array {
  const point = base64UrlToBytes(pointB64Url);
  // SEQUENCE { SEQUENCE { OID ecPublicKey, OID prime256v1 }, BIT STRING <point> }
  return new Uint8Array([
    0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a, 0x86, 0x48,
    0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00, ...point,
  ]);
}

Deno.test("VAPID subject doğrulaması (RFC 8292)", () => {
  assert(isValidVapidSubject("mailto:ops@calorix.app"));
  assert(isValidVapidSubject("https://calorix.app"));
  assert(isValidVapidSubject("https://calorix.app/contact"));
  assert(!isValidVapidSubject("ops@calorix.app"), "mailto: öneki zorunlu");
  assert(!isValidVapidSubject("http://calorix.app"), "http reddedilir");
  assert(!isValidVapidSubject("mailto:"));
  assert(!isValidVapidSubject(""));
});

Deno.test("ECDSA imzası ham R||S (64 bayt) olarak normalize edilir", () => {
  const raw = new Uint8Array(64).fill(7);
  assertBytes(normalizeEcdsaSignature(raw), raw);

  // DER varyant: r'nin başında 0x00 dolgu, s 31 bayt.
  const der = new Uint8Array([
    0x30, 0x44, 0x02, 0x21, 0x00, ...new Array(32).fill(0xaa), 0x02, 0x1f, ...new Array(31).fill(0xbb),
  ]);
  const out = normalizeEcdsaSignature(der);
  assertEquals(out.length, 64);
  assertEquals(out[0], 0xaa);
  assertEquals(out[31], 0xaa);
  assertEquals(out[32], 0x00, "s 32 bayta hizalı yazılmalı");
  assertEquals(out[33], 0xbb);
  assertEquals(out[63], 0xbb);

  assertThrows(() => normalizeEcdsaSignature(new Uint8Array(32)), VapidError);
  assertThrows(() => normalizeEcdsaSignature(new Uint8Array([0x30, 0x06, 0x02, 0x01, 0x01, 0x02])), VapidError);
});

Deno.test("VAPID JWT: typ/alg/aud/exp/sub ve imza doğrulanır", async () => {
  const key = await importVapidPrivateKey(TEST_SCALAR_B64URL);
  const jwt = await buildVapidJwt({
    subject: SUBJECT,
    audience: "https://fcm.googleapis.com/some/path?q=1",
    privateKey: key,
    nowMs: FIXED_NOW_MS,
    ttlSeconds: 3600,
  });

  const parts = jwt.split(".");
  assertEquals(parts.length, 3, "JWT üç segment içermeli");

  const header = decodeJwtSegment<{ typ: string; alg: string }>(parts[0]);
  assertEquals(header.typ, "JWT");
  assertEquals(header.alg, "ES256");

  const payload = decodeJwtSegment<{ aud: string; exp: number; sub: string }>(parts[1]);
  assertEquals(payload.aud, AUDIENCE, "aud yol/sorgu dışında origin olmalı");
  assertEquals(payload.exp, Math.floor(FIXED_NOW_MS / 1000) + 3600);
  assert(payload.exp === Math.floor(FIXED_NOW_MS / 1000) + 3600, "exp = now + ttl");
  assert(payload.exp - Math.floor(FIXED_NOW_MS / 1000) < 24 * 3600, "exp 24 saatten kısa olmalı");
  assertEquals(payload.sub, SUBJECT);
  assertEquals(Object.keys(payload).sort(), ["aud", "exp", "sub"]);

  const signature = base64UrlToBytes(parts[2]);
  assertEquals(signature.length, 64, "ES256 imzası ham 64 bayt olmalı (DER değil)");

  const verifyKey = await publicKeyOf(key);
  // İmza girdisi ASCII "b64.b64" metnidir; base64 *kod* değildir, düz bayt kullanılır.
  const ascii = (s: string) => new TextEncoder().encode(s);
  const signingInput = ascii(parts[0] + "." + parts[1]);
  assert(await verify(verifyKey, signingInput, signature), "imza public key ile doğrulanmalı");

  // Kurcalanmış gövde imzayı geçersiz kılmalı
  const tampered = bytesToBase64Url(
    new TextEncoder().encode(JSON.stringify({ aud: AUDIENCE, exp: payload.exp + 1, sub: SUBJECT })),
  );
  assert(
    !await verify(verifyKey, ascii(parts[0] + "." + tampered), signature),
    "kurcalanmış gövde reddedilmeli",
  );

  // Farklı anahtarla imza doğrulanmamalı
  const otherKey = await publicKeyOf(await importVapidPrivateKey(bytesToBase64Url(new Uint8Array(32).fill(9))));
  assert(!await verify(otherKey, signingInput, signature), "yanlış public key reddedilmeli");
});

Deno.test("VAPID JWT: üretimde exp gelecekte olur (now + 12 saat)", async () => {
  const key = await importVapidPrivateKey(TEST_SCALAR_B64URL);
  const jwt = await buildVapidJwt({ subject: SUBJECT, audience: AUDIENCE, privateKey: key });
  const payload = decodeJwtSegment<{ exp: number }>(jwt.split(".")[1]);
  const now = Math.floor(Date.now() / 1000);
  assert(payload.exp > now, "exp gelecekte olmalı");
  assert(payload.exp - now <= 12 * 3600, "ttl 12 saatle sınırlı olmalı");
});

Deno.test("VAPID JWT: geçersiz subject / audience reddedilir", async () => {
  const key = await importVapidPrivateKey(TEST_SCALAR_B64URL);
  await assertRejects(
    () => buildVapidJwt({ subject: "ops@calorix.app", audience: AUDIENCE, privateKey: key }),
    VapidError,
  );
  await assertRejects(
    () => buildVapidJwt({ subject: SUBJECT, audience: "fcm.googleapis.com", privateKey: key }),
    VapidError,
  );
  await assertRejects(
    () => buildVapidJwt({ subject: SUBJECT, audience: "http://fcm.googleapis.com", privateKey: key }),
    VapidError,
  );
});

Deno.test("Authorization başlığı RFC 8292 biçiminde", async () => {
  const key = await importVapidPrivateKey(TEST_SCALAR_B64URL);
  const publicKey = await deriveVapidPublicKey(key);
  const header = await buildVapidAuthorization({
    subject: SUBJECT,
    audience: AUDIENCE,
    privateKey: key,
    publicKey,
    nowMs: FIXED_NOW_MS,
  });
  const match = /^vapid t=([A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+), k=([A-Za-z0-9_-]+)$/.exec(header);
  assert(match, `başlık biçimi geçersiz: ${header}`);
  assertEquals(match![2], publicKey);
  assertEquals(base64UrlToBytes(match![2]).length, 65);
});

Deno.test("push payload şeması ve boyut sınırı", () => {
  const ok = preparePushPayload({ title: "  Öğün Hatırlatması  ", body: "  Bir şeyler ye  " });
  assertEquals(ok.payload.title, "Öğün Hatırlatması");
  assertEquals(ok.payload.body, "Bir şeyler ye");
  assert(ok.body.length <= MAX_PUSH_PAYLOAD_BYTES);

  assertThrows(() => preparePushPayload({ title: 42 as unknown as string, body: "x" }), VapidError);
  assertThrows(() => preparePushPayload({ title: "x", body: null as unknown as string }), VapidError);
  assertThrows(() => preparePushPayload({ title: "   ", body: "x" }), VapidError);
  assertThrows(() => preparePushPayload({ title: "x".repeat(200), body: "x" }), VapidError);
  assertThrows(
    () => preparePushPayload({ title: "x", body: "x", data: [1, 2] as unknown as Record<string, unknown> }),
    VapidError,
  );

  const long = preparePushPayload({ title: "Başlık", body: "a".repeat(4000) });
  assert(long.body.length <= MAX_PUSH_PAYLOAD_BYTES, "uzun gövde kırpılmalı");

  const withData = preparePushPayload({
    title: "Başlık",
    body: "k".repeat(500),
    data: Object.fromEntries(Array.from({ length: 20 }, (_, i) => [`k${i}`, "v".repeat(500)])),
  });
  assert(withData.body.length <= MAX_PUSH_PAYLOAD_BYTES, "aşırı büyük data düşürülmeli");

  const cleaned = preparePushPayload({
    title: "t",
    body: "b",
    data: { ok: "yes", nested: { a: 1 }, bad: NaN, many: 3 } as Record<string, unknown>,
  });
  assertEquals(Object.keys(cleaned.payload.data!).sort(), ["many", "ok"]);
  assertEquals(cleaned.payload.data!.ok, "yes");
  assertEquals(cleaned.payload.data!.many, 3);
});
