/**
 * `delete-account` fonksiyonunun **saf** (Edge DB'den bağımsız) yardımcıları.
 *
 * Neden ayrı dosya? Supabase edge function'ları her dizinde **tek bir giriş
 * dosyası** (`index.ts`) dağıtır; `_test.ts` dosyaları dağıtıma dahil edilmez.
 * Test edilebilir çekirdek burada tutulur, `index.ts` yalnızca onu kullanır.
 *
 * Buradaki her fonksiyon yan etkisizdir ve `delete_account_test.ts` tarafından
 * Edge DB olmadan doğrulanır.
 */

/**
 * Kullanıcıya ait **veri** silinen tablolar.
 *
 * Sıralama kasıtlıdır:
 *   1) Bağımlılığı olmayan çocuk satırlar (chat mesajları, favoriler, son
 *      kullanılanlar) önce — FK sırası ihlal edilirse silme yarıda kalmasın.
 *   2) Kullanıcının birincil verisi.
 *   3) Profil **en son**: `handle_new_user` trigger'ı ve istemci kodu profile
 *      bağlı olabilir; profil en sonda silinir.
 *
 * `user_roles` BİLEREK YOKTUR: RLS'te yazma yolu kapalı olan bir tablodur ve
 * `ON DELETE CASCADE` ile zaten `auth.admin.deleteUser()` aşamasında silinir.
 * `rate_limits` de yoktur (global sayaç, kişiye bağlı değil).
 */
export const DATA_TABLES: readonly string[] = [
  // Bağımlılıksız çocuk satırlar
  "chat_messages",
  "favorite_foods",
  "recent_foods",
  // Kullanıcı verisi
  "meal_entries",
  "water_entries",
  "weight_entries",
  "notifications",
  "notification_preferences",
  "user_settings",
  "push_subscriptions",
  "chat_threads",
  // Profil en son
  "profiles",
] as const;

/**
 * `user_id` kolonu olmayan ama silinmesi gereken tablo → filtre kolonu eşlemesi.
 * `profiles` birincil anahtarı `id` olduğu için ayrı ele alınır.
 */
export const OWNER_FILTER_OVERRIDES: Readonly<Record<string, string>> = Object.freeze({
  profiles: "id",
});

/** Verilen tablo için `user_id` (veya `id`) filtre kolonunu döndürür. */
export function ownerFilterColumn(table: string): string {
  return OWNER_FILTER_OVERRIDES[table] ?? "user_id";
}

/**
 * Silme sırasının bütünlüğünü doğrular. `chat_messages` `chat_threads`'ten
 * önce, `chat_threads` `profiles`'ten önce silinmelidir (FK bağımlılığı).
 * Yanlış sıralama yarıda kalmış silmeye yol açar; bu yüzden test edilir.
 */
export function assertSafeDeletionOrder(tables: readonly string[] = DATA_TABLES): void {
  const index = new Map(tables.map((t, i) => [t, i]));
  const order: Array<[string, string]> = [
    ["chat_messages", "chat_threads"],
    ["chat_threads", "profiles"],
  ];
  for (const [child, parent] of order) {
    const childIndex = index.get(child);
    const parentIndex = index.get(parent);
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
