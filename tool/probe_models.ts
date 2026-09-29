/**
 * `calculate-macros` model uyumluluk teşhis betiği (A1r11).
 *
 * AMAÇ
 *   `supabase/functions/calculate-macros/index.ts:147-184` katmanındaki
 *   varsayılan hata noktalarını **varsayıma dayanmadan ölçmek**:
 *     1. `response_format: { type: "json_object" }` açık / kapalı farkı
 *     2. `max_tokens` vs `max_completion_tokens` farkı
 *     3. `temperature: 0.7` kabul ediliyor mu
 *     4. `choices[0].message.content` gerçekte hangi tipte dönüyor
 *        (string / content-parts dizisi / `text` / `reasoning_content`)
 *     5. `JSON.parse` zincirinin hangi adımda kırıldığı
 *     6. `finish_reason: "length"` (500 token yetmez mi?)
 *   Her model **en az 3 kez** koşulur ("bazen" diyorsa tek sefer yetmez;
 *   oran verilir).
 *
 * ⭐ ANAHTAR KURALI
 *   API anahtarı **yalnız** `DENO_USTAGPT_KEY` environment variable'ından
 *   okunur. Bu dosyada hiçbir yerde sabit yazılı değildir, loglanmaz ve
 *   `Authorization` başlığı asla rapora/çıktıya yazılmaz.
 *
 * TEK KAYNAK (single source of truth)
 *   `systemPrompt` **kopyalanmaz**; production dosyasından **kaynak metin
 *   olarak okunur** (`extractTemplateLiteral`). Böylece production prompt'u
 *   değişirse probe eskisi değil yenisini ölçer.
 *
 * ÇALIŞTIRMA (anahtarı shell'e geçir, dosyaya yazma):
 *   DENO_USTAGPT_KEY='...' \
 *   deno run --allow-env --allow-read --allow-net tool/probe_models.ts
 *
 *   --runs=3            her senaryo/model için tekrar sayısı (varsayılan 3)
 *   --models=a,b        yalnız bu modelleri koş
 *   --json              ham JSON özeti stdout'a bas (tabloyu atla)
 *   --out=<dosya>       rapor tablosunu dosyaya yaz (varsayılan stdout)
 *
 * ÇIKTI
 *   - `plans/analiz-26-09-27/MODEL-UYUMLULUK-RAPORU.md` markdown tablosu
 *   - Konsol özeti (kısaltılmış ham yanıtlar — anahtar/PII yok)
 */

import { buildMacroPrompts, PROMPT_SOURCE } from "./probe_prompt_source.ts";

// ---------------------------------------------------------------------------
// Yapılandırma (gizli değer YOK)
// ---------------------------------------------------------------------------
const BASE_URL = Deno.env.get("PROBE_BASE_URL") || "https://api.ustagpt.com.tr/v1";
const API_KEY_ENV = "DENO_USTAGPT_KEY";

const DEFAULT_MODELS = [
  "gemini-2.5-flash",
  "gemini-3.7-flash",
  "gemma-4-31b-it",
  "glm-5.3-flash",
  "gpt-4.1",
  "gpt-5-mini",
];

const REQUEST_TIMEOUT_MS = 60_000;
const RAW_PREVIEW_CHARS = 300;

type JsonMode = "on" | "off";
type TokenField = "max_tokens" | "max_completion_tokens";
type TemperatureMode = "with" | "without";

interface Scenario {
  id: string;
  label: string;
  jsonMode: JsonMode;
  tokenField: TokenField;
  temperature: TemperatureMode;
  maxTokens: number;
  /** Bu senaryo production'ın **birebir** parametre setidir (temel karşılaştırma). */
  productionParity: boolean;
}

/** Varsayılan hata noktalarını izole eden senaryo ızgarası. */
function buildScenarios(): Scenario[] {
  return [
    {
      id: "prod",
      label: "PROD (json_object + max_tokens:500 + temperature:0.7)",
      jsonMode: "on",
      tokenField: "max_tokens",
      temperature: "with",
      maxTokens: 500,
      productionParity: true,
    },
    {
      id: "nojson",
      label: "response_format YOK (+ max_completion_tokens:500)",
      jsonMode: "off",
      tokenField: "max_completion_tokens",
      temperature: "with",
      maxTokens: 500,
      productionParity: false,
    },
    {
      id: "nojson_mt",
      label: "response_format YOK + max_tokens:500 (token alanı prod'daki)",
      jsonMode: "off",
      tokenField: "max_tokens",
      temperature: "with",
      maxTokens: 500,
      productionParity: false,
    },
    {
      id: "nojson_notemp",
      label: "response_format YOK + temperature YOK (+ max_completion_tokens:500)",
      jsonMode: "off",
      tokenField: "max_completion_tokens",
      temperature: "without",
      maxTokens: 500,
      productionParity: false,
    },
    {
      id: "nojson_big",
      label: "response_format YOK + max_tokens:2000 (length testi)",
      jsonMode: "off",
      tokenField: "max_tokens",
      temperature: "with",
      maxTokens: 2000,
      productionParity: false,
    },
    {
      id: "json_big",
      label: "json_object + max_tokens:2000 (length testi)",
      jsonMode: "on",
      tokenField: "max_tokens",
      temperature: "with",
      maxTokens: 2000,
      productionParity: false,
    },
  ];
}

// ---------------------------------------------------------------------------
// Ölçüm kaydı
// ---------------------------------------------------------------------------
type FailureStage =
  | "ok"
  | "request" // istek reddedildi (HTTP 4xx/5xx) veya ağ/timeout
  | "no_content" // content boş/null
  | "not_json" // JSON.parse patladı
  | "not_object" // JSON parse oldu ama nesne değil
  | "missing_field" // beklenen alan eksik/aralık dışı
  | "length" // finish_reason === "length" (kesilmiş)

interface RunRecord {
  model: string;
  scenario: string;
  run: number;
  ok: boolean;
  stage: FailureStage;
  httpStatus?: number;
  contentType: string; // "string" | "array" | "null" | "missing" | "number" | "other"
  contentParts?: string; // dizi ise eleman tipleri
  hasTextField: boolean;
  hasReasoningContent: boolean;
  reasoningPreview?: string;
  finishReason?: string;
  usage?: Record<string, unknown>;
  preview: string; // ilk 300 karakter (anahtar yok)
  errorSnippet?: string; // hata gövdesinden ilk 200 karakter
  latencyMs: number;
}

function describeType(value: unknown): string {
  if (value === null) return "null";
  if (value === undefined) return "missing";
  if (Array.isArray(value)) return "array";
  return typeof value;
}

function describeParts(value: unknown): string {
  if (!Array.isArray(value)) return "";
  return value
    .map((part) => {
      if (part && typeof part === "object") {
        const p = part as Record<string, unknown>;
        return typeof p.text === "string" ? `${String(p.type ?? "?")}(text)` : String(p.type ?? typeof p);
      }
      return typeof part;
    })
    .join(",");
}

/** Ham yanıt gövdesini loglanmaya güvenli biçimde kısaltır (anahtar/PII yok). */
function scrub(text: string): string {
  return text
    // Bearer / sk- anahtarları
    .replace(/sk-[A-Za-z0-9_-]{8,}/g, "[REDACTED_KEY]")
    .replace(/Bearer\s+[A-Za-z0-9._-]{8,}/gi, "Bearer [REDACTED]")
    .slice(0, RAW_PREVIEW_CHARS);
}

// ---------------------------------------------------------------------------
// İstek
// ---------------------------------------------------------------------------
function buildBody(model: string, scenario: Scenario, systemPrompt: string, userPrompt: string): Record<string, unknown> {
  const body: Record<string, unknown> = {
    model,
    messages: [
      { role: "system", content: systemPrompt },
      { role: "user", content: userPrompt },
    ],
  };
  if (scenario.jsonMode === "on") body.response_format = { type: "json_object" };
  body[scenario.tokenField] = scenario.maxTokens;
  if (scenario.temperature === "with") body.temperature = 0.7;
  return body;
}

const REQUIRED_FIELDS = [
  ["daily_calorie_target", 0, 20000],
  ["protein_target_g", 0, 2000],
  ["carbs_target_g", 0, 2000],
  ["fat_target_g", 0, 2000],
  ["daily_water_target_ml", 0, 10000],
  ["bmr", 0, 20000],
  ["tdee", 0, 20000],
] as const;

/** Production `requireNumber(...)` zincirini birebir taklit eder. */
function classifyParsed(parsed: unknown): FailureStage {
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return "not_object";
  const record = parsed as Record<string, unknown>;
  for (const [field, min, max] of REQUIRED_FIELDS) {
    const raw = record[field];
    const num = typeof raw === "number" ? raw : typeof raw === "string" ? Number(raw) : NaN;
    if (!Number.isFinite(num) || num < min || num > max) return "missing_field";
  }
  return "ok";
}

async function runOnce(
  apiKey: string,
  model: string,
  scenario: Scenario,
  run: number,
  systemPrompt: string,
  userPrompt: string,
): Promise<RunRecord> {
  const started = Date.now();
  const record: RunRecord = {
    model,
    scenario: scenario.id,
    run,
    ok: false,
    stage: "request",
    contentType: "missing",
    hasTextField: false,
    hasReasoningContent: false,
    preview: "",
    latencyMs: 0,
  };

  let response: Response;
  try {
    response = await fetch(`${BASE_URL}/chat/completions`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      body: JSON.stringify(buildBody(model, scenario, systemPrompt, userPrompt)),
    });
  } catch (error) {
    record.stage = "request";
    record.errorSnippet = scrub(error instanceof Error ? `${error.name}: ${error.message}` : String(error));
    record.latencyMs = Date.now() - started;
    return record;
  }

  record.httpStatus = response.status;
  if (!response.ok) {
    record.stage = "request";
    record.errorSnippet = scrub(await response.text());
    record.latencyMs = Date.now() - started;
    return record;
  }

  let data: unknown;
  try {
    data = await response.json();
  } catch (error) {
    record.stage = "request";
    record.errorSnippet = `govde JSON degil: ${scrub(String(error))}`;
    record.latencyMs = Date.now() - started;
    return record;
  }

  const dataRecord = (data ?? {}) as Record<string, unknown>;
  const usage = (dataRecord.usage ?? undefined) as Record<string, unknown> | undefined;
  record.usage = usage;
  const choices = Array.isArray(dataRecord.choices) ? dataRecord.choices : [];
  const choice = (choices[0] ?? {}) as Record<string, unknown>;
  const finishReason = typeof choice.finish_reason === "string" ? choice.finish_reason : undefined;
  record.finishReason = finishReason;
  const message = (choice.message ?? {}) as Record<string, unknown>;
  const rawContent = message.content;
  record.contentType = describeType(rawContent);
  record.contentParts = describeParts(rawContent);
  record.hasTextField = typeof message.text === "string" && (message.text as string).length > 0;
  const reasoning = message.reasoning_content;
  record.hasReasoningContent = typeof reasoning === "string" && (reasoning as string).length > 0;
  if (record.hasReasoningContent) record.reasoningPreview = scrub(reasoning as string);

  // ---------------------------------------------------------------------
  // PRODUCTION'IN YAPTIGI EXTRACT: yalnızca düz string `content`.
  //    (index.ts:172) `const content = data.choices?.[0]?.message?.content;`
  //    Dizide/başka alanda dönen içerik burada KAYBOLUR.
  // ---------------------------------------------------------------------
  const productionContent = rawContent;
  record.preview = scrub(typeof productionContent === "string" ? productionContent : JSON.stringify(productionContent ?? null));

  if (!productionContent) {
    record.stage = "no_content";
    record.ok = false;
  } else if (typeof productionContent !== "string") {
    // Production `JSON.parse(content)` -> dizi/object verilirse TypeError
    // (parse, diziyi de nesneyi de "parse eder" ama alanlar okunmaz/yanlış).
    record.stage = "not_object";
    record.ok = false;
  } else {
    if (finishReason === "length") {
      // Kesilmiş JSON: parse bile "şanslıysa" yarım nesne verir.
      record.stage = "length";
      record.ok = false;
    } else {
      let parsed: unknown;
      try {
        parsed = JSON.parse(productionContent);
      } catch (_) {
        record.stage = "not_json";
        record.ok = false;
      }
      if (record.stage !== "not_json") {
        const stage = classifyParsed(parsed);
        record.stage = stage;
        record.ok = stage === "ok";
      }
    }
  }

  record.latencyMs = Date.now() - started;
  return record;
}

// ---------------------------------------------------------------------------
// Rapor üretimi
// ---------------------------------------------------------------------------
const STAGE_TR: Record<FailureStage, string> = {
  ok: "BASARILI",
  request: "istek reddi (HTTP/ağ)",
  no_content: "content null/bos",
  not_json: "JSON.parse PATLADI",
  not_object: "JSON degil (dizi/nesne)",
  missing_field: "eksik/aralik disi alan",
  length: "finish_reason=length (kesilmis)",
};

function pct(ok: number, total: number): string {
  return `${ok}/${total} (${total ? Math.round((ok / total) * 100) : 0}%)`;
}

interface Aggregate {
  model: string;
  scenario: string;
  label: string;
  total: number;
  ok: number;
  stages: Partial<Record<FailureStage, number>>;
  contentTypes: Partial<Record<string, number>>;
  finishReasons: Partial<Record<string, number>>;
  httpStatuses: Partial<Record<string, number>>;
  records: RunRecord[];
}

function aggregate(records: RunRecord[], scenarioById: Map<string, Scenario>): Aggregate[] {
  const groups = new Map<string, RunRecord[]>();
  for (const record of records) {
    const key = `${record.model}::${record.scenario}`;
    const list = groups.get(key) ?? [];
    list.push(record);
    groups.set(key, list);
  }
  const out: Aggregate[] = [];
  for (const [key, list] of groups) {
    const [model, scenario] = key.split("::");
    const stages: Partial<Record<FailureStage, number>> = {};
    const contentTypes: Partial<Record<string, number>> = {};
    const finishReasons: Partial<Record<string, number>> = {};
    const httpStatuses: Partial<Record<string, number>> = {};
    for (const record of list) {
      stages[record.stage] = (stages[record.stage] ?? 0) + 1;
      contentTypes[record.contentType] = (contentTypes[record.contentType] ?? 0) + 1;
      if (record.finishReason) finishReasons[record.finishReason] = (finishReasons[record.finishReason] ?? 0) + 1;
      if (record.httpStatus) httpStatuses[String(record.httpStatus)] = (httpStatuses[String(record.httpStatus)] ?? 0) + 1;
    }
    out.push({
      model,
      scenario,
      label: scenarioById.get(scenario)?.label ?? scenario,
      total: list.length,
      ok: list.filter((r) => r.ok).length,
      stages,
      contentTypes,
      finishReasons,
      httpStatuses,
      records: list,
    });
  }
  const order = new Map(DEFAULT_MODELS.map((m, i) => [m, i]));
  return out.sort((a, b) => {
    const ma = order.get(a.model) ?? 99;
    const mb = order.get(b.model) ?? 99;
    if (ma !== mb) return ma - mb;
    return a.scenario.localeCompare(b.scenario);
  });
}

function renderMarkdown(aggregates: Aggregate[], runsPerScenario: number): string {
  const lines: string[] = [];
  lines.push("# MODEL UYUMLULUK RAPORU — `calculate-macros` (A1r11)");
  lines.push("");
  lines.push(`> Üretim tarihi: ${new Date().toISOString().slice(0, 10)} · tekrar: **${runsPerScenario} koşu/senaryo/model**`);
  lines.push(`> Endpoint: \`${BASE_URL}\` · Anahtar: \`${API_KEY_ENV}\` ortam değişkeninden okundu (dosyada/logda YOK)`);
  lines.push(`> Prompt kaynağı: \`${PROMPT_SOURCE}\` (kopyalanmadı, dosyadan okundu)`);
  lines.push("");

  lines.push("## 1) Model × senaryo × sonuç");
  lines.push("");
  lines.push("| Model | Senaryo | Sonuc | `content` tipi | `finish_reason` | HTTP | Kırılma adımı |");
  lines.push("|---|---|---|---|---|---|---|");
  for (const agg of aggregates) {
    const stages = Object.entries(agg.stages)
      .map(([stage, count]) => `${STAGE_TR[stage as FailureStage]} ×${count}`)
      .join(", ");
    const contentTypes = Object.entries(agg.contentTypes).map(([t, c]) => `${t} ×${c}`).join(", ");
    const finish = Object.keys(agg.finishReasons).length ? Object.entries(agg.finishReasons).map(([r, c]) => `${r} ×${c}`).join(", ") : "—";
    const http = Object.keys(agg.httpStatuses).length ? Object.entries(agg.httpStatuses).map(([s, c]) => `${s} ×${c}`).join(", ") : "—";
    lines.push(
      `| \`${agg.model}\` | ${agg.label} | ${pct(agg.ok, agg.total)} | ${contentTypes} | ${finish} | ${http} | ${stages} |`,
    );
  }
  lines.push("");

  lines.push("## 2) `response_format` açık/kapalı etkisi (PROD senaryosu vs karşılığı)");
  lines.push("");
  lines.push("| Model | json_object AÇIK (PROD) | json_object KAPALI | Fark |");
  lines.push("|---|---|---|---|");
  const prodByModel = new Map(aggregates.filter((a) => a.scenario === "prod").map((a) => [a.model, a]));
  const offByModel = new Map(
    aggregates.filter((a) => a.scenario === "nojson_mt" || a.scenario === "nojson").map((a) => [a.model, a]),
  );
  for (const model of DEFAULT_MODELS) {
    const on = prodByModel.get(model);
    const off = offByModel.get(model);
    if (!on || !off) continue;
    const diff = on.ok === off.ok ? "aynı" : on.ok > off.ok ? "**AÇIK daha iyi**" : "**KAPALI daha iyi**";
    lines.push(`| \`${model}\` | ${pct(on.ok, on.total)} | ${pct(off.ok, off.total)} | ${diff} |`);
  }
  lines.push("");

  lines.push("## 3) Ham yanıt örnekleri (kısaltılmış, ilk 300 karakter)");
  lines.push("");
  for (const agg of aggregates) {
    const first = agg.records[0];
    if (!first) continue;
    lines.push(`### \`${agg.model}\` — ${agg.label}`);
    lines.push("");
    lines.push(`- Sonuç: **${pct(agg.ok, agg.total)}** · kırılma: ${STAGE_TR[first.stage]}`);
    lines.push(`- \`content\` tipi: \`${first.contentType}\`${first.contentParts ? ` (parçalar: ${first.contentParts})` : ""}`);
    lines.push(`- \`message.text\` alanı: ${first.hasTextField ? "VAR" : "yok"} · \`reasoning_content\`: ${first.hasReasoningContent ? "VAR" : "yok"}`);
    lines.push(`- \`finish_reason\`: ${first.finishReason ?? "—"} · gecikme: ~${first.latencyMs}ms`);
    if (first.usage) lines.push(`- \`usage\`: \`${JSON.stringify(first.usage)}\``);
    if (first.errorSnippet) lines.push(`- hata: \`${first.errorSnippet.replace(/\|/g, "\\|")}\``);
    lines.push(`- içerik önizlemesi:`);
    lines.push("");
    lines.push("```text");
    lines.push(first.preview || "(bos)");
    lines.push("```");
    lines.push("");
  }

  return lines.join("\n");
}

function renderConsole(aggregates: Aggregate[]): void {
  console.log("\n=== OLCUM TABLOSU (konsol) ===");
  for (const agg of aggregates) {
    const stages = Object.entries(agg.stages).map(([s, c]) => `${STAGE_TR[s as FailureStage]}×${c}`).join(", ");
    const first = agg.records[0];
    console.log(
      `${agg.model.padEnd(20)} ${agg.scenario.padEnd(13)} ${pct(agg.ok, agg.total).padEnd(12)} content=${first?.contentType} finish=${first?.finishReason ?? "-"} :: ${stages}`,
    );
  }
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------
function parseArgs(): { runs: number; models: string[]; json: boolean; out?: string } {
  const args = new Map<string, string>();
  for (const arg of Deno.args) {
    const match = /^--([a-zA-Z0-9_-]+)(?:=(.*))?$/.exec(arg);
    if (match) args.set(match[1], match[2] ?? "1");
  }
  return {
    runs: Math.max(1, Number(args.get("runs") ?? "3") || 3),
    models: (args.get("models") ?? "").split(",").map((m) => m.trim()).filter(Boolean),
    json: args.has("json"),
    out: args.get("out"),
  };
}

async function main(): Promise<number> {
  const apiKey = Deno.env.get(API_KEY_ENV);
  if (!apiKey) {
    console.error(`HATA: ${API_KEY_ENV} tanimli degil. Anahtri environment'tan gecir (dosyaya YAZMA).`);
    return 2;
  }

  const { runs, models, json, out } = parseArgs();
  const modelList = models.length ? models : DEFAULT_MODELS;
  const scenarios = buildScenarios();
  const scenarioById = new Map(scenarios.map((s) => [s.id, s]));

  // Tek kaynak: production dosyasından prompt'ları oku.
  const { systemPrompt, userPrompt } = await buildMacroPrompts();

  console.log(`Endpoint : ${BASE_URL}`);
  console.log(`Modeller : ${modelList.join(", ")}`);
  console.log(`Senaryolar: ${scenarios.map((s) => s.id).join(", ")}`);
  console.log(`Tekrar   : ${runs} (her model × senaryo)`);
  console.log(`Prompt   : ${PROMPT_SOURCE} (system ${systemPrompt.length} karakter)`);

  const records: RunRecord[] = [];
  for (const model of modelList) {
    for (const scenario of scenarios) {
      for (let run = 1; run <= runs; run++) {
        const record = await runOnce(apiKey, model, scenario, run, systemPrompt, userPrompt);
        records.push(record);
        const flag = record.ok ? "OK  " : "FAIL";
        console.log(
          `  [${flag}] ${model} / ${scenario.id} #${run} -> ${STAGE_TR[record.stage]}` +
            `${record.httpStatus ? ` (HTTP ${record.httpStatus})` : ""}` +
            ` content=${record.contentType} finish=${record.finishReason ?? "-"} ${record.latencyMs}ms` +
            `${record.errorSnippet ? `\n         hata: ${record.errorSnippet}` : ""}`,
        );
        // Upstream'e yük binmesin (rate limit koruması).
        if (!(model === modelList.at(-1) && scenario === scenarios.at(-1) && run === runs)) {
          await new Promise((r) => setTimeout(r, 400));
        }
      }
    }
  }

  const aggregates = aggregate(records, scenarioById);
  if (!json) renderConsole(aggregates);

  const markdown = renderMarkdown(aggregates, runs);
  if (out) {
    await Deno.writeTextFile(out, markdown);
    console.log(`\nMarkdown rapor yazildi: ${out}`);
  } else {
    console.log("\n" + markdown);
  }

  const jsonPath = out ? out.replace(/\.md$/, ".json") : null;
  if (jsonPath) {
    // Anahtar bu dosyada da YOK: yalnız ölçüm kayıtları serileştirilir.
    await Deno.writeTextFile(jsonPath, JSON.stringify(aggregates, null, 2));
    console.log(`JSON olcum yazildi: ${jsonPath}`);
  }

  const prodRuns = records.filter((r) => r.scenario === "prod");
  const prodOk = prodRuns.filter((r) => r.ok).length;
  console.log(`\nOZET: production parametre seti (json_object + max_tokens:500 + temperature:0.7): ${prodOk}/${prodRuns.length} basarili`);
  return 0;
}

if (import.meta.main) {
  const code = await main();
  Deno.exit(code);
}
