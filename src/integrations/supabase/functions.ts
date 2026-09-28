// Edge Function çağrı sarmalayıcısı.
//
// ## JWT akışı — A6r3'ün doğruladığı gerçek durum (2026-09-28)
//
// Görev "React istemci 401 alıyor olabilir, `Authorization: Bearer <user access
// token>` gönderiliyor mu?" idi. **Gönderiliyor.** Kanıt zinciri:
//
//   1. `src/integrations/supabase/client.ts` `createClient(...)` çağırıyor ve
//      `global.fetch` **vermiyor** → `SupabaseClient` varsayılanı devrede.
//   2. `SupabaseClient` constructor'ında
//      `this.fetch = fetchWithAuth(supabaseKey, this._getAccessToken.bind(this),
//      settings.global.fetch)` — yani `fetch` **daima** `fetchWithAuth`'tir.
//   3. `get functions()` her erişimde
//      `new FunctionsClient(functionsUrl, { headers: this.headers,
//      customFetch: this.fetch })` kuruyor; `FunctionsClient` bu `customFetch`'i
//      `this.fetch` olarak saklıyor ve `invoke()` içinde onunla istek atıyor.
//   4. `fetchWithAuth` her istekte `apikey` + `Authorization: Bearer <token>`
//      ekliyor, `<token>` `_getAccessToken()`'tan geliyor:
//      `session?.access_token ?? supabaseKey`.
//
// Yani oturum varsa edge function **kullanıcının JWT'sini**, yoksa anon/publishable
// anahtarı görür ve A1'in `_shared/auth.ts` `requireUserContext()`'i
// `auth.getUser()` ile 401 döner. `OnboardingPage`/`SettingsPage` çağrıları
// `ProtectedRoute` arkasında olduğu için bu doğru davranıştır — React'in
// `calculate-macros` çağrılarında JWT eksikliği **yok**.
//
// ## Bu sarmalayıcı ne ekliyor?
//
// Yalnızca iki şey; JWT mantığına dokunmaz (dokunmak davranışı riske atar):
//
//   - **Zaman aşımı.** `FunctionsClient.invoke` `options.signal` destekliyor ama
//     bizim çağrılarımızda kullanılmıyordu. `ai-chat` (AI + 3 tablo) ve
//     `calculate-macros` (45 sn AI üst sınırı) yavaşladığında buton "bekliyor"
//     durumunda kalıyor ve kullanıcı işlemi iptal edemiyordu.
//   - **Tek giriş noktası.** 6 `functions.invoke` çağrısı hepsi aynı
//     varsayılanları alıyor; ileride `x-calorix-internal` gibi bir başlık ya da
//     farklı süre gerektiğinde tek dosya değişiyor.
//
// `throwOnError` **kullanılmıyor**: çağıranlar `if (error) throw error` kalıbını
// kullanıyor, davranışı değiştirmek regression riski taşır.
import { supabase } from "./client";

/**
 * Edge function çağrısı için üst süre. En yavaş akış `ai-chat`
 * (AI çağrısı + 3 tablo); `calculate-macros` sunucu tarafında 45 sn AI üst
 * sınırı uyguluyor, yani 60 sn hem onu hem ağ gecikmesini kapsar.
 */
export const FUNCTION_TIMEOUT_MS = 60_000;

/**
 * `calculate-macros` edge function'ının döndüğü şema.
 * (supabase/functions/calculate-macros/index.ts `jsonResponse` gövdesi.)
 */
export interface MacroCalcResponse {
  bmr: number;
  tdee: number;
  daily_calorie_target: number;
  protein_target_g: number;
  carbs_target_g: number;
  fat_target_g: number;
  daily_water_target_ml: number;
  explanation?: string;
}

/**
 * `supabase.functions.invoke` ile aynı sözleşme + zaman aşımı.
 *
 * @returns `{ data, error }` — `error` yalnızca ağ/zaman aşımı ya da HTTP
 * hatasıysa doludur; çağıran `if (error) throw error` deseniyle ilerler.
 */
export async function invokeFunction<T = unknown>(
  functionName: string,
  body: Record<string, unknown>,
): Promise<{ data: T | null; error: Error | null }> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), FUNCTION_TIMEOUT_MS);
  try {
    const result = await supabase.functions.invoke(functionName, {
      body,
      signal: controller.signal,
    });
    if (result.error) return { data: null, error: result.error as Error };
    return { data: (result.data ?? null) as T | null, error: null };
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      return {
        data: null,
        error: new Error(
          `"${functionName}" zaman aşımına uğradı (${FUNCTION_TIMEOUT_MS / 1000} sn).`,
        ),
      };
    }
    return { data: null, error: error as Error };
  } finally {
    clearTimeout(timeoutId);
  }
}
