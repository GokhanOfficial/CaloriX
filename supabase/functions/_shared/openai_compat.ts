/**
 * OpenAI-uyumlu `/chat/completions` yanıtlarını **sağlayıcıdan bağımsız**
 * okumak için saf katman yardımcıları (A1r11).
 *
 * ⭐ NEDEN VAR
 *   `calculate-macros/index.ts` (ve aynı deseni taşıyan `recognize-food*`,
 *   `ai-chat`) yanıtı şöyle okuyordu:
 *
 *     const content = data.choices?.[0]?.message?.content;
 *     if (!content) return 502;
 *     parsed = JSON.parse(content);
 *
 *   Ölçüm (`plans/analiz-26-09-27/MODEL-UYUMLULUK-RAPORU.md`, A1r11) şunu
 *   gösterdi: bu **tek varsayım** — "içerik daima `message.content` içinde
 *   düz string'dir" — farklı sağlayıcılarda sağmıyor. Aynı endpoint'te
 *   `content` dizi (content-parts) olarak, `message.text` alanında, `null`
 *   olarak dönüyor; `reasoning_content` ayrı geliyor; `finish_reason: "length"`
 *   ile **kesilmiş** JSON dönüyor. Her biri üretimde sessiz 502'ye düşüyor.
 *
 * TASARIM İLKELERİ
 *   1. **Sessiz başarısızlık yasak.** Bozuk/eksik yanıt üzerine uydurma veri
 *      üretilmez; çağıran bunu yakalayıp net hata döner.
 *   2. **Katmanlar tek yerde toplanır**, her edge function kopyalamaz.
 *   3. Saf (ağ/ortam bağımlılığı yok) → birim testi kolay, `deno test` ağsız.
 */

/** Sağlayıcının `message.content` alanında dönebileceği JSON parçası. */
export interface ContentPart {
  type?: string;
  text?: string;
  // Bazı sağlayıcılar `content` yerine `text`/`value`/`output_text` kullanır.
  [key: string]: unknown;
}

/** Bir sağlayıcı yanıtının ilgilendiğimiz kısmı (tamamı `unknown` olabilir). */
export interface ChatCompletionLike {
  choices?: Array<{
    message?: {
      content?: string | ContentPart[] | null;
      text?: string | null;
      reasoning_content?: string | null;
      reasoning?: string | null;
      [key: string]: unknown;
    } | null;
    finish_reason?: string | null;
    [key: string]: unknown;
  }>;
  [key: string]: unknown;
}

/** Yanıtın okunabildiği kanıtı — hata ayıklamada **model adı + şekil** loglanır. */
export interface ExtractedText {
  text: string;
  /** İçeriğin bulunduğu yer (tanı için; istemciye ASLA dönülmez). */
  source: "content_string" | "content_parts" | "message_text" | "none";
  /** `content` gerçekte hangi tipteydi (tanı için). */
  contentShape: "string" | "array" | "null" | "missing" | "other";
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Bir content-part dizisinden metin parçalarını toplar. */
function partsToText(parts: unknown[]): string {
  const chunks: string[] = [];
  for (const part of parts) {
    if (typeof part === "string") {
      chunks.push(part);
      continue;
    }
    if (!isRecord(part)) continue;
    // OpenAI content-part: { type: "text", text: "..." }
    // Vertex/Bedrock tarzı: { text: "..." } veya { output_text: "..." }
    for (const key of ["text", "output_text", "value", "content"] as const) {
      const candidate = part[key];
      if (typeof candidate === "string" && candidate) {
        chunks.push(candidate);
        break;
      }
    }
  }
  return chunks.join("");
}

/**
 * Sağlayıcıdan bağımsız metin çıkarma.
 *
 * Denenen sıra:
 *   1. `message.content` düz string ise
 *   2. `message.content` dizi ise → içindeki text parçalarının birleşimi
 *   3. `message.text` (bazı proxy'ler içeriği buraya taşır)
 *   4. `message.output_text` (Responses API tarzı proxy'ler)
 *   5. hiçbiri yoksa `source: "none"`, `text: ""`
 *
 * ⚠️ `reasoning_content` **bilinçli olarak kullanılmaz**: gerekçe/analiz
 * metnidir ve makro JSON'u içermez. Onu "içerik" sanmak, model çıktısı
 * olmayan bir yanıtı geçerli sayardı (sessiz başarısızlık).
 */
export function extractText(data: unknown): ExtractedText {
  const root = isRecord(data) ? data : null;
  const choices = root && Array.isArray(root.choices) ? root.choices : [];
  const choice = choices.length ? choices[0] : null;
  const message = choice && isRecord(choice.message) ? choice.message : null;

  if (!message) {
    return { text: "", source: "none", contentShape: "missing" };
  }

  const content = message.content;
  if (typeof content === "string" && content.trim()) {
    return { text: content, source: "content_string", contentShape: "string" };
  }
  if (Array.isArray(content)) {
    const text = partsToText(content);
    if (text.trim()) return { text, source: "content_parts", contentShape: "array" };
  }
  for (const key of ["text", "output_text"] as const) {
    const candidate = message[key];
    if (typeof candidate === "string" && candidate.trim()) {
      return { text: candidate, source: "message_text", contentShape: typeof content === "string" ? "string" : Array.isArray(content) ? "array" : content === null || content === undefined ? "missing" : "other" };
    }
  }

  const shape: ExtractedText["contentShape"] = content === null
    ? "null"
    : content === undefined
    ? "missing"
    : Array.isArray(content)
    ? "array"
    : typeof content === "string"
    ? "string"
    : "other";
  return { text: "", source: "none", contentShape: shape };
}

/**
 * Ayarlanabilir JSON çıkarma.
 *
 * Model sarmalayıcıları (```` ```json ... ``` ````, `Here's the JSON:`, sonundaki
 * açıklama cümlesi) yaygındır. Sırayla dener:
 *   1. doğrudan `JSON.parse`
 *   2. kod bloğunu (```json / ```) soy
 *   3. metindeki **ilk `{` ile son `}`** arasını al
 *   4. ilk `[{` ile son `}]` arasını al (dizi kökü)
 *
 * ⚠️ **Kırık JSON onarımı YAPILMAZ.** Yarım/bozuk metin üzerine tahmin
 * edilen sayı üretmek, kullanıcıya yanlış hedef göstermektir (A1r4'ün
 * "kısmi silme 200 başarı" hatasının aynısı). Onarılamazsa `null` döner ve
 * çağıran **net hata** verir.
 */
export function parseJsonLoose<T = unknown>(raw: string | null | undefined): T | null {
  if (typeof raw !== "string") return null;
  const text = raw.trim();
  if (!text) return null;

  const direct = tryParse<T>(text);
  if (direct !== undefined) return direct;

  // ```json ... ``` / ``` ... ``` kod bloğu
  const fenced = /```(?:[a-zA-Z0-9_+-]*)\s*\n?([\s\S]*?)```/.exec(text);
  if (fenced?.[1]) {
    const parsed = tryParse<T>(fenced[1].trim());
    if (parsed !== undefined) return parsed;
  }

  // Açıklama + nesne / dizi.
  //
  // ⚠️ SIRA ÖNEMLİ: `Sonuçlar: [{"a":1}]` metninde `{` **diziden önce**
  // gelmez ama `sliceBalanced(text,"{","}")` dizinin İÇİNDEKİ nesneyi döndürür
  // ve dizi kökü sessizce kaybolur. Bu yüzden metinde **önce başlayan**
  // parça seçilir: kök hangisi önce geliyorsa odur.
  const objectSlice = sliceBalanced(text, "{", "}");
  const arraySlice = sliceBalanced(text, "[", "]");
  const candidates: Array<{ start: number; text: string }> = [];
  if (objectSlice !== null) candidates.push({ start: text.indexOf("{"), text: objectSlice });
  if (arraySlice !== null) candidates.push({ start: text.indexOf("["), text: arraySlice });
  candidates.sort((a, b) => a.start - b.start);
  for (const candidate of candidates) {
    const parsed = tryParse<T>(candidate.text);
    if (parsed !== undefined) return parsed;
  }

  return null;
}

function tryParse<T>(text: string): T | undefined {
  if (!text) return undefined;
  try {
    return JSON.parse(text) as T;
  } catch (_) {
    return undefined;
  }
}

/**
 * `open` ile `close` karakterleri arasındaki **ilk tam parçayı** döndürür.
 * Tırnak/escape farkında saymaz, böylece açıklama metnindeki `{` karakteri
 * JSON'u bozmaz. Eşleşen kapanış yoksa `null` döner (kesilmiş yanıt tespiti).
 */
function sliceBalanced(text: string, open: string, close: string): string | null {
  const start = text.indexOf(open);
  if (start === -1) return null;
  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let i = start; i < text.length; i++) {
    const char = text[i];
    if (inString) {
      if (escaped) escaped = false;
      else if (char === "\\") escaped = true;
      else if (char === '"') inString = false;
      continue;
    }
    if (char === '"') {
      inString = true;
      continue;
    }
    if (char === open) depth++;
    else if (char === close) {
      depth--;
      if (depth === 0) return text.slice(start, i + 1);
    }
  }
  return null; // kapanış yok → kesilmiş yanıt
}

/** `finish_reason` okur; yoksa `null`. */
export function readFinishReason(data: unknown): string | null {
  const root = isRecord(data) ? data : null;
  const choices = root && Array.isArray(root.choices) ? root.choices : [];
  const choice = choices.length && isRecord(choices[0]) ? choices[0] : null;
  const reason = choice?.finish_reason;
  return typeof reason === "string" ? reason : null;
}

/** Upstream'in gövdeyi kesip kesmediğini söyler (`length`/`max_tokens`). */
export function isTruncated(finishReason: string | null): boolean {
  if (!finishReason) return false;
  const reason = finishReason.toLowerCase();
  return reason === "length" || reason === "max_tokens" || reason === "token_limit";
}

/** `reasoning_content` var mı? (yalnız **tanı** loglaması için). */
export function hasReasoningContent(data: unknown): boolean {
  const root = isRecord(data) ? data : null;
  const choices = root && Array.isArray(root.choices) ? root.choices : [];
  const choice = choices.length && isRecord(choices[0]) ? choices[0] : null;
  const message = choice && isRecord(choice.message) ? choice.message : null;
  if (!message) return false;
  const reasoning = message.reasoning_content ?? message.reasoning;
  return typeof reasoning === "string" && reasoning.length > 0;
}

// ===========================================================================
// İSTEK GÖVDESİ — sağlayıcı kademeli geri çekilmesi (A1r11)
// ===========================================================================

/** Kademeli denenecek istek parametreleri. */
export interface RequestProfile {
  /** `response_format: { type: "json_object" }` gönderilsin mi? */
  jsonMode: boolean;
  /** Token sınırı alanı. */
  tokenField: "max_tokens" | "max_completion_tokens";
  /** `temperature` gönderilsin mi (reasoning modelleri reddedebilir)? */
  temperature: number | null;
  maxTokens: number;
}

export function buildRequestBody(
  model: string,
  systemPrompt: string,
  userPrompt: string,
  profile: RequestProfile,
): Record<string, unknown> {
  const body: Record<string, unknown> = {
    model,
    messages: [
      { role: "system", content: systemPrompt },
      { role: "user", content: userPrompt },
    ],
  };
  if (profile.jsonMode) body.response_format = { type: "json_object" };
  body[profile.tokenField] = profile.maxTokens;
  if (profile.temperature !== null) body.temperature = profile.temperature;
  return body;
}

/**
 * Sağlayıcı reddi (4xx) için **kademeli** geri çekilme sırası.
 *
 * Ölçüm gerekçesi (bkz. MODEL-UYUMLULUK-RAPORU.md):
 *   - `response_format` desteklemeyen sağlayıcı 400 döner → önce kaldırılır.
 *   - `max_completion_tokens` isteyen modeller `max_tokens`'ı reddeder → alan değişir.
 *   - `temperature` kabul etmeyen reasoning modelleri 400 döner → alan kaldırılır.
 *
 * `retries` yalnız **istem reddi (4xx)** üzerinde ilerler; 5xx/ağ hatasında
 * tekrar denemek yanlış (aynı hata tekrarlanır, gecikme uzar).
 */
export function buildRequestProfiles(maxTokens: number): RequestProfile[] {
  return [
    { jsonMode: true, tokenField: "max_tokens", temperature: 0.7, maxTokens },
    { jsonMode: false, tokenField: "max_completion_tokens", temperature: 0.7, maxTokens },
    { jsonMode: false, tokenField: "max_tokens", temperature: 0.7, maxTokens },
    { jsonMode: false, tokenField: "max_completion_tokens", temperature: null, maxTokens },
    { jsonMode: false, tokenField: "max_tokens", temperature: null, maxTokens },
  ];
}

/** Bir 400'e karşılık gelen, desteklenmeyen alanı yansıtan istek-reduktörü. */
export function shouldRetryWithNextProfile(status: number): boolean {
  // 408/425/429 geçici; 400/404/415/422 ise "istek biçimi/alan" kaynaklıdır.
  // 5xx ve ağ hatalarında tekrar denemek aynı hatayı uzatır.
  if (status === 408 || status === 425 || status === 429) return false;
  return status >= 400 && status < 500;
}

// ===========================================================================
// YANIT → NESNE — sessiz başarısızlığın KAPISI (A1r11)
// ===========================================================================

/** Başarısızlık nedenleri (istemciye sabit mesaj eşlenir, logda zenginleştirilir). */
export type JsonResponseFailureReason = "no_content" | "truncated" | "not_json" | "not_object";

/** Tanı için loglanabilir, **gövde içermeyen** hata bağlamı. */
export interface ResponseDiagnostic {
  finishReason: string | null;
  contentShape: ExtractedText["contentShape"];
  source: ExtractedText["source"];
  hasReasoningContent: boolean;
}

export type JsonResponseResult<T> =
  | { ok: true; value: T; text: string; diagnostic: ResponseDiagnostic }
  | { ok: false; reason: JsonResponseFailureReason; diagnostic: ResponseDiagnostic };

/**
 * Upstream yanıtını **tek bir kapıdan** nesneye çevirir.
 *
 * Sıra (her adım ayrı tanı üretir — sessizce "düzeltilmez"):
 *   1. `extractText` → içerik yoksa `no_content`
 *   2. `isTruncated(finish_reason)` → `truncated` (kesilmiş JSON ASLA kullanılmaz)
 *   3. `parseJsonLoose` → ayrıştırılamadıysa `not_json`
 *   4. sonuç nesne değilse (dizi/sayı/string) `not_object`
 *
 * ⚠️ **Uydurma yok.** Adım 2-4 başarısız olduğunda `ok: false` döner; çağıran
 * kullanıcıya hedef uydurmak yerine hata gösterir.
 */
export function parseJsonObjectResponse<T = Record<string, unknown>>(data: unknown): JsonResponseResult<T> {
  const finishReason = readFinishReason(data);
  const extracted = extractText(data);
  const diagnostic: ResponseDiagnostic = {
    finishReason,
    contentShape: extracted.contentShape,
    source: extracted.source,
    hasReasoningContent: hasReasoningContent(data),
  };

  if (!extracted.text.trim()) {
    return { ok: false, reason: "no_content", diagnostic };
  }
  // Kesilmiş yanıt: `JSON.parse` bazen "şanslıysa" yarım nesne verebilir.
  // Bu, **sessiz başarısızlığın** en tehlikeli hâlidir: yarım makro hedefleri
  // kullanıcıya "geçerli cevap" olarak gider. Kesilmiş yanıt asla kullanılmaz.
  if (isTruncated(finishReason)) {
    return { ok: false, reason: "truncated", diagnostic };
  }
  const parsed = parseJsonLoose<T>(extracted.text);
  if (parsed === null) {
    return { ok: false, reason: "not_json", diagnostic };
  }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    return { ok: false, reason: "not_object", diagnostic };
  }
  return { ok: true, value: parsed as T, text: extracted.text, diagnostic };
}

