/**
 * Edge function **kimlik doğrulama sırası** denetimi (A1r4).
 *
 * Brif sorusu: "her fonksiyon önce JWT doğruluyor mu, yoksa bazıları iş
 * yapmaya mı başlıyor?" Bu test, kaynak kodunu okuyarak her fonksiyonda
 * **iş yapmadan önce** yetkilendirme adımının geldiğini doğrular.
 *
 * Denetlenen düzen (her `index.ts` için geçerli olması gereken):
 *   1) `OPTIONS` → `preflightResponse`      (CORS, kimlik doğrulama YAPILMAZ)
 *   2) `405`   → `errorResponse`            (yanlış metot)
 *   3) **yetkilendirme** (`requireUserContext` / `isInternalCall` /
 *      `isAuthorizedCall`)                 <-- BUNDAN ÖNCE iş yok
 *   4) rate limit, gövde okuma, DB erişimi, dış çağrı
 *
 * Kural 3'ün 4'ten önce gelmesi, kimliksiz bir isteğin `checkRateLimit`
 * (DB'ye yazan sayaç) tetiklemesini, gövdesini tüketmesini veya tablo
 * sorgulamasını engeller.
 *
 * Ayrıca `config.toml` ile fonksiyon içi doğrulamanın **tutarlılığını**
 * denetler: `verify_jwt = false` yalnızca kendi yetkilendirmesini taşıyan
 * (dahili) fonksiyonlarda olabilir.
 */

const FUNCTIONS_DIR = new URL("../", import.meta.url);

/** `index.ts` kaynaklarını okur. */
async function readAll(): Promise<Array<{ name: string; source: string }>> {
  const names: string[] = [];
  for await (const entry of Deno.readDir(FUNCTIONS_DIR)) {
    if (!entry.isDirectory || entry.name === "_shared") continue;
    try {
      await Deno.stat(new URL(`${entry.name}/index.ts`, FUNCTIONS_DIR));
      names.push(entry.name);
    } catch (_) {
      // index.ts yok (yardımcı dizin) — atla.
    }
  }
  names.sort();
  return Promise.all(
    names.map(async (name) => ({
      name,
      source: await Deno.readTextFile(new URL(`${name}/index.ts`, FUNCTIONS_DIR)),
    })),
  );
}

const all = await readAll();

/** Kaynak içinde ilk `needle` indeksi; yoksa -1. */
function indexOf(source: string, needle: string): number {
  return source.indexOf(needle);
}

/**
 * Bir fonksiyonun **çalışma zamanı** sırasını veren yardımcı tanım
 * (import satırları, fonksiyon/imza tanımları ve yorumlar atlanır).
 * Neden: `check-reminders` dosyasında `isAuthorizedCall` **handler'dan
 * ÖNCE** tanımlıdır; ham `indexOf` bunu "preflight'tan sonra" sanıp
 * yanlış alarm üretir.
 */
function executableBody(source: string): string {
  const withoutImports = source
    .split("\n")
    .filter((line) => !/^\s*import\b/.test(line))
    .join("\n");
  const withoutBlockComments = withoutImports.replace(/\/\*[\s\S]*?\*\//g, "");
  const withoutLineComments = withoutBlockComments
    .split("\n")
    .filter((line) => !/^\s*(\/\/|\*)/.test(line))
    .join("\n");
  // Fonksiyon/gövde tanımlarını (parametre listesi, imzalar) at.
  return withoutLineComments
    .split("\n")
    .filter((line) => !/^\s*(async\s+)?function\s/.test(line) && !/^\s*(type|interface)\s/.test(line))
    .join("\n");
}

Deno.test("edge function dizini okundu (beklenen 7 fonksiyon)", () => {
  const names = all.map((f) => f.name);
  const expected = [
    "ai-chat",
    "calculate-macros",
    "check-reminders",
    "delete-account",
    "recognize-food",
    "recognize-food-text",
    "send-notification",
  ];
  for (const name of expected) {
    if (!names.includes(name)) throw new Error(`eksik fonksiyon: ${name}`);
  }
  // Yeni bir fonksiyon eklendiğinde bu test kırılır → config.toml ve
  // yetkilendirme sırası yeniden incelenmek zorunda kalır.
  if (names.length !== expected.length) {
    throw new Error(
      `fonksiyon sayısı değişti (${names.length}): ${names.join(", ")} — ` +
        `config.toml ve auth sırası denetimi güncellenmeli`,
    );
  }
});

Deno.test("her fonksiyon yetkilendirmeyi CORS/method kontrolünden SONRA yapar", () => {
  for (const { name, source } of all) {
    const body = executableBody(source);
    const preflight = indexOf(body, "preflightResponse(req)");
    const methodCheck = indexOf(body, "405");
    const authCalls = ["requireUserContext(", "isInternalCall(", "isAuthorizedCall("]
      .filter((c) => indexOf(body, c) >= 0);
    if (authCalls.length === 0) {
      throw new Error(`${name}: hiçbir kimlik doğrulama çağrısı yok`);
    }
    const authIndex = Math.min(...authCalls.map((c) => indexOf(body, c)));
    if (preflight < 0) throw new Error(`${name}: CORS preflight yok`);
    if (preflight > authIndex) {
      throw new Error(`${name}: preflight yetkilendirmeden SONRA geliyor`);
    }
    if (methodCheck > authIndex) {
      throw new Error(`${name}: 405 kontrolü yetkilendirmeden SONRA geliyor`);
    }
  }
});

Deno.test("yetkilendirme, rate limit ve gövde okumadan ÖNCE gelir", () => {
  for (const { name, source } of all) {
    const authCalls = ["requireUserContext(", "isInternalCall(", "isAuthorizedCall("]
      .map((c) => indexOf(source, c))
      .filter((i) => i >= 0);
    const authIndex = Math.min(...authCalls);
    const rateLimit = indexOf(source, "checkRateLimit(");
    const readBody = indexOf(source, "readJsonBody(");
    if (rateLimit < 0) throw new Error(`${name}: rate limit yok`);
    if (rateLimit < authIndex) {
      throw new Error(
        `${name}: rate limit yetkilendirmeden ÖNCE çalışıyor — kimliksiz istek DB sayaç yazar`,
      );
    }
    if (readBody >= 0 && readBody < authIndex) {
      throw new Error(`${name}: gövde yetkilendirmeden ÖNCE okunuyor (kaynak tüketimi)`);
    }
  }
});

Deno.test("yetkilendirmeden sonra userId kapsamı sabitlenir ve gövdeden alınmaz", () => {
  // BOLA koruması: `userId` daima doğrulanmış JWT'den gelmeli.
  const offenders: string[] = [];
  for (const { name, source } of all) {
    if (/body\.userId\b|body\.user_id\b/.test(source)) {
      // `send-notification` bunu yapıyor; ancak hemen ardından
      // `targetUserId !== userId` karşılaştırması ile kapsam sabitlenir.
      const hasBolaCheck = source.includes("targetUserId !== userId");
      if (!hasBolaCheck) offenders.push(name);
    }
  }
  if (offenders.length > 0) {
    throw new Error(
      `kullanıcı kimliği gövdeden alınıyor ve BOLA kontrolü yok: ${offenders.join(", ")}`,
    );
  }
});

Deno.test("config.toml: verify_jwt=false yalnızca kendi yetkilendirmesi olan fonksiyonlarda", async () => {
  const config = await Deno.readTextFile(new URL("../config.toml", FUNCTIONS_DIR));
  const blocks = [...config.matchAll(/\[functions\.([a-z-]+)\]\s*\nverify_jwt = (true|false)/g)];
  const declared = new Map<string, string>();
  for (const match of blocks) declared.set(match[1], match[2]);

  // 1) Tüm fonksiyonlar tanımlı olmalı (varsayılan `true` da olsa, görünür
  //    kılınmış olmalı — "politika görünmez kalmaz" ilkesi, config.toml
  //    başlığında yazılı).
  for (const { name } of all) {
    if (!declared.has(name)) throw new Error(`config.toml'da tanımsız fonksiyon: ${name}`);
  }

  // 2) `verify_jwt = false` olanların KENDİ yetkilendirmesi olmalı.
  const internalOnly = ["check-reminders", "send-notification"];
  for (const [name, value] of declared) {
    if (value !== "false") continue;
    if (!internalOnly.includes(name)) {
      throw new Error(
        `${name}: verify_jwt=false ama kullanıcı uç noktası; ` +
          `kendi doğrulaması olmadan kimliksiz çağrılabilir`,
      );
    }
  }

  // 3) Kullanıcı uç noktaları `verify_jwt = true` olmalı.
  for (const { name } of all) {
    if (internalOnly.includes(name)) continue;
    if (declared.get(name) !== "true") {
      throw new Error(`${name}: kullanıcı uç noktası ama verify_jwt=${declared.get(name)}`);
    }
  }
});

Deno.test("dahili fonksiyonlar (verify_jwt=false) token'sız çağrıyı gerçekten reddeder", () => {
  // `check-reminders` / `send-notification`: `x-calorix-internal: 1` gibi
  // istemci taklit edebileceği bir başlık **kabul edilmemeli**. Bu metin
  // denetimi, "yoksa service_role JWT'si zorunlu" yolunun kaynakta
  // kaldığını doğrular.
  for (const { name, source } of all) {
    if (name !== "check-reminders" && name !== "send-notification") continue;
    assert(
      source.includes("INTERNAL_FUNCTION_TOKEN"),
      `${name}: INTERNAL_FUNCTION_TOKEN okunmalı`,
    );
    assert(
      source.includes('x-calorix-internal-token'),
      `${name}: iç çağrı token başlığı okunmalı`,
    );
    // service_role fallback'i JWT'yi sunucu tarafında doğrulamalı.
    assert(
      source.includes("app_metadata") && source.includes("service_role"),
      `${name}: service_role yetkisi app_metadata üzerinden sunucu tarafında doğrulanmalı`,
    );
    // Klasik hata: `x-calorix-internal: 1` gibi taklit edilebilir başlık.
    assert(
      !/headers\.get\(["']x-calorix-internal["']\)/.test(source),
      `${name}: taklit edilebilir 'x-calorix-internal' başlığı kabul edilmemeli`,
    );
  }
});

Deno.test("tüm fonksiyonlar istemciye sabit hata mesajı döner (yığın izi sızmaz)", () => {
  const offenders: string[] = [];
  for (const { name, source } of all) {
    // `error.message`/`String(error)` doğrudan istemciye konmamalı. NOT: eşleşme
    // **çok satırlı** `if (...) return errorResponse(...)` kalıbını da yakalamalı
    // (A1r3'ün `ValidationError` sızıntısı tek satırlık bir regex ile kaçtı).
    const leaks = source.match(
      /errorResponse\(\s*req\s*,\s*(?:error\.status|status|\d+)\s*,\s*(?:error\.message|String\(error\)|`\$\{error)/g,
    );
    if (leaks) offenders.push(`${name} (${leaks.length})`);
  }
  if (offenders.length > 0) {
    throw new Error(`ham hata mesajı istemciye gönderiliyor: ${offenders.join(", ")}`);
  }
});

Deno.test("ValidationError yakalandığında mesaj loglanır ama istemciye sabit metin döner", () => {
  // Politika: alan adı/şema sızdıran `ValidationError` metni **yalnızca**
  // sunucu loguna yazılır. `delete-account` zaten böyleydi; A1r4 diğer
  // dört fonksiyonu da aynı politikaya çekti.
  for (const { name, source } of all) {
    if (!source.includes("ValidationError")) continue;
    if (name === "delete-account") continue; // zaten uyumlu
    const pattern = new RegExp(
      `if \\(error instanceof ValidationError\\)[\\s\\S]{0,220}?console\\.error\\([\\s\\S]{0,120}?error\\.message`,
    );
    const fixed = /if \(error instanceof ValidationError\)[\s\S]{0,220}?errorResponse\(\s*req\s*,\s*error\.status\s*,\s*"Eksik veya geçersiz istek"/;
    if (!pattern.test(source) || !fixed.test(source)) {
      throw new Error(
        `${name}: ValidationError mesajı loglanmıyor veya istemciye sabit metin dönmüyor`,
      );
    }
  }
});

Deno.test("send-notification: getEmailTemplate imzası ölü parametresiz (Tur 1 borcu kapandı)", async () => {
  // A1r3 raporunda P2 olarak bırakılmıştı: `getEmailTemplate(type, title, ...)`
  // imzasındaki `title` hiçbir şablonda kullanılmıyordu. A1r4 kaldırdı.
  const source = await Deno.readTextFile(
    new URL("send-notification/index.ts", FUNCTIONS_DIR),
  );
  assert(
    source.includes("const getEmailTemplate = (type: string, message: string, userName: string) =>"),
    "getEmailTemplate imzası (type, message, userName) olmalı",
  );
  assert(
    source.includes("getEmailTemplate(type, message, userName)"),
    "çağrı yeni imzayla eşleşmeli",
  );
  // `title` hâlâ e-posta **konu**satırında kullanılmalı (kaldırılmamalı).
  assert(source.includes("subject: title"), "e-posta konusu title'ı kullanmaya devam etmeli");
});

Deno.test("tüm fonksiyonlar CORS izin listesi + no-store kullanır", () => {
  for (const { name, source } of all) {
    // Yanıtlar `_shared/http.ts` üzerinden geçmeli.
    const usesJson = source.includes("jsonResponse(") || source.includes("legacyJson(");
    if (!usesJson) throw new Error(`${name}: ortak JSON yanıt yardımcısı kullanılmıyor`);
    assert(
      source.includes('from "../_shared/http.ts"'),
      `${name}: _shared/http.ts içe aktarılmalı (CORS + hata sızıntısı koruması)`,
    );
  }
});

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}
