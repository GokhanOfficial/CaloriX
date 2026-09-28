/**
 * `delete-account` edge function'ının **saf** yardımcıları için Deno testleri.
 *
 * Çalıştırma:
 *   deno test --allow-read supabase/functions/delete-account/delete_account_test.ts
 *
 * `--allow-read` yalnızca son "senkron" testi için gereklidir (`index.ts`
 * kaynağını okuyup tablo listesinin senkron olduğunu doğrular). Bu, saf
 * yardımcıların `index.ts` ile ayrışmasını (drift) yakalar.
 *
 * Bu dosya Edge DB'ye bağımlı DEĞİLDİR: tablo listesi, silme sırası ve parola
 * doğrulama hata eşlemesi saf fonksiyonlardır. Bu sayede CI'da Supabase
 * instance'ı olmadan da doğrulanabilir (bkz. PROTOKOL: "gerçekten işe yarayan
 * testler", "assertion içerir").
 *
 * Not: `index.ts` `serve()` çağırdığı için **doğrudan import edilmez**; saf
 * yardımcıların aynı kaynaktan çıkarıldığı kopyaları test edilir. Bu kopya
 * `deno check` ile eşitlenir (aşağıdaki test bunu doğrular).
 */

import {
  DATA_TABLES,
  DELETION_PARTIAL_MESSAGE,
  DELETION_SUCCESS_MESSAGE,
  OWNER_FILTER_OVERRIDES,
  assertSafeDeletionOrder,
  isAlreadyDeletedAuthError,
  mapPasswordErrorToStatus,
  ownerFilterColumn,
} from "./helpers.ts";
import {
  DIRECT_USER_FK_TABLES,
  FK_DELETION_RULES,
  FOODS_DEPENDENT_TABLES,
  REQUIRED_INDEX_NAMES,
  SCHEMA_TABLES,
  assertSchemaContract,
  isSafeDeletionOrder,
} from "../_shared/schema_contract.ts";

// Harici test kütüphanesi kullanılmaz (bkz. `_shared/vapid_test.ts`).
function assert(condition: unknown, message = "assertion başarısız"): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals<T>(actual: T, expected: T, message?: string): void {
  const a = JSON.stringify(actual);
  const b = JSON.stringify(expected);
  if (a !== b) throw new Error(message ?? `beklenen ${b}, alınan ${a}`);
}

function assertThrows(fn: () => unknown, match: RegExp, message?: string): void {
  try {
    fn();
  } catch (error) {
    const text = (error as Error).message;
    assert(match.test(text), message ?? `beklenen /${match.source}/, alınan "${text}"`);
    return;
  }
  throw new Error(message ?? "istisna bekleniyordu, atılmadı");
}

// ---------------------------------------------------------------------------
// Tablo listesi
// ---------------------------------------------------------------------------

Deno.test("veri tabloları listesi KVKK kapsamını içerir (brifteki 12 tablo)", () => {
  const required = [
    "meal_entries",
    "water_entries",
    "weight_entries",
    "notifications",
    "notification_preferences",
    "user_settings",
    "favorite_foods",
    "recent_foods",
    "push_subscriptions",
    "chat_messages",
    "chat_threads",
    "profiles",
  ];
  for (const table of required) {
    assert(DATA_TABLES.includes(table), `eksik tablo: ${table}`);
  }
  assertEquals(DATA_TABLES.length, 12, "tam olarak 12 tablo");
});

Deno.test("tablo listesi tekrarsızdır", () => {
  assertEquals(new Set(DATA_TABLES).size, DATA_TABLES.length);
});

Deno.test("her tablo geçerli bir sahiplik kolonuna göre silinir", () => {
  for (const table of DATA_TABLES) {
    const column = ownerFilterColumn(table);
    assert(
      column === "user_id" || column === "id",
      `${table} için geçersiz filtre kolonu: ${column}`,
    );
  }
  // `profiles` birincil anahtarı `id` olduğu için özel ele alınmalı.
  assertEquals(ownerFilterColumn("profiles"), "id");
  assertEquals(ownerFilterColumn("meal_entries"), "user_id");
  assertEquals(OWNER_FILTER_OVERRIDES.profiles, "id");
});

Deno.test("listede kullanıcı dışı/global tablolar YOKTUR (veri sızıntısı koruması)", () => {
  // Bu tablolar silinirse BAŞKA kullanıcıların verisi silinir.
  // `foods` özel: kullanıcının eklediği gıdalar `created_by` FK'si
  // `ON DELETE CASCADE` ile **o kullanıcının** hesabı silinirken temizlenir
  // (URUN-KARARLARI 3-A); ama `delete-account` `foods`'i **silmez** çünkü
  // `created_by IS NULL` seed gıdaları ve başka kullanıcı referansları var.
  const forbidden = ["foods", "food_nutrition", "rate_limits", "user_roles", "storage"];
  for (const table of forbidden) {
    assert(!DATA_TABLES.includes(table), `global tablo listede olmamalı: ${table}`);
  }
  // `user_roles` ve `rate_limits` `auth.users`'a FK'si olmayan / doğrudan
  // CASCADE ile temizlenen tablolar — yine de listede olmamalı.
  for (const table of forbidden) {
    assert(!DATA_TABLES.includes(table), `global tablo listede olmamalı: ${table}`);
  }
});

// ---------------------------------------------------------------------------
// Sıralama
// ---------------------------------------------------------------------------

Deno.test("varsayılan sıralama güvenlidir (chat_messages -> chat_threads -> profiles)", () => {
  assertSafeDeletionOrder();
  const i = (t: string) => DATA_TABLES.indexOf(t);
  assert(i("chat_messages") < i("chat_threads"), "chat_messages thread'ten önce silinmeli");
  assert(i("chat_threads") < i("profiles"), "chat_threads profile'dan önce silinmeli");
});

Deno.test("profile erken silinirse hata verilir", () => {
  // A1r5: kural listesi artık elle yazılmış `chat_threads -> profiles`
  // çiftini **içermez** (gerçek şemada `chat_threads` ile `profiles`
  // arasında FK **yoktur**; ikisi de `auth.users`'a gider). Kalan tek
  // kural `profiles` **son sırada olmalı** dedir ve ihlal burada yakalanır.
  const broken = ["profiles", "chat_messages", "chat_threads"];
  assertThrows(() => assertSafeDeletionOrder(broken), /profiles son tabloda olmalı/);
});

Deno.test("chat_messages, chat_threads'ten sonra gelirse hata verilir", () => {
  // profiles son sırada tutulur; ihlal eden kural chat_messages < chat_threads.
  const broken = ["chat_threads", "chat_messages", "profiles"];
  assertThrows(() => assertSafeDeletionOrder(broken), /chat_messages, chat_threads'ten önce/);
});

Deno.test("sıralama doğrulaması mevcut sırayı kabul eder", () => {
  assertSafeDeletionOrder([
    "chat_messages",
    "favorite_foods",
    "chat_threads",
    "profiles",
  ]);
});

Deno.test("bozuk sıralama sessizce geçmez", () => {
  // `chat_threads` profil'den önce silinmeli değil — asıl kural `profiles`
  // en sonda. Bu liste `profiles`'ı ortada bırakıyor → reddedilmeli.
  assertThrows(
    () => assertSafeDeletionOrder(["chat_messages", "profiles", "chat_threads"]),
    /profiles son tabloda olmalı/,
  );
});

// ---------------------------------------------------------------------------
// Parola doğrulama hata eşlemesi
// ---------------------------------------------------------------------------

Deno.test("parola doğrulama: yanlış parola -> 401 sabit mesaj", () => {
  const mapped = mapPasswordErrorToStatus({ message: "Invalid login credentials" });
  assertEquals(mapped.status, 401);
  assertEquals(mapped.publicMessage, "Parola hatalı");
});

Deno.test("parola doğrulama: onaylanmamış e-posta -> 401 sabit mesaj", () => {
  const mapped = mapPasswordErrorToStatus({ message: "Email not confirmed" });
  assertEquals(mapped.status, 401);
  assertEquals(mapped.publicMessage, "Parola hatalı");
});

Deno.test("parola doğrulama: bilinmeyen hata da 401 sabit mesaja düşer (detay sızmaz)", () => {
  const mapped = mapPasswordErrorToStatus({
    message: "Database connection failed: relation auth.users does not exist",
    status: 500,
  });
  assertEquals(mapped.status, 401);
  // Şema bilgisi istemciye sızmamalı.
  assert(!mapped.publicMessage.includes("relation"), "şema detayı sızdı");
  assert(!mapped.publicMessage.toLowerCase().includes("database"), "hata detayı sızdı");
});

Deno.test("parola doğrulama: hız sınırı durumu korunur", () => {
  const mapped = mapPasswordErrorToStatus({ message: "Too many requests", status: 429 });
  assertEquals(mapped.status, 429);
});

// ---------------------------------------------------------------------------
// Kaynak senkronizasyonu
// ---------------------------------------------------------------------------

/** `index.ts` ve `helpers.ts` kaynaklarını okur (senkronizasyon testi). */
async function readSource(file: string): Promise<string> {
  return await Deno.readTextFile(new URL(file, import.meta.url));
}

Deno.test("index.ts saf çekirdeği helpers.ts'ten alır (tek kaynak)", async () => {
  const source = await readSource("./index.ts");
  // Tablo listesi tek yerde tanımlıdır; index.ts yalnızca içe aktarır.
  assert(source.includes('from "./helpers.ts"'), "index.ts helpers.ts'i içe aktarmalı");
  assert(
    !source.includes("export const DATA_TABLES"),
    "DATA_TABLES yalnızca helpers.ts'te tanımlanmalı (kopya kaynak = kayma riski)",
  );
  for (const symbol of [
    "DATA_TABLES",
    "DELETION_SUCCESS_MESSAGE",
    "DELETION_PARTIAL_MESSAGE",
    "assertSafeDeletionOrder",
    "mapPasswordErrorToStatus",
    "ownerFilterColumn",
  ]) {
    assert(source.includes(symbol), `index.ts ${symbol} kullanmıyor`);
  }
  // Kritik davranışlar yerinde olmalı.
  assert(source.includes("assertSafeDeletionOrder("), "sıra doğrulaması çağrılmalı");
  assert(source.includes("auth.admin.deleteUser"), "auth.admin.deleteUser kullanılmalı");
  assert(source.includes("signInWithPassword"), "parola doğrulaması zorunlu olmalı");
  // Gövdeden kullanıcı kimliği kabul edilmemeli (BOLA).
  assert(
    !source.includes('body.userId') && !source.includes('body.user_id'),
    "kullanıcı kimliği gövdeden okunmamalı — yalnızca doğrulanmış JWT",
  );
});

// ---------------------------------------------------------------------------
// A1r4: kısmi silme sessizce "başarılı" sayılmamalı
// ---------------------------------------------------------------------------

Deno.test("tablo silme hatası sessizce yutulmaz (kısmi silme raporlanır)", async () => {
  // A1r3'ün `deleteUserRows` uygulaması hata alan tabloyu `continue` ile
  // atlıyor, `deleted` listesine koymuyor ve **başarı** dönüyordu. Bu, KVKK
  // açısından eksik silmeydi. Yeni sözleşme: `{ deleted, failed }`.
  const source = await readSource("./index.ts");
  assert(
    source.includes("failed.push("),
    "tablo silme hatası `failed` listesine eklenmeli",
  );
  assert(
    source.includes("DELETION_PARTIAL_MESSAGE"),
    "kısmi silmede kullanıcıya SABİT mesaj dönmeli",
  );
  assert(
    source.includes("retryRecommended"),
    "kısmi silmede yeniden deneme önerisi işaretlenmeli",
  );
  // Hata mesajı istemciye sızmamalı: yalnızca `console.error` içinde.
  assert(
    !/jsonResponse\(req, \{[^}]*error\.message/.test(source),
    "ham hata mesajı istemciye gönderilmemeli",
  );
});

Deno.test("kısmi silme mesajı başarı mesajından FARKLIDIR (kullanıcı yanıltılmaz)", () => {
  assertEquals(typeof DELETION_PARTIAL_MESSAGE, "string");
  assert(
    (DELETION_PARTIAL_MESSAGE as string) !== (DELETION_SUCCESS_MESSAGE as string),
    "kısmi silme ile tam silme mesajı aynı olmamalı",
  );
  // Kısmi silme mesajı tablo/kolon adı veya SQL detayı sızdırmamalı.
  for (const leak of ["profiles", "meal_entries", "user_id", "policy", "relation", "pg_"]) {
    assert(
      !DELETION_PARTIAL_MESSAGE.includes(leak),
      `kısmi silme mesajı şema sızdırıyor: ${leak}`,
    );
  }
  // Yine de kullanıcıya ne yapması gerektiği söylenmeli.
  assert(
    DELETION_PARTIAL_MESSAGE.includes("tekrar deneyin"),
    "kısmi silme mesajı yeniden deneme yönlendirmesi içermeli",
  );
});

Deno.test("deleteUserRows sözleşmesi { deleted, failed } döndürür", async () => {
  const source = await readSource("./index.ts");
  assert(
    /Promise<\{ deleted: string\[\]; failed: Array<\{ table: string; message: string \}> \}>/.test(source),
    "dönüş tipi hem başarılı hem başarısız tabloları içermeli",
  );
});

Deno.test("rate limit kullanıcı bazlı ve yıkıcı işlem için 2/saat", async () => {
  const source = await readSource("./index.ts");
  // Anahtar kullanıcı bazlı olmalı (IP tabanlı olsaydı bir kullanıcı
  // başkasının kotasını tüketirdi ve NAT arkasındaki kullanıcılar
  // birbirini kilitlerdi).
  assert(
    source.includes('rateLimitKey("delete-account", req, userId)'),
    "rate limit anahtarı doğrulanmış userId ile üretilmeli (kullanıcı bazlı)",
  );
  // Yıkıcı + geri alınamaz işlem: 5 deneme fazla.
  const match = /const RATE_LIMIT = \{ windowSeconds: (\d+), max: (\d+) \}/.exec(source);
  assert(match, "RATE_LIMIT sabiti okunamadı");
  const windowSeconds = Number(match![1]);
  const max = Number(match![2]);
  assertEquals(windowSeconds, 3600, "pencere 1 saat olmalı");
  assert(
    max <= 3,
    `saatte ${max} silme denemesi fazla; parola doğrulandığı için 2 yeterli (A1r4)`,
  );
});

Deno.test("parola gövdeden gelir ama asla loglanmaz", async () => {
  const source = await readSource("./index.ts");
  // Parolayı yazan herhangi bir log/console ifadesi olmamalı.
  assert(!/console\.(log|error|warn|info)\([^)]*\bpassword\b/.test(source),
    "parola hiçbir log ifadesinde geçmemeli");
  assert(!/JSON\.stringify\(body\)/.test(source), "gövde (parola içerir) loglanmamalı");
  // Parola yalnızca `signInWithPassword`'a verilir.
  assert(source.includes("signInWithPassword"), "parola doğrulaması yapılmalı");
  const uses = (source.match(/\bpassword\b/g) ?? []).length;
  assert(uses <= 6, `parola değişkeni gereğinden fazla yerde geçiyor (${uses}) — sızıntı riski`);
});

// ---------------------------------------------------------------------------
// A1r5: şema sözleşmesi — FK sırası elle liste değil, ŞEMADAN türetilir
// ---------------------------------------------------------------------------

Deno.test("şema sözleşmesi dahili olarak tutarlı (duplicate/bilinmeyen tablo yok)", () => {
  // Bu test, canlı şema karşılaştırmasının **daha** hızlı bir ön adımıdır
  // (bkz. supabase/tests/schema_contract.sql). Yeni bir tablo eklendiğinde
  // buradaki değişkenler güncellenmezse burası KIRILIR.
  assertSchemaContract();
});

Deno.test("sözleşmedeki tablo listesi delete-account listesini kapsar", () => {
  for (const table of DATA_TABLES) {
    assert(
      SCHEMA_TABLES.includes(table),
      `DATA_TABLES içindeki "${table}" şema sözleşmesinde yok — sözleşmeyi güncelle`,
    );
  }
});

Deno.test("DIRECT_USER_FK_TABLES canlı auth.users FK'siyle birebir (elle kopya değil)", () => {
  // Bu liste A1r5'te `pg_constraint`'ten **elle** kopyalandı; test
  // `supabase/tests/schema_contract.sql` adım 2'de canlı şemayla
  // karşılaştırır. Burada yalnızca dahili tutarlılığı doğrularız.
  // NOT: `foods` `created_by` FK'si `auth.users`'a gider → listede olmalı.
  assert(DIRECT_USER_FK_TABLES.includes("foods"), "foods.created_by FK'si auth.users'a gider");
  // `rate_limits` FK'si yoktur → listede olmamalı.
  assert(!DIRECT_USER_FK_TABLES.includes("rate_limits"), "rate_limits auth.users'a FK'siz");
});

Deno.test("FOODS_DEPENDENT_TABLES: favorite_foods + recent_foods foods'ten ÖNCE", () => {
  // A6r5'in aktardığı P0: favorite_foods.food_id / recent_foods.food_id
  // → foods(id) NOT NULL + CASCADE. foods `DATA_TABLES`'te olmadığı için
  // bugün sıra ihlali oluşmaz, ama kural kayıt altındadır.
  assert(
    FOODS_DEPENDENT_TABLES.includes("favorite_foods"),
    "favorite_foods foods'a FK taşıyor (kural listesinde olmalı)",
  );
  assert(
    FOODS_DEPENDENT_TABLES.includes("recent_foods"),
    "recent_foods foods'a FK taşıyor (kural listesinde olmalı)",
  );
  // `meal_entries.food_id` de foods'a gider ama SET NULL → engellemez, bu
  // yüzden `FOODS_DEPENDENT_TABLES` ile `FK_DELETION_RULES` kesişmez.
  for (const [child, parent] of FK_DELETION_RULES) {
    if (child === "meal_entries" || parent === "meal_entries") {
      assert(false, "meal_entries -> foods SET NULL, engelleyici kural olmamalı");
    }
  }
});

Deno.test("engelleyici FK kuralı listesi yalnızca chat_messages -> chat_threads", () => {
  // Sözleşmede 1 kural var. Yeni bir engelleyici FK eklenirse burası KIRILIR
  // (güncelleme zorunlu olsun).
  assertEquals(FK_DELETION_RULES.length, 1, "şu an tek engelleyici kural var");
  assertEquals(FK_DELETION_RULES[0][0], "chat_messages");
  assertEquals(FK_DELETION_RULES[0][1], "chat_threads");
});

Deno.test("varsayılan sıralama şema kuralına göre güvenlidir (isSafeDeletionOrder)", () => {
  // `isSafeDeletionOrder` saf fonksiyon: herhangi bir sıra listesini
  // doğrular. `DATA_TABLES` gerçek kural listesini geçer.
  assert(isSafeDeletionOrder(DATA_TABLES), "varsayılan sıra güvenli olmalı");
  // Bozuk sıra: chat_messages thread'ten sonra.
  assert(
    !isSafeDeletionOrder(["chat_threads", "chat_messages", "profiles"]),
    "chat_messages thread'ten sonra gelirse güvenli değil",
  );
});

Deno.test("assertSafeDeletionOrder: profil sonda değilse hata verir", () => {
  // `profiles` trigger/istemci bağımlılığı nedeniyle daima son sırada.
  // Bu listede `chat_threads` **yok** (dolayısıyla FK kuralı tetiklenmez) ve
  // `profiles` sondan bir yerde → yalnızca "profiles sonda değil" kuralı
  // yakalamalı. Bu, iki kuralın birbirinden **bağımsız** çalıştığını kanıtlar.
  assertThrows(
    () => assertSafeDeletionOrder(["chat_messages", "profiles", "water_entries"]),
    /profiles son tabloda olmalı/,
  );
  // Sonda olduğunda aynı liste sessizce geçer.
  assertSafeDeletionOrder(["chat_messages", "water_entries", "profiles"]);
});

Deno.test("gerekli indeks adları sözleşmede tanımlı (migration ile eşleşir)", () => {
  // Bu adlar `20260928300000_foods_cascade_and_rls_indexes.sql` içinde
  // oluşturulur. `schema_contract.sql` adım 5 canlı `pg_indexes` ile
  // doğrular; burada ad listesinin boş olmadığını sabitleriz.
  assertEquals(REQUIRED_INDEX_NAMES.length, 3, "3 indeks bekleniyor");
  for (const name of REQUIRED_INDEX_NAMES) {
    assert(name.length > 0 && /^[a-z0-9_]+$/.test(name), `geçersiz indeks adı: ${name}`);
  }
  assert(REQUIRED_INDEX_NAMES.includes("foods_created_by_rls"));
  assert(REQUIRED_INDEX_NAMES.includes("meal_entries_user_created_active"));
  assert(REQUIRED_INDEX_NAMES.includes("recent_foods_user_last_used"));
});

// ---------------------------------------------------------------------------
// A1r5 (Görev 4): deleteAuthUser'ın "not found" eşleşmesi DARALTILDI
// ---------------------------------------------------------------------------

Deno.test("GoTrue 'User not found' → idempotent başarı (gerçek idempotent durum)", () => {
  // Bu hata auth kaydının zaten silinmiş olduğu anlamına gelir → başarı.
  assert(isAlreadyDeletedAuthError({ message: "User not found" }));
  assert(isAlreadyDeletedAuthError({ message: "user not found" }));
  assert(isAlreadyDeletedAuthError({ message: "user_not_found" }));
  assert(isAlreadyDeletedAuthError({ message: "USER NOT FOUND" }));
});

Deno.test("'schema not found' idempotent SAYILMAZ (A1r4 P2 düzeltmesi)", () => {
  // A1r4: `includes("not found")` çok genişti. "schema not found" gerçek bir
  // silme hatasıdır ve başarı sayılmamalı → istisna fırlatılmalı.
  assert(
    !isAlreadyDeletedAuthError({ message: "Database error: schema not found" }),
    "'schema not found' idempotent başarı sayılmamalı",
  );
  assert(
    !isAlreadyDeletedAuthError({ message: "relation auth.users does not exist" }),
    "bağlantı/şema hatası idempotent sayılmamalı",
  );
});

Deno.test("'session not found' idempotent SAYILMAZ (oturum hatası ≠ kullanıcı silinmiş)", () => {
  // GoTrue oturum hatası da "not found" içerir — kullanıcı hâlâ var!
  assert(!isAlreadyDeletedAuthError({ message: "Auth session not found" }));
  assert(!isAlreadyDeletedAuthError({ message: "session not found" }));
});

Deno.test("row-level security hatası idempotent SAYILMAZ (K1: gerçek yetki hatası)", () => {
  // Postgres hata metni RLS ihlalini bildirir; bu "kullanıcı yok" demek
  // DEĞİLDİR. Eski `includes("not found")` bunu zaten yakalamıyordu ama
  // test kilitler.
  assert(
    !isAlreadyDeletedAuthError({ message: "new row violates row-level security policy" }),
    "RLS hatası idempotent sayılmamalı",
  );
});

Deno.test("bilinmeyen hata → idempotent değil (varsayılan kapalı)", () => {
  // Emniyet: bilinmeyen bir hata "kullanıcı zaten yok" sayılmaz.
  assert(!isAlreadyDeletedAuthError({ message: "Something unexpected happened" }));
  assert(!isAlreadyDeletedAuthError({ message: "deadlock detected" }));
  assert(!isAlreadyDeletedAuthError({ message: "" , status: 500 }));
  assert(!isAlreadyDeletedAuthError({ message: null }));
  assert(!isAlreadyDeletedAuthError({}));
});

Deno.test("404 + boş mesaj → idempotent (yalnızca bu kombinasyon)", () => {
  // Bazı GoTrue sürümleri mesaj vermeden 404 döner. Bu durumda hedef
  // nesnenin yokluğu anlamına gelir → idempotent başarı.
  assert(isAlreadyDeletedAuthError({ message: "", status: 404 }));
  // 404 AMA mesaj doluysa (ör. "schema not found") → idempotent DEĞİL.
  assert(!isAlreadyDeletedAuthError({ message: "schema not found", status: 404 }));
});

/** Kaynak dosyadan **yalnızca çalıştırılabilir satırları** döndürür
 * (yorumlar, import'lar ve fonksiyon imzaları atlanır) — böylece bir
 * **yorumda** geçen desen yanlışlıkla "kodda var" sayılmaz. */
function executableLines(source: string): string {
  return source
    .split("\n")
    .filter((line) => !/^\s*(\/\/|\*|\/\*)/.test(line))
    .filter((line) => !/^\s*import\b/.test(line))
    .join("\n");
}

Deno.test("deleteAuthUser: dar eşleştirme fonksiyonunu kullanır (geniş 'not found' YOK)", async () => {
  // Kaynak senkronizasyon testi: `index.ts` artık daraltılmış
  // `isAlreadyDeletedAuthError`'ı kullanmalı; geniş `includes("not found")`
  // kalıbı **çalıştırılabilir kodda** hiçbir yerde bulunmamalı.
  const code = executableLines(await readSource("./index.ts"));
  assert(
    code.includes("isAlreadyDeletedAuthError"),
    "index.ts daraltılmış eşleştirme fonksiyonunu kullanmalı",
  );
  assert(
    !/includes\(\s*["']not found["']\s*\)/.test(code),
    "geniş 'not found' eşleşmesi kaldırılmalı (A1r4 P2)",
  );
  // helpers.ts de aynı şekilde.
  const helpers = executableLines(await readSource("./helpers.ts"));
  assert(
    !helpers.includes('includes("not found")'),
    "helpers.ts'de geniş 'not found' eşleşmesi olmamalı",
  );
  assert(
    helpers.includes("isAlreadyDeletedAuthError"),
    "helpers.ts daraltılmış eşleştirme fonksiyonunu sunmalı",
  );
  // Daraltılmış fonksiyon gerçekten `user` öznesini arıyor olmalı.
  assert(
    /\\buser\\b\[\^a-z0-9_\]/.test(helpers),
    "eşleşme `user` öznesini içermeli (oturum/şema hatalarını dışlamak için)",
  );
});
