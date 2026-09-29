/**
 * `gpt-5` serisi + alternatif model ölçüm betiği (A1r12).
 *
 * AMAÇ
 *   `calculate-macros` varsayılan modeli (`gpt-5-mini`) yerine konabilecek
 *   adayları **varsayıma dayanmadan** ölçmek ve `TimeoutError`ın kök nedenini
 *   (a) yavaş model / (b) rate-limit / (c) bozuk shim / (d) ağ-doygunluk /
 *   (e) reasoning token patlaması — kanıtla ayırmak.
 *
 * ⭐ DENEY TASARIMI (A1r11'in sonucunun güvenilmez kılan iki kusuru giderilir)
 *
 *   1. MODEL BLOKLARI DEĞİL, TUR TUR (round-robin) SIRALAMA.
 *      A1r11 modelleri blok blok koşmuştu: "gpt-5-mini 3/5 timeout" gözlemi
 *      aslında "o dakika sağlayıcı doygundu" olabilir. `--order=interleaved`
 *      (varsayılan) her koşu numarasında TÜM modelleri sırayla dener; böylece
 *      model etkisi ile zaman/doygunluk etkisi ayrışır. `--order=block` eski
 *      davranıştır (kontrol için).
 *
 *   2. DOYGUNLUK KANARYASI (canary) — `--canary=glm-5.3-flash`.
 *      Bilinen-çalışan, FARKLI sağlayıcı yönlendirmeli ucuz model, her model
 *      bloğundan/koşusundan hemen önce tek istek atar. Canary başarısız olursa
 *      o anki `gpt-5*` başarısızlığı **model değil, doygunluk** demektir.
 *      Bu, A1r11'in 403 `all_providers_failed` gözlemini doğrudan
 *      "gpt-5* modeline mi, tüm sağlayıcıya mı" diye ayırır.
 *
 *   3. GENİŞ ZAMAN BÜTÇESİ `--timeout=`.
 *      `raw` kipinde varsayılan **150 sn**: production'ın 55 sn'si bir timeout'u
 *      "model yavaş" ile "model hiç dönmüyor" arasında ayıramaz. 150 sn'de
 *      dönen bir istek → (a)/(e); 429/403/5xx dönen istek → (b)/(d)/(c);
 *      150 sn'de de dönmeyen istek → (c)/(d).
 *
 * KİPLER
 *   --mode=raw     TEK HTTP isteği, production'ın 1. profil parametreleriyle
 *                  (json_object + max_tokens 8000 + temperature 0.7). Ham
 *                  HTTP/usage/finish_reason ölçümü için (parse hatası yok).
 *   --mode=prod    Production zincirinin **birebir** taklidi: kademeli profil
 *                  geri çekilmesi + `parseJsonObjectResponse` + alan doğrulama
 *                  + `--timeout` (production 55 sn'yi taklit eder).
 *
 * EŞZAMANLILIK FAZI `--conc=N`
 *   Sıralı faz bittikten sonra her model için **N istek aynı anda** atılır
 *   (`Promise.all`). Amaç: "sağlayıcı eşzamanlı yük altında ne yapıyor?" —
 *   A1r11'in 403 `all_providers_failed` gözlemini kademe kademe (N=1→N=5)
 *   yeniden üretip hangi eşzamanlılıkta çöktüğünü bulmak. `calculate-macros`
 *   kullanıcı başına 10 istek/dk sınırlı olsa da **birden fazla kullanıcı**
 *   aynı anda istek atabilir.
 *
 * ÇIKIŞ
 *   --out=<dosya.md>  markdown tablo (yanına .json da yazılır)
 *
 * ⭐ ANAHTAR KURALI
 *   API anahtarı **yalnız** `DENO_USTAGPT_KEY` ortam değişkeninden okunur.
 *   Dosyada hiçbir yerde sabit yazılı değildir, loglanmaz, `Authorization`
 *   başlığı asla çıktıya yazılmaz. `scrub()` olası `sk-`/`Bearer` kalıntılarını
 *   `[REDACTED]` ile siler.
 *
 * ÇALIŞTIRMA
 *   DENO_USTAGPT_KEY='...' deno run --allow-env --allow-read --allow-net \
 *     tool/probe_gpt5.ts --models=gpt-5-nano,gpt-5-mini --runs=5
 */

import {
  buildRequestBody,
  buildRequestProfiles,
  parseJsonObjectResponse,
  shouldRetryWithNextProfile,
} from "../supabase/functions/_shared/openai_compat.ts";
import { buildMacroPrompts } from "./probe_prompt_source.ts";

// ---------------------------------------------------------------------------
// Yapılandırma (gizli değer YOK)
// ---------------------------------------------------------------------------
const BASE_URL = Deno.env.get("PROBE_BASE_URL") || "https://api.ustagpt.com.tr/v1";
const API_KEY_ENV = "DENO_USTAGPT_KEY";
/** Production ile aynı bütçe (`calculate-macros/index.ts:MAX_COMPLETION_TOKENS`). */
const MAX_COMPLETION_TOKENS = 8000;
const RAW_PREVIEW_CHARS = 200;

// ---------------------------------------------------------------------------
// Production alan doğrulaması (calculate-macros/index.ts ile aynı)
// ---------------------------------------------------------------------------
const AI_TARGET_FIELDS = [
  { key: "daily_calorie_target", min: 500, max: 20000 },
  { key: "protein_target_g", min: 0, max: 2000 },
  { key: "carbs_target_g", min: 0, max: 2000 },
  { key: "fat_target_g", min: 0, max: 2000 },
  { key: "daily_water_target_ml", min: 2000, max: 10000 },
  { key: "bmr", min: 500, max: 20000 },
  { key: "tdee", min: 500, max: 20000 },
] as const;

type ProdOutcome =
  | "ok"
  | "no_content"
  | "truncated"
  | "not_json"
  | "not_object"
  | "missing_field"
  | "upstream"
  | "timeout";

type ErrorKind = "none" | "timeout" | "network" | "http_error";

interface Record_ {
  phase: string; // "seq" | "conc" | "canary"
  mode: "raw" | "prod";
  model: string;
  run: number;
  ok: boolean;
  httpStatus: number | null;
  errorKind: ErrorKind;
  errorSnippet: string;
  finishReason: string | null;
  latencyMs: number;
  contentType: string;
  hasReasoningContent: boolean;
  reasoningTokens: number | null;
  completionTokens: number | null;
  promptTokens: number | null;
  upstreamModel: string | null;
  prodOutcome: ProdOutcome;
  prodDetail: string;
  attempts: number;
  preview: string;
}

function scrub(text: string): string {
  return text
    .replace(/sk-[A-Za-z0-9_-]{8,}/g, "[REDACTED_KEY]")
    .replace(/Bearer\s+[A-Za-z0-9._-]{8,}/gi, "Bearer [REDACTED]")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 300);
}

function describeType(value: unknown): string {
  if (value === null) return "null";
  if (value === undefined) return "missing";
  if (Array.isArray(value)) return "array";
  return typeof value;
}

function num(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function baseRecord(phase: string, mode: "raw" | "prod", model: string, run: number): Record_ {
  return {
    phase,
    mode,
    model,
    run,
    ok: false,
    httpStatus: null,
    errorKind: "none",
    errorSnippet: "",
    finishReason: null,
    latencyMs: 0,
    contentType: "missing",
    hasReasoningContent: false,
    reasoningTokens: null,
    completionTokens: null,
    promptTokens: null,
    upstreamModel: null,
    prodOutcome: "upstream",
    prodDetail: "",
    attempts: 0,
    preview: "",
  };
}

/** Yanıt gövdesinden ölçüm alanlarını doldurur (parse **yapmaz**). */
function absorb(rec: Record_, data: unknown): void {
  const root = (data ?? {}) as Record<string, unknown>;
  rec.upstreamModel = typeof root.model === "string" ? (root.model as string) : null;
  const usage = (root.usage ?? {}) as Record<string, unknown>;
  const details = (usage.completion_tokens_details ?? {}) as Record<string, unknown>;
  rec.promptTokens = num(usage.prompt_tokens);
  rec.completionTokens = num(usage.completion_tokens);
  rec.reasoningTokens = num(details.reasoning_tokens);

  const choices = Array.isArray(root.choices) ? root.choices : [];
  const choice = (choices[0] ?? {}) as Record<string, unknown>;
  rec.finishReason = typeof choice.finish_reason === "string" ? (choice.finish_reason as string) : null;
  const message = (choice.message ?? {}) as Record<string, unknown>;
  rec.contentType = describeType(message.content);
  const reasoning = message.reasoning_content ?? message.reasoning;
  rec.hasReasoningContent = typeof reasoning === "string" && reasoning.length > 0;
  const content = message.content;
  rec.preview = scrub(
    typeof content === "string" ? content : JSON.stringify(content ?? null),
  ).slice(0, RAW_PREVIEW_CHARS);
}

/** Production alan doğrulaması — birebir `calculate-macros/index.ts`. */
function validateTargets(value: Record<string, unknown>): { outcome: ProdOutcome; detail: string } {
  for (const field of AI_TARGET_FIELDS) {
    const raw = value[field.key];
    const n = typeof raw === "number" ? raw : typeof raw === "string" ? Number(raw) : NaN;
    if (!Number.isFinite(n) || n < field.min || n > field.max) {
      return { outcome: "missing_field", detail: field.key };
    }
  }
  return { outcome: "ok", detail: "tam" };
}

// ---------------------------------------------------------------------------
// raw kipi: TEK istek, production 1. profili
// ---------------------------------------------------------------------------
async function runRaw(
  apiKey: string,
  model: string,
  run: number,
  phase: string,
  systemPrompt: string,
  userPrompt: string,
  timeoutMs: number,
): Promise<Record_> {
  const rec = baseRecord(phase, "raw", model, run);
  const started = Date.now();
  const body = buildRequestBody(model, systemPrompt, userPrompt, {
    jsonMode: true,
    tokenField: "max_tokens",
    temperature: 0.7,
    maxTokens: MAX_COMPLETION_TOKENS,
  });
  rec.attempts = 1;

  let response: Response;
  try {
    response = await fetch(`${BASE_URL}/chat/completions`, {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      signal: AbortSignal.timeout(timeoutMs),
      body: JSON.stringify(body),
    });
  } catch (error) {
    const name = error instanceof Error ? error.name : "unknown";
    rec.errorKind = name === "TimeoutError" || name === "AbortError" ? "timeout" : "network";
    rec.errorSnippet = scrub(`${name}: ${error instanceof Error ? error.message : String(error)}`);
    rec.latencyMs = Date.now() - started;
    rec.prodOutcome = "timeout";
    rec.prodDetail = rec.errorSnippet;
    return rec;
  }

  rec.httpStatus = response.status;
  if (!response.ok) {
    rec.errorKind = "http_error";
    rec.errorSnippet = scrub(await response.text());
    rec.latencyMs = Date.now() - started;
    rec.prodOutcome = "upstream";
    rec.prodDetail = `HTTP ${response.status}`;
    return rec;
  }

  let data: unknown;
  try {
    data = await response.json();
  } catch (error) {
    rec.errorKind = "http_error";
    rec.errorSnippet = `govde JSON degil: ${scrub(String(error))}`;
    rec.latencyMs = Date.now() - started;
    return rec;
  }
  absorb(rec, data);
  rec.latencyMs = Date.now() - started;

  // Production'un parse zinciri de ölçülür (raw = "gecikmesiz gerçek" karşılaştırması).
  const parsed = parseJsonObjectResponse<Record<string, unknown>>(data);
  if (!parsed.ok) {
    rec.prodOutcome = parsed.reason;
    rec.prodDetail = `finish=${parsed.diagnostic.finishReason} shape=${parsed.diagnostic.contentShape} src=${parsed.diagnostic.source}`;
    return rec;
  }
  const validated = validateTargets(parsed.value);
  rec.prodOutcome = validated.outcome;
  rec.prodDetail = validated.detail;
  rec.ok = validated.outcome === "ok";
  return rec;
}

// ---------------------------------------------------------------------------
// prod kipi: production zincirinin birebir taklidi
// ---------------------------------------------------------------------------
async function runProd(
  apiKey: string,
  model: string,
  run: number,
  phase: string,
  systemPrompt: string,
  userPrompt: string,
  timeoutMs: number,
): Promise<Record_> {
  const rec = baseRecord(phase, "prod", model, run);
  const started = Date.now();
  const profiles = buildRequestProfiles(MAX_COMPLETION_TOKENS);
  let data: unknown = null;
  let lastStatus = 0;
  let lastError = "";

  for (let attempt = 0; attempt < profiles.length; attempt++) {
    rec.attempts = attempt + 1;
    let response: Response;
    try {
      response = await fetch(`${BASE_URL}/chat/completions`, {
        method: "POST",
        headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
        signal: AbortSignal.timeout(timeoutMs),
        body: JSON.stringify(buildRequestBody(model, systemPrompt, userPrompt, profiles[attempt])),
      });
    } catch (error) {
      const name = error instanceof Error ? error.name : "unknown";
      const isTimeout = name === "TimeoutError" || name === "AbortError";
      rec.errorKind = isTimeout ? "timeout" : "network";
      rec.errorSnippet = scrub(`${name}: ${error instanceof Error ? error.message : String(error)}`);
      rec.latencyMs = Date.now() - started;
      rec.prodOutcome = "timeout";
      rec.prodDetail = `${rec.errorSnippet} @attempt=${attempt + 1}/${profiles.length} (${(timeoutMs / 1000).toFixed(0)}sn)`;
      return rec;
    }
    if (response.ok) {
      try {
        data = await response.json();
      } catch (_) {
        rec.errorKind = "http_error";
        rec.errorSnippet = "govde JSON degil";
        rec.latencyMs = Date.now() - started;
        rec.prodDetail = "govde JSON degil";
        return rec;
      }
      absorb(rec, data);
      break;
    }
    lastStatus = response.status;
    lastError = scrub(await response.text());
  }

  rec.latencyMs = Date.now() - started;
  if (data === null) {
    rec.httpStatus = lastStatus;
    rec.errorKind = "http_error";
    rec.errorSnippet = lastError;
    rec.prodOutcome = "upstream";
    rec.prodDetail = `HTTP ${lastStatus} @${rec.attempts} profil`;
    return rec;
  }

  const parsed = parseJsonObjectResponse<Record<string, unknown>>(data);
  if (!parsed.ok) {
    rec.prodOutcome = parsed.reason;
    rec.prodDetail = `finish=${parsed.diagnostic.finishReason} shape=${parsed.diagnostic.contentShape} src=${parsed.diagnostic.source}`;
    return rec;
  }
  const validated = validateTargets(parsed.value);
  rec.prodOutcome = validated.outcome;
  rec.prodDetail = validated.detail;
  rec.ok = validated.outcome === "ok";
  return rec;
}

// ---------------------------------------------------------------------------
// Rapor yardımcıları
// ---------------------------------------------------------------------------
function pctl(values: number[], p: number): number {
  if (!values.length) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const idx = Math.min(sorted.length - 1, Math.max(0, Math.ceil((p / 100) * sorted.length) - 1));
  return sorted[idx];
}

const OUTCOME_TR: Record<ProdOutcome, string> = {
  ok: "BASARILI",
  no_content: "content yok",
  truncated: "KESILMIS (length)",
  not_json: "JSON.parse PATLADI",
  not_object: "JSON degil",
  missing_field: "eksik alan",
  upstream: "upstream hata",
  timeout: "TIMEOUT",
};

function fmtSec(ms: number): string {
  return `${(ms / 1000).toFixed(1)}s`;
}

function renderTable(records: Record_[]): string[] {
  const lines: string[] = [];
  const models = [...new Set(records.map((r) => r.model))];
  lines.push("| Model | Koşu | Sonuç | HTTP | p50 | p90 | max | finish_reason | reasoning_tok | completion_tok | Hata/kırılma |");
  lines.push("|---|---|---|---|---|---|---|---|---|---|---|");
  for (const model of models) {
    const rows = records.filter((r) => r.model === model);
    const lats = rows.map((r) => r.latencyMs);
    const ok = rows.filter((r) => r.ok).length;
    const http = [...new Set(rows.map((r) => r.httpStatus))].filter((s): s is number => s !== null);
    const finish = [...new Set(rows.map((r) => r.finishReason).filter((f): f is string => f !== null))];
    const reason = rows.map((r) => r.reasoningTokens).filter((v): v is number => v !== null);
    const comp = rows.map((r) => r.completionTokens).filter((v): v is number => v !== null);
    const detail = [...new Set(rows.map((r) => r.prodDetail || r.errorSnippet).filter(Boolean))]
      .map((s) => s.replace(/\|/g, "\\|"))
      .slice(0, 3)
      .join("<br>");
    lines.push(
      `| \`${model}\` | ${ok}/${rows.length} | ${ok === rows.length ? "✅" : "⚠️"} | ${http.length ? http.join(",") : "—"} | ` +
        `${fmtSec(pctl(lats, 50))} | ${fmtSec(pctl(lats, 90))} | ${fmtSec(Math.max(...lats))} | ${finish.join(",") || "—"} | ` +
        `${reason.length ? `${Math.min(...reason)}-${Math.max(...reason)}` : "—"} | ` +
        `${comp.length ? `${Math.min(...comp)}-${Math.max(...comp)}` : "—"} | ${detail || "—"} |`,
    );
  }
  return lines;
}

function renderPerRun(records: Record_[]): string[] {
  const lines: string[] = [];
  const models = [...new Set(records.map((r) => r.model))];
  lines.push("| Koşu | " + models.map((m) => `\`${m}\``).join(" | ") + " |");
  lines.push("|---" + "|".repeat(models.length) + "|");
  const maxRun = Math.max(...records.map((r) => r.run));
  for (let run = 1; run <= maxRun; run++) {
    const cells = models.map((model) => {
      const rec = records.find((r) => r.model === model && r.run === run);
      if (!rec) return "—";
      const mark = rec.ok ? "✅" : "❌";
      const rt = rec.reasoningTokens !== null ? ` r${rec.reasoningTokens}` : "";
      return `${mark} ${fmtSec(rec.latencyMs)}${rt} ${OUTCOME_TR[rec.prodOutcome]}`;
    });
    lines.push(`| #${run} | ${cells.join(" | ")} |`);
  }
  return lines;
}

function renderMarkdown(records: Record_[], meta: Record<string, string>): string {
  const phase = (p: string) => records.filter((r) => r.phase === p);
  const seq = phase("seq");
  const conc = phase("conc");
  const canaries = phase("canary");
  const lines: string[] = [];
  lines.push("# gpt-5 SERİSİ ÖLÇÜM RAPORU — `calculate-macros` (A1r12)");
  lines.push("");
  lines.push(`> Tarih: ${new Date().toISOString().slice(0, 10)} · Endpoint: \`${BASE_URL}\``);
  lines.push(`> Anahtar: yalnız \`${API_KEY_ENV}\` ortam değişkeninden okundu (dosyada/logda YOK)`);
  lines.push(`> Prompt kaynağı: \`supabase/functions/calculate-macros/index.ts\` (kopyalanmadı)`);
  lines.push(`> Kip: \`${meta.mode}\` · koşu/model: **${meta.runs}** · timeout: **${meta.timeout}** · sıralama: \`${meta.order}\``);
  lines.push(`> Kanarya (doygunluk dedektörü): \`${meta.canary}\` · istekler arası bekleme: **${meta.delay}**`);
  lines.push("");
  lines.push(`**Blok: A — SIRALI ÖLÇÜM (koşu ${meta.runs}/model)**`);
  lines.push("");
  lines.push("## A1) Model özeti (sıralı)");
  lines.push("");
  lines.push(...renderTable(seq));
  lines.push("");
  lines.push(`## A2) Koşu koşu (zaman sırası — doygunluk etkisini görünür kılar)`);
  lines.push("");
  lines.push(...renderPerRun(seq));
  lines.push("");
  lines.push(`## A3) Kanarya (doygunluk dedektörü) — ${canaries.length} kayıt`);
  lines.push("");
  if (!canaries.length) {
    lines.push("_(bu koşuda kanarya çalıştırılmadı)_");
  } else {
    lines.push("| # | Model | Sonuç | HTTP | süre | finish_reason | tamamlanan token | Hata |");
    lines.push("|---|---|---|---|---|---|---|---|");
    for (const c of canaries) {
      lines.push(
        `| #${c.run} | \`${c.model}\` | ${c.ok ? "✅" : "❌"} | ${c.httpStatus ?? "—"} | ${fmtSec(c.latencyMs)} | ${c.finishReason ?? "—"} | ${c.completionTokens ?? "—"} | ${(c.errorSnippet || c.prodDetail).replace(/\|/g, "\\|").slice(0, 90) || "—"} |`,
      );
    }
    lines.push("");
    const canaryOk = canaries.filter((c) => c.ok).length;
    lines.push(
      `> Kanarya özeti: **${canaryOk}/${canaries.length}** başarılı. ` +
        `${canaryOk === canaries.length
          ? "Sıralı fazdaki `gpt-5*` başarısızlıkları **model kaynaklıdır**, sağlayıcı doygunluğu değil."
          : "Kanarya da düştüğüne göre sıralı fazdaki başarısızlıklar **doygunluk kaynaklıdır** (model yargısı geçersiz)."}`,
    );
  }
  lines.push("");
  if (conc.length) {
    lines.push(`**Blok: B — EŞZAMANLILIK ÖLÇÜMÜ (her model için ${meta.conc} istek aynı anda)**`);
    lines.push("");
    lines.push("## B1) Model özeti (eşzamanlı)");
    lines.push("");
    lines.push(...renderTable(conc));
    lines.push("");
    lines.push(`## B2) Eşzamanlı koşular (zaman sırası)`);
    lines.push("");
    lines.push(...renderPerRun(conc));
    lines.push("");
  }
  lines.push(`## C) Başarısız koşuların ham hata/diagnostic kayıtları`);
  lines.push("");
  const failures = records.filter((r) => r.phase !== "canary" && !r.ok);
  if (!failures.length) {
    lines.push("_(başarısız koşu yok)_");
  } else {
    lines.push("| Faz | Model | Koşu | HTTP | süre | errorKind | finish_reason | diagnostic/hata |");
    lines.push("|---|---|---|---|---|---|---|---|");
    for (const f of failures) {
      lines.push(
        `| ${f.phase} | \`${f.model}\` | #${f.run} | ${f.httpStatus ?? "—"} | ${fmtSec(f.latencyMs)} | ${f.errorKind} | ${f.finishReason ?? "—"} | ${(f.errorSnippet || f.prodDetail).replace(/\|/g, "\\|").slice(0, 140)} |`,
      );
    }
  }
  lines.push("");
  lines.push("## D) Ham içerik örnekleri (ilk koşu, 200 karakter)");
  lines.push("");
  for (const model of [...new Set(records.map((r) => r.model))]) {
    const first = records.find((r) => r.model === model);
    if (!first) continue;
    lines.push(`### \`${model}\` (upstream \`${first.upstreamModel ?? "—"}\`, content tipi \`${first.contentType}\`, reasoning_content: ${first.hasReasoningContent ? "VAR" : "yok"})`);
    lines.push("");
    lines.push("```text");
    lines.push(first.preview || "(bos)");
    lines.push("```");
    lines.push("");
  }
  return lines.join("\n");
}

function consoleLine(rec: Record_): void {
  const mark = rec.ok ? "OK  " : "FAIL";
  const extra = [
    rec.httpStatus !== null ? `HTTP ${rec.httpStatus}` : null,
    `finish=${rec.finishReason ?? "-"}`,
    rec.reasoningTokens !== null ? `r${rec.reasoningTokens}` : null,
    rec.completionTokens !== null ? `c${rec.completionTokens}` : null,
  ].filter(Boolean).join(" ");
  const detail = rec.errorSnippet || rec.prodDetail;
  console.log(
    `  [${mark}] ${rec.phase.padEnd(6)} ${rec.model.padEnd(20)} #${rec.run} ${fmtSec(rec.latencyMs).padStart(6)} ${extra}${detail && !rec.ok ? ` :: ${detail.slice(0, 110)}` : ""}`,
  );
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------
function parseArgs() {
  const args = new Map<string, string>();
  for (const arg of Deno.args) {
    const m = /^--([a-zA-Z0-9_-]+)(?:=(.*))?$/.exec(arg);
    if (m) args.set(m[1], m[2] ?? "1");
  }
  return {
    models: (args.get("models") ?? "gpt-5-nano,gpt-5-mini").split(",").map((s) => s.trim()).filter(Boolean),
    runs: Math.max(1, Number(args.get("runs") ?? "5") || 5),
    mode: (args.get("mode") ?? "prod") as "raw" | "prod",
    timeout: Math.max(1, Number(args.get("timeout") ?? (args.get("mode") === "raw" ? "150" : "55")) || 55) * 1000,
    delay: Math.max(0, Number(args.get("delay") ?? "1") || 0) * 1000,
    order: args.get("order") ?? "interleaved",
    canary: args.get("canary") ?? "glm-5.3-flash",
    conc: Math.max(0, Number(args.get("conc") ?? "0") || 0),
    out: args.get("out"),
  };
}

async function main(): Promise<number> {
  const apiKey = Deno.env.get(API_KEY_ENV);
  if (!apiKey) {
    console.error(`HATA: ${API_KEY_ENV} tanimli degil. Anahtri environment'tan gecir (dosyaya YAZMA).`);
    return 2;
  }
  const cfg = parseArgs();
  const { systemPrompt, userPrompt } = await buildMacroPrompts();
  const call = cfg.mode === "raw" ? runRaw : runProd;

  console.log(`Endpoint   : ${BASE_URL}`);
  console.log(`Modeller   : ${cfg.models.join(", ")}`);
  console.log(`Kip        : ${cfg.mode} · timeout ${(cfg.timeout / 1000).toFixed(0)}sn · sıralama ${cfg.order} · bekleme ${cfg.delay}ms`);
  console.log(`Kanarya    : ${cfg.canary}`);
  console.log(`Prompt     : production'dan okundu (system ${systemPrompt.length} karakter)\n`);

  const records: Record_[] = [];
  const order: Array<{ model: string; run: number }> = [];
  if (cfg.order === "block") {
    for (const model of cfg.models) for (let run = 1; run <= cfg.runs; run++) order.push({ model, run });
  } else {
    for (let run = 1; run <= cfg.runs; run++) for (const model of cfg.models) order.push({ model, run });
  }

  let canaryCounter = 0;
  for (const item of order) {
    // Doygunluk kanaryası: her koşudan hemen önce bilinen-çalışan model.
    if (cfg.canary && item.run === 1) {
      const c = await runProd(apiKey, cfg.canary, ++canaryCounter, "canary", systemPrompt, userPrompt, cfg.timeout);
      records.push(c);
      consoleLine(c);
    }
    const rec = await call(apiKey, item.model, item.run, "seq", systemPrompt, userPrompt, cfg.timeout);
    records.push(rec);
    consoleLine(rec);
    if (cfg.delay) await new Promise((r) => setTimeout(r, cfg.delay));
  }

  const meta = {
    mode: cfg.mode,
    runs: String(cfg.runs),
    timeout: `${(cfg.timeout / 1000).toFixed(0)}s`,
    order: cfg.order,
    canary: cfg.canary || "(yok)",
    delay: `${cfg.delay}ms`,
    conc: String(cfg.conc),
  };
  console.log("\n=== OLCUM TABLOSU ===");
  console.log(renderTable(records).join("\n"));

  const totalOk = records.filter((r) => r.phase === "seq" && r.ok).length;
  const seqTotal = records.filter((r) => r.phase === "seq").length;
  const canaryOk = records.filter((r) => r.phase === "canary" && r.ok).length;
  const canaryTotal = records.filter((r) => r.phase === "canary").length;

  // --- Eşzamanlılık fazı ---------------------------------------------------
  if (cfg.conc > 0) {
    console.log(`\n=== EZSAMANLILIK FAZI (her model icin ${cfg.conc} istek ayni anda) ===`);
    for (const model of cfg.models) {
      const batch = await Promise.all(
        Array.from({ length: cfg.conc }, (_, i) =>
          call(apiKey, model, i + 1, "conc", systemPrompt, userPrompt, cfg.timeout)),
      );
      for (const rec of batch) {
        records.push(rec);
        consoleLine(rec);
      }
      const ok = batch.filter((r) => r.ok).length;
      const statuses = [...new Set(batch.map((r) => r.httpStatus))].filter((s): s is number => s !== null);
      const lats = batch.map((r) => r.latencyMs).sort((a, b) => a - b);
      console.log(
        `  -> ${model}: ${ok}/${cfg.conc} basarili · HTTP ${statuses.join(",") || "-"} · ` +
          `p50 ${fmtSec(pctl(lats, 50))} · max ${fmtSec(Math.max(...lats))} · ` +
          `kalan hata: ${batch.filter((r) => !r.ok).map((r) => r.prodDetail || r.errorSnippet).join(" | ").slice(0, 200) || "-"}`,
      );
      if (cfg.delay) await new Promise((r) => setTimeout(r, cfg.delay));
    }
  }

  if (cfg.out) {
    await Deno.writeTextFile(cfg.out, renderMarkdown(records, meta));
    await Deno.writeTextFile(cfg.out.replace(/\.md$/, ".json"), JSON.stringify({ meta, records }, null, 2));
    console.log(`\nRapor yazildi: ${cfg.out} (+ .json)`);
  }

  const concTotal = records.filter((r) => r.phase === "conc").length;
  const concOk = records.filter((r) => r.phase === "conc" && r.ok).length;
  console.log(`\nOZET: modeller ${totalOk}/${seqTotal} · kanarya ${canaryOk}/${canaryTotal} · eszamanli ${concOk}/${concTotal}`);
  return 0;
}

if (import.meta.main) {
  Deno.exit(await main());
}
