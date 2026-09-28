/**
 * `delete-account` fonksiyonunun **saf** (Edge DB'den bağımsız) yardımcıları.
 *
 * Neden ayrı dosya? Supabase edge function'ları her dizinde **tek bir giriş
 * dosyası** (`index.ts`) dağıtır; `_test.ts` dosyaları dağıtıma dahil edilmez.
 * Test edilebilir çekirdek burada tutulur, `index.ts` yalnızca onu kullanır.
 *
 * Buradaki her fonksiyon yan etkisizdir ve `delete_account_test.ts` tarafından
 * Edge DB olmadan doğrulanır.
 *
 * A1r5: tablo listesi ve **FK silme sırası** `_shared/schema_contract.ts`'ten
 * gelir. Böylece "yeni tablo/FK eklendi, `delete-account` listesini güncelle"
 * uyarısı `supabase/tests/schema_contract.sql` ile CI'da görünür olur
 * (elle tutulan listede sessizce bayatlama riski vardı).
 */

import {
  FK_DELETION_RULES,
  OWNER_COLUMN as SCHEMA_OWNER_COLUMN,
} from "../_shared/schema_contract.ts";

/**
 * Kullanıcıya ait **veri** silinen tablolar.
 *
 * Sıralama kasıtlıdır:
 *   1) Bağımlılığı olan çocuk satırlar (`chat_messages` → `chat_threads`,
 *      `favorite_foods`/`recent_foods` → `foods`) **önce** — FK sırası ihlal
 *      edilirse silme yarıda kalmasın.
 *   2) Kullanıcının birincil verisi.
 *   3) Profil **en son**: `handle_new_user` trigger'ı ve istemci kodu profile
 *      bağlı olabilir; profil en sonda silinir.
 *
 * `user_roles` BİLEREK YOKTUR: RLS'te yazma yolu kapalı olan bir tablodur ve
 * `ON DELETE CASCADE` ile zaten `auth.admin.deleteUser()` aşamasında silinir.
 * `rate_limits` de yoktur (global sayaç, kişiye bağlı değil).
 *
 * **`foods` de BİLEREK YOKTUR.** `foods` paylaşılan bir katalogdur: başka
 * kullanıcıların `meal_entries.food_id` referansı taşıyabilir. Bu tablodaki
 * satırlar, sahibi (`created_by`) silinen kullanıcıya aitse
 * `ON DELETE CASCADE` ile **o kullanıcının** hesabı silinirken temizlenir
 * (URUN-KARARLARI 3-A; migration `20260928300000`).
 * `created_by IS NULL` satırlar (seed/admin) hiçbir zaman silinmez.
 */
export const DATA_TABLES: readonly string[] = [
  // Bağımlılığı olan çocuk satırlar (FK → ebeveyn)
  "chat_messages", // → chat_threads (NOT NULL + CASCADE) ← ENGELLEYİCİ
  "favorite_foods", // → foods        (NOT NULL + CASCADE)
  "recent_foods", // → foods        (NOT NULL + CASCADE)
  // Kullanıcı verisi
  "meal_entries", // → foods        (SET NULL — engellemez)
  "water_entries",
  "weight_entries",
  "notifications",
  "notification_preferences",
  "user_settings",
  "push_subscriptions",
  "chat_threads", // → auth.users
  // Profil en son
  "profiles",
] as const;

/**
 * `user_id` kolonu olmayan ama silinmesi gereken tablo → filtre kolonu eşlemesi.
 * `profiles` birincil anahtarı `id` olduğu için ayrı ele alınır.
 *
 * Kaynak: `_shared/schema_contract.ts` → `OWNER_COLUMN` (şema sözleşmesi).
 * A1r5 bu eşlemeyi şema sözleşmesinden **türetir**; yeni bir tablo eklendiğinde
 * `supabase/tests/schema_contract.sql` canlı `information_schema` ile
 * karşılaştırıp farkı hata olarak bildirir.
 */
export const OWNER_FILTER_OVERRIDES: Readonly<Record<string, string>> = Object.freeze(
  Object.fromEntries(
    DATA_TABLES.map((table) => [table, SCHEMA_OWNER_COLUMN[table] ?? "user_id"]),
  ),
);

/** Verilen tablo için `user_id` (veya `id`) filtre kolonunu döndürür. */
export function ownerFilterColumn(table: string): string {
  return OWNER_FILTER_OVERRIDES[table] ?? "user_id";
}

/**
 * Silme sırasının bütünlüğünü doğrular.
 *
 * **A1r5 değişikliği:** kural listesi artık **elle yazılmış iki satır
 * değil**, `_shared/schema_contract.ts` → `FK_DELETION_RULES`'tan gelir ve
 * `supabase/tests/schema_contract.sql` canlı `pg_constraint` ile karşılaştırır.
 *
 * Gerçek şemada `public` içi FK'lar ve silme sırasına etkileri:
 *
 *   | çocuk              | → ebeveyn      | NOT NULL | silmeyi engeller mi? |
 *   |--------------------|---------------|----------|-----------------------|
 *   | `chat_messages`    | `chat_threads`| evet     | **evet** (mesaj, thread'dan önce) |
 *   | `favorite_foods`   | `foods`       | evet     | **hayır** (aşağıya bak) |
 *   | `recent_foods`     | `foods`       | evet     | **hayır**              |
 *   | `meal_entries`     | `foods`       | hayır    | hayır (`SET NULL`)     |
 *   | `food_nutrition`   | `foods`       | evet     | hayır (sahiplik kolonu yok, listede değil) |
 *   | (her tablo)        | `auth.users`  | çoğu     | hayır (`auth.admin.deleteUser()` CASCADE) |
 *
 * **A1r4'ün düzelttiği yanlış kural:** eski kodda
 * `["chat_threads", "profiles"]` ikinci bir kural olarak **elle** vardı.
 * Gerçek şemada `chat_threads` ile `profiles` arasında **FK yoktur** (ikisi
 * de `auth.users`'a gider), yani bu kural **uydurmadan** ibaretti ve hiçbir
 * FK ihlalini yakalayamazdı. A1r5 bu kuralı kaldırdı; `profiles`'ın son
 * sırada olması ayrı bir kural olarak korundu (trigger/istemci bağımlılığı).
 *
 * `favorite_foods`/`recent_foods` → `foods` bağımlılığı bugün **tehdit
 * oluşturmuyor**, çünkü `foods` `DATA_TABLES`'te yok (`auth.admin.deleteUser()`
 * foods'i hiç silmiyor; yalnızca `created_by`'ı silinen satırları CASCADE ile
 * temizliyor). Yine de kural **bilerek** kayıt altındadır
 * (`FOODS_DEPENDENT_TABLES`): `foods` ileride `DATA_TABLES`'e eklenirse
 * (ürün kararı değişirse) sıra ihlali bir FK hatasına dönüşür ve silme
 * yarıda kalır.
 */
export function assertSafeDeletionOrder(tables: readonly string[] = DATA_TABLES): void {
  const index = new Map(tables.map((t, i) => [t, i]));

  for (const [child, parent] of FK_DELETION_RULES) {
    const childIndex = index.get(child);
    const parentIndex = index.get(parent);
    // Kuralın bir ucu listede yoksa kural bu akışta **geçerli değildir**
    // (ör. ebeveyn `foods` `DATA_TABLES`'te yok) — sessizce geç, çünkü
    // silme sırası ihlali ancak ikisi de siliniyorsa oluşabilir.
    if (childIndex === undefined || parentIndex === undefined) continue;
    if (childIndex > parentIndex) {
      throw new Error(`silme sırası hatalı: ${child}, ${parent}'ten önce silinmeli`);
    }
  }

  // Profil her zaman son sırada olmalıdır (trigger/istemci bağımlılığı).
  if (index.get("profiles") !== tables.length - 1) {
    throw new Error("silme sırası hatalı: profiles son tabloda olmalı");
  }
}

/**
 * `auth.admin.deleteUser()` hatasının "kullanıcı zaten yok" (idempotent
 * başarı) olup olmadığını **dar** bir kalıpla belirler.
 *
 * A1r4 bulgusu (P2): eski kod `message.includes("not found")` ile eşleşiyordu.
 * Bu **çok geniş** bir kalıptır: Supabase/GoTrue'nin aşağıdaki gerçek
 * hataları da bu kalıba girer ve **idempotent başarı** sayılır:
 *
 *   - `"User not found"`                        → doğru (idempotent)
 *   - `"user not found"` / `"User Not Found"`    → doğru (idempotent)
 *   - `"Auth session not found"` / `"session not found"` → **yanlış**: oturum
 *     hatası, silme yapılmadı
 *   - `"Database connection failed: schema not found"` → **yanlış**: bağlantı
 *     hatası, auth kaydı duruyor ama kullanıcıya "başarı" deniyor
 *   - `"new row violates row-level security policy"` → "not found" içermese
 *     bile eşleşmezdi; yine de kapsam dışı bırakıldı (aşağıda).
 *
 * Etki (A1r4): "Gerçek bir silme hatası başarı sayılabilir" → KVKK
 * "sil" talebi sessizce karşılanmamış sayılıyor.
 *
 * Çözüm: eşleşme **kullanıcıyı özneye alan** kalıplara daraltıldı
 * (`user ... not found` / `user_not_found` / HTTP 404 + `user`).
 * `row-level security` / `schema` / `session` içeren hatalar artık
 * istisna fırlatır → çağıran `DELETION_PARTIAL_MESSAGE` döner.
 */
export function isAlreadyDeletedAuthError(error: {
  message?: string | null;
  status?: number | null;
  code?: string | null;
}): boolean {
  const message = (error?.message ?? "").toLowerCase();

  // 1) GoTrue'nin gerçek "kullanıcı yok" hatası: `User not found`.
  //    `user` **mutlaka** geçmeli; `session not found` / `schema not found`
  //    gibi "başka bir şey bulunamadı" hataları bu kalıba girmez.
  if (/\buser\b[^a-z0-9_]+(?:was\s+)?not[\s_-]?found\b/.test(message)) return true;
  // 2) Bazı sürümler snake_case döner: `user_not_found`.
  if (/\buser_not_found\b/.test(message)) return true;
  // 3) Hata gövdesi boşsa HTTP durumu tek sinyal: 404 = hedef yok.
  if (message === "" && error?.status === 404) return true;

  return false;
}

/** Parola doğrulama hatasını istemciye sızan mesaj olmadan HTTP durumuna eşler. */
export function mapPasswordErrorToStatus(error: {
  message?: string | null;
  status?: number | null;
}): { status: number; publicMessage: string } {
  const message = (error?.message ?? "").toLowerCase();
  // Supabase Auth "Invalid login credentials" döner; ayrıntı yalnızca loglanır.
  if (message.includes("invalid login credentials")) {
    return { status: 401, publicMessage: "Parola hatalı" };
  }
  if (message.includes("email not confirmed")) {
    return { status: 401, publicMessage: "Parola hatalı" };
  }
  if (typeof error?.status === "number" && error.status === 429) {
    return { status: 429, publicMessage: "Çok fazla deneme yapıldı, lütfen bekleyin" };
  }
  return { status: 401, publicMessage: "Parola hatalı" };
}

/** Yanıtta kullanıcıya dönen SABİT mesaj (KVKK onayı). */
export const DELETION_SUCCESS_MESSAGE = "Hesabınız ve tüm verileriniz kalıcı olarak silindi.";

/**
 * Kısmi silme yanıtı (A1r4): `auth.admin.deleteUser()` BAŞARISIZ olduğu için
 * bu mesaj yalnızca o durumda döner. Kullanıcıya "başarı" gibi görünmemeli
 * ama tablo/kolon adı da sızdırılmamalıdır.
 */
export const DELETION_PARTIAL_MESSAGE =
  "Hesabınızın bir bölümü silinemedi. Lütfen birkaç dakika sonra tekrar deneyin.";
