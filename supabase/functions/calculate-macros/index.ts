// Makro hedefi hesaplama (AI).
// Güvenlik: sunucu tarafı JWT doğrulama, tip/aralık doğrulaması, hız sınırı,
// timeout, hata sızıntısı yok. Dönen şema istemciyle (MacroCalculator) uyumludur.
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { AuthError, readJsonBody, requireUserContext } from "../_shared/auth.ts";
import { errorResponse, jsonResponse, preflightResponse } from "../_shared/http.ts";
import {
  buildRequestBody,
  buildRequestProfiles,
  parseJsonObjectResponse,
  shouldRetryWithNextProfile,
} from "../_shared/openai_compat.ts";
import { checkRateLimit, rateLimitKey } from "../_shared/rate_limit.ts";
import {
  ValidationError,
  optionalString,
  requireEnum,
  requireNumber,
  requireString,
} from "../_shared/validate.ts";

/**
 * Dış AI çağrısı için üst süre sınırı.
 *
 * ⭐ ÖLÇÜM NOTU (A1r11): gerekçe tüketen modeller ölçümde **13.6s - 24.5s**
 * sürdü (gemini-2.5-flash p50 ≈ 18s). Eski 45s sınırı, bir kez 30s'yi aşan
 * bir çağrıda kullanıcıya yine 502 döndürürdü. Supabase edge fonksiyonlarının
 * platform üst sınırı göz önüne alınarak 55s'ye çıkarıldı; 24.5s ölçümünün
 * 2 katından fazla pay bırakır.
 *
 * 2026-10-17 güncelleme: 60 s'ye çıkarıldı — sağlayıcı vision yollarında
 * 47-60 s ölçüldü (bkz. recognize-food). Bu metin yolu daha hızlıdır ama
 * aynı sağlayıcı doygunluğunu paylaşır; 55 s, A1r11'in ölçtüğü 59.6 s
 * p95'in altında kalıyordu.
 */
const AI_TIMEOUT_MS = 60_000;
const RATE_LIMIT = { windowSeconds: 60, max: 10 };

// ===========================================================================
// ⭐ AI İSTEK/ÇIKTI UYUMLULUĞU (A1r11) — ÖLÇÜM DAYANAKLI DÜZELTME
// ---------------------------------------------------------------------------
// Şikâyet: "GPT modelleriyle sorunsuz çalışıyor, Gemini/Gemma bazen hata veriyor."
//
// ÖLÇÜM (`plans/analiz-26-09-27/MODEL-UYUMLULUK-RAPORU.md`, 6 model × 6 senaryo
// × 3 koşu = 108 istek) iki ayrı kök nedeni kesinleştirdi:
//
//  (1) KOD BLOĞU SARMA (asıl neden). `gemini-2.5-flash`, `gemini-3.7-flash`,
//      `gemma-4-31b-it`, `glm-5.3-flash` JSON'u **```` ```json ... ``` ````**
//      içinde döndürüyor — `response_format: { type: "json_object" }`
//      GÖNDERİLMİŞ OLMASI BİLE. Eski `JSON.parse(content)` bu metni
//      doğrudan reddediyordu → kullanıcıya 502. `gpt-4.1`/`gpt-5-mini`
//      çıplak JSON döndürdüğü için aynı kod onlarda çalışıyordu. **Bu,
//      "GPT çalışıyor / Gemini kırılıyor" gözleminin tam açıklamasıdır.**
//
//  (2) TOKEN BÜTÇESİ. `max_tokens: 500` gerekçe modelleri için yetersiz:
//      gemini-3.7-flash tek koşuda **2186 reasoning token** harcadı
//      (`usage.completion_tokens_details.reasoning_tokens`), yanıt
//      `finish_reason: "length"` ile ortasından kesildi → JSON yarım kaldı.
//      Bu da `JSON.parse` hatası olarak görünüyordu (iki hata iç içe).
//
// DÜZELTMELER (her biri bir ölçüme bağlı):
//   - `parseJsonLoose` → kod bloğunu soyar / ön-son metni atlar (ölçüm 1).
//   - `max_tokens` 500 → 4000 (ölçüm 2: en yüksek reasoning tüketimi 2186 +
//     ~800 token'lık JSON + güvenlik payı).
//   - `extractText` → `content` string/dizi/`text` alanı (ölçüm 3: `content`
//     beklenmedik yerlerde dönüyor).
//   - Kademeli istek profilleri (ölçüm 4: sağlayıcı 4xx döndüğünde
//     desteklenmeyen alanlar sırayla kaldırılır).
//
// ⚠️ SESSİZ BAŞARISIZLIK YASAK: `finish_reason === "length"` olan yanıt
//    **asla** kabul edilmez; alan eksikse `requireNumber` reddeder. Yarım
//    cevap üzerine sayı uydurulmaz.
// ===========================================================================

/**
 * Yanıt için token bütçesi.
 *
 * ÖLÇÜM (canlı, `max_tokens: 16000` ile tavan yok koşusu):
 *   gemini-2.5-flash : completion 2076 / 2487 / 2970 / **3297**
 *                      (reasoning 1819 / 2255 / 2753 / **3102** token)
 *   gemini-3.7-flash : completion 265-303 + reasoning **2078-2727** token
 *
 * ⭐ Reasoning tüketimi **model seçimine bağlı ve öngörülemez** (1.8k-3.1k
 * aralığında salınıyor). 500 (eski) ve 4000 (ilk deneme) tavanları ikisini
 * de kesiyordu: 4000 ile ölçümde hâlâ `finish_reason: "length"` alındı.
 *
 * `max_tokens` bir **tavandır, fatura değil** — kullanılan token kadar
 * ücretlendirilir. Bu yüzden güvenli pay (gerekçe 3.1k + JSON ~0.8k + başlık
 * payı) 8000'dir: tavan yükseltmek maliyeti artırmaz, kesilme riskini kaldırır.
 */
const MAX_COMPLETION_TOKENS = 8000;

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

    // --- Dış AI çağrısı: kademeli parametre profilleriyle -------------------
    //
    // Ölçüm, `response_format`/`temperature`/token alanı adlarının sağlayıcıdan
    // sağlayıcıya **desteklenmediğini** gösterdi. Bu yüzden tam parametreli
    // istek atılır; upstream **istem reddi (4xx)** dönerse desteklenmeyen
    // alanlar kademeli olarak kaldırılarak yeniden denenir. 5xx/rate-limit
    // durumunda tekrar denenmez (`shouldRetryWithNextProfile`).
    const profiles = buildRequestProfiles(MAX_COMPLETION_TOKENS);
    let data: unknown = null;
    let lastStatus = 0;
    let lastErrorBody = "";

    for (let attempt = 0; attempt < profiles.length; attempt++) {
      const profile = profiles[attempt];
      let response: Response;
      try {
        response = await fetch(`${baseUrl}/chat/completions`, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${openAIApiKey}`,
            "Content-Type": "application/json",
          },
          signal: AbortSignal.timeout(AI_TIMEOUT_MS),
          body: JSON.stringify(buildRequestBody(model, systemPrompt, userPrompt, profile)),
        });
      } catch (error) {
        // Ağ/timeout: tekrar denemek aynı sonucu verir.
        console.error("calculate-macros upstream çağrısı başarısız", {
          model,
          attempt,
          error: error instanceof Error ? error.name : "unknown",
        });
        return errorResponse(req, 502, "Makro hedefleri şu anda hesaplanamıyor");
      }

      if (response.ok) {
        try {
          data = await response.json();
        } catch (_) {
          console.error("calculate-macros upstream gövdesi JSON değil", { model, attempt });
          return errorResponse(req, 502, "AI servisinden yanıt alınamadı");
        }
        break;
      }

      lastStatus = response.status;
      // Gövde yalnızca sunucu loguna yazılır; **anahtar sızdırmaz** (istek
      // gövdesi loglanmaz) ve istemciye hiçbir şekilde dönülmez.
      lastErrorBody = (await response.text()).slice(0, 300);
      const isLast = attempt === profiles.length - 1;
      if (isLast || !shouldRetryWithNextProfile(response.status)) break;
      // Bir sonraki profille (daha gevşek parametrelerle) tekrar dene.
    }

    if (data === null) {
      console.error("calculate-macros upstream hata durumu", {
        model,
        status: lastStatus,
        body: lastErrorBody,
      });
      return errorResponse(req, 502, "Makro hedefleri şu anda hesaplanamıyor");
    }

    // --- Yanıtı sağlayıcıdan bağımsız ayrıştır ---------------------------
    //
    // `extractText` (string/dizi/`text`) + kod bloğu temizleme + kesilmiş
    // yanıt reddi. Tanı logu **model adı + finish_reason + content şekli**
    // içerir; ham gövde/anahtar **yazılmaz**.
    const parsedResult = parseJsonObjectResponse<Record<string, unknown>>(data);
    if (!parsedResult.ok) {
      console.error("calculate-macros AI yanıtı işlenemedi", {
        model,
        reason: parsedResult.reason,
        ...parsedResult.diagnostic,
      });
      if (parsedResult.reason === "truncated") {
        // Kesilmiş yanıt: kullanıcıya yarım hedef göstermektense anlaşılır
        // hata. Yeniden denemede daha yüksek bütçe kullanılabilir.
        return errorResponse(req, 502, "AI yanıtı eksik geldi, lütfen tekrar deneyin");
      }
      return errorResponse(req, 502, "AI yanıtı işlenemedi");
    }
    const parsed = parsedResult.value;
    // Tanı logları için `finish_reason` (başarı dalında da anlamlı: model
    // yanıtı `stop` ile mi bitirdi, kesildi mi?).
    const finishReason = parsedResult.diagnostic.finishReason;

    // ⚠️ `requireNumber` **ValidationError** fırlatır ve dışarıdaki catch bloğu
    // onu 400 "Eksik veya geçersiz istek" olarak döner. Burada alanlar **model
    // çıktısıdır**, kullanıcı isteği değil — model eksik alan döndüğünde
    // kullanıcıya "istediğiniz eksik" demek yanlış olur ve şema sızdırır.
    // Bu yüzden AI çıktısı doğrulaması AYRI ve sessizce geçmeyen bir yol izler.
    //
    // ⭐ SESSİZ BAŞARISIZLIK YASAK: eksik alan **sıfıra doldurulmaz**
    //    (A1r4'ün "kısmi silme 200 başarı" hatasının kaynağı buydu). Eksik alan
    //    varsa istek 502 ile kapanır.
    const AI_TARGET_FIELDS = [
      { key: "daily_calorie_target", min: 500, max: 20000 },
      { key: "protein_target_g", min: 0, max: 2000 },
      { key: "carbs_target_g", min: 0, max: 2000 },
      { key: "fat_target_g", min: 0, max: 2000 },
      { key: "daily_water_target_ml", min: 2000, max: 10000 },
      { key: "bmr", min: 500, max: 20000 },
      { key: "tdee", min: 500, max: 20000 },
    ] as const;

    const result: Record<string, number | string | undefined> = {};
    for (const field of AI_TARGET_FIELDS) {
      const raw = parsed[field.key];
      const num = typeof raw === "number" ? raw : typeof raw === "string" ? Number(raw) : NaN;
      if (!Number.isFinite(num) || num < field.min || num > field.max) {
        console.error("calculate-macros AI yanıtında alan eksik/geçersiz", {
          model,
          field: field.key,
          finishReason,
        });
        return errorResponse(req, 502, "AI yanıtı eksik geldi, lütfen tekrar deneyin");
      }
      result[field.key] = Math.round(num);
    }
    // `explanation` isteğe bağlıdır; alan yoksa alan **atlanır** (uydurulmaz).
    const explanation = optionalString(parsed.explanation, "explanation", 2000);
    if (explanation) result.explanation = explanation;

    return jsonResponse(req, result);
  } catch (error) {
    if (error instanceof AuthError) return errorResponse(req, error.status, error.status === 401 ? "Yetkisiz" : "İstek işlenemedi");
    // A1r4: `ValidationError` mesajı **istemciye** gönderiliyordu. Bu mesaj
    // `requireEnum`/`requireNumber` gibi doğrulayıcılardan gelen ALAN ADI ve
    // beklenen aralık içerir ("height_cm 100-260 aralığında olmalı") —
    // yani şema hakkında bilgi sızdırır. `_shared/auth.ts` (`readJsonBody`)
    // zaten 415/413/400 için sabit mesaj kullanıyor; `delete-account` da
    // sabit mesaj döndürüyor. Burada da aynı politika uygulanır.
    if (error instanceof ValidationError) {
      console.error("calculate-macros doğrulama hatası:", error.message);
      return errorResponse(req, error.status, "Eksik veya geçersiz istek");
    }
    console.error("calculate-macros beklenmeyen hata", error);
    return errorResponse(req, 500, "Beklenmeyen bir hata oluştu");
  }
});
