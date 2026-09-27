// Makro hedefi hesaplama (AI).
// Güvenlik: sunucu tarafı JWT doğrulama, tip/aralık doğrulaması, hız sınırı,
// timeout, hata sızıntısı yok. Dönen şema istemciyle (MacroCalculator) uyumludur.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { AuthError, readJsonBody, requireUserContext } from "../_shared/auth.ts";
import { errorResponse, jsonResponse, preflightResponse } from "../_shared/http.ts";
import { checkRateLimit, rateLimitKey } from "../_shared/rate_limit.ts";
import {
  ValidationError,
  optionalString,
  requireEnum,
  requireNumber,
  requireString,
} from "../_shared/validate.ts";

/** Dış AI çağrısı için üst süre sınırı. */
const AI_TIMEOUT_MS = 45_000;
const RATE_LIMIT = { windowSeconds: 60, max: 10 };

const GENDERS = ["male", "female", "other"] as const;
const ACTIVITY_LEVELS = ["sedentary", "light", "moderate", "active", "very_active"] as const;
const GOALS = ["lose", "maintain", "gain"] as const;

serve(async (req) => {
  // CORS preflight
  if (req.method === "OPTIONS") return preflightResponse(req);
  if (req.method !== "POST") return errorResponse(req, 405, "Yalnızca POST desteklenir");

  try {
    // 1) Sunucu tarafı kimlik doğrulama.
    const { userId } = await requireUserContext(req, { serviceRole: false });

    // 2) Maliyet koruması (AI çağrısı).
    const limit = await checkRateLimit(rateLimitKey("calculate-macros", req, userId), RATE_LIMIT);
    if (!limit.allowed) {
      return jsonResponse(req, { error: "Çok fazla istek gönderildi, lütfen biraz bekleyin" }, 429, {
        "Retry-After": String(limit.retryAfter),
      });
    }

    const openAIApiKey = Deno.env.get("OPENAI_API_KEY");
    if (!openAIApiKey) {
      console.error("OPENAI_API_KEY yapılandırılmamış");
      return errorResponse(req, 500, "AI servisi yapılandırılmamış");
    }
    const baseUrl = Deno.env.get("OPENAI_BASE_URL") || "https://gen.pollinations.ai/v1";
    const model = Deno.env.get("OPENAI_MODEL") || "gpt-5-mini";

    // 3) Gövde doğrulama: eksik alan, hatalı tip ve makul aralık şartı.
    //    (Eski kod yalnızca `!age` ile kontrol ediyordu; negatif/NaN değerler
    //     prompt'a olduğu gibi giriyordu.)
    const body = await readJsonBody(req);
    const age = requireNumber(body.age, "age", 10, 120);
    const gender = requireEnum(body.gender, "gender", GENDERS);
    const heightCm = requireNumber(body.height_cm, "height_cm", 100, 260);
    const currentWeightKg = requireNumber(body.current_weight_kg, "current_weight_kg", 25, 400);
    const targetWeightKg = requireNumber(body.target_weight_kg, "target_weight_kg", 25, 400);
    const activityLevel = requireEnum(body.activity_level, "activity_level", ACTIVITY_LEVELS);
    const goal = requireEnum(body.goal, "goal", GOALS);
    const previousWeightKg = body.previous_weight_kg === undefined || body.previous_weight_kg === null
      ? null
      : requireNumber(body.previous_weight_kg, "previous_weight_kg", 25, 400);

    // Önceki makrolar: yalnızca beklenen sayısal alanlar, sınırlar içinde.
    let previousMacros: Record<string, number> | null = null;
    if (body.previous_macros !== undefined && body.previous_macros !== null) {
      const raw = body.previous_macros;
      if (typeof raw !== "object" || Array.isArray(raw)) {
        throw new ValidationError("previous_macros nesne olmalı");
      }
      const record = raw as Record<string, unknown>;
      previousMacros = {
        daily_calorie_target: requireNumber(record.daily_calorie_target, "previous_macros.daily_calorie_target", 0, 20000),
        protein_target_g: requireNumber(record.protein_target_g, "previous_macros.protein_target_g", 0, 2000),
        carbs_target_g: requireNumber(record.carbs_target_g, "previous_macros.carbs_target_g", 0, 2000),
        fat_target_g: requireNumber(record.fat_target_g, "previous_macros.fat_target_g", 0, 2000),
      };
    }

    // Kimlik/görünürlük amaçlı: değişiklik yok, yalnızca gereksiz log kaydı önlenir.
    requireString(userId, "userId", 64);

    const systemPrompt = `Sen bir beslenme ve diyet uzmanısın. Kullanıcının verilerine göre günlük kalori, makro ve su hedeflerini hesaplayacaksın.

Mifflin-St Jeor formülünü temel al ama kişiselleştirilmiş öneriler sun:
- Erkekler için BMR = 10 × ağırlık(kg) + 6.25 × boy(cm) − 5 × yaş + 5
- Kadınlar için BMR = 10 × ağırlık(kg) + 6.25 × boy(cm) − 5 × yaş − 161

Aktivite çarpanları:
- sedentary: 1.2
- light: 1.375
- moderate: 1.55
- active: 1.725
- very_active: 1.9

Hedef ayarlamaları:
- lose: günlük 500 kalori açığı
- gain: günlük 300 kalori fazlası
- maintain: değişiklik yok

Makro dağılımı:
- Protein: vücut ağırlığı × 1.6-2.2g (hedefe göre ayarla)
- Karbonhidrat: toplam kalorinin %40-50
- Yağ: toplam kalorinin %25-30

Su hedefi hesaplama:
- Temel formül: vücut ağırlığı × 30-35 ml
- Aktivite seviyesine göre artır (active ve very_active için +500-1000ml)
- Kilo verme hedefi varsa +250ml ekle
- Minimum 2000ml, maksimum 4000ml

JSON formatında yanıt ver:
{
  "daily_calorie_target": number,
  "protein_target_g": number,
  "carbs_target_g": number,
  "fat_target_g": number,
  "daily_water_target_ml": number,
  "bmr": number,
  "tdee": number,
  "explanation": "string (Türkçe kısa açıklama)"
}`;

    // Kullanıcı girdisi allow-list ile doğrulandığı için prompt enjeksiyonu yüzeyi yok.
    let userPrompt = `Kullanıcı bilgileri:
- Yaş: ${age}
- Cinsiyet: ${gender === "male" ? "Erkek" : gender === "female" ? "Kadın" : "Belirtilmemiş"}
- Boy: ${heightCm} cm
- Mevcut Kilo: ${currentWeightKg} kg
- Hedef Kilo: ${targetWeightKg} kg
- Aktivite Seviyesi: ${activityLevel}
- Hedef: ${goal === "lose" ? "Kilo vermek" : goal === "gain" ? "Kilo almak" : "Kiloyu korumak"}`;

    if (previousMacros && previousWeightKg !== null) {
      userPrompt += `

Önceki Veriler (kilo değişikliği sonrası güncelleme):
- Önceki Kilo: ${previousWeightKg} kg
- Önceki Kalori Hedefi: ${previousMacros.daily_calorie_target} kcal
- Önceki Protein: ${previousMacros.protein_target_g}g
- Önceki Karbonhidrat: ${previousMacros.carbs_target_g}g
- Önceki Yağ: ${previousMacros.fat_target_g}g

Kilo ${previousWeightKg > currentWeightKg ? "azaldı" : "arttı"}. Yeni kiloya göre makroları güncelle ve açıklamada ilerlemeyi değerlendir.`;
    }

    const response = await fetch(`${baseUrl}/chat/completions`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${openAIApiKey}`,
        "Content-Type": "application/json",
      },
      signal: AbortSignal.timeout(AI_TIMEOUT_MS),
      body: JSON.stringify({
        model,
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userPrompt },
        ],
        response_format: { type: "json_object" },
        max_tokens: 500,
        temperature: 0.7,
      }),
    });

    if (!response.ok) {
      console.error("OpenAI hata durumu:", response.status, (await response.text()).slice(0, 500));
      return errorResponse(req, 502, "Makro hedefleri şu anda hesaplanamıyor");
    }

    const data = await response.json();
    const content = data.choices?.[0]?.message?.content;
    if (!content) {
      console.error("OpenAI yanıtında içerik yok");
      return errorResponse(req, 502, "AI servisinden yanıt alınamadı");
    }

    let parsed: Record<string, unknown>;
    try {
      parsed = JSON.parse(content);
    } catch (_) {
      console.error("OpenAI yanıtı JSON değil");
      return errorResponse(req, 502, "AI yanıtı işlenemedi");
    }

    // İstemcinin beklediği alanları sayısal olarak normalize et (NaN/null kırılmasın).
    const result = {
      daily_calorie_target: Math.round(requireNumber(parsed.daily_calorie_target, "daily_calorie_target", 0, 20000)),
      protein_target_g: Math.round(requireNumber(parsed.protein_target_g, "protein_target_g", 0, 2000)),
      carbs_target_g: Math.round(requireNumber(parsed.carbs_target_g, "carbs_target_g", 0, 2000)),
      fat_target_g: Math.round(requireNumber(parsed.fat_target_g, "fat_target_g", 0, 2000)),
      daily_water_target_ml: Math.round(requireNumber(parsed.daily_water_target_ml, "daily_water_target_ml", 0, 10000)),
      bmr: Math.round(requireNumber(parsed.bmr, "bmr", 0, 20000)),
      tdee: Math.round(requireNumber(parsed.tdee, "tdee", 0, 20000)),
      explanation: optionalString(parsed.explanation, "explanation", 2000) ?? undefined,
    };

    return jsonResponse(req, result);
  } catch (error) {
    if (error instanceof AuthError) return errorResponse(req, error.status, error.status === 401 ? "Yetkisiz" : "İstek işlenemedi");
    if (error instanceof ValidationError) return errorResponse(req, error.status, error.message);
    console.error("calculate-macros beklenmeyen hata", error);
    return errorResponse(req, 500, "Beklenmeyen bir hata oluştu");
  }
});
