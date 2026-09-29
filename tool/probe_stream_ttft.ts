/**
 * Time-to-first-token (TTFT) ölçümü (A1r12) — timeout kök nedeni ayrımı.
 *
 * AMAÇ
 *   `gpt-5-mini` neden bu kadar yavaş? İki hipotez ayrılır:
 *     (a) model gerçekten yavaş  → TTFT de yavaşsa upstream gecikmesi modelin
 *         kendisindedir.
 *     (c) shim tamponluyor      → TTFT çok hızlı, ama içerik tek seferde
 *         geliyorsa sağlayıcının shim'i yanıtı biriktiriyor demektir
 *         (bu durumda `stream:true` göndermek kök nedeni göstermeye yarar).
 *
 * ÖLÇÜLEN
 *   - `stream: true` + `stream_options: { include_usage: true }` ile
 *     **her SSE parçasının geliş saati** kaydedilir.
 *   - `ttft_ms` = ilk `data:` parçasına kadar geçen süre.
 *   - `total_ms` = son parçaya kadar.
 *   - parça sayısı ve token/ısı (throughput) = (completion+reasoning)/süre.
 *
 * ⭐ Anahtar yalnız `DENO_USTAGPT_KEY` ortam değişkeninden okunur; çıktıda
 *   `Authorization` başlığı **yok**.
 */

const BASE_URL = Deno.env.get("PROBE_BASE_URL") || "https://api.ustagpt.com.tr/v1";
const API_KEY_ENV = "DENO_USTAGPT_KEY";
const TIMEOUT_MS = 170_000;

interface Result {
  model: string;
  run: number;
  httpStatus: number | null;
  ttftMs: number | null;
  totalMs: number;
  chunks: number;
  contentChars: number;
  reasoningTokens: number | null;
  completionTokens: number | null;
  finishReason: string | null;
  firstChunk: string;
  error: string;
}

function scrub(text: string): string {
  return text
    .replace(/sk-[A-Za-z0-9_-]{8,}/g, "[REDACTED_KEY]")
    .replace(/Bearer\s+[A-Za-z0-9._-]{8,}/gi, "Bearer [REDACTED]")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 200);
}

async function probe(
  apiKey: string,
  model: string,
  run: number,
  systemPrompt: string,
  userPrompt: string,
): Promise<Result> {
  const res: Result = {
    model,
    run,
    httpStatus: null,
    ttftMs: null,
    totalMs: 0,
    chunks: 0,
    contentChars: 0,
    reasoningTokens: null,
    completionTokens: null,
    finishReason: null,
    firstChunk: "",
    error: "",
  };
  const started = Date.now();
  let response: Response;
  try {
    response = await fetch(`${BASE_URL}/chat/completions`, {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      signal: AbortSignal.timeout(TIMEOUT_MS),
      body: JSON.stringify({
        model,
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userPrompt },
        ],
        max_tokens: 8000,
        temperature: 0.7,
        response_format: { type: "json_object" },
        stream: true,
        stream_options: { include_usage: true },
      }),
    });
  } catch (error) {
    const name = error instanceof Error ? error.name : "unknown";
    res.error = scrub(`${name}: ${error instanceof Error ? error.message : String(error)}`);
    res.totalMs = Date.now() - started;
    return res;
  }

  res.httpStatus = response.status;
  if (!response.ok) {
    res.error = scrub(await response.text());
    res.totalMs = Date.now() - started;
    return res;
  }

  let text = "";
  const decoder = new TextDecoder();
  let buffer = "";
  const reader = response.body?.getReader();
  if (!reader) {
    res.error = "gövde yok";
    res.totalMs = Date.now() - started;
    return res;
  }

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    const elapsed = Date.now() - started;
    buffer += decoder.decode(value, { stream: true });
    let idx: number;
    while ((idx = buffer.indexOf("\n\n")) !== -1) {
      const raw = buffer.slice(0, idx);
      buffer = buffer.slice(idx + 2);
      for (const line of raw.split("\n")) {
        if (!line.startsWith("data:")) continue;
        const payload = line.slice(5).trim();
        if (payload === "[DONE]") continue;
        res.chunks++;
        if (res.ttftMs === null) {
          res.ttftMs = elapsed;
          res.firstChunk = scrub(payload);
        }
        try {
          const evt = JSON.parse(payload) as Record<string, unknown>;
          const choices = Array.isArray(evt.choices) ? evt.choices : [];
          const choice = (choices[0] ?? {}) as Record<string, unknown>;
          const msg = (choice.message ?? {}) as Record<string, unknown>;
          const delta = (choice.delta ?? {}) as Record<string, unknown>;
          const piece = typeof msg.content === "string" ? msg.content : typeof delta.content === "string" ? (delta.content as string) : "";
          res.contentChars += piece.length;
          if (typeof choice.finish_reason === "string") res.finishReason = choice.finish_reason as string;
          const usage = (evt.usage ?? {}) as Record<string, unknown>;
          const det = (usage.completion_tokens_details ?? {}) as Record<string, unknown>;
          if (typeof usage.completion_tokens === "number") res.completionTokens = usage.completion_tokens;
          if (typeof det.reasoning_tokens === "number") res.reasoningTokens = det.reasoning_tokens;
        } catch (_) {
          // bozuk/eksik SSE parçası — yok sayılır (sayımda görünür)
        }
      }
    }
  }
  res.totalMs = Date.now() - started;
  return res;
}

async function main(): Promise<number> {
  const apiKey = Deno.env.get(API_KEY_ENV);
  if (!apiKey) {
    console.error(`HATA: ${API_KEY_ENV} tanimli degil.`);
    return 2;
  }
  const args = new Map<string, string>();
  for (const a of Deno.args) {
    const m = /^--([a-zA-Z0-9_-]+)(?:=(.*))?$/.exec(a);
    if (m) args.set(m[1], m[2] ?? "1");
  }
  const models = (args.get("models") ?? "gpt-5-nano,gpt-5-mini,gpt-5").split(",").map((s) => s.trim()).filter(Boolean);
  const runs = Math.max(1, Number(args.get("runs") ?? "3") || 3);
  const tiny = args.has("tiny");

  // Production prompt'unu tek kaynaktan oku (A1r11 deseni).
  const { buildMacroPrompts } = await import("./probe_prompt_source.ts");
  const full = await buildMacroPrompts();
  const systemPrompt = tiny ? "Return JSON only." : full.systemPrompt;
  const userPrompt = tiny ? 'Return {"ok":true}' : full.userPrompt;

  console.log(`Endpoint: ${BASE_URL}`);
  console.log(`Modeller: ${models.join(", ")} · koşu: ${runs} · akış: streaming · prompt: ${tiny ? "TINY" : "PRODUCTION"}\n`);

  const results: Result[] = [];
  // interleaved: model etkisi ile zaman etkisi ayrışsın
  for (let run = 1; run <= runs; run++) {
    for (const model of models) {
      const r = await probe(apiKey, model, run, systemPrompt, userPrompt);
      results.push(r);
      const tok = (r.completionTokens ?? 0) + (r.reasoningTokens ?? 0);
      console.log(
        `  ${model.padEnd(20)} #${run}  HTTP ${r.httpStatus ?? "-"}  ttft=${r.ttftMs !== null ? (r.ttftMs / 1000).toFixed(1) + "s" : "-"}  ` +
          `toplam=${(r.totalMs / 1000).toFixed(1)}s  parca=${r.chunks}  icerik=${r.contentChars}k  ` +
          `tok=${tok}  hiz=${r.totalMs > 0 ? (tok / (r.totalMs / 1000)).toFixed(1) : "-"} tok/s  finish=${r.finishReason ?? "-"}${r.error ? `  :: ${r.error.slice(0, 90)}` : ""}`,
      );
      await new Promise((r2) => setTimeout(r2, 2000));
    }
  }

  console.log("\n=== TTFT OZETI ===");
  for (const model of models) {
    const rows = results.filter((r) => r.model === model);
    const ttfts = rows.map((r) => r.ttftMs).filter((v): v is number => v !== null).sort((a, b) => a - b);
    const totals = rows.map((r) => r.totalMs).sort((a, b) => a - b);
    const toks = rows.map((r) => (r.completionTokens ?? 0) + (r.reasoningTokens ?? 0));
    const speed = totals.map((t, i) => t > 0 ? toks[i] / (t / 1000) : 0).sort((a, b) => a - b);
    const ok = rows.filter((r) => r.error === "" && r.httpStatus === 200).length;
    const med = (a: number[]): string => (a.length ? (a[Math.floor(a.length / 2)] / 1000).toFixed(1) : "-");
    console.log(
      `  ${model.padEnd(20)} ${ok}/${rows.length} · ttft p50=${med(ttfts)}s max=${ttfts.length ? (ttfts.at(-1)! / 1000).toFixed(1) : "-"}s · ` +
        `toplam p50=${med(totals)}s · hiz p50=${speed.length ? speed[Math.floor(speed.length / 2)].toFixed(1) : "-"} tok/s`,
    );
  }
  return 0;
}

if (import.meta.main) {
  Deno.exit(await main());
}
