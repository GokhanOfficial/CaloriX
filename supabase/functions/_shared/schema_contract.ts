/**
 * `public` şemasının **anlık görüntüsü** (A1r5) — "şema sözleşmesi".
 *
 * Neden bu dosya var? 7 tur migration eklendi ve her turda tablo/kolon/FK
 * listeleri **elle** tutuldu. Bu listeler bayatladığında hata **sessizce**
 * oluşuyordu:
 *  - `DATA_TABLES` yeni bir tabloyu kaçırırsa KVKK kapsamı eksik kalır,
 *  - FK sırası kontrolü yeni bir bağımlılığı görmez (bugün `foods`'e bağlı
 *    `favorite_foods`/`recent_foods` kuralı **hiç** kısıtlanmamıştı),
 *  - RLS `auth.uid() = <kolon>` süzgeci indekssiz kalırsa tablo taranır.
 *
 * Bu dosya listeleri tek noktadan türetmek için kullanılır ve **iki** test
 * tarafından denetlenir:
 *  1) `delete_account_test.ts` → `assertSchemaContract()` (dahili tutarlılık;
 *     Edge DB olmadan çalışır, CI'da `deno test` ile koşar),
 *  2) `supabase/tests/schema_contract.sql` → **canlı** `pg_class` /
 *     `pg_constraint` / `pg_index` ile birebir karşılaştırma.
 *
 * Yeni bir tablo/FK eklendiğinde ikinci test **kırılır** → bu dosyanın ve
 * `delete-account/helpers.ts` listesinin güncellenmesi zorunlu olur.
 *
 * Kaynak: `supabase/migrations/**` (Postgres 16.15'te `information_schema` /
 * `pg_constraint` / `pg_index` üzerinden doğrulandı) + `full_setup.sql`.
 * Bu dosya **derleme zamanı** bağımlılığı değildir; Edge Runtime'ta
 * içe aktarılır, Deno'yu çalıştırmaz.
 */

// ---------------------------------------------------------------------------
// 1) Tablo envanteri
// ---------------------------------------------------------------------------

/** `public` şemasındaki **her** tablo (alfabetik). */
export const SCHEMA_TABLES: readonly string[] = [
  "chat_messages",
  "chat_threads",
  "favorite_foods",
  "food_nutrition",
  "foods",
  "meal_entries",
  "notification_preferences",
  "notifications",
  "profiles",
  "push_subscriptions",
  "rate_limits",
  "recent_foods",
  "user_roles",
  "user_settings",
  "water_entries",
  "weight_entries",
];

/**
 * Sahiplik süzgeci yapılan tablolar ve süzgeç kolonu.
 *
 * Kolon `id` ise tablo `profiles`'tir (birincil anahtar `id`).
 * `foods` **yoktur**: sahiplik kolonu `created_by`'dır ama `delete-account`
 * `foods`'i **silmez** (paylaşılan katalog) — aşağıya bak.
 */
export const OWNER_COLUMN: Readonly<Record<string, string>> = Object.freeze({
  chat_messages: "user_id",
  chat_threads: "user_id",
  favorite_foods: "user_id",
  meal_entries: "user_id",
  notification_preferences: "user_id",
  notifications: "user_id",
  profiles: "id",
  push_subscriptions: "user_id",
  recent_foods: "user_id",
  user_roles: "user_id",
  user_settings: "user_id",
  water_entries: "user_id",
  weight_entries: "user_id",
});

/**
 * `auth.users`'a **doğrudan** FK'si olan tablolar.
 *
 * `delete-account` bu tabloların hepsini `DATA_TABLES`'e **eklemez**:
 *  - `user_roles`: RLS'te yazma yolu kapalı + `auth.admin.deleteUser()`
 *    aşamasında `ON DELETE CASCADE` ile temizlenir.
 *  - `foods`: paylaşılan katalog; `delete-account` **silmez**. Yalnızca
 *    `created_by`'ı silinen satırlar `auth.admin.deleteUser()` sırasında
 *    CASCADE ile gider (URUN-KARARLARI 3-A / migration `20260928300000`).
 *
 * `rate_limits` burada **yoktur**: `auth.users`'a FK'si yoktur (sayaç anahtarı
 * `scope:u:<uuid>` biçiminde metindir) ve `cleanup_rate_limits()` ile zamanla
 * silinir.
 */
export const DIRECT_USER_FK_TABLES: readonly string[] = [
  "chat_messages",
  "chat_threads",
  "favorite_foods",
  "foods",
  "meal_entries",
  "notification_preferences",
  "notifications",
  "profiles",
  "push_subscriptions",
  "recent_foods",
  "user_roles",
  "user_settings",
  "water_entries",
  "weight_entries",
];

/**
 * Silme sırasını **engelleyen** çocuk → ebeveyn FK çiftleri.
 *
 * `deleteUserRows` yalnızca `OWNER_COLUMN` tablolarını siler. Kural, ikisi de
 * silme listesinde olan FK'lar içindir: çocuk, ebeveynden **önce** silinmeli.
 *
 * Bugün **tek** engelleyici kural vardır. `foods`'e bağlı üç NOT NULL FK
 * (`food_nutrition`, `favorite_foods`, `recent_foods`) **kural listesinde
 * değildir** çünkü `foods` `OWNER_COLUMN` tablosu değildir (silme akışı
 * `foods`'e hiç dokunmaz); bu bağımlılıklar
 * `NON_BLOCKING_FK_REFERENCES`/`FOODS_DEPENDENT_TABLES` ile kayıt altındadır.
 *
 * TÜRETİLMEDİR — `supabase/tests/schema_contract.sql` adım 3 canlı
 * `pg_constraint`'i taramayla karşılaştırır. Yeni bir engelleyici FK
 * eklendiğinde test **kırılır**.
 */
export const FK_DELETION_RULES: ReadonlyArray<readonly [string, string]> = [
  // `chat_messages` → `chat_threads` (thread silinmeden mesaj silinemez)
  ["chat_messages", "chat_threads"],
];

/**
 * `OWNER_COLUMN` tablolarının **dışarı** giden FK'ları.
 *
 * `auth`  = `auth.users` → `auth.admin.deleteUser()` aşamasında
 *           `ON DELETE CASCADE` ile temizlenir, silme sırası kuralı **değildir**.
 * `foods` = `public.foods` → `delete-account` `foods`'i **silmez**; sadece
 *           `created_by`'ı silinen gıdalar CASCADE ile temizlenir. Yine de
 *           kural **kayıt altına alınır**: `foods` ileride `DATA_TABLES`'e
 *           eklenirse, `favorite_foods`/`recent_foods` `foods`'ten **önce**
 *           silinmelidir — bu listeden hatırlatılmazsa FK hatasıyla silme
 *           yarıda kalır.
 */
export const NON_BLOCKING_FK_REFERENCES: Readonly<Record<string, readonly string[]>> = Object.freeze({
  chat_messages: ["auth"],
  chat_threads: ["auth"],
  favorite_foods: ["auth", "foods"],
  meal_entries: ["auth", "foods"],
  notification_preferences: ["auth"],
  notifications: ["auth"],
  profiles: ["auth"],
  push_subscriptions: ["auth"],
  recent_foods: ["auth", "foods"],
  user_roles: ["auth"],
  user_settings: ["auth"],
  water_entries: ["auth"],
  weight_entries: ["auth"],
});

/**
 * `NON_BLOCKING_FK_REFERENCES`'te `foods` geçen tablolar — yani
 * `delete-account` akışında `foods`'ten **önce** silinmesi gereken çocuk
 * satırlar (A6r5 aktarımı). **TÜRETİLMİŞTİR**; `supabase/tests/schema_contract.sql`
 * adım 3 canlı `pg_constraint` ile doğrular.
 *
 * NOT: `meal_entries` de burada görünür (`food_id` → `foods`) ama FK'si
 * `ON DELETE SET NULL` olduğu için silmeyi **engellemez** — bu yüzden
 * `FK_DELETION_RULES` ile kesişmez (`assertSchemaContract` doğrular).
 */
export const FOODS_DEPENDENT_TABLES: readonly string[] = Object.keys(NON_BLOCKING_FK_REFERENCES)
  .filter((t) => (NON_BLOCKING_FK_REFERENCES[t] ?? []).includes("foods"))
  .sort();

/**
 * RLS sahiplik süzgecinin **indeksli olması gereken** kolonlar.
 *
 * RLS politikası `auth.uid() = <kolon>` ekler; indeks yoksa tablo taranır.
 * A1r5'in eklediği üç indeks bu gereksinimi doğrudan karşılar; mevcut
 * indeksler (UNIQUE kısıtları dahil) listede **zaten** karşılanmış olanlardır
 * ve `schema_contract.sql` adım 5 yalnızca **eksik olan** üçünü doğrular.
 *
 * `foods.created_by` ayrıdır: `foods` `OWNER_COLUMN` tablosu olmadığı için
 * ayrı bir girdi (`created_by`) taşır.
 */
export const REQUIRED_OWNER_INDEXES: ReadonlyArray<readonly [string, string]> = [
  // A1r5'in eklediği indeksler (migration 20260928300000)
  ["foods", "created_by"],
  ["meal_entries", "user_id"],
  ["recent_foods", "user_id"],
];

/** Bu sözleşmenin gerektirdiği indeks adları (migration ile birebir). */
export const REQUIRED_INDEX_NAMES: readonly string[] = [
  "foods_created_by_rls",
  "meal_entries_user_created_active",
  "recent_foods_user_last_used",
];

// ---------------------------------------------------------------------------
// 2) Tutarlılık denetimi (Edge Runtime'da çağrılabilir, saf)
// ---------------------------------------------------------------------------

export type SchemaContractIssue = { kind: string; detail: string };

/**
 * Sözleşmenin **dahili** tutarlılığını denetler. Canlı şemayla karşılaştırma
 * `supabase/tests/schema_contract.sql` işidir; bu fonksiyon o olmadan da
 * "elle kopyada tutarsızlık" yakalar.
 */
export function assertSchemaContract(): void {
  const issues: SchemaContractIssue[] = [];

  // a) Tablo listesi tekrarsız ve alfabetik mi?
  const unique = new Set(SCHEMA_TABLES);
  if (unique.size !== SCHEMA_TABLES.length) {
    issues.push({
      kind: "duplicate-table",
      detail: `${SCHEMA_TABLES.length} giriş, ${unique.size} benzersiz`,
    });
  }
  const sorted = [...SCHEMA_TABLES].sort();
  if (sorted.join(",") !== SCHEMA_TABLES.join(",")) {
    issues.push({ kind: "unsorted-tables", detail: "SCHEMA_TABLES alfabetik değil" });
  }

  // b) Her `OWNER_COLUMN` anahtarı gerçek bir tablo olmalı.
  for (const table of Object.keys(OWNER_COLUMN)) {
    if (!unique.has(table)) {
      issues.push({ kind: "unknown-owner-table", detail: table });
    }
  }

  // c) Her `DIRECT_USER_FK_TABLES` girdisi hem `SCHEMA_TABLES` hem
  //    `OWNER_COLUMN` içinde olmalı — `foods` hariç (bkz. DIRECT_USER_FK_TABLES).
  for (const table of DIRECT_USER_FK_TABLES) {
    if (!unique.has(table)) issues.push({ kind: "unknown-fk-table", detail: table });
    if (!(table in OWNER_COLUMN) && table !== "foods") {
      issues.push({ kind: "owner-column-missing", detail: table });
    }
  }

  // d) `FK_DELETION_RULES` içindeki iki uç da `OWNER_COLUMN` tablosu olmalı
  //    (aksi halde kural uygulanamaz).
  for (const [child, parent] of FK_DELETION_RULES) {
    if (!(child in OWNER_COLUMN)) issues.push({ kind: "fk-rule-child-unknown", detail: child });
    if (!(parent in OWNER_COLUMN)) issues.push({ kind: "fk-rule-parent-unknown", detail: parent });
    if (child === parent) issues.push({ kind: "fk-rule-self", detail: child });
  }

  // e) Her `OWNER_COLUMN` tablosu için `NON_BLOCKING_FK_REFERENCES` girdisi
  //    olmalı — aksi halde yeni bir FK sessizce kural dışı kalır.
  for (const table of Object.keys(OWNER_COLUMN)) {
    if (!(table in NON_BLOCKING_FK_REFERENCES)) {
      issues.push({ kind: "fk-reference-missing", detail: table });
    }
  }

  // e1) `FOODS_DEPENDENT_TABLES` yalnızca `OWNER_COLUMN` tablolarından
  //     türetilmelidir.
  for (const table of FOODS_DEPENDENT_TABLES) {
    if (!(table in OWNER_COLUMN)) {
      issues.push({ kind: "foods-dependent-not-owner", detail: table });
    }
  }

  // e2) `FOODS_DEPENDENT_TABLES` ile `FK_DELETION_RULES` **kesişmemeli**:
  //     `foods` silme listesinde olmadığı için foods'a bağlı hiçbir tablo
  //     engelleyici kural olamaz.
  for (const [child] of FK_DELETION_RULES) {
    if (FOODS_DEPENDENT_TABLES.includes(child)) {
      issues.push({ kind: "foods-dependent-also-blocking", detail: child });
    }
  }

  // f) Gerekli indeksler gerçek tabloların gerçek kolonlarını kapsamalı
  //    (`foods.created_by` hariç: `foods` `OWNER_COLUMN` tablosu değildir).
  for (const [table, column] of REQUIRED_OWNER_INDEXES) {
    if (!unique.has(table)) issues.push({ kind: "index-table-unknown", detail: table });
    if (table !== "foods" && OWNER_COLUMN[table] !== column) {
      issues.push({ kind: "index-column-mismatch", detail: `${table}.${column}` });
    }
  }

  if (issues.length > 0) {
    const detail = issues.map((i) => `${i.kind}(${i.detail})`).join(", ");
    throw new Error(`şema sözleşmesi tutarsız: ${detail}`);
  }
}

/**
 * Verilen silme sırası `FK_DELETION_RULES` için güvenli mi?
 * Çocuk, ebeveynden önce gelmelidir.
 */
export function isSafeDeletionOrder(order: readonly string[]): boolean {
  const index = new Map(order.map((t, i) => [t, i]));
  for (const [child, parent] of FK_DELETION_RULES) {
    const c = index.get(child);
    const p = index.get(parent);
    if (c === undefined || p === undefined) continue;
    if (c > p) return false;
  }
  return true;
}
