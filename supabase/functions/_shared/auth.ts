/**
 * Ortak kimlik doğrulama yardımcıları.
 *
 * NOT: `config.toml` içindeki `verify_jwt = true` yalnızca JWT'nin **imzasını ve
 * süresini** kontrol eder; kullanıcının gerçekten var olduğunu doğrulamaz.
 * Bu yüzden istemci tarafı denetimlerinin (çok faktörlü, oturum iptali vb.)
 * atlanmaması ve kullanıcı kapsamının (BOLA) kaynak tarafında sabitlenmesi için
 * her korumalı edge function `SUPABASE_ANON_KEY` ile `auth.getUser()` çağırır.
 * Yalnızca JWT payload'ı çözmek (`jwt.decode`) **güvenlik açığıdır** ve kullanılmaz.
 */

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export type AuthContext = {
  /** Doğrulanmış kullanıcının id'si — tüm sorgularda user_id filtresi olarak kullanılır. */
  userId: string;
  /** Kullanıcının kendi JWT'si ile açılan istemci (RLS'in devrede kalması için). */
  userClient: SupabaseClient;
  /** Sunucu tarafı işlemler (service_role) — yalnızca kullanıcı kapsamı sabitlendikten sonra. */
  serviceClient: SupabaseClient;
};

export class AuthError extends Error {
  readonly status: number;
  constructor(message: string, status = 401) {
    super(message);
    this.name = "AuthError";
    this.status = status;
  }
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new AuthError(`Sunucu yapılandırması eksik: ${name}`, 500);
  return value;
}

/**
 * `Authorization` başlığını sunucu tarafında doğrular ve kullanıcı kapsamını sabitler.
 * `authUserClient: false` verilirse (dahili, kendi yetkilendirmesi olan akışlar)
 * `getUser()` atlanır — bu durumda çağıran, `authHeader` doğrulamasının
 * fonksiyon içinde yapıldığından emin olmalıdır.
 */
export async function requireUserContext(
  req: Request,
  options: { serviceRole?: boolean; authUserClient?: boolean } = {},
): Promise<AuthContext> {
  const { serviceRole = true, authUserClient = true } = options;
  const authHeader = req.headers.get("Authorization") || "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    throw new AuthError("Yetkilendirme başlığı eksik", 401);
  }

  const supabaseUrl = requiredEnv("SUPABASE_URL");
  const supabaseAnonKey = requiredEnv("SUPABASE_ANON_KEY");

  const userClient = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  if (authUserClient) {
    // Sunucu tarafı doğrulama: imza + süre + kullanıcı varlığı kontrol edilir.
    const { data, error } = await userClient.auth.getUser();
    if (error || !data?.user) throw new AuthError("Geçersiz oturum", 401);
    return {
      userId: data.user.id,
      userClient,
      serviceClient: serviceRole
        ? createClient(supabaseUrl, requiredEnv("SUPABASE_SERVICE_ROLE_KEY"), {
            auth: { persistSession: false, autoRefreshToken: false },
          })
        : userClient,
    };
  }

  return {
    userId: "",
    userClient,
    serviceClient: serviceRole
      ? createClient(supabaseUrl, requiredEnv("SUPABASE_SERVICE_ROLE_KEY"), {
          auth: { persistSession: false, autoRefreshToken: false },
        })
      : userClient,
  };
}

/**
 * Varsayılan gövde boyutu sınırı (bayt).
 *
 * Gerekçe: 1 MB **varsayılan olarak çok büyüktü**. `recognize-food` gövdesi
 * base64 görsel taşır ve 8 MB'a kadar meşru (bkz. `requireImageBase64`), ama
 * diğer fonksiyonların ihtiyacı bunun çok altında. `maxBytes` verilmeyen her
 * çağrı JSON metnini tamamen belleğe aldığı için sınırsız bir gövde bellek
 * tüketimi (DoS) yaratıyordu. Varsayılan bu yüzden 256 KB'a çekildi; görsel
 * taşıyan fonksiyonlar kendi sınırını **açıkça** geçmeli.
 */
export const DEFAULT_MAX_BODY_BYTES = 256 * 1024;

/**
 * İstek gövdesini güvenli şekilde JSON olarak okur (boyut sınırlı).
 *
 * `maxBytes` verilmezse {@link DEFAULT_MAX_BODY_BYTES} kullanılır. Tıklama
 * bastırma (clickjacking/HTML form) ile `Content-Type: application/json`
 * gönderilemediği için gövde JSON parse edilemez ve 400 döner.
 */
export async function readJsonBody(req: Request, maxBytes = DEFAULT_MAX_BODY_BYTES): Promise<Record<string, unknown>> {
  const contentType = (req.headers.get("content-type") || "").split(";")[0].trim().toLowerCase();
  if (contentType && contentType !== "application/json") {
    // Yalnızca JSON kabul edilir; `text/plain` ile gelen istek reddedilir.
    throw new AuthError("Geçersiz içerik türü", 415);
  }
  const contentLength = Number(req.headers.get("content-length") || "0");
  if (Number.isFinite(contentLength) && contentLength > maxBytes) {
    throw new AuthError("Gövde çok büyük", 413);
  }
  const raw = await req.text();
  if (raw.length > maxBytes) throw new AuthError("Gövde çok büyük", 413);
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch (_) {
    throw new AuthError("Geçersiz JSON gövdesi", 400);
  }
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new AuthError("Geçersiz gövde şeması", 400);
  }
  return parsed as Record<string, unknown>;
}
