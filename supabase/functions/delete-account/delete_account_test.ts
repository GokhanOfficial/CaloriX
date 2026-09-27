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
  OWNER_FILTER_OVERRIDES,
  assertSafeDeletionOrder,
  mapPasswordErrorToStatus,
  ownerFilterColumn,
} from "./helpers.ts";

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
  const forbidden = ["foods", "food_nutrition", "rate_limits", "user_roles", "storage"];
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
  const broken = ["profiles", "chat_messages", "chat_threads"];
  assertThrows(() => assertSafeDeletionOrder(broken), /chat_threads, profiles'ten önce/);
});

Deno.test("chat_messages, chat_threads'ten sonra gelirse hata verilir", () => {
  // profiles son sırada tutulur; ihlal eden ilk kural chat_messages < chat_threads.
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
  // profiles'ı sona almayan liste reddedilmeli.
  assertThrows(
    () => assertSafeDeletionOrder(["chat_messages", "profiles", "chat_threads"]),
    /chat_threads, profiles'ten önce/,
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
