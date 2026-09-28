/**
 * Kanal etkinliği (`push` / `email`) — master anahtar gölgelenmesi (A1r10, P1)
 *
 * Çalıştırma:
 *   cd supabase && deno test --allow-env --allow-read \
 *     functions/_shared/channel_switch_test.ts
 *
 * ---------------------------------------------------------------------------
 * BUGÜN DÜZELTİLEN AÇIK
 * ---------------------------------------------------------------------------
 * `send-notification/index.ts` kanal kararını şöyle veriyordu:
 *
 *   const pushEnabled  = preference?.push_enabled  ?? profile.push_notifications_enabled  ?? true;
 *   const emailEnabled = preference?.email_enabled ?? profile.email_notifications_enabled ?? true;
 *
 * `??` **yalnız `null`/`undefined` üstüne** düşer. `notification_preferences`
 * tablosunun `push_enabled` kolonu `BOOLEAN DEFAULT true` ve **NOT NULL
 * değil**; yani bir satır yazıldığı anda dolu olur. `check-reminders`
 * "satır yoksa kapalı" davranır (`pref?.push_enabled || pref?.email_enabled`
 * → satır yoksa `false`), bu yüzden Flutter (A4r7) ve web (A5r10) **her tip
 * için satır yazan** istemciler oldu.
 *
 * Ölçülen sonuç: master `false` + yazılmış satır `true` → `??` satırı seçer
 * → **bildirim gider**. Kullanıcının üstteki "Push Bildirimleri" anahtarı
 * ölü kalır.
 *
 * A4r8 açığı **istemci tarafında** `applyMasterSwitches` ile kapattı. Bu
 * **tek katmandır**: DB'de zaten yazılmış satırları (yedek içe aktarım, eski
 * istemci sürümü, elle SQL) engellemez. İstemci tabanlı bildirim tercihi bir
 * güvenlik sınırı **değildir**; karar sunucuda verilmelidir.
 *
 * ---------------------------------------------------------------------------
 * "BAŞKA BİR GÖLGELENME YOLU VAR MI?" (Görev 4'ün sorusu) — EVET, 3 tane
 * ---------------------------------------------------------------------------
 * 1. `send-notification` kanal kararı (yukarıdaki `??` zinciri) — **düzeltildi**
 * 2. `check-reminders` tetikleme koşulu: `pref?.push_enabled ||
 *    pref?.email_enabled` — profil master anahtarına **hiç bakmıyor**. Yani
 *    master `false` olsa bile `check-reminders` tetiklenip `send-notification`'a
 *    gider (orada artık kapatılır → bildirim olmaz, ama gereksiz HTTP + DB
 *    sorgusu yapılır). Düzeltme: `send-notification` kapısı yeterli; ancak
 *    `check-reminders` içinde de master okunmalı ki hiç gidilmesin.
 * 3. `profile` **yoksa** (`.single()` 404 döndü) fonksiyon 404 ile bitiyor —
 *    master anahtarı da okunamıyor. Bu doğru davranış.
 *
 * Testler 1'i düzeltilmiş haliyle, 2'nin "en azından bildirim gitmez" kısmını
 * ise `resolveChannelEnabled` üzerinden ölçer.
 */

import { resolveChannelEnabled } from "./http.ts";

function assert(condition: unknown, message = "assertion başarısız"): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals<T>(actual: T, expected: T, message?: string): void {
  const a = JSON.stringify(actual);
  const b = JSON.stringify(expected);
  if (a !== b) throw new Error(message ?? `beklenen ${b}, alınan ${a}`);
}

// ---------------------------------------------------------------------------
// 1) ⭐ ANAHTAR TESTİ: master `false` + tip `true` → KAPALI (gölgelenme yok)
// ---------------------------------------------------------------------------

Deno.test("⭐ master false + tip true → KAPALI (eski `??` zinciri burada AÇTIKTI)", () => {
  // A4r8'in ölçtüğü senaryo: master `false`, varsayılan `true`.
  assertEquals(
    resolveChannelEnabled({ preferenceEnabled: true, masterEnabled: false }),
    false,
    "master kapandıysa tip açık olsa bile kanal KAPALI olmalı",
  );

  // Eski davranışın karşıtı (kendi kendini reddeden kanıt):
  const old = (p: boolean | null | undefined, m: boolean | null | undefined) =>
    p ?? m ?? true;
  assertEquals(
    old(true, false),
    true,
    "ESKİ davranış master'ı gölgeliyordu (bildirim giderdi) — düzeltilen hata",
  );
});

Deno.test("master false → tip değeri ne olursa olsun KAPALI (4 kombinasyon)", () => {
  for (const pref of [true, false, null, undefined]) {
    assertEquals(
      resolveChannelEnabled({ preferenceEnabled: pref, masterEnabled: false }),
      false,
      `master=false, tip=${String(pref)} → kapalı olmalı`,
    );
  }
});

Deno.test("master true + tip false → KAPALI (tip tercihi saygı görür)", () => {
  assertEquals(resolveChannelEnabled({ preferenceEnabled: false, masterEnabled: true }), false);
});

Deno.test("master true + tip true → AÇIK (her iki katman da izin veriyor)", () => {
  assertEquals(resolveChannelEnabled({ preferenceEnabled: true, masterEnabled: true }), true);
});

Deno.test("master true + tip satırı YOK → master belirler (true)", () => {
  assertEquals(resolveChannelEnabled({ preferenceEnabled: null, masterEnabled: true }), true);
  assertEquals(resolveChannelEnabled({ preferenceEnabled: undefined, masterEnabled: true }), true);
});

Deno.test("master satırı YOK + tip true → tip belirler (eski kullanıcılar)", () => {
  assertEquals(resolveChannelEnabled({ preferenceEnabled: true, masterEnabled: null }), true);
});

Deno.test("iki katman da YOK → varsayılan (geriye uyum true)", () => {
  assertEquals(resolveChannelEnabled({}), true, "tercih yok, master yok → true (geriye uyum)");
  assertEquals(
    resolveChannelEnabled({ preferenceEnabled: null, masterEnabled: null }),
    true,
  );
  assertEquals(
    resolveChannelEnabled({ preferenceEnabled: null, masterEnabled: undefined }),
    true,
  );
  // Açık fallback verilebilir.
  assertEquals(
    resolveChannelEnabled({ fallback: false }),
    false,
    "fallback parametresi saygı görür",
  );
  assertEquals(
    resolveChannelEnabled({ masterEnabled: null, fallback: false }),
    false,
  );
  // ⭐ `fallback` **yalnız** her iki katman da yokken devreye girer; master
  // veya tip karar veriyorsa ezilmez.
  assertEquals(
    resolveChannelEnabled({ preferenceEnabled: true, fallback: false }),
    true,
    "tip tercihi varken fallback ezilmemeli",
  );
  assertEquals(
    resolveChannelEnabled({ masterEnabled: true, fallback: false }),
    true,
    "master varken fallback ezilmemeli",
  );
  assertEquals(
    resolveChannelEnabled({ masterEnabled: false, fallback: true }),
    false,
    "kapalı master fallback ile açılamaz",
  );
});

// ---------------------------------------------------------------------------
// 2) GÖLGELENME YOLU 2: master `false` iken hiçbir kombinasyon açılmaz
// ---------------------------------------------------------------------------

Deno.test("⭐ master false iken 9 kombinasyonun HİÇBİRİ kanalı açmaz", () => {
  // Tam kapsam matrisi. `resolveChannelEnabled` "kapalı master üstün
  // kazanır" kuralını bozulursa bu test kırmızı olur.
  let opened = 0;
  for (const pref of [true, false, null, undefined]) {
    for (const master of [false, true, null, undefined]) {
      const r = resolveChannelEnabled({ preferenceEnabled: pref, masterEnabled: master });
      if (master === false && r !== false) opened++;
    }
  }
  assertEquals(opened, 0, "master=false iken hiçbir kombinasyon açılmamalı");
});

Deno.test("kapalı master, açık tipi yazan satırı da ezmez (satır yazma yolu onaysız)", () => {
  // Yedek içe aktarım (data_transfer_import.dart) `notification_preferences`
  // satırlarını dosyadan yazabiliyor. Bu yol `applyMasterSwitches`'tan
  // GEÇMEZ. Sunucu kapısı bu satırları da durdurur.
  const imported = { push_enabled: true, email_enabled: true };
  const masterOff = { masterEnabled: false };
  assertEquals(
    resolveChannelEnabled({ preferenceEnabled: imported.push_enabled, ...masterOff }),
    false,
    "ithal edilmiş `true` satırı master kapalıyken de durdurulmalı",
  );
  assertEquals(
    resolveChannelEnabled({ preferenceEnabled: imported.email_enabled, ...masterOff }),
    false,
  );
});

Deno.test("kapalı master, tip satırı olmasa da kapatır (eski kullanıcılar korunur)", () => {
  // Hiç `notification_preferences` satırı yazmamış kullanıcı: master `false`
  // → eski `??` zinciri doğru çalışırdı. Yeni kural da doğru olmalı.
  assertEquals(
    resolveChannelEnabled({ preferenceEnabled: null, masterEnabled: false }),
    false,
    "satır yokken master false → kapalı (bu zaten doğruydu, bozulmamalı)",
  );
});

// ---------------------------------------------------------------------------
// 3) KAYNAK SENKRONİZASYONU — `??` zinciri gerçekten kalıktan kalktı mı?
// ---------------------------------------------------------------------------

Deno.test("send-notification `??` zincirini kullanmıyor (gölgelenme kaynağı kapalı)", async () => {
  const source = await Deno.readTextFile(
    new URL("../send-notification/index.ts", import.meta.url),
  );
  // Yorum satırları eski kodu **anlatmak** için içerebilir; bu yüzden
  // yalnızca kod satırları taranır (A4r7b tuzağı).
  const code = source.split("\n")
    .filter((l) => !l.trim().startsWith("//") && !l.trim().startsWith("*"))
    .join("\n");

  assert(
    !/preference\?\.(push|email)_enabled\s*\?\?/.test(code),
    "eski `preference?.push_enabled ?? ...` zinciri KODDA kalmamalı",
  );
  assert(code.includes("resolveChannelEnabled("), "sunucu resolveChannelEnabled kullanmalı");
});

Deno.test("resolveChannelEnabled tek kaynak: başka dosyada kopya tanım yok", async () => {
  const sendSource = await Deno.readTextFile(
    new URL("../send-notification/index.ts", import.meta.url),
  );
  assert(
    !sendSource.includes("function resolveChannelEnabled"),
    "kopya tanım send-notification içinde olmamalı",
  );
  const httpSource = await Deno.readTextFile(new URL("./http.ts", import.meta.url));
  assert(
    httpSource.includes("export function resolveChannelEnabled"),
    "tek uygulama _shared/http.ts'te olmalı",
  );
});

// ---------------------------------------------------------------------------
// 4) GÖLGELENME YOLU 2 — `check-reminders` master anahtarları hiç okumuyordu
// ---------------------------------------------------------------------------

Deno.test("⭐ check-reminders master anahtarları okuyor (gölgelenme yolu 2 kapandı)", async () => {
  // `check-reminders` `pref?.push_enabled || pref?.email_enabled` ile
  // tetikleniyor ve master anahtarlara **hiç bakmıyordu**. Sonuç: master
  // `false` olan kullanıcı için de her koşuda `send-notification`'a HTTP
  // çağrısı yapılıyordu (bildirim gönderilmiyordu, ama gereksiz yük,
  // `rate_limit_hit` sayımı ve `notifications` INSERT'i oluşuyordu).
  const source = await Deno.readTextFile(
    new URL("../check-reminders/index.ts", import.meta.url),
  );

  // (a) master kolonları SELECT'e dahil olmalı
  assert(
    source.includes("push_notifications_enabled") &&
      source.includes("email_notifications_enabled"),
    "check-reminders master anahtar kolonlarını SELECT etmeli",
  );
  // (b) kapı gerçekten uygulanmalı
  assert(
    source.includes("masterPush === false && masterEmail === false"),
    "iki master da kapalıyken profil atlanmalı",
  );
  // (c) `continue` ile atlama **sessiz** olmamalı: sayaç koşu özetinde
  //     görünmeli (A1r3'ün "sessiz hata yutma" ilkesi).
  assert(source.includes("skippedByMaster"), "atlanan profil sayısı izlenebilir olmalı");
  assert(
    /skippedByMaster,/.test(source),
    "skippedByMaster HTTP gövdesinde dönmeli (cron logunda görünsün)",
  );
});

Deno.test("master kapısı yalnız İKİ master da kapalıyken tetiklenir", async () => {
  // `null` master = "belirsiz" → **kapatılmış sayılmaz**. Aksi halde profili
  // hiç doldurmamış yeni kullanıcılar hiç hatırlatma almaz (geriye uyum
  // bozulur; A1r4'ün "sessizce kapanma" sınıfı).
  const source = await Deno.readTextFile(
    new URL("../check-reminders/index.ts", import.meta.url),
  );
  assert(
    !/masterPush\s*!==\s*true\s*&&\s*masterEmail\s*!==\s*true/.test(source),
    "`null` master'ı kapalı sayan koşul olmamalı (geriye uyum)",
  );
  assert(
    source.includes("masterPush === false && masterEmail === false"),
    "yalnız açıkça `false` olan master'lar kapatıcı olmalı",
  );
});
