/**
 * Kalıcı (DB) rate limit ve bellek içi yedek yol için Deno testleri.
 *
 * Çalıştırma:
 *   deno test --allow-env --allow-net supabase/functions/_shared/rate_limit_test.ts
 *
 * Testler `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` tanımlıysa RPC'yi
 * gerçekten çağırır (p pencere sınırı, anahtar izolasyonu, eşzamanlılık).
 * Tanımlı değilse DB bağımlı testler atlanır ama **bellek içi yol her zaman**
 * test edilir — böylece testler anahtarsız da anlamlı sonuç verir.
 */

import {
  checkRateLimit,
  checkRateLimitMemory,
  rateLimitKey,
  type RateLimitRule,
} from "./rate_limit.ts";

const hasDb = Boolean(Deno.env.get("SUPABASE_URL") && Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));

function uniqueKey(suffix: string): string {
  return `test:${suffix}:${crypto.randomUUID()}`;
}

// ---------------------------------------------------------------
// Bellek içi yol (her zaman test edilir)
// ---------------------------------------------------------------

Deno.test("bellek ici: pencere sinirini asan istek reddedilir", () => {
  const key = uniqueKey("bellek-pencere");
  const rule: RateLimitRule = { windowSeconds: 60, max: 3 };

  for (let i = 0; i < 3; i++) {
    const r = checkRateLimitMemory(key, rule);
    if (!r.allowed) throw new Error(`İstek ${i + 1} reddedildi, bekleniyordu: izin`);
  }
  const blocked = checkRateLimitMemory(key, rule);
  if (blocked.allowed) throw new Error("4. istek izin aldı, bekleniyordu: ret");
  if (blocked.retryAfter <= 0 || blocked.retryAfter > 60) {
    throw new Error(`retryAfter geçersiz: ${blocked.retryAfter}`);
  }
});

Deno.test("bellek ici: anahtar izolasyonu", () => {
  const a = uniqueKey("bellek-izolasyon-a");
  const b = uniqueKey("bellek-izolasyon-b");
  const rule: RateLimitRule = { windowSeconds: 60, max: 1 };

  if (!checkRateLimitMemory(a, rule).allowed) throw new Error("A ilk istekte reddedildi");
  if (!checkRateLimitMemory(b, rule).allowed) {
    throw new Error("B, A'nin dolu kovası etkileniyor (anahtar izolasyonu bozuk)");
  }
  if (checkRateLimitMemory(a, rule).allowed) throw new Error("A ikinci istekte izin aldı");
});

Deno.test("bellek ici: sure dolunca kova sifirlanir", async () => {
  const key = uniqueKey("bellek-sifirlama");
  // Kısa pencere kullanıyoruz ki gerçekten dolmasını bekleyebilelim.
  const rule: RateLimitRule = { windowSeconds: 0.05, max: 1 };

  if (!checkRateLimitMemory(key, rule).allowed) throw new Error("ilk istek reddedildi");
  if (checkRateLimitMemory(key, rule).allowed) throw new Error("ikinci istek izin aldı");

  // Pencere (50 ms) dolsun.
  await new Promise((r) => setTimeout(r, 80));

  const fresh = checkRateLimitMemory(key, rule);
  if (!fresh.allowed) throw new Error("süresi dolmuş kova izin vermedi");
});

Deno.test("rateLimitKey: kullanici varsa userId, yoksa IP kullanir", () => {
  const req = new Request("https://example.test/", {
    headers: { "x-forwarded-for": "203.0.113.5, 10.0.0.1" },
  });
  if (rateLimitKey("ai-chat", req, "user-1") !== "ai-chat:u:user-1") {
    throw new Error("kullanici bazli anahtar yanlis");
  }
  // x-forwarded-for'da ilk deger dikkate alinir.
  if (rateLimitKey("ai-chat", req) !== "ai-chat:ip:203.0.113.5") {
    throw new Error("IP bazli anahtar yanlis");
  }
  if (rateLimitKey("ai-chat", new Request("https://example.test/")) !== "ai-chat:ip:unknown") {
    throw new Error("IP yoksa 'unknown' kullanilmalı");
  }
});

// ---------------------------------------------------------------
// Kalıcı DB yolu (SUPABASE_* tanımlıysa)
// ---------------------------------------------------------------

Deno.test({
  name: "kalici DB: pencere siniri, anahtar izolasyonu, eszamanlilik",
  ignore: !hasDb,
  async fn() {
    const rule: RateLimitRule = { windowSeconds: 60, max: 5 };
    const keyA = uniqueKey("db-a");
    const keyB = uniqueKey("db-b");

    // 1) İlk 5 istek izin almalı, 6. istek reddedilmeli.
    for (let i = 0; i < 5; i++) {
      const r = await checkRateLimit(keyA, rule);
      if (!r.allowed) throw new Error(`istek ${i + 1} reddedildi, izin bekleniyordu`);
    }
    const blocked = await checkRateLimit(keyA, rule);
    if (blocked.allowed) throw new Error("6. istek izin aldı, ret bekleniyordu");
    if (blocked.retryAfter <= 0) throw new Error(`retryAfter pozitif olmalıydı: ${blocked.retryAfter}`);

    // 2) Anahtar izolasyonu: B etkilenmemeli.
    const b1 = await checkRateLimit(keyB, rule);
    if (!b1.allowed) throw new Error("B, A'nın dolu kovası etkileniyor");

    // 3) Eşzamanlı 10 istek: sınır 5 olduğu için TAM OLARAK 5'i izin almalı.
    //    (Atomik artırma yoksa bu sayı 5'ten büyük olurdu — race condition kanıtı.)
    const keyC = uniqueKey("db-eszamanli");
    const results = await Promise.all(
      Array.from({ length: 10 }, () => checkRateLimit(keyC, rule)),
    );
    const allowedCount = results.filter((r) => r.allowed).length;
    if (allowedCount !== rule.max) {
      throw new Error(`es zamanlı isteklerde izin sayisi ${allowedCount}, bekleniyordu: ${rule.max}`);
    }
  },
});

Deno.test({
  name: "kalici DB: DB erisilemezse bellek ici yola duser (fonksiyon cokmez)",
  ignore: hasDb, // sadece SUPABASE_* tanımlı DEĞİLKEN anlamlı
  async fn() {
    const rule: RateLimitRule = { windowSeconds: 60, max: 2 };
    const key = uniqueKey("db-yok");
    for (let i = 0; i < 2; i++) {
      const r = await checkRateLimit(key, rule);
      if (!r.allowed) throw new Error(`istek ${i + 1} reddedildi`);
    }
    const blocked = await checkRateLimit(key, rule);
    if (blocked.allowed) throw new Error("3. istek izin aldı");
  },
});
