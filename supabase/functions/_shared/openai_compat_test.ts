/**
 * `openai_compat.ts` saf katman birim testleri (A1r11) — **ağ gerektirmez**.
 *
 * Çalıştırma:
 *   cd supabase && deno test --frozen=true --allow-env --allow-read --allow-net \
 *     functions/_shared/openai_compat_test.ts
 *
 * ---------------------------------------------------------------------------
 * Bu testler hangi ÜRETİM HATASINI kilitler?
 * ---------------------------------------------------------------------------
 * `calculate-macros/index.ts` (ölçüm: MODEL-UYUMLULUK-RAPORU.md) üç ayrı
 * sağlayıcı varsayımıyla çalışıyordu:
 *
 *   A) `message.content` **her zaman düz string**dir.
 *      → Gemini/proxy katmanları content-parts **dizi**si döndüğünde
 *        `if (!content)` geçer (dizi boş değildir!), `JSON.parse(dizi)` ya
 *        TypeError verir ya da alanları okunmayan bir nesne üretir → sessiz
 *        hatalı hedef ya da 502.
 *   B) `JSON.parse(content)` **her zaman** çalışır.
 *      → Model ```` ```json ```` bloğü ya da "Here's the JSON:" öneki
 *        döndürdüğünde doğrudan parse PATLAR.
 *   C) Kesilmiş yanıt (`finish_reason: "length"`) **yeterince** yakalanır.
 *      → `JSON.parse` yarım metni "şanslıysa" kabul eder ve **yarım makro
 *        hedefleri kullanıcıya geçerli cevap olarak gider**. Bu, A1r4'ün
 *        "kısmi silme 200 başarı" ile kapattığı hatanın aynı türüdür.
 *
 * ⭐ NEGATİF ÖLÇÜM: `openai_compat_test.ts` içindeki "KALDIRMA TESTLERİ"
 *   bölümü, düzeltmeyi geri alıp kırmızı görmek için kullanılır
 *   (bkz. RAPOR-A1r11, "Negatif ölçüm" bölümü).
 */

import {
  buildRequestBody,
  buildRequestProfiles,
  extractText,
  hasReasoningContent,
  isTruncated,
  parseJsonLoose,
  parseJsonObjectResponse,
  readFinishReason,
  shouldRetryWithNextProfile,
  type RequestProfile,
} from "./openai_compat.ts";

// ---------------------------------------------------------------------------
// Yerel assertion yardımcıları.
//
// ⚠️ Neden `jsr:@std/assert` DEĞİL?
//   `supabase/deno.lock` **değişmemelidir** (görev kuralı + CI `--frozen=true`).
//   std/assert eklemek kilidi yenilemeyi gerektirirdi. Depodaki mevcut testler
//   (`channel_switch_test.ts`, `rate_limit_test.ts`) de aynı yolu izliyor.
// ---------------------------------------------------------------------------
function assert(condition: unknown, message = "assertion başarısız"): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals<T>(actual: T, expected: T, message?: string): void {
  const a = JSON.stringify(actual);
  const b = JSON.stringify(expected);
  if (a !== b) throw new Error(message ?? `beklenen ${b}, alınan ${a}`);
}


// ---------------------------------------------------------------------------
// Yardımcı: sahte sağlayıcı yanıtı üreticileri
// ---------------------------------------------------------------------------
const VALID_MACROS = {
  daily_calorie_target: 2077,
  protein_target_g: 150,
  carbs_target_g: 210,
  fat_target_g: 62,
  daily_water_target_ml: 2800,
  bmr: 1831,
  tdee: 2577,
  explanation: "Kilo kaybı devam ediyor.",
};

function completion(
  message: Record<string, unknown>,
  finishReason: string | null = "stop",
): Record<string, unknown> {
  return {
    id: "chatcmpl-probe",
    object: "chat.completion",
    model: "test-model",
    choices: finishReason === null ? [{ index: 0, message }] : [{ index: 0, message, finish_reason: finishReason }],
    usage: { prompt_tokens: 606, completion_tokens: 208, total_tokens: 814 },
  };
}

function stringContent(text: string, finishReason: string | null = "stop") {
  return completion({ role: "assistant", content: text }, finishReason);
}

function partsContent(parts: unknown[], finishReason: string | null = "stop") {
  return completion({ role: "assistant", content: parts }, finishReason);
}

// ===========================================================================
// 1) extractText — içerik nerede olursa olsun bulunmalı
// ===========================================================================
Deno.test("extractText: düz string content", () => {
  const result = extractText(stringContent(JSON.stringify(VALID_MACROS)));
  assert(result.source === "content_string", `source: ${result.source}`);
  assert(result.contentShape === "string", `shape: ${result.contentShape}`);
  assert(result.text.includes("daily_calorie_target"), "metin içeriği dönmeli");
});

Deno.test("extractText: content-parts DİZİSİ (Gemini/proxy şekli) → metne döner", () => {
  const result = extractText(
    partsContent([
      { type: "text", text: '{"daily_calorie_target": 2077,' },
      { type: "text", text: ' "protein_target_g": 150}' },
    ]),
  );
  // ⭐ Bu, production'da sessizce kaybolan yoldur: `content` dizi olduğu için
  // eski kod `if (!content)` geçiyor, `JSON.parse` diziyi nesne sanıyordu.
  assert(result.source === "content_parts", `source: ${result.source}`);
  assert(result.contentShape === "array", `shape: ${result.contentShape}`);
  assert(result.text === '{"daily_calorie_target": 2077, "protein_target_g": 150}', `text: ${result.text}`);
});

Deno.test("extractText: content null → source none", () => {
  const result = extractText(completion({ role: "assistant", content: null }));
  assert(result.source === "none", `source: ${result.source}`);
  assert(result.contentShape === "null", `shape: ${result.contentShape}`);
  assertEquals(result.text, "");
});

Deno.test("extractText: content undefined/missing → source none", () => {
  const result = extractText(completion({ role: "assistant" }));
  assert(result.source === "none", `source: ${result.source}`);
  assert(result.contentShape === "missing", `shape: ${result.contentShape}`);
});

Deno.test("extractText: boş string içerik → source none", () => {
  const result = extractText(stringContent("   \n  "));
  assert(result.source === "none", `source: ${result.source}`);
  assertEquals(result.text, "");
});

Deno.test("extractText: message.text alanına taşınmış içerik (bazı proxy'ler)", () => {
  const result = extractText(completion({ role: "assistant", content: null, text: JSON.stringify(VALID_MACROS) }));
  assert(result.source === "message_text", `source: ${result.source}`);
  assert(result.text.includes("bmr"), "text alanından okunmalı");
});

Deno.test("extractText: yalnız reasoning_content varsa içerik DEĞİLDİR", () => {
  // ⭐ Sessiz başarısızlık tuzağı: gerekçe metni "içerik" sanılırsa model
  //    çıktısı olmayan bir yanıt geçerli sayılır.
  const result = extractText(
    completion({
      role: "assistant",
      content: null,
      reasoning_content: "Önce BMR'ı hesaplayayım, sonra makroları dağıtayım...",
    }),
  );
  assert(result.source === "none", `source: ${result.source}`);
  assertEquals(result.text, "");
  assert(hasReasoningContent({ choices: [{ message: { reasoning_content: "x" } }] }), "reasoning algılanmalı");
});

Deno.test("extractText: choices yoksa / message null ise çökmez", () => {
  assertEquals(extractText(null).text, "");
  assertEquals(extractText({}).text, "");
  assertEquals(extractText({ choices: [] }).text, "");
  assertEquals(extractText({ choices: [{ message: null }] }).text, "");
  assertEquals(extractText("string değil").text, "");
  assertEquals(extractText({ choices: "dizi değil" }).text, "");
});

Deno.test("extractText: içerik parçası içinde iç içe tırnaklı metin", () => {
  const result = extractText(partsContent([{ type: "text", text: '{"explanation": "içte } parantez var"}' }]));
  assert(result.source === "content_parts", `source: ${result.source}`);
  assert(result.text.includes("}"), "tırnak içindeki } korunmalı");
});

// ===========================================================================
// 2) parseJsonLoose — sarmalayıcıları soy, bozuğu UYDURMA
// ===========================================================================
Deno.test("parseJsonLoose: temiz JSON", () => {
  const parsed = parseJsonLoose<{ a: number }>('{"a":1}');
  assert(parsed !== null, "parse edilmeli");
  assertEquals(parsed!.a, 1);
});

Deno.test("parseJsonLoose: ```json kod bloğu içinde", () => {
  const parsed = parseJsonLoose<{ a: number }>('```json\n{"a":1}\n```');
  assert(parsed !== null, "kod bloğu soyulmalı");
  assertEquals(parsed!.a, 1);
});

Deno.test("parseJsonLoose: dil etiketsiz ``` bloğu", () => {
  const parsed = parseJsonLoose<{ a: number }>('```\n{"a":2}\n```');
  assert(parsed !== null, "dil etiketsiz blok da soyulmalı");
  assertEquals(parsed!.a, 2);
});

Deno.test("parseJsonLoose: ön metin ('Here's the JSON:')", () => {
  const parsed = parseJsonLoose<{ a: number }>("Here's the JSON:\n{\"a\":3}");
  assert(parsed !== null, "ön metin atlanmalı");
  assertEquals(parsed!.a, 3);
});

Deno.test("parseJsonLoose: son metin açıklaması", () => {
  const parsed = parseJsonLoose<{ a: number }>('{"a":4}\n\nUmarım yardımcı olur!');
  assert(parsed !== null, "son metin atlanmalı");
  assertEquals(parsed!.a, 4);
});

Deno.test("parseJsonLoose: ön + son metin + kod bloğu", () => {
  const parsed = parseJsonLoose<{ a: number }>('Tabii! İşte sonuç:\n```json\n{"a":5}\n```\nBaşka sorun?');
  assert(parsed !== null, "kombinasyon çözülmeli");
  assertEquals(parsed!.a, 5);
});

// ⭐ NEGATİF ÖLÇÜM DERSİ (A1r11) — bu test, "kod bloğu temizleme
//   kaldırılınca test kırmızıya döner" kuralını **garanti eder**.
//   İlk yazımda testler yeşil kalıyordu: çünkü mevcut testler, ön metin
//   içinde **başka bir `{...}` bulunmayan** durumları ölçüyordu ve
//   `sliceBalanced` temizliği zaten üstleniyordu. Aşağıdaki senaryo ise
//   "ön metinde şema örneği de var" halini ölçer: burada gerçek yanıt
//   **ikinci** JSON'dur ve ilk-blok seçimi YANLIŞ cevabı verir.
//   Kod bloğu adımı olmadan parse `{"a":0}` döner → bu test kırmızıya düşer.
Deno.test("parseJsonLoose: ön metinde şema ÖRNEĞİ varsa GERÇEK kod bloğu seçilir", () => {
  const raw = [
    "Beklenen format (örnek): {\"daily_calorie_target\": 0, \"bmr\": 0}",
    "```json",
    JSON.stringify({ daily_calorie_target: 2077, bmr: 1831 }),
    "```",
  ].join("\n");
  const parsed = parseJsonLoose<{ daily_calorie_target: number; bmr: number }>(raw);
  assert(parsed !== null, "parse edilmeli");
  // ⚠️ 0 değerleri ÖRNEK verisidir; gerçek yanıttır.
  assertEquals(parsed!.daily_calorie_target, 2077, "gerçek yanıt seçilmeli, örnek değil");
  assertEquals(parsed!.bmr, 1831, "gerçek yanıt seçilmeli, örnek değil");
});

Deno.test("parseJsonLoose: boş kod bloğu + gerçek metin (blok atlanır)", () => {
  // Model boş bir kod bloğu açıp kapanmış, içeriği normal metinde yazmış olabilir.
  const raw = '```json\n```\n{"a":9}';
  const parsed = parseJsonLoose<{ a: number }>(raw);
  assert(parsed !== null, "blok boşsa normal metinden ayrıştırmalı");
  assertEquals(parsed!.a, 9);
});

Deno.test("parseJsonLoose: kod bloğu JSON DEĞİLSE normal metne düşer", () => {
  // Bozuk blok içeriği varsa (ör. "```json\nexplained\n```") ayrıştırma
  // yapılmaz; bir sonraki adıma düşülür.
  const raw = '```json\nbu JSON değil\n```\n{"a":11}';
  const parsed = parseJsonLoose<{ a: number }>(raw);
  assert(parsed !== null, "bozuk blok sonrası normal metin ayrıştırılmalı");
  assertEquals(parsed!.a, 11);
});

Deno.test("parseJsonLoose: dizi kökü", () => {
  const parsed = parseJsonLoose<Array<{ a: number }>>("Sonuçlar: [{\"a\":6}]");
  assert(Array.isArray(parsed), "dizi kökü bulunmalı");
  assertEquals(parsed![0].a, 6);
});

Deno.test("parseJsonLoose: EKSİK alan → nesne döner ama alan eksiktir (uydurma yok)", () => {
  // Model makroları unuttuysa `parseJsonLoose` **kısmi nesne** döndürür;
  // doğrulama katmanı (requireNumber) eksik alanı yakalar. Burada asıl
  // kritik olan: parse hatası gizlenmiyor, alan eksikliği görünür.
  const parsed = parseJsonLoose<Record<string, unknown>>('{"daily_calorie_target": 2000}');
  assert(parsed !== null, "kısmi JSON ayrıştırılmalı");
  assertEquals(parsed!["protein_target_g"], undefined);
});

Deno.test("parseJsonLoose: bozuk tırnak → null (sessizce düzeltilMEZ)", () => {
  const parsed = parseJsonLoose('{"a": "bozuk tırnak}');
  assertEquals(parsed, null);
});

Deno.test("parseJsonLoose: KESİLMİŞ JSON → null (yarım nesne UYDURULMAZ)", () => {
  // ⭐ Bu test, "yarım cevabı kullanıcıya gönderme" kuralının kilididir.
  const parsed = parseJsonLoose('{"daily_calorie_target": 2077, "protein_target_g": 150, "carbs_');
  assertEquals(parsed, null);
});

Deno.test("parseJsonLoose: kesilmiş JSON'da sürekli/az sayı geçer", () => {
  // Kesilmiş metin `{"a": 1` gibi bir sonuç verirse bile bu bozuk kabul edilir.
  assertEquals(parseJsonLoose('{"daily_calorie_target": 2077, "bmr": 1831'), null);
});

Deno.test("parseJsonLoose: boş/null girdi → null", () => {
  assertEquals(parseJsonLoose(""), null);
  assertEquals(parseJsonLoose("   "), null);
  assertEquals(parseJsonLoose(null), null);
  assertEquals(parseJsonLoose(undefined), null);
});

Deno.test("parseJsonLoose: düz sayı metni JSON değildir", () => {
  // `"42"` parse edilir ama nesne değildir; `parseJsonObjectResponse` bunu
  // `not_object` olarak eler. Katman ayrımı test ediliyor.
  assertEquals(parseJsonLoose("42"), 42);
  assertEquals(parseJsonLooseObject("42"), false);
});

function parseJsonLooseObject(raw: string): boolean {
  const value = parseJsonLoose(raw);
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

// ===========================================================================
// 3) finish_reason — kesilmiş yanıt kapısı
// ===========================================================================
Deno.test("isTruncated: length / max_tokens / TOKEN_LIMIT", () => {
  assert(isTruncated("length"), "length kesilmedir");
  assert(isTruncated("max_tokens"), "max_tokens kesilmedir");
  assert(isTruncated("MAX_TOKENS"), "büyük harf normalleştirilir");
  assert(isTruncated("token_limit"), "token_limit kesilmedir");
});

Deno.test("isTruncated: stop / tool_calls / null kesilme DEĞİLDİR", () => {
  assertEquals(isTruncated("stop"), false);
  assertEquals(isTruncated("tool_calls"), false);
  assertEquals(isTruncated("content_filter"), false);
  assertEquals(isTruncated(null), false);
});

Deno.test("readFinishReason", () => {
  assertEquals(readFinishReason(stringContent("{}", "length")), "length");
  assertEquals(readFinishReason({ choices: [{ finish_reason: "stop" }] }), "stop");
  assertEquals(readFinishReason({}), null);
  assertEquals(readFinishReason(null), null);
  assertEquals(readFinishReason({ choices: [{}] }), null);
});

// ===========================================================================
// 4) parseJsonObjectResponse — üretim hattının tam kapısı
// ===========================================================================
Deno.test("parseJsonObjectResponse: mutlu yol (OpenAI string içerik)", () => {
  const result = parseJsonObjectResponse(stringContent(JSON.stringify(VALID_MACROS)));
  assert(result.ok, "başarılı olmalı");
  if (result.ok) assertEquals(result.value["daily_calorie_target"], 2077);
});

Deno.test("parseJsonObjectResponse: content-parts dizisi → BAŞARILI (eski kod 502 dönerdi)", () => {
  const result = parseJsonObjectResponse(
    partsContent([{ type: "text", text: JSON.stringify(VALID_MACROS) }]),
  );
  assert(result.ok, "content-parts dizisi işlenmeli");
  if (result.ok) assertEquals(result.value["bmr"], 1831);
});

Deno.test("parseJsonObjectResponse: message.text taşınmış içerik → BAŞARILI", () => {
  const result = parseJsonObjectResponse(
    completion({ role: "assistant", content: null, text: JSON.stringify(VALID_MACROS) }),
  );
  assert(result.ok, "text alanı okunmalı");
});

Deno.test("parseJsonObjectResponse: kesilmiş yanıt → HATA, yarım veri DÖNMEZ", () => {
  const result = parseJsonObjectResponse(
    stringContent('{"daily_calorie_target": 2077, "protein_target_g": 150, "carbs_', "length"),
  );
  assertEquals(result.ok, false, "kesilmiş yanıt kabul edilmemeli");
  if (!result.ok) {
    assertEquals(result.reason, "truncated", `reason: ${result.reason}`);
    assertEquals(result.diagnostic.finishReason, "length", "tanıda finish_reason olmalı");
  }
});

Deno.test("parseJsonObjectResponse: kesilmiş AMA parse edilebilir yanıt → yine HATA", () => {
  // ⭐ EN TEHLİKELİ HALE: JSON.parse kabul ediyor ama veri eksik.
  const truncatedButParsable = '{"daily_calorie_target": 2077, "protein_target_g": 150}';
  const result = parseJsonObjectResponse(stringContent(truncatedButParsable, "length"));
  assertEquals(result.ok, false, "finish_reason=length her zaman reddedilmeli");
  if (!result.ok) assertEquals(result.reason, "truncated");
});

Deno.test("parseJsonObjectResponse: içerik yok → no_content", () => {
  const result = parseJsonObjectResponse(completion({ role: "assistant", content: null }));
  assertEquals(result.ok, false);
  if (!result.ok) assertEquals(result.reason, "no_content");
});

Deno.test("parseJsonObjectResponse: bozuk metin → not_json", () => {
  const result = parseJsonObjectResponse(stringContent("Maalesef JSON üretemiyorum, tekrar deneyin."));
  assertEquals(result.ok, false);
  if (!result.ok) assertEquals(result.reason, "not_json");
});

Deno.test("parseJsonObjectResponse: dizi kökü → not_object", () => {
  const result = parseJsonObjectResponse(stringContent('["a","b"]'));
  assertEquals(result.ok, false);
  if (!result.ok) assertEquals(result.reason, "not_object");
});

Deno.test("parseJsonObjectResponse: tanı alanları anahtar/gövde SIZDIRMAZ", () => {
  const result = parseJsonObjectResponse(
    stringContent("API anahtarım sk-ustagpt-GIZLI sızdı", "length"),
  );
  const serialized = JSON.stringify(result);
  assert(!serialized.includes("GIZLI"), "tanı gövdeyi taşımamalı");
  assertEquals(result.ok, false);
});

Deno.test("parseJsonObjectResponse: tanı alanları model+şekil bilgisini taşır", () => {
  const result = parseJsonObjectResponse(partsContent([], null));
  assertEquals(result.ok, false);
  if (!result.ok) {
    assertEquals(result.diagnostic.contentShape, "array", "content şekli tanıda olmalı");
  }
});

// ===========================================================================
// 5) İstek profilleri — kademeli geri çekilme
// ===========================================================================
Deno.test("buildRequestBody: response_format açıkken json_object gönderilir", () => {
  const body = buildRequestBody("m", "S", "U", { jsonMode: true, tokenField: "max_tokens", temperature: 0.7, maxTokens: 500 });
  assertEquals(body.response_format, { type: "json_object" });
  assertEquals(body.max_tokens, 500);
  assertEquals(body.temperature, 0.7);
  assertEquals(body.max_completion_tokens, undefined);
});

Deno.test("buildRequestBody: response_format kapalıyken alan HİÇ gönderilmez", () => {
  const body = buildRequestBody("m", "S", "U", { jsonMode: false, tokenField: "max_completion_tokens", temperature: 0.7, maxTokens: 800 });
  assertEquals(body.response_format, undefined);
  assertEquals(body.max_completion_tokens, 800);
  assertEquals(body.max_tokens, undefined);
});

Deno.test("buildRequestBody: temperature null → alan gönderilmez (reasoning modelleri)", () => {
  const body = buildRequestBody("m", "S", "U", { jsonMode: false, tokenField: "max_tokens", temperature: null, maxTokens: 500 });
  assertEquals("temperature" in body, false, "temperature anahtarı hiç bulunmamalı");
});

Deno.test("buildRequestBody: system+user mesajları her zaman var", () => {
  const body = buildRequestBody("m", "SİSTEM", "KULLANICI", { jsonMode: true, tokenField: "max_tokens", temperature: 0.7, maxTokens: 500 });
  const messages = body.messages as Array<Record<string, string>>;
  assertEquals(messages.length, 2);
  assertEquals(messages[0].role, "system");
  assertEquals(messages[0].content, "SİSTEM");
  assertEquals(messages[1].role, "user");
  assertEquals(messages[1].content, "KULLANICI");
});

Deno.test("buildRequestProfiles: tam çözüm → en kademeliye doğru monotonik gevşeme", () => {
  const profiles = buildRequestProfiles(500);
  assert(profiles.length >= 3, "birden fazla kademe olmalı");
  // İlk kademe production ile birebir aynı.
  assertEquals(profiles[0], { jsonMode: true, tokenField: "max_tokens", temperature: 0.7, maxTokens: 500 });
  // Her kademe bir öncekinden en fazla bir alan eksiktir.
  const countKeys = (p: RequestProfile) => (p.jsonMode ? 1 : 0) + 1 + (p.temperature !== null ? 1 : 0);
  for (let i = 1; i < profiles.length; i++) {
    assert(
      countKeys(profiles[i]) <= countKeys(profiles[i - 1]),
      `kademe ${i} öncekinden daha çok alan içermemeli`,
    );
  }
  // Son kademe mutlaka parametresiz (yalnız model+messages) olmalı ki
  // hiçbir sağlayıcı reddedemez.
  const last = profiles[profiles.length - 1];
  assertEquals(last.jsonMode, false);
  assertEquals(last.temperature, null);
  const body = buildRequestBody("m", "S", "U", last);
  assertEquals("response_format" in body, false);
  assertEquals("temperature" in body, false);
});

Deno.test("shouldRetryWithNextProfile: 400/404/415/422 → kademe ilerlet", () => {
  for (const status of [400, 404, 415, 422, 401, 403]) {
    assert(shouldRetryWithNextProfile(status), `${status} kademe ilerletmeli`);
  }
});

Deno.test("shouldRetryWithNextProfile: 429/5xx/ağ → TEKRAR DENEME (maliyet koruması)", () => {
  for (const status of [429, 408, 425, 500, 502, 503, 504]) {
    assertEquals(shouldRetryWithNextProfile(status), false, `${status} tekrar denenmemeli`);
  }
});

// ===========================================================================
// 6) ⭐ MODEL BAŞINA "ÖNCE KIRILDI, ŞİMDİ GEÇTİ" SENARYOLARI
//    (sahte API yanıtlarıyla — ağ yok)
// ===========================================================================

/** Ölçümde gözlenen kırılma şekli → eski davranış vs yeni davranış. */
interface RegressionCase {
  model: string;
  /** Ölçümde gözlenen upstream yanıtı. */
  response: unknown;
  /**
   * Eski üretim kodu bu yanıtta ne yapardı?
   *  - `ok` = zaten geçiyordu (kontrol grubu; yeni katman da geçmeli)
   *  - diğerleri = kırılıyordu; yeni katman DÜZELTMELİ
   */
  oldBehavior: "ok" | "throws" | "not_object" | "accepts_truncated" | "no_content";
}

const REGRESSION_CASES: RegressionCase[] = [
  {
    // Ölçüm: gemini-2.5-flash `max_tokens: 500` ile **3/3 finish_reason=length**
    // döndürdü; gövde ortada kesildiği için `JSON.parse` doğrudan PATLADI.
    // Yeni katman: `truncated` tanısıyla reddeder (yarım veri asla işlenmez).
    model: "gemini-2.5-flash",
    response: stringContent('{"daily_calorie_target": 2077, "protein_target_g": 150, "carbs_target_g": 210, "fa', "length"),
    oldBehavior: "throws",
  },
  {
    // Ölçüm: bazı sağlayıcılar içeriği content-parts dizisi olarak döndürüyor.
    model: "gemini-3.7-flash",
    response: partsContent([{ type: "text", text: JSON.stringify(VALID_MACROS) }]),
    oldBehavior: "not_object",
  },
  {
    // Ölçüm: proxy içeriği `message.text` alanına taşıyor.
    model: "gemma-4-31b-it",
    response: completion({ role: "assistant", content: null, text: JSON.stringify(VALID_MACROS) }),
    oldBehavior: "no_content",
  },
  {
    model: "glm-5.3-flash",
    response: stringContent("```json\n" + JSON.stringify(VALID_MACROS) + "\n```"),
    oldBehavior: "throws",
  },
  {
    model: "gpt-4.1",
    response: stringContent("İşte hesaplamanız:\n" + JSON.stringify(VALID_MACROS)),
    oldBehavior: "throws",
  },
  {
    // Ölçüm: bu model production parametre setiyle **sorunsuz** çalışıyor
    // (kontrol grubu). Yeni katman da geçmeli — kırılan taraf değil.
    model: "gpt-5-mini",
    response: stringContent(JSON.stringify(VALID_MACROS)),
    oldBehavior: "ok",
  },
];

/**
 * Ölçümde `finish_reason: "length"` gözlenen modeller.
 * Bu modellerde yeni katmanın amacı **düzeltmek değil, reddetmektir**:
 * kesilmiş JSON'dan makro üretmek sessiz başarısızlıktır.
 */
const truncatedCases = new Set<string>(["gemini-2.5-flash"]);

/** Eski üretim kodu (`index.ts:171-184`) — davranışı ölçmek için birebir. */
function oldParseBehavior(data: unknown): { outcome: string; value?: unknown } {
  const choices = (data as { choices?: Array<{ message?: { content?: unknown } }> }).choices;
  const content = choices?.[0]?.message?.content;
  if (!content) return { outcome: "no_content" };
  if (typeof content !== "string") {
    // `JSON.parse(dizi)` TypeError verir; `JSON.parse(nesne)` "[object Object]"e
    // düşer. İkisini de "bozuk nesne" olarak modelliyoruz.
    return { outcome: "not_object" };
  }
  try {
    return { outcome: "ok", value: JSON.parse(content) };
  } catch (_) {
    return { outcome: "throws" };
  }
}

Deno.test("REGRESYON: model başına eski davranış KIRILDI, yeni katman GEÇTİ", () => {
  const seen = new Set<string>();
  let fixedCount = 0;
  for (const testCase of REGRESSION_CASES) {
    // Eski yolun gerçekten bu yanıtta ne yaptığını ÖLÇ (varsayım değil).
    const old = oldParseBehavior(testCase.response);
    assertEquals(
      old.outcome,
      testCase.oldBehavior,
      `${testCase.model}: test kaydı eski davranışla uyuşmuyor (ölçüm: ${old.outcome})`,
    );

    // Yeni yol
    const next = parseJsonObjectResponse(testCase.response);
    if (testCase.oldBehavior === "ok") {
      // Kontrol grubu: çalışan senaryo çalışmaya devam etmeli (regresyon yok).
      assert(next.ok, `${testCase.model}: kontrol grubu bozuldu`);
    } else if (truncatedCases.has(testCase.model)) {
      // Kesilmiş yanıt: yeni katman da reddetmeli (sessiz başarısızlık yok).
      assertEquals(next.ok, false, `${testCase.model}: kesilmiş yanıt kabul edilmemeli`);
      if (!next.ok) assertEquals(next.reason, "truncated", `${testCase.model}: neden 'truncated' olmalı`);
    } else {
      fixedCount++;
      assert(next.ok, `${testCase.model}: yeni katman kırığı düzeltmeli (eski: ${old.outcome})`);
    }
    if (next.ok) {
      assertEquals(next.value["daily_calorie_target"], VALID_MACROS.daily_calorie_target, `${testCase.model}: alanlar okunmalı`);
    }
    seen.add(testCase.model);
  }
  assertEquals(seen.size, 6, "6 modelin her biri için en az 1 senaryo işlenmeli");
  assertEquals(fixedCount, 4, "4 kırık model senaryosu düzeltilmiş olmalı");
  assertEquals(truncatedCases.size + fixedCount + 1, 6, "6 senaryo: düzeltilen + kesilen + kontrol grubu");
});

Deno.test("REGRESYON: kesilmiş yanıt YENİ katmanda da reddedilir (sessiz başarısızlık yok)", () => {
  const result = parseJsonObjectResponse(
    stringContent(JSON.stringify(VALID_MACROS), "length"),
  );
  assertEquals(result.ok, false, "kesilmiş yanıt asla kabul edilmemeli");
  if (!result.ok) assertEquals(result.reason, "truncated");
});

Deno.test("REGRESYON: eksik alanlı ama tamamlanmış yanıt parse edilir, doğrulama katmanı yakalar", () => {
  // Üretim hattında `requireNumber` eksik alanı ValidationError ile reddeder.
  // Saf katmanın görevi yalnız JSON'u doğru ayrıştırmak; sessizce doldurmak DEĞİL.
  const result = parseJsonObjectResponse(stringContent('{"daily_calorie_target": 2000}'));
  assert(result.ok, "JSON geçerli, katman geçirmeli");
  if (result.ok) {
    assertEquals(result.value["protein_target_g"], undefined, "eksik alan UYDURULMAMALI");
  }
});
