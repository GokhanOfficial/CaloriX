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
 * Bu **çok geniş** bir kalıptır: GoTrue'nun aşağıdaki gerçek hataları da bu
 * kalıba girer ve **idempotent başarı** sayılır:
 *
 *   - `"User not found"`                        → doğru (idempotent)
 *   - `"Session not found"`                     → **yanlış**: oturum hatası
 *   - `"Confirmation Token not found"`          → **yanlış**
 *   - `"Refresh Token not found"`               → **yanlış**
 *   - `"Database connection failed: schema not found"` → **yanlış**: bağlantı
 *     hatası, auth kaydı duruyor ama kullanıcıya "başarı" deniyor
 *
 * Etki (A1r4): "Gerçek bir silme hatası başarı sayılabilir" → KVKK
 * "sil" talebi sessizce karşılanmamış sayılıyor.
 *
 * ---------------------------------------------------------------------------
 * A1r8 — KALIP, SÜRÜM-SABİTLİ KAYNAK KODLA DOĞRULANDI
 * ---------------------------------------------------------------------------
 * A1r5 "bu kalıplar canlı GoTrue'ye karşı denenmedi" diye raporlamıştı. Bu
 * turda **doğrulandı** — tahminle değil, **sürüm sabitlenmiş kaynak kodla**
 * (canlıya bağlanmadan):
 *
 *   - Projede bağlı GoTrue sürümü: `supabase/.temp/gotrue-version` →
 *     **`v2.185.0`**
 *   - `internal/models/errors.go`:
 *       `func (e UserNotFoundError) Error() string { return "User not found" }`
 *   - `internal/api/admin.go` → `loadUser()`:
 *       `apierrors.NewNotFoundError(apierrors.ErrorCodeUserNotFound, "User not found")`
 *   - `internal/api/apierrors/errorcode.go`:
 *       `ErrorCodeUserNotFound ErrorCode = "user_not_found"`
 *   - `internal/api/apierrors/apierrors.go` → `HTTPError` JSON etiketleri:
 *       `{"code": <http durumu>, "error_code": "<ErrorCode>", "msg": "<Message>"}`
 *
 * `admin.deleteUser()` "kullanıcı yok" durumunda **tam olarak** şunu döner:
 *
 *   HTTP 404 · `{"code":404,"error_code":"user_not_found","msg":"User not found"}`
 *
 * `supabase-js` bunu `AuthApiError` olarak sarar, alanları şöyle doldurur
 * (`@supabase/auth-js@2.117.2` → `lib/fetch.js` → `handleError`):
 *   `error.message = data.msg`  → `"User not found"`
 *   `error.status  = HTTP 404`
 *   `error.code    = data.error_code` (yoksa `data.code`) → `"user_not_found"`
 *
 * ### KALIP NEDEN BÖYLE (ve neden `code` birincil)
 *
 * **`code` birincil sinyaldir.** `user_not_found` GoTrue'nun **mühürlü**
 * hata kodudur. Mesaj metni sürümden sürüme değişebilir (A1r5'in korkusu
 * buydu) ama hata kodu değişmez. Bu yüzden karar önce `code`'a bakar.
 *
 * Mesaj regex'i **ikincil** sinyaldir ve iki amaçla tutulur:
 *   1) `error_code` alanı gelmeyen ama gövdesi `User not found` olan eski
 *      sürüm ya da vakalar (ör. hata loglarından kopyalanmış metin).
 *   2) `status` 404 olmadan gelen ama kodu yine `user_not_found` olan
 *      yanıtlar (bazı edge ağ geçitleri durum kodunu değiştirir).
 *
 * Mesaj deseni **kasıtlı olarak `user ... not found` kalıbına daraltıldı**:
 * GoTrue'daki diğer `* not found` hataları (`Session`, `Refresh Token`,
 * `Confirmation Token`, `Identity`, `Factor`, `Flow State`, …) bu kalıba
 * **giremez** — hiçbiri `user` sözcüğü içermez.
 *
 * ### GERİYE UYUM
 *
 *  - `error_code` dönmeyen eski GoTrue sürümleri: mesaj regex'i onları
 *    yakalamaya devam eder (A1r5 davranışı, `user_not_found` snake_case
 *    kalıbı dâhil, korunur).
 *  - `message === "" && status === 404` kuralı **korundu**: ters proxy
 *    (gateway) hata gövdesini yutabiliyor; bu durumda durum kodu tek
 *    sinyaldir.
 *  - Varsayılan **kapalıdır**: eşleşmeyen her hata istisna fırlatır
 *    (`DELETION_PARTIAL_MESSAGE`).
 *
 * ### ⭐ A1r8'DE ÖLÇÜLEN DÜZELTME: bilinen ALAKASIZ kod mesajı ezmez
 *
 * Yeni test yazarken şu senaryo **kırmızı** çıktı ve gerçek bir açık
 * gösterdi:
 *
 *   `{ message: "", status: 404, code: "session_not_found" }` → `true` idi.
 *
 * Sebep: 3. kural (`boş + 404` ⇒ idempotent) `code` alanına **bakmıyordu**.
 * Yani GoTrue "oturum bulunamadı" dediğinde, hata kodu elinde dururken
 * fonksiyon bunu "kullanıcı zaten yok" sayıp **başarı** dönüyordu →
 * `auth.admin.deleteUser()` aslında kullanıcıyı silmemiş olmasına rağmen
 * KVKK talebi "karşılandı" görünüyordu. Bu, A1r4'ün kapatmaya çalıştığı
 * açığın `code` alanı üzerinden **yeniden** açılmasıydı.
 *
 * Düzeltme: `code` **doluysa** karar `code`'a aittir (birebir `user_not_found`
 * ⇒ idempotent, aksi hâlde ⇒ istisna). "Boş + 404" kuralı yalnızca hiç
 * hata kodu gelmemiş yanıtlar için geçerlidir.
 */
export function isAlreadyDeletedAuthError(error: {
  message?: string | null;
  status?: number | null;
  code?: string | null;
}): boolean {
  // 1) BİRİNCİL: GoTrue'nun mühürlü hata kodu. `error_code` alanı
  //    (`user_not_found`) birebir karşılaştırılır — `includes` DEĞİL
  //    (kısmen eşleşen bir kod "yok" anlamına gelmez).
  //    Kaynak: apierrors/errorcode.go → ErrorCodeUserNotFound.
  const code = (error?.code ?? "").trim().toLowerCase();
  if (code === "user_not_found") return true;
  // `code` **biliyorsak** ve `user_not_found` DEĞİLSE bu hata başka bir
  // şeyin yokluğudur (`session_not_found`, `factor_not_found`, …) ve
  // mesaja bakılmaz. A1r8'de ölçülen hata: boş gövde + 404 + bilinen
  // alakasız kod, 3. kural yüzünden (aşağıda) yanlışlıkla "idempotent
  // başarı" sayılıyordu → gerçek silme hatası KVKK "başarı"sına dönüşüyordu.
  if (code !== "") return false;

  // 2) İKİNCİL: mesaj deseni. `user` sözcüğü ZORUNLU; GoTrue'daki
  //    `Session / Refresh Token / Confirmation Token / Identity / Factor /
  //    Flow State not found` hataları bu kalıba giremez (models/errors.go).
  //    A1r5'in `user_not_found` (snake_case, mesaj içinde) kalıbı da korunur.
  const message = (error?.message ?? "").toLowerCase();
  if (/\buser\b[^a-z0-9_]+(?:was\s+)?not[\s_-]?found\b/.test(message)) return true;
  if (/\buser_not_found\b/.test(message)) return true;

  // 3) Gövde tamamen boşsa **ve** hata kodu hiç gelmemişse HTTP durumu tek
  //    sinyal: 404 = hedef yok. (Ters proxy hata gövdesini yutabiliyor.)
  //    `code` boş olduğu için kural 1'de zaten elendi.
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
