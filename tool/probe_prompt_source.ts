/**
 * `probe_models.ts` için **tek kaynak** prompt okuyucu (A1r11).
 *
 * AMAÇ
 *   `calculate-macros` production prompt'unu **kopyalamadan** kullanmak.
 *   Betik `supabase/functions/calculate-macros/index.ts` dosyasını okur,
 *   `systemPrompt`/`userPrompt` bloğunu (önceki makrolar dalı dahil) çıkarır
 *   ve onu gerçek örnek girdilerle **çalıştırır**. Böylece:
 *     - production prompt'u değişirse probe eskisini değil yenisini ölçer,
 *     - iki kopyanın sessizce ayrışması (drift) imkânsızlaşır.
 *
 * ⚠️ Güvenlik: çıkarılan kaynak **hiçbir gizli değer içermez**
 *   (`index.ts` yalnız `Deno.env.get("OPENAI_API_KEY")` okur, prompt'larda
 *   anahtar yoktur). Yine de sonuç metni istemciye/rapora yazılmadan önce
 *   kısaltılır.
 */

import { extractTemplateLiteral } from "./probe_extract.ts";

/** Kaynak dosya (repo köküne göre). */
export const PROMPT_SOURCE = "supabase/functions/calculate-macros/index.ts";

/** Probe için gerçekçi, geçerli bir kullanıcı girdisi (production allow-list aralıklarında). */
export interface ProbeInput {
  age: number;
  gender: "male" | "female" | "other";
  heightCm: number;
  currentWeightKg: number;
  targetWeightKg: number;
  activityLevel: "sedentary" | "light" | "moderate" | "active" | "very_active";
  goal: "lose" | "maintain" | "gain";
  previousWeightKg?: number | null;
  previousMacros?: Record<string, number> | null;
}

export const DEFAULT_PROBE_INPUT: ProbeInput = {
  age: 30,
  gender: "male",
  heightCm: 178,
  currentWeightKg: 82.5,
  targetWeightKg: 76,
  activityLevel: "moderate",
  goal: "lose",
  previousWeightKg: 84,
  previousMacros: {
    daily_calorie_target: 2350,
    protein_target_g: 150,
    carbs_target_g: 250,
    fat_target_g: 70,
  },
};

/** Sahte ortam: `index.ts` yalnız bu sembolleri kullanıyor. */
declare const Deno: { readTextFile(path: string): Promise<string> };

export async function buildMacroPrompts(
  input: ProbeInput = DEFAULT_PROBE_INPUT,
): Promise<{ systemPrompt: string; userPrompt: string }> {
  const source = await Deno.readTextFile(PROMPT_SOURCE);
  // Bitiş işareti kasıtlı olarak **kırılgan değil**: üretim kodu istek zincirini
  // yeniden düzenlediğinde (A1r11) bu sabit bayat kalıp probe'ı çökertiyordu.
  // Bu yüzden bitiş, "dış AI çağrısı" bölümünü işaretleyen yorum satırlarından
  // bulunur; bulunamazsa hata **açıkça** verilir (sessiz yanlış prompt olmaz).
  const endMarkers = [
    "// --- Dış AI çağrısı",
    "const response = await fetch(",
    "const profiles = buildRequestProfiles(",
  ];
  let extracted: string | null = null;
  const startIndex = source.indexOf("const systemPrompt =");
  if (startIndex === -1) {
    throw new Error(`PROMPT_SOURCE değişmiş: 'const systemPrompt =' bulunamadı (${PROMPT_SOURCE})`);
  }
  for (const marker of endMarkers) {
    const index = source.indexOf(marker, startIndex);
    if (index !== -1) {
      extracted = extractTemplateLiteral(source, "const systemPrompt =", marker);
      break;
    }
  }
  if (extracted === null) {
    throw new Error(
      `PROMPT_SOURCE değişmiş: prompt bloğunun bitişi bulunamadı (${PROMPT_SOURCE}). ` +
        `Aranan işaretler: ${endMarkers.join(", ")}`,
    );
  }

  // `extractTemplateLiteral` `start` işaretini **sonuna kadar** kestiği için
  // geri getiriyoruz: blok `const systemPrompt =` olmadan geçersiz JS olurdu.
  const block = `const systemPrompt = ${extracted}`;

  const previousWeightKg = input.previousWeightKg ?? null;
  const previousMacros = input.previousMacros ?? null;

  // `index.ts`'in prompt bloğu yalnız bu serbest değişkenlere bağlıdır; hepsi
  // burada karşılanır. `new Function` ile **gerçek production kodunu** çalıştırırız.
  const factory = new Function(
    "age",
    "gender",
    "heightCm",
    "currentWeightKg",
    "targetWeightKg",
    "activityLevel",
    "goal",
    "previousWeightKg",
    "previousMacros",
    `${block}\nreturn { systemPrompt, userPrompt };`,
  );

  const result = factory(
    input.age,
    input.gender,
    input.heightCm,
    input.currentWeightKg,
    input.targetWeightKg,
    input.activityLevel,
    input.goal,
    previousWeightKg,
    previousMacros,
  ) as { systemPrompt: string; userPrompt: string };

  if (typeof result?.systemPrompt !== "string" || typeof result?.userPrompt !== "string") {
    throw new Error(`PROMPT_SOURCE çıkarımı bozuk: ${PROMPT_SOURCE} değişmiş olabilir (systemPrompt/userPrompt bulunamadı).`);
  }
  return result;
}
