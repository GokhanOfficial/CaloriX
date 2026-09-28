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
  isDbBypassed,
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

// ---------------------------------------------------------------
// KOVA BAZLI KISA DEVRE (A1r8)
// -----------------------------------------------------------------
// A1r5'e kadar kısa devre TEK global değişkendi: bir kovanın DB arızası
// aynı instance'taki TÜM kovaları 60 sn bellem içi yola düşürüyordu.
// Aşağıdaki testler bu çapraz etkiyi ölçer.

Deno.test({
  name: "kova bazli kisa devre: bir kovanin arızasi digerini ETKILEMEZ",
  // SUPABASE_* tanimli degilken `checkRateLimitDb` her kova icin bypass
  // baslatir; bu durumda zaten hicbir kova DB'ye gitmez ve testin kanıtladigi
  // izolasyon olcumu anlamsiz olur. Bu yuzden yalnizca DB YOKKEN anlamlidir.
  ignore: hasDb,
  async fn() {
    const rule: RateLimitRule = { windowSeconds: 60, max: 5 };
    const id = crypto.randomUUID();

    // 1) "ai-chat" kovasını DB'ye gidemeyecek şekilde tetikle: bu, o kova
    //    için 60 sn'lik kısa devreyi AÇAR.
    const aiKey = `ai-chat:u:${id}`;
    const first = await checkRateLimit(aiKey, rule);
    if (!first.allowed) throw new Error("ai-chat ilk istekte reddedildi");
    if (!isDbBypassed("ai-chat")) {
      throw new Error("ai-chat bypass bekleniyordu ama acik degil (kisa devre kurulmadi)");
    }

    // 2) KRİTİK KONTROL: "delete-account" kovası HİÇBİR ZAMAN DB'ye
    //    gitmedi. Eğer kısa devre hâlâ global olsaydı, bu kova da bypass'a
    //    düşerdi. Şimdi bypass TUTULMAMALI.
    if (isDbBypassed("delete-account")) {
      throw new Error(
        "delete-account kovasi ai-chat'in arızasi nedeniyle bypass oldu — kova izolasyonu bozuk",
      );
    }

    // 3) Kanıt: delete-account kovası kendi bellem içi sayacını **kendi**
    //    kullanıyor, yani kendi eşiğine kadar izin veriyor.
    const delKey = `delete-account:u:${id}`;
    for (let i = 0; i < rule.max; i++) {
      const r = await checkRateLimit(delKey, rule);
      if (!r.allowed) throw new Error(`delete-account istek ${i + 1} reddedildi`);
    }
    const delBlocked = await checkRateLimit(delKey, rule);
    if (delBlocked.allowed) {
      throw new Error("delete-account kendi sınırını uygulamıyor");
    }
  },
});

Deno.test({
  name: "kova bazli kisa devre: ayni kovanin penceresi kapanmadan yenisi acilmaz",
  ignore: hasDb,
  async fn() {
    const rule: RateLimitRule = { windowSeconds: 60, max: 5 };
    const id = crypto.randomUUID();
    const key = `ai-chat:u:${id}`;

    // İlk çağrı kısa devreyi açar.
    await checkRateLimit(key, rule);
    if (!isDbBypassed("ai-chat")) throw new Error("kisa devre acilmadi");

    // Aynı kova ikinci kez çağrılırsa kısa devre **korunur**: sürekli yeni
    // kısa devre penceresi açılmamalı (her istekte RPC yeniden denenmesin).
    const second = await checkRateLimit(key, rule);
    if (!second.allowed) throw new Error("ikinci istek reddedildi");
    if (!isDbBypassed("ai-chat")) {
      throw new Error("ikinci çağrı kısa devreyi sıfırladı — pencere kaydı kayboldu");
    }
  },
});

Deno.test({
  name: "kova bazli kisa devre: hicbir kova bypass degilse gozlem sifirlanir",
  ignore: hasDb,
  async fn() {
    const rule: RateLimitRule = { windowSeconds: 60, max: 5 };
    const id = crypto.randomUUID();
    // Tamamen yeni, daha önce hiç kullanılmamış kovalar.
    await checkRateLimit(`ai-chat:u:${id}`, rule);
    if (!isDbBypassed("ai-chat")) throw new Error("kisa devre acilmadi");
    // Pencerenin bitiş zamanı geçmiş bir anla "gözlem" kontrolü.
    const gelecek = Date.now() + 10 * 60_000;
    if (isDbBypassed("ai-chat", gelecek)) {
      throw new Error("pencere dolmuş görünüyor ama hâlâ bypass diyor");
    }
    // Gelecekte açılmış HİÇBİR kova yok → bu kova bypass değil.
    if (isDbBypassed("hic-boyle-bir-kova", gelecek)) {
      throw new Error("tanımsız kova bypass görünüyor");
    }
  },
});

Deno.test({
  name: "isDbBypassed: hic arıza olmamis kova bypass degildir (temiz durum)",
  // Bu test DB'nin SAGLIKLI olduğu durumda da anlamlıdır: hiç arıza yoksa
  // hicbir kova bypass olmamalıdır.
  async fn() {
    const id = crypto.randomUUID();
    if (isDbBypassed(`asla-kullanilmamis-kova-${id}`)) {
      throw new Error("temiz durumda kova bypass görünüyor");
    }
  },
});
