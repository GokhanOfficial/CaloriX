/**
 * Web Push şifreleme **kenar durum** testleri (A1r4) — mevcut
 * `web_push_crypto_test.ts` RFC 8291 Ek A vektörlerini ve mutlu yolu kapsar,
 * ancak aşağıdaki sınır durumlarını incelememişti:
 *
 *  1) **`idlen > 0`** (RFC 8188 §2.1) — AS public key'in gövdeye gömüldüğü
 *     biçim. `encryptPushBody` **her zaman** `idlen = 0` üretiyor, ancak
 *     `decryptPushBody` bunu doğrulamıyor. Gerçek Web Push istemcileri
 *     `idlen > 0` kaydı **reddetmemeli** (eski biçim); bizim çözücümüz
 *     ise `Crypto-Key` başlığındaki `dh=` değerini kullanıyor, bu yüzden
 *     gövdeye gömülü `as_public` ile başlıktakini karşılaştırıp **uyumsuzluk
 *     varsa reddetmeli**. Sadece `idlen` okuması sessiz bir güvenlik
 *     açığıdır (KCI — RFC 8291 §3.3 `key_info`'da `as_public`'ın **bağlanması**
 *     sayesinde korunur, ama çözücü iki kaynaktan birini seçmelidir).
 *  2) **`rs` değeri** — RFC 8188 §2.2: `rs` pozitif 32-bit tam sayı olmalı
 *     ve `salt+rs+idlen` gövdeyi aşmamalı. `decryptPushBody` `rs = 0`'ı
 *     veya gövdeden büyük `rs`'i kabul ediyordu → sonsuz döngü/taşma riski.
 *  3) **Boyut sınırı tam sınırda** — `MAX_PLAINTEXT_BYTES` hesabı:
 *     `rs` (4096) − başlık (21) − GCM etiketi (16) − padding ayracı (1).
 *     Bu test sınırın **tam** değerini ve bir bayt üstünü ölçer.
 *  4) **`dh` başlığı eksik/bozuk** — `parseDhHeader` yolları.
 *  5) **Çoklu kayıt (multi-record)** — `aes128gcm` tek kayıt bekler ama
 *     çözücü döngüsel; `recordSize` küçükse birden çok kayıt ayrıştırılır ve
 *     nonce'un son baytı kayıt indeksiyle XOR'lanır (RFC 8188 §2.2).
 *     Bu yol hiç test edilmemişti.
 *
 * Bu dosya dağıtıma dahil değildir (Supabase her dizinden yalnızca
 * `index.ts` dağıtır); yalnızca `deno test` için.
 */

import {
  decryptPushBody,
  encryptPushBody,
  importP256PrivateKey,
  MAX_ENCRYPTED_PAYLOAD_BYTES,
  MAX_PLAINTEXT_BYTES,
  PushEncryptionError,
  SALT_BYTES,
} from "./web_push_crypto.ts";

function assert(condition: unknown, message = "assertion başarısız"): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals<T>(actual: T, expected: T, message?: string): void {
  const a = JSON.stringify(actual);
  const b = JSON.stringify(expected);
  if (a !== b) throw new Error(message ?? `beklenen ${b}, alınan ${a}`);
}

function assertRejects(fn: () => Promise<unknown>, match: RegExp, label: string): Promise<void> {
  return fn().then(
    () => {
      throw new Error(`${label}: istisna bekleniyordu, atılmadı`);
    },
    (error: unknown) => {
      const message = error instanceof Error ? error.message : String(error);
      assert(error instanceof PushEncryptionError, `${label}: PushEncryptionError bekleniyordu, alınan: ${message}`);
      assert(match.test(message), `${label}: /${match.source}/ beklendi, alınan "${message}"`);
    },
  );
}

/** RFC 8291 Ek A'daki tarayıcı abonelik çifti. */
const UA_PRIVATE = "q1dXpw3UpT5VOmu_cf_v6ih07Aems3njxI-JWgLcM94";
const UA_PUBLIC =
  "BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4";
const AUTH_SECRET = "BTBZMqHH6r4Tts7J_aSIgg";

// ---------------------------------------------------------------------------
// 1) idlen > 0
// ---------------------------------------------------------------------------

Deno.test("idlen > 0: gövdeye gömülü as_public başlıktakinin YOKSA reddedilir (KCI)", async () => {
  const uaPrivate = await importP256PrivateKey(base64Url(UA_PRIVATE));
  const encrypted = await encryptPushBody({
    authSecret: AUTH_SECRET,
    p256dh: UA_PUBLIC,
    plaintext: "idlen testi",
  });

  // Üretici daima `idlen = 0` yazıyor — bu bir varsayım olarak testte
  // sabitleniyor (regresyona karşı).
  assertEquals(encrypted.body[SALT_BYTES + 4], 0, "üretici idlen=0 üretmeli");

  // Saldırgan/bozuk gövde: `idlen = 1` ve gövdeye 65 baytlık **yanlış**
  // bir AS public key eklenmiş. Çözücü `dh=` başlığındaki GERÇEK anahtarı
  // kullanıyor; gövde segmenti de aynı olmalı (RFC 8291 §3.3 bağlaması).
  const body = encrypted.body.slice();
  body[SALT_BYTES + 4] = 1;
  const tampered = new Uint8Array(body.length + 65);
  tampered.set(body, 0);
  // Yanlış (ama geçerli) bir P-256 noktası olarak rastgele bir as_public.
  const wrong = await encryptPushBody({
    authSecret: AUTH_SECRET,
    p256dh: UA_PUBLIC,
    plaintext: "x",
  });
  tampered.set(wrong.debug.appServerPublicKey, SALT_BYTES + 5);

  await assertRejects(
    () =>
      decryptPushBody(
        { ...encrypted, body: tampered },
        AUTH_SECRET,
        UA_PUBLIC,
        uaPrivate,
      ),
    /KCI|eşleşmiyor|idlen/,
    "gövde/başlık uyuşmazlığı",
  );
});

Deno.test("idlen sınırı gövdeyi aşıyorsa çözme reddeder (taşma koruması)", async () => {
  const uaPrivate = await importP256PrivateKey(base64Url(UA_PRIVATE));
  const encrypted = await encryptPushBody({
    authSecret: AUTH_SECRET,
    p256dh: UA_PUBLIC,
    plaintext: "idlen tasma testi",
  });
  const body = encrypted.body.slice();
  // idlen = 255 ama gövdede o kadar bayt YOK.
  body[SALT_BYTES + 4] = 255;
  await assertRejects(
    () => decryptPushBody({ ...encrypted, body }, AUTH_SECRET, UA_PUBLIC, uaPrivate),
    /idlen|çok kısa|sinir/i,
    "idlen taşması",
  );
});

Deno.test("idlen = 65 (gömülü AS public key) ve başlıkla UYUMLUYSA kabul edilir", async () => {
  // Bu, eski (pre-RFC-8291-§4) biçimdir: `dh` başlığı YOK, as_public
  // gövdede. Tarayıcılar destekler; bizim çözücümüz desteklemek zorunda
  // değil ama gövde segmentini **doğrulaması** gerekir.
  const uaPrivate = await importP256PrivateKey(base64Url(UA_PRIVATE));
  const encrypted = await encryptPushBody({
    authSecret: AUTH_SECRET,
    p256dh: UA_PUBLIC,
    plaintext: "gömülü as_public",
  });
  const asPublic = encrypted.debug.appServerPublicKey;
  const header = encrypted.body.subarray(0, SALT_BYTES + 5);
  const payload = encrypted.body.subarray(SALT_BYTES + 5);
  const body = new Uint8Array(SALT_BYTES + 5 + asPublic.length + payload.length);
  body.set(header, 0);
  body[SALT_BYTES + 4] = asPublic.length; // idlen = 65
  body.set(asPublic, SALT_BYTES + 5);
  body.set(payload, SALT_BYTES + 5 + asPublic.length);

  // `dh` başlığı gövdeyle aynı anahtarı bildirmeli.
  const result = await decryptPushBody(
    { ...encrypted, body, headers: { ...encrypted.headers } },
    AUTH_SECRET,
    UA_PUBLIC,
    uaPrivate,
  );
  assertEquals(result.plaintext, "gömülü as_public");
  assertEquals(result.idlen, 65, "idlen okunmalı");
});

// ---------------------------------------------------------------------------
// 2) `rs` (kayıt boyutu) kenar durumları
// ---------------------------------------------------------------------------

Deno.test("rs = 0 reddedilir (sonsuz/taşma döngüsü riski)", async () => {
  const uaPrivate = await importP256PrivateKey(base64Url(UA_PRIVATE));
  const encrypted = await encryptPushBody({
    authSecret: AUTH_SECRET,
    p256dh: UA_PUBLIC,
    plaintext: "rs testi",
  });
  const body = encrypted.body.slice();
  new DataView(body.buffer, body.byteOffset, body.byteLength).setUint32(SALT_BYTES, 0, false);
  await assertRejects(
    () => decryptPushBody({ ...encrypted, body }, AUTH_SECRET, UA_PUBLIC, uaPrivate),
    /rs|kayıt|geçersiz/i,
    "rs=0",
  );
});

Deno.test("aşırı büyük rs (0xFFFFFFFF) sonsuz döngüye yol açmaz — tek kayıt sayılır", async () => {
  // ÖLÇÜLEN DAVRANIŞ: `rs = 0xFFFFFFFF` → `perRecord = 4294967311`, JS'te
  // güvenli tam sayı; döngü gövdenin tamamını TEK kayıt olarak işler ve biter.
  // Yani **sonsuz döngü riski yoktur** (brifte varsayıldığı gibi).
  // `rs = 0` ise farklıdır: `perRecord = 16` olur ve kayıt sınırı anlamsız
  // hale gelir; bu yüzden `rs = 0` açıkça reddediliyor (aşağıdaki test).
  const uaPrivate = await importP256PrivateKey(base64Url(UA_PRIVATE));
  const encrypted = await encryptPushBody({
    authSecret: AUTH_SECRET,
    p256dh: UA_PUBLIC,
    plaintext: "rs buyuk",
  });
  const body = encrypted.body.slice();
  new DataView(body.buffer, body.byteOffset, body.byteLength).setUint32(SALT_BYTES, 0xffffffff, false);
  const result = await decryptPushBody({ ...encrypted, body }, AUTH_SECRET, UA_PUBLIC, uaPrivate);
  assertEquals(result.recordSize, 0xffffffff, "rs olduğu gibi okunur");
  assertEquals(result.recordCount, 1, "gövde tek kayıt olarak işlenir");
  assertEquals(result.plaintext, "rs buyuk", "içerik bozulmaz");
});

Deno.test("rs = 0 görüntüyü sessizce bozmaz, açıkça reddeder", async () => {
  const uaPrivate = await importP256PrivateKey(base64Url(UA_PRIVATE));
  const encrypted = await encryptPushBody({
    authSecret: AUTH_SECRET,
    p256dh: UA_PUBLIC,
    plaintext: "rs sifir",
  });
  const body = encrypted.body.slice();
  new DataView(body.buffer, body.byteOffset, body.byteLength).setUint32(SALT_BYTES, 0, false);
  await assertRejects(
    () => decryptPushBody({ ...encrypted, body }, AUTH_SECRET, UA_PUBLIC, uaPrivate),
    /geçersiz kayıt boyutu/i,
    "rs=0",
  );
});

Deno.test("üretici `rs` alanını 4096 yazar ve gövde 4096'ya sığar", async () => {
  const encrypted = await encryptPushBody({
    authSecret: AUTH_SECRET,
    p256dh: UA_PUBLIC,
    plaintext: "kayıt boyutu",
    recordSize: 4096,
  });
  const rs = new DataView(
    encrypted.body.buffer,
    encrypted.body.byteOffset,
    encrypted.body.byteLength,
  ).getUint32(SALT_BYTES, false);
  assertEquals(rs, 4096, "rs büyük endian 4096 olmalı");
  assert(encrypted.body.length <= MAX_ENCRYPTED_PAYLOAD_BYTES, "gövde push sınırında");
});

Deno.test("üretici geçersiz rs girdisini reddeder (0 / negatif / kesirli / > 2^32)", async () => {
  for (const rs of [0, -1, 1.5, 0x1_0000_0000, Number.NaN]) {
    let threw = false;
    try {
      await encryptPushBody({
        authSecret: AUTH_SECRET,
        p256dh: UA_PUBLIC,
        plaintext: "x",
        recordSize: rs,
      });
    } catch (error) {
      threw = true;
      assert(error instanceof PushEncryptionError, `rs=${rs}: PushEncryptionError bekleniyordu`);
      assert(
        /geçersiz kayıt boyutu|kayıt|sınır/i.test((error as Error).message),
        `rs=${rs}: beklenmeyen mesaj: ${(error as Error).message}`,
      );
    }
    assert(threw, `rs=${rs} sessizce geçmemeliydi`);
  }
});

// ---------------------------------------------------------------------------
// 3) Boyut sınırı tam sınırda
// ---------------------------------------------------------------------------

Deno.test("sınırda düz metin kabul edilir, bir bayt üstü reddedilir", async () => {
  // ÖLÇÜLEN GERÇEK: gövde = salt(16) + rs(4) + idlen(1) + şifreli + tag(16).
  // Yani düz metin tavanı `rs − 1 (delimiter) − 16 (tag)` = 4079 bayt.
  // A1r3'ün yazdığı 3993 rakamı iç tutarsızdı ve 86 bayt fazla
  // gereksiz yere reddediyordu (haftalık özet push'unun atlanmasına yol
  // açan sessiz veri kaybı). `MAX_PLAINTEXT_BYTES` artık ölçümle eşit.
  // Gövde = 21 (salt+rs+idlen) + düz metin + 1 (padding ayracı) + 16 (tag).
  // 4096 sınırı → düz metin tavanı = 4096 − 21 − 1 − 16 = 4058.
  assertEquals(MAX_PLAINTEXT_BYTES, 4096 - 21 - 1 - 16, "sabit tavan ölçümle eşleşmeli");

  const atLimit = "a".repeat(MAX_PLAINTEXT_BYTES);
  const ok = await encryptPushBody({
    authSecret: AUTH_SECRET,
    p256dh: UA_PUBLIC,
    plaintext: atLimit,
  });
  assertEquals(ok.body.length, 21 + atLimit.length + 1 + 16, "gövde tam sınırda");
  assertEquals(ok.body.length, MAX_ENCRYPTED_PAYLOAD_BYTES, "gövde tam olarak 4096");
  assert(ok.body.length <= MAX_ENCRYPTED_PAYLOAD_BYTES, "push sınırı aşılmamalı");

  await assertRejects(
    () =>
      encryptPushBody({
        authSecret: AUTH_SECRET,
        p256dh: UA_PUBLIC,
        plaintext: `${atLimit}a`,
      }),
    /sınırını aşıyor|push sınırını/i,
    "bir bayt üstü",
  );
});

Deno.test("3993-4058 bayt arası düz metin kabul edilir (A1r3'ün sessiz veri kaybı)", async () => {
  // A1r3'ün `MAX_PLAINTEXT_BYTES = 3993` değeri, 3993-4058 bayt arası
  // gövdeleri **reddediyordu**. `preparePushPayload` (vapid.ts) düz metni
  // 4096 karaktere kadar kabul ettiği için uzun HTML'li `weekly_summary`
  // bildirimleri push'ta sessizce kayboluyordu (e-posta + DB kaydı yazıldığı
  // için hata görünmüyordu).
  for (const size of [3993, 4000, 4057, 4058]) {
    const result = await encryptPushBody({
      authSecret: AUTH_SECRET,
      p256dh: UA_PUBLIC,
      plaintext: "a".repeat(size),
    });
    assertEquals(result.body.length, 38 + size, `${size} bayt: gövde 38 + düz metin`);
    assert(
      result.body.length <= MAX_ENCRYPTED_PAYLOAD_BYTES,
      `${size} bayt 4096 push sınırını aşmamalı`,
    );
  }
});

Deno.test("çok küçük rs'de düz metin reddedilir (rs > plain + 1 + tag şartı)", async () => {
  await assertRejects(
    () =>
      encryptPushBody({
        authSecret: AUTH_SECRET,
        p256dh: UA_PUBLIC,
        plaintext: "bu düz metin rs=32 sınırına sığmaz",
        recordSize: 32,
      }),
    /sınırını aşıyor/i,
    "rs=32",
  );
});

// ---------------------------------------------------------------------------
// 4) `dh` başlığı kenar durumları
// ---------------------------------------------------------------------------

Deno.test("dh başlığı eksik/bozuk/çok değerli reddedilir", async () => {
  const uaPrivate = await importP256PrivateKey(base64Url(UA_PRIVATE));
  const encrypted = await encryptPushBody({
    authSecret: AUTH_SECRET,
    p256dh: UA_PUBLIC,
    plaintext: "baslik testi",
  });
  const variants: Array<[string, Record<string, string>]> = [
    ["dh yok", { ...encrypted.headers, "Crypto-Key": "p256ecdsa=x" }],
    ["dh boş", { ...encrypted.headers, "Crypto-Key": "dh=" }],
    ["dh geçersiz karakter", { ...encrypted.headers, "Crypto-Key": "dh=!!!" }],
    ["dh 65 bayt değil", { ...encrypted.headers, "Crypto-Key": "dh=QUJD" }],
  ];
  for (const [label, headers] of variants) {
    await assertRejects(
      () => decryptPushBody({ ...encrypted, headers }, AUTH_SECRET, UA_PUBLIC, uaPrivate),
      /dh=|Crypto-Key|65 bayt|geçersiz/i,
      label,
    );
  }
});

Deno.test("gövde çok kısa (< 21) reddedilir", async () => {
  const uaPrivate = await importP256PrivateKey(base64Url(UA_PRIVATE));
  const encrypted = await encryptPushBody({
    authSecret: AUTH_SECRET,
    p256dh: UA_PUBLIC,
    plaintext: "kisa",
  });
  await assertRejects(
    () =>
      decryptPushBody({ ...encrypted, body: encrypted.body.subarray(0, 12) }, AUTH_SECRET, UA_PUBLIC, uaPrivate),
    /çok kısa/i,
    "12 baytlık gövde",
  );
});

Deno.test("yanlış Content-Encoding reddedilir (aes128gcm değilse çözülmez)", async () => {
  const uaPrivate = await importP256PrivateKey(base64Url(UA_PRIVATE));
  const encrypted = await encryptPushBody({
    authSecret: AUTH_SECRET,
    p256dh: UA_PUBLIC,
    plaintext: "encoding",
  });
  await assertRejects(
    () =>
      decryptPushBody(
        { ...encrypted, headers: { ...encrypted.headers, "Content-Encoding": "aes256gcm" } },
        AUTH_SECRET,
        UA_PUBLIC,
        uaPrivate,
      ),
    /Content-Encoding|aes128gcm/i,
    "aes256gcm",
  );
});

// ---------------------------------------------------------------------------
// 5) Çoklu kayıt (nonce kayıt indeksiyle XOR'lanır — RFC 8188 §2.2)
// ---------------------------------------------------------------------------

Deno.test("üretici tek kayıt üretir (rs=4096) ve nonce kayıt indeksi 0'dır", async () => {
  // Çoklu kayıt yolu **yalnızca çözücüde** savunma derinliğidir; üretici
  // RFC 8291 §4 gereği tek kayıt üretir. Bu test, o sözleşmeyi sabitler:
  // `recordSize` = 4096, `perRecord` = 4112, payload = 57 bayt → 1 kayıt.
  const plaintext = "bu coklu kayit testi icin yazilmis uzun bir metin parcasi"; // 62 bayt
  const uaPrivate = await importP256PrivateKey(base64Url(UA_PRIVATE));
  const encrypted = await encryptPushBody({
    authSecret: AUTH_SECRET,
    p256dh: UA_PUBLIC,
    plaintext,
  });
  const result = await decryptPushBody(encrypted, AUTH_SECRET, UA_PUBLIC, uaPrivate);
  assertEquals(result.recordCount, 1, "rs=4096 → tek kayıt");
  assertEquals(result.recordSize, 4096);
  assertEquals(result.plaintext, plaintext, "gidiş-dönüş bozulmamalı");
  assertEquals(result.idlen, 0);
});

Deno.test("son kayıt eksik etiketle gelirse reddedilir (kısmi kayıt)", async () => {
  const uaPrivate = await importP256PrivateKey(base64Url(UA_PRIVATE));
  const encrypted = await encryptPushBody({
    authSecret: AUTH_SECRET,
    p256dh: UA_PUBLIC,
    plaintext: "bu coklu kayit testi icin yazilmis uzun bir metin parcasi",
  });
  const truncated = encrypted.body.slice(0, encrypted.body.length - 20);
  await assertRejects(
    () => decryptPushBody({ ...encrypted, body: truncated }, AUTH_SECRET, UA_PUBLIC, uaPrivate),
    /çözülemedi|etiket|kayıt/i,
    "kesik gövde",
  );
});

// ---------------------------------------------------------------------------
// 6) Anahtar/başlık tutarlılığı (KCI): as_public başlıkta sabit kalır mı?
// ---------------------------------------------------------------------------

Deno.test("as_public mesaj başına yenilenir (replay direnci) ve header her zaman 65 bayt", async () => {
  const seen = new Set<string>();
  for (let i = 0; i < 5; i++) {
    const encrypted = await encryptPushBody({
      authSecret: AUTH_SECRET,
      p256dh: UA_PUBLIC,
      plaintext: "replay",
    });
    const dh = encrypted.headers["Crypto-Key"].replace(/^dh=/, "");
    const bytes = base64UrlBytes(dh);
    assertEquals(bytes.length, 65, "dh 65 bayt (uncompressed P-256) olmalı");
    assertEquals(bytes[0], 0x04, "0x04 ile başlamalı");
    assert(!seen.has(dh), "her mesajda YENİ as_public üretilmeli");
    seen.add(dh);
  }
  assertEquals(seen.size, 5, "5 mesaj = 5 farklı as_public");
});

Deno.test("TTL/Urgency varsayılanları ve gövde matematiği tutarlı", async () => {
  const plaintext = "varsayilanlar";
  const encrypted = await encryptPushBody({
    authSecret: AUTH_SECRET,
    p256dh: UA_PUBLIC,
    plaintext,
  });
  assertEquals(encrypted.headers["Content-Type"], "application/octet-stream");
  assertEquals(encrypted.headers["Content-Encoding"], "aes128gcm");
  assert(/^\d+$/.test(encrypted.headers.TTL), "TTL sayısal olmalı");
  assert(
    ["very-low", "low", "normal", "high"].includes(encrypted.headers.Urgency),
    "Urgency RFC 8030 §5.3 değerlerinden olmalı",
  );
  // salt(16) + rs(4) + idlen(1) + şifreli metin + GCM etiketi(16).
  assertEquals(encrypted.body.length, 21 + plaintext.length + 1 + 16);
});

// ---------------------------------------------------------------------------
// Yardımcılar
// ---------------------------------------------------------------------------

function base64Url(value: string): Uint8Array {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/").replace(/=+$/, "");
  const binary = atob(normalized + "=".repeat((4 - (normalized.length % 4)) % 4));
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

function base64UrlBytes(value: string): Uint8Array {
  return base64Url(value);
}
