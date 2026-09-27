/**
 * Web Push `aes128gcm` şifreleme/çözme (RFC 8188 + RFC 8291) Deno testleri.
 *
 * Çalıştırma:
 *   deno test --allow-env supabase/functions/_shared/web_push_crypto_test.ts
 *
 * En kritik test "RFC 8291 Ek A vektörleri"dir: modülün ürettiği `ecdh_secret`,
 * `PRK_key`, `IKM`, `PRk`, `CEK` ve `NONCE` değerleri RFC'nin **kendi ara
 * değerleriyle** bayt bayt karşılaştırılır. Bu, "şifreliyoruz" iddiasının
 * tarayıcının açacağı anlamına geldiğinin en güçlü kanıtıdır ve elle yazılan
 * HKDF zincirindeki herhangi bir sapmayı anında yakalar.
 *
 * İkinci bölüm, gerçek bir tarayıcı aboneliğinin `p256dh`/`auth` çiftini taklit
 * eden uçtan uca gidiş-dönüş testleri yapar.
 */

// Harici test kütüphanesi kullanılmaz (bkz. `vapid_test.ts`): edge function
// dağıtımında `deno.land` erişimi olmayabilir ve `deno lint`'in
// `no-import-prefix` kuralına takılır. Bu yüzden assertion'lar yerelde.
function assertEquals<T>(actual: T, expected: T, message?: string): void {
  const a = JSON.stringify(actual);
  const b = JSON.stringify(expected);
  if (a !== b) throw new Error(message ?? `beklenen ${b}, alınan ${a}`);
}

import {
  AES128GCM_ENCODING,
  buildKeyInfo,
  CEK_INFO,
  bytesToBase64Url,
  decryptPushBody,
  DEFAULT_RECORD_SIZE,
  encryptPushBody,
  importP256PrivateKey,
  importP256PublicKey,
  exportP256PublicKey,
  deriveEcdhSecret,
  hkdfExpand,
  hkdfExtract,
  MAX_ENCRYPTED_PAYLOAD_BYTES,
  NONCE_INFO,
  PushEncryptionError,
  SALT_BYTES,
} from "./web_push_crypto.ts";

// ---------------------------------------------------------------------------
// RFC 8291 §5 + Ek A çalışma örneği (bilinen/doğrulanmış vektörler)
// ---------------------------------------------------------------------------

const RFC_UA_PRIVATE = "q1dXpw3UpT5VOmu_cf_v6ih07Aems3njxI-JWgLcM94";
const RFC_UA_PUBLIC =
  "BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4";
const RFC_AS_PRIVATE = "yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw";
const RFC_AS_PUBLIC =
  "BP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8";
const RFC_AUTH_SECRET = "BTBZMqHH6r4Tts7J_aSIgg";
const RFC_SALT = "DGv6ra1nlYgDCS1FRnbzlw";
const RFC_PLAINTEXT = "When I grow up, I want to be a watermelon";

/** RFC Ek A'daki ara değerler (base64url). */
const RFC_IKM = "S4lYMb_L0FxCeq0WhDx813KgSYqU26kOyzWUdsXYyrg";
const RFC_CEK = "oIhVW04MRdy2XN9CiKLxTg";
const RFC_NONCE = "4h_95klXJ5E_qnoN";
/** RFC Ek A'daki `key_info` (satır kaydırmaları birleştirilmiş): "WebPush: info" + 0x00 + ua + as */
const RFC_KEY_INFO =
  "V2ViUHVzaDogaW5mbwAEJXGyvs3942BVGq8e0PTNNmwRzr5VX4m8t7GGpTM5FzFo7OLr4BhZe9MEebhuPI-OztV3ylkYfpJGmQ22ggCLDgT-M_SrDepxkU21WCP3O1SUj0EwbZIHMtu5pZpTKGSCIA5Zent7wmC6HCJ5mFgJkuk5cwAvMBKiiujwa7t45ewP";
/** Ek A'daki ara değerler 32 bayttır (SHA-256 çıktısı). */
const RFC_ECDH_SECRET = "kyrL1jIIOHEzg3sM2ZWRHDRB62YACZhhSlknJ672kSs";
const RFC_PRK_KEY = "Snr3JMxaHVDXHWJn5wdC52WjpCtd2EIEGBykDcZW32k";
const RFC_PRK = "09_eUZGrsvxChDCGRCdkLiDXrReGOEVeSCdCcPBSJSc";

function fromB64Url(value: string): Uint8Array {
  const std = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = std + "=".repeat((4 - (std.length % 4)) % 4);
  const binary = atob(padded);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

Deno.test("RFC 8291 Ek A: ECDH ortak gizli tam olarak RFC değerini üretir", async () => {
  const asPrivate = await importP256PrivateKey(fromB64Url(RFC_AS_PRIVATE));
  const uaPublic = await importP256PublicKey(RFC_UA_PUBLIC);
  const secret = await deriveEcdhSecret(asPrivate, uaPublic);
  assertEquals(bytesToBase64Url(secret), RFC_ECDH_SECRET);
});

Deno.test("RFC 8291 Ek A: public key türetme 65 bayt ve doğru", async () => {
  const asPrivate = await importP256PrivateKey(fromB64Url(RFC_AS_PRIVATE));
  const jwk = await crypto.subtle.exportKey("jwk", asPrivate);
  const asPublic = await crypto.subtle.importKey(
    "jwk",
    { kty: "EC", crv: jwk.crv!, x: jwk.x!, y: jwk.y! },
    { name: "ECDH", namedCurve: "P-256" },
    true,
    [],
  );
  const exported = await exportP256PublicKey(asPublic);
  assertEquals(exported.length, 65);
  assertEquals(exported[0], 0x04);
  assertEquals(bytesToBase64Url(exported), RFC_AS_PUBLIC);
});

Deno.test("RFC 8291 §3.3: key_info = 'WebPush: info' || 0x00 || ua || as (RFC metniyle birebir)", () => {
  const info = buildKeyInfo(fromB64Url(RFC_UA_PUBLIC), fromB64Url(RFC_AS_PUBLIC));
  // "WebPush: info" 13 bayt + 1 NUL ayıracı + 65 (ua) + 65 (as)
  assertEquals(info.length, 13 + 1 + 65 + 65);
  const prefix = new TextDecoder().decode(info.subarray(0, 13));
  assertEquals(prefix, "WebPush: info");
  assertEquals(info[13], 0x00, "NUL ayırıcı key_info'nin public key'lerden ÖNCE gelmeli");
  // RFC Ek A key_info'nin **tamamı** (satır kaydırmaları kaldırılmış).
  assertEquals(bytesToBase64Url(info), RFC_KEY_INFO);
});

Deno.test("RFC 8291 Ek A: IKM/PRK/CEK/NONCE zinciri bayt bayt RFC ile aynı", async () => {
  // Zinciri bağımsız olarak kurup modülün ürettiği debug değerleriyle karşılaştır.
  const ecdh = fromB64Url(RFC_ECDH_SECRET);
  const auth = fromB64Url(RFC_AUTH_SECRET);
  const salt = fromB64Url(RFC_SALT);

  const prkKey = await hkdfExtract(auth, ecdh);
  assertEquals(bytesToBase64Url(prkKey), RFC_PRK_KEY, "PRK_key = HKDF-Extract(auth, ecdh)");

  const ikm = await hkdfExpand(prkKey, buildKeyInfo(fromB64Url(RFC_UA_PUBLIC), fromB64Url(RFC_AS_PUBLIC)), 32);
  assertEquals(bytesToBase64Url(ikm), RFC_IKM, "IKM = HKDF-Expand(PRK_key, key_info, 32)");

  const prk = await hkdfExtract(salt, ikm);
  assertEquals(bytesToBase64Url(prk), RFC_PRK, "PRK = HKDF-Extract(salt, IKM)");

  const cek = await hkdfExpand(prk, CEK_INFO, 16);
  assertEquals(bytesToBase64Url(cek), RFC_CEK, "CEK = HKDF-Expand(PRK, cek_info, 16)");

  const nonce = await hkdfExpand(prk, NONCE_INFO, 12);
  assertEquals(bytesToBase64Url(nonce), RFC_NONCE, "NONCE = HKDF-Expand(PRK, nonce_info, 12)");
});

Deno.test("RFC 8291 §5: örnek mesaj şifrelenir ve çözülür (gidiş-dönüş)", async () => {
  const asPrivate = await importP256PrivateKey(fromB64Url(RFC_AS_PRIVATE));
  const jwk = await crypto.subtle.exportKey("jwk", asPrivate);
  const asPublicFromPrivate = await crypto.subtle.importKey(
    "jwk",
    { kty: "EC", crv: jwk.crv!, x: jwk.x!, y: jwk.y! },
    { name: "ECDH", namedCurve: "P-256" },
    true,
    [],
  );

  const encrypted = await encryptPushBody({
    authSecret: RFC_AUTH_SECRET,
    p256dh: RFC_UA_PUBLIC,
    plaintext: RFC_PLAINTEXT,
    salt: fromB64Url(RFC_SALT),
    applicationServerKeyPair: { privateKey: asPrivate, publicKey: asPublicFromPrivate },
  });

  // Türetilen ara değerler RFC ile birebir aynı olmalı.
  assertEquals(bytesToBase64Url(encrypted.debug.ikm), RFC_IKM);
  assertEquals(bytesToBase64Url(encrypted.debug.prk), RFC_PRK);
  assertEquals(bytesToBase64Url(encrypted.debug.cek), RFC_CEK);
  assertEquals(bytesToBase64Url(encrypted.debug.nonce), RFC_NONCE);

  // Başlıklar.
  assertEquals(encrypted.headers["Content-Encoding"], AES128GCM_ENCODING);
  assertEquals(encrypted.headers["Content-Type"], "application/octet-stream");
  assertEquals(encrypted.headers["Crypto-Key"], `dh=${RFC_AS_PUBLIC}`);

  // Gövde yapısı: salt(16) || rs(4) || idlen(1) || ciphertext(+16 tag)
  assertEquals(encrypted.body.length, 21 + RFC_PLAINTEXT.length + 1 + 16);
  assertEquals(bytesToBase64Url(encrypted.body.subarray(0, SALT_BYTES)), RFC_SALT);
  const rs = new DataView(
    encrypted.body.buffer,
    encrypted.body.byteOffset,
    encrypted.body.byteLength,
  ).getUint32(16, false);
  assertEquals(rs, DEFAULT_RECORD_SIZE, "rs = 4096 (büyük endian)");
  assertEquals(encrypted.body[20], 0, "idlen = 0 (keyid yok, dh başlığında)");

  // Gidiş-dönüş: gerçek istemci (RFC'nin UA özel anahtarı) çözer.
  const decrypted = await decryptPushBody(
    encrypted,
    RFC_AUTH_SECRET,
    RFC_UA_PUBLIC,
    await importP256PrivateKey(fromB64Url(RFC_UA_PRIVATE)),
  );
  assertEquals(decrypted.plaintext, RFC_PLAINTEXT);
  assertEquals(decrypted.recordCount, 1, "RFC 8291 §4: tek kayıt");
  assertEquals(decrypted.idlen, 0);
});

// ---------------------------------------------------------------------------
// Tarayıcı abonelik taklidi: gerçek bir `p256dh`/`auth` çifti üretilir
// (W3C Push API "Generating an auth secret" akışı birebir)
// ---------------------------------------------------------------------------

interface TestSubscription {
  p256dh: string;
  auth: string;
  privateKey: CryptoKey;
}

/** W3C Push API'deki `generateAuthSecret()` ile aynı davranış. */
async function createBrowserLikeSubscription(): Promise<TestSubscription> {
  const keyPair = await crypto.subtle.generateKey(
    { name: "ECDH", namedCurve: "P-256" },
    true,
    ["deriveBits"],
  ) as CryptoKeyPair;

  // Tarayıcı: ecdhSecret = ECDH(ua_private, as_public) — RFC 8291 §3.4
  // "For a user agent: ecdh_secret = ECDH(ua_private, as_public)".
  // Bu yüzden **kendi özel** anahtarımız, sunucunun public key'i ile çarpılır.
  const asPublic = await importP256PublicKey(RFC_AS_PUBLIC);
  const ecdhSecret = await deriveEcdhSecret(keyPair.privateKey, asPublic);

  // auth = HMAC-SHA-256(key_pair_private, ecdhSecret) -> ilk 16 bayt
  // (Push API: "the first 16 octets of the HMAC output")
  const hmacKey = await crypto.subtle.importKey(
    "raw",
    await exportRawPrivateScalar(keyPair.privateKey) as unknown as BufferSource,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = new Uint8Array(
    await crypto.subtle.sign("HMAC", hmacKey, ecdhSecret as unknown as BufferSource),
  ).slice(0, 16);

  return {
    p256dh: bytesToBase64Url(await exportP256PublicKey(keyPair.publicKey)),
    auth: bytesToBase64Url(mac),
    privateKey: keyPair.privateKey,
  };
}

/** JWK `d` alanından ham 32 bayt skaler (test amaçlı iç yardımcı). */
async function exportRawPrivateScalar(key: CryptoKey): Promise<Uint8Array> {
  const jwk = await crypto.subtle.exportKey("jwk", key);
  if (!jwk.d) throw new Error("JWK skaler alanı yok");
  return fromB64Url(jwk.d);
}

Deno.test("şifre → çöz: bilinen p256dh/auth çifti orijinal metne döner", async () => {
  const sub = await createBrowserLikeSubscription();
  const message = JSON.stringify({ title: "Su İçme Zamanı!", body: "Bugün 3/5 litre içtin." });
  const encrypted = await encryptPushBody({
    authSecret: sub.auth,
    p256dh: sub.p256dh,
    plaintext: message,
  });
  const decrypted = await decryptPushBody(encrypted, sub.auth, sub.p256dh, sub.privateKey);
  assertEquals(decrypted.plaintext, message);
});

Deno.test("çıktı yapısı doğru: salt 16, rs 4, idlen 1 bayt", async () => {
  const sub = await createBrowserLikeSubscription();
  const encrypted = await encryptPushBody({
    authSecret: sub.auth,
    p256dh: sub.p256dh,
    plaintext: "merhaba",
  });
  assertEquals(encrypted.body.length > 21, true);
  assertEquals(encrypted.body.length, 21 + "merhaba".length + 1 + 16);
  // rs: 4 bayt, büyük endian, 4096
  const view = new DataView(encrypted.body.buffer, encrypted.body.byteOffset, encrypted.body.byteLength);
  assertEquals(view.getUint32(SALT_BYTES, false), DEFAULT_RECORD_SIZE, "rs = 4096 (büyük endian)");
  // Bayt bayt doğrulama: 0x00 0x00 0x10 0x00
  assertEquals(Array.from(encrypted.body.subarray(SALT_BYTES, SALT_BYTES + 4)), [0, 0, 0x10, 0]);
  // idlen
  assertEquals(encrypted.body[SALT_BYTES + 4], 0);
});

Deno.test("aes128gcm üst başlığı zorunlu", async () => {
  const sub = await createBrowserLikeSubscription();
  const encrypted = await encryptPushBody({ authSecret: sub.auth, p256dh: sub.p256dh, plaintext: "x" });
  assertEquals(encrypted.headers["Content-Encoding"], "aes128gcm");
  assertEquals(encrypted.headers["Content-Type"], "application/octet-stream");
  assertEquals(typeof encrypted.headers["TTL"], "string");
  assertEquals(typeof encrypted.headers["Urgency"], "string");
  // Başlık olmadan çözme reddedilir.
  const tampered = { ...encrypted, headers: { ...encrypted.headers, "Content-Encoding": "gzip" } };
  let threw = false;
  try {
    await decryptPushBody(tampered, sub.auth, sub.p256dh, sub.privateKey);
  } catch (e) {
    threw = e instanceof PushEncryptionError;
  }
  assertEquals(threw, true, "Content-Encoding aes128gcm değilse çözme reddedilmeli");
});

Deno.test("aynı secret ile iki şifreleme FARKLI ciphertext üretir (rastgele salt)", async () => {
  const sub = await createBrowserLikeSubscription();
  const a = await encryptPushBody({ authSecret: sub.auth, p256dh: sub.p256dh, plaintext: "aynı" });
  const b = await encryptPushBody({ authSecret: sub.auth, p256dh: sub.p256dh, plaintext: "aynı" });
  assertEquals(a.body.length, b.body.length);
  // Salt farklı olduğu için gövdeler farklı olmalı.
  assertEquals(bytesToBase64Url(a.body) === bytesToBase64Url(b.body), false, "salt rastgele olmalı");
  // Her ikisi de doğru çözülür.
  assertEquals((await decryptPushBody(a, sub.auth, sub.p256dh, sub.privateKey)).plaintext, "aynı");
  assertEquals((await decryptPushBody(b, sub.auth, sub.p256dh, sub.privateKey)).plaintext, "aynı");
});

Deno.test("bozuk/eksik auth alanında fonksiyon çökmez — PushEncryptionError fırlatır", async () => {
  const sub = await createBrowserLikeSubscription();
  const badInputs = [
    { authSecret: "", p256dh: sub.p256dh },
    { authSecret: "   ", p256dh: sub.p256dh },
    { authSecret: "AAA", p256dh: sub.p256dh },
    { authSecret: bytesToBase64Url(new Uint8Array(8)), p256dh: sub.p256dh },
    { authSecret: bytesToBase64Url(new Uint8Array(24)), p256dh: sub.p256dh },
  ];
  for (const input of badInputs) {
    let threw = false;
    try {
      await encryptPushBody({ ...input, plaintext: "test" });
    } catch (e) {
      threw = e instanceof PushEncryptionError;
    }
    assertEquals(threw, true, `auth="${input.authSecret.slice(0, 8)}" reddedilmeliydi`);
  }
});

Deno.test("bozuk/eksik p256dh alanında fonksiyon çökmez", async () => {
  const sub = await createBrowserLikeSubscription();
  for (const bad of ["", "abc", bytesToBase64Url(new Uint8Array(64))]) {
    let threw = false;
    try {
      await encryptPushBody({ authSecret: sub.auth, p256dh: bad, plaintext: "test" });
    } catch (e) {
      threw = e instanceof PushEncryptionError;
    }
    assertEquals(threw, true, `p256dh="${bad.slice(0, 8)}" reddedilmeliydi`);
  }
});

Deno.test("MIME/boyut: şifreli gövde 4096 baytı aşmaz, sınır kontrolü var", async () => {
  const sub = await createBrowserLikeSubscription();
  // Gerçeküstü sınır: gövde = 21 (başlık) + düz metin + 1 (padding ayracı) + 16 (GCM etiketi)
  // 4096 sınırı → düz metin en fazla 4058 bayt olabilir (RFC §4'ün 3993 rakamı
  // 86 baytlık *keyid* başlığı varsayımıyla; bizde keyid yok, `dh` başlıkta).
  const maxPlaintext = MAX_ENCRYPTED_PAYLOAD_BYTES - 21 - 1 - 16;
  const big = "a".repeat(maxPlaintext);
  const encrypted = await encryptPushBody({ authSecret: sub.auth, p256dh: sub.p256dh, plaintext: big });
  assertEquals(encrypted.body.length, 4096, "sınırdaki gövde tam olarak 4096 bayt olmalı");
  assertEquals(
    (await decryptPushBody(encrypted, sub.auth, sub.p256dh, sub.privateKey)).plaintext.length,
    maxPlaintext,
  );
  // Sınırı aşan düz metin reddedilir (rs = düz metin + 1 + tag toplamından büyük olmalı).
  let threw = false;
  try {
    await encryptPushBody({ authSecret: sub.auth, p256dh: sub.p256dh, plaintext: "a".repeat(maxPlaintext + 1) });
  } catch (e) {
    threw = e instanceof PushEncryptionError;
  }
  assertEquals(threw, true);
});

Deno.test("Türkçe/emoji metinler bozulmadan gidiş-dönüş yapar", async () => {
  const sub = await createBrowserLikeSubscription();
  const text = JSON.stringify({ title: "💧 Su İçme Zamanı!", body: "Günaydın, 2.400 ml içtin. ĞÜŞİÖÇ ğüşıöç" });
  const encrypted = await encryptPushBody({ authSecret: sub.auth, p256dh: sub.p256dh, plaintext: text });
  assertEquals((await decryptPushBody(encrypted, sub.auth, sub.p256dh, sub.privateKey)).plaintext, text);
});

Deno.test("padding delimiter bozulursa çözme reddeder (RFC 8291 §4)", async () => {
  const sub = await createBrowserLikeSubscription();
  const encrypted = await encryptPushBody({ authSecret: sub.auth, p256dh: sub.p256dh, plaintext: "test" });
  // Son baytı değiştir -> GCM etiketi bozulur -> çözme hata vermeli.
  const corrupted = { ...encrypted, body: encrypted.body.slice() };
  corrupted.body[corrupted.body.length - 1] ^= 0xff;
  let threw = false;
  try {
    await decryptPushBody(corrupted, sub.auth, sub.p256dh, sub.privateKey);
  } catch (e) {
    threw = e instanceof PushEncryptionError;
  }
  assertEquals(threw, true, "bozuk ciphertext reddedilmeli");
});
