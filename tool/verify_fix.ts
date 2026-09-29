/**
 * Düzeltme DOĞRULAMA betiği (A1r11) — production katmanını canlı API ile ölçer.
 *
 * ⚠️ `calculate-macros/index.ts` içindeki istek+ayrıştırma zincirinin **birebir
 *    aynısını** çalıştırır (saf katman `openai_compat.ts` + üretimdeki alan
 *    doğrulaması). Amaç: "düzeltme sonrası tüm modeller geçiyor mu?" sorusunun
 *    CEVABINI ölçmek; iddia etmek değil.
 *
 * Anahtar yalnız `DENO_USTAGPT_KEY` ortam değişkeninden okunur.
 * Çalıştırma:
 *   DENO_USTAGPT_KEY='...' deno run --allow-env --allow-read --allow-net \
 *     tool/verify_fix.ts --runs=3
 */

import {
  buildRequestBody,
  buildRequestProfiles,
  parseJsonObjectResponse,
  shouldRetryWithNextProfile,
} from "../supabase/functions/_shared/openai_compat.ts";
import { buildMacroPrompts } from "./probe_prompt_source.ts";

const BASE_URL = Deno.env.get("PROBE_BASE_URL") || "https://api.ustagpt.com.tr/v1";
// Production ile AYNI bütçe (`calculate-macros/index.ts:MAX_COMPLETION_TOKENS`).
// Değiştirirken iki dosyayı birlikte güncelle.
const MAX_COMPLETION_TOKENS = 8000;

const MODELS = [
  "gemini-2.5-flash",
  "gemini-3.7-flash",
  "gemma-4-31b-it",
  "glm-5.3-flash",
  "gpt-4.1",
  "gpt-5-mini",
];

/** Production `calculate-macros/index.ts` ile aynı alan doğrulaması. */
const AI_TARGET_FIELDS = [
  { key: "daily_calorie_target", min: 500, max: 20000 },
  { key: "protein_target_g", min: 0, max: 2000 },
  { key: "carbs_target_g", min: 0, max: 2000 },
  { key: "fat_target_g", min: 0, max: 2000 },
  { key: "daily_water_target_ml", min: 2000, max: 10000 },
  { key: "bmr", min: 500, max: 20000 },
  { key: "tdee", min: 500, max: 20000 },
] as const;

type Outcome = "ok" | "no_content" | "truncated" | "not_json" | "not_object" | "missing_field" | "upstream";

/** Production zincirinin birebir taklidi. */
async function callProductionChain(
  apiKey: string,
  model: string,
  systemPrompt: string,
  userPrompt: string,
): Promise<{ outcome: Outcome; detail: string; attempts: number; latencyMs: number }> {
  const profiles = buildRequestProfiles(MAX_COMPLETION_TOKENS);
  let data: unknown = null;
  let lastStatus = 0;
  let lastLatency = 0;
  const started = Date.now();

  for (let attempt = 0; attempt < profiles.length; attempt++) {
    let response: Response;
    try {
      response = await fetch(`${BASE_URL}/chat/completions`, {
        method: "POST",
        headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
        signal: AbortSignal.timeout(60_000),
        body: JSON.stringify(buildRequestBody(model, systemPrompt, userPrompt, profiles[attempt])),
      });
    } catch (error) {
      return {
        outcome: "upstream",
        detail: error instanceof Error ? error.name : "unknown",
        attempts: attempt + 1,
        latencyMs: Date.now() - started,
      };
    }
    if (response.ok) {
      data = await response.json();
      lastLatency = Date.now() - started;
      break;
    }
    lastStatus = response.status;
    await response.text();
    if (attempt === profiles.length - 1 || !shouldRetryWithNextProfile(response.status)) break;
  }

  const attempts = profiles.length;
  if (data === null) {
    return { outcome: "upstream", detail: `HTTP ${lastStatus}`, attempts: 1, latencyMs: lastLatency };
  }

  const parsed = parseJsonObjectResponse<Record<string, unknown>>(data);
  if (!parsed.ok) {
    return {
      outcome: parsed.reason,
      detail: `finish=${parsed.diagnostic.finishReason} shape=${parsed.diagnostic.contentShape}`,
      attempts: 1,
      latencyMs: lastLatency,
    };
  }
  for (const field of AI_TARGET_FIELDS) {
    const raw = parsed.value[field.key];
    const num = typeof raw === "number" ? raw : typeof raw === "string" ? Number(raw) : NaN;
    if (!Number.isFinite(num) || num < field.min || num > field.max) {
      return { outcome: "missing_field", detail: field.key, attempts: 1, latencyMs: lastLatency };
    }
  }
  return { outcome: "ok", detail: "tam", attempts: 1, latencyMs: lastLatency };
}

async function main(): Promise<number> {
  const apiKey = Deno.env.get("DENO_USTAGPT_KEY");
  if (!apiKey) {
    console.error("HATA: DENO_USTAGPT_KEY tanimli degil.");
    return 2;
  }
  const runs = Math.max(1, Number(Deno.args.find((a) => a.startsWith("--runs="))?.split("=")[1] ?? "3"));
  const { systemPrompt, userPrompt } = await buildMacroPrompts();

  const results: Array<{ model: string; run: number; outcome: Outcome; detail: string; latencyMs: number }> = [];
  for (const model of MODELS) {
    for (let run = 1; run <= runs; run++) {
      const r = await callProductionChain(apiKey, model, systemPrompt, userPrompt);
      results.push({ model, run, outcome: r.outcome, detail: r.detail, latencyMs: r.latencyMs });
      console.log(
        `  [${r.outcome === "ok" ? "OK  " : "FAIL"}] ${model} #${run} -> ${r.outcome} (${r.detail}) ${(r.latencyMs / 1000).toFixed(1)}s`,
      );
      await new Promise((r) => setTimeout(r, 500));
    }
  }

  console.log("\n=== DUZELTME SONRASI OZET ===");
  let totalOk = 0;
  for (const model of MODELS) {
    const rows = results.filter((r) => r.model === model);
    const ok = rows.filter((r) => r.outcome === "ok").length;
    totalOk += ok;
    const failures = rows.filter((r) => r.outcome !== "ok").map((r) => `${r.outcome}(${r.detail})`);
    const latencies = rows.map((r) => r.latencyMs).sort((a, b) => a - b);
    console.log(
      `${model.padEnd(20)} ${ok}/${rows.length} p50=${(latencies[Math.floor(latencies.length / 2)] / 1000).toFixed(1)}s max=${(latencies.at(-1)! / 1000).toFixed(1)}s ${failures.length ? ":: " + failures.join(", ") : ""}`,
    );
  }
  console.log(`\nTOPLAM: ${totalOk}/${results.length} (${Math.round((totalOk / results.length) * 100)}%)`);
  return totalOk === results.length ? 0 : 1;
}

if (import.meta.main) {
  Deno.exit(await main());
}
