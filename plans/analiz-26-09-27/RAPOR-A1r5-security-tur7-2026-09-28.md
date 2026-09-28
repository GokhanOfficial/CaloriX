# RAPOR — A1r5-security — 2026-09-28 — Tur 7

> Kapsam: `supabase/**` (migration + edge function + config + SQL test).
> `flutter_app/**`, `src/**`, `tool/**`, `.github/**` dosyalarına
> **dokunulmadı** (`A2`/`A3`/`A4`/`A6` alanları).
> Doğrulama ortamı: **Postgres 16.15 (Docker `a1r5-pg` / `a1r5-fs`)**,
> `deno 2.9.7`. Test dosyaları `supabase/tests/` altında (kullanıcı kısıtı:
> `/tmp` dışında).
> **Ürün kararı 3-A uygulandı** (`URUN-KARARLARI.md`), **4-A uygulanmadı**
> (`photo_url`'a dokunulmadı).

## Özet (5 madde)

1. **`foods.created_by` FK artık `ON DELETE CASCADE`** (URUN-KARARLARI 3-A).
   Yeni migration `20260928300000`. Zincir ölçüldü:
   `auth.users → foods → food_nutrition / favorite_foods / recent_foods`
   (üçü de `NOT NULL` + `CASCADE`), `meal_entries.food_id → SET NULL`
   (öğün satırı **korunur**). **`created_by IS NULL` satırlar (seed/admin)
   CASCADE ile TETİKLENMEZ** — topluluk verisi bozulmuyor. Dört iddia
   `supabase/tests/foods_cascade.sql` (yeni) ile kanıtlandı, **iki kurulum
   yolunda da**.

2. **⭐ P1 — `full_setup.sql` ile migration yolu ayrışmıştı, düzeltildi.**
   `full_setup.sql`, `20260927120000`'de yapılan `meal_entries.food_id`
   FK düzeltmesini (`ON DELETE SET NULL`) **hiç uygulamıyordu**; Postgres
   varsayılanı `NO ACTION` ile tablo üretiyordu. Sonuç: (a) bir gıda
   silinmek istendiğinde ona bağlı öğün varsa DELETE **başarısız** oluyordu
   (kullanıcı kendi eklediği gıdayı silemiyordu), (b) `foods.created_by`
   CASCADE ile hesap silinirken `auth.admin.deleteUser()` **FK ihlali**
   veriyordu. A1r5'in CASCADE testi bu farkı yakaladı. Ayrıca
   `chat_threads_user_archived` ve `foods_name_brand_unique` indeksleri de
   `full_setup`'ta eksikti → eklendi. **FK/CHECK/kolon/index/politika
   paritesi artık iki yolda birebir aynı** (20 FK · 14 CHECK · 39 index · 55 politika).

3. **Görev 1 — FK sıra testi artık şemadan türetiliyor.** Yeni
   `_shared/schema_contract.ts` (tablo envanteri, sahiplik kolonları,
   FK kuralları) + `tests/schema_contract.sql` (10 kontrol). Yeni tablo veya
   engelleyici FK eklendiğinde test **kırılıyor** — bu **ölçüldü**
   (`a1r5_probe` tablosu ve `chat_threads→notifications` FK'si eklendi → ikisi
   de kırmızı; sonra temizlendi). Yan bulgu: A1r4'ün elle yazdığı
   `chat_threads → profiles` kuralı **uydurma**ydı (gerçek şemada aralarında
   FK yok) ve kaldırıldı; `favorite_foods`/`recent_foods → foods` kuralı ise
   hiç kısıtlanmamıştı → `FOODS_DEPENDENT_TABLES` ile kayıt altına alındı.

4. **Görev 4 + 5 — `deleteAuthUser` daraltıldı, `dbBypassUntil` belgelendi.**
   `includes("not found")` → `isAlreadyDeletedAuthError()`: yalnızca GoTrue'nun
   gerçek "User not found" / `user_not_found` hataları (ve boş mesaj + HTTP
   404) idempotent başarı sayılıyor; `"schema not found"`, `"session not
   found"`, RLS ihlali ve bilinmeyen hatalar artık istisya fırlatıyor.
   `DB_BYPASS_COOLDOWN_MS = 60_000` için gerekçe + güvenlik değerlendirmesi
   yazıldı: **istek atlanmaz**, yalnızca kova instance başına sayılır.

5. **Görev 3 — Şema borcu envanteri çıkarıldı; 3 ölçülmüş indeks + 1 CHECK
   eklendi.** RLS'in `auth.uid() = user_id` süzgeci `foods` dışında her yerde
   zaten indeksliydi; eksik olan iki yer `foods.created_by` (RLS politikası
   süzgeci **indekssiz**) ve `recent_foods.last_used_at` (hiçbir indekste
   yok) idi. En büyük kazanç `meal_entries(user_id, created_at DESC) WHERE
   deleted_at IS NULL`: 20.000 satırda **7.49 ms → 0.06 ms (125×)**, çünkü
   iki istemcinin de favorileri/son kullanılanları türettiği sorgu tam olarak
   bu deseni kullanıyor. **Kanıtsız indeks eklenmedi.** `food_nutrition`
   negatif besin değeri kısıtı eklendi.

## Düzeltilenler

| Sev | Dosya | Ne yapıldı | Doğrulama |
|---|---|---|---|
| **P0** | `migrations/20260928300000_foods_cascade_and_rls_indexes.sql` (**yeni**) | `foods.created_by` FK: `SET NULL` → **`CASCADE`** (yalnızca gerçekten `SET NULL` ise; başka davranışa dokunulmaz). `created_by IS NULL` envanteri NOTICE ile raporlanır, hiçbir satır değişmez. 3 index + 1 CHECK aşağıda | 17 migration sıfırdan 0 hata · **3× üst üste idempotent** · `tests/foods_cascade.sql` 2/2 iki yolda |
| **P1** | `full_setup.sql` | ⭐ `meal_entries.food_id` FK → **`ON DELETE SET NULL`** (yoktu, `NO ACTION` idi) · `foods.created_by` → `CASCADE` · 3 yeni index (`foods_created_by_rls`, `meal_entries_user_created_active`, `recent_foods_user_last_used`) · 2 **eksik** index (`chat_threads_user_archived`, `foods_name_brand_unique`) · `food_nutrition_values_non_negative` CHECK | Sıfırdan **0 hata**, 55 politika · **FK/CHECK/kolon/index parite `diff` = boş** |
| **P1** | `functions/_shared/schema_contract.ts` (**yeni**, 298 satır) | Şema sözleşmesi: `SCHEMA_TABLES` (16), `OWNER_COLUMN`, `DIRECT_USER_FK_TABLES` (14), `FK_DELETION_RULES`, `NON_BLOCKING_FK_REFERENCES`, `FOODS_DEPENDENT_TABLES` (türetilmiş), `REQUIRED_INDEX_NAMES`, `assertSchemaContract()`, `isSafeDeletionOrder()` | `deno check` 0 hata · `delete_account_test.ts` 7 yeni test |
| **P1** | `functions/delete-account/helpers.ts` | `assertSafeDeletionOrder` artık `FK_DELETION_RULES`'tan iterasyon yapıyor (elle `[chat_messages, chat_threads]` listesi yerine). `OWNER_FILTER_OVERRIDES` şema sözleşmesinden türetiliyor. **Yeni**: `isAlreadyDeletedAuthError()` | 6 yeni senaryo testi |
| **P1** | `functions/delete-account/index.ts` | `deleteAuthUser` geniş `includes("not found")` → `isAlreadyDeletedAuthError({message, status, code})`. `foods.created_by` CASCADE notu başlığa eklendi | Kaynak senkronizasyon testi (geniş kalıp **yorumlarda bile** aranmıyor) |
| **P1** | `tests/schema_contract.sql` (**yeni**, 429 satır, 10 kontrol) | (1) tablo envanteri ↔ canlı `pg_class` · (2) `DIRECT_USER_FK_TABLES` ↔ canlı `pg_constraint` · (3) engelleyici FK kuralı · (3b) `foods`'e NOT NULL FK sahipleri · (4) 12 tablo gerçekten bu sırayla silinebiliyor · (5) 3 RLS indeksi var + `created_by` kapsıyor · (6) negatif besin reddi · (7) CASCADE · **(7b) 17 FK'nin `ON DELETE` davranışı tam liste olarak sabit** | **10/10 iki yolda** · negatif senaryo ölçüldü (yeni tablo → kırmızı) |
| **P1** | `tests/foods_cascade.sql` (**yeni**, 119 satır, 2 kontrol / 4 iddia) | 3-A kararının 4 iddiası: (1) gıda CASCADE silinir, (2) `food_nutrition` zincirle silinir, (3) **başka kullanıcının öğünü `food_id=NULL` ile korunur**, (4) **`created_by IS NULL` seed gıdası + besini + başkasının favorisi sağlam kalır** | 2/2 iki yolda · `ROLLBACK` ile kalıcı değişiklik yok |
| **P2** | `functions/_shared/rate_limit.ts` | `DB_BYPASS_COOLDOWN_MS` gerekçesi (maliyet, thundering herd, süre seçimi) + **güvenlik değerlendirmesi**: istek atlanmaz, kova instance başına sayılır; `delete-account` parola doğrulaması + kullanıcı bazlı anahtarla dengeleniyor | Yorum bloğu (kod değişmedi) |
| **P2** | `tests/account_deletion_scope.sql` | Adım 3 genişletildi: `foods.created_by` CASCADE, `favorite/recent → foods` NOT NULL CASCADE FK, **`foods` `DATA_TABLES`'te olmamalı** (veri sızıntısı koruması) | **6/6 iki yolda** |
| **P2** | `functions/delete-account/delete_account_test.ts` | 100 → **115 test**. 15 yeni: şema sözleşmesi, `FOODS_DEPENDENT_TABLES`, kural sayısı, indeks adları, 6 `isAlreadyDeletedAuthError` senaryosu, geniş kalıp yok testi | **115 passed / 0 failed / 1 ignored** |

## Bulunurlar (düzeltilmedi, gerekçe)

| Sev | Dosya:satır | Bulgu | Etki | Öneri |
|---|---|---|---|---|
| **P1** | `functions/_shared/schema_contract.ts` (`FK_DELETION_RULES`) | `favorite_foods`/`recent_foods` → `foods` kuralı **bilerek** kural listesinde **değil**, çünkü `foods` silme akışına girmiyor. Bugün ihlal olamaz; `foods` listeye eklenirse `schema_contract.sql` adım 3 kırmızıya döner | Düşük (kural kayıt altında) | — |
| **P1** | `functions/_shared/rate_limit.ts` (`dbBypassUntil`) | **Tek modül düzeyi değişken**: bir instance'ta DB'ye ulaşılamadıysa o instance'taki **tüm** kovalar (`ai-chat`, `delete-account`, …) 60 sn bellek içi yola düşer. A1r2'den kalan | Çok-instance'da sınır N katına kadar gevşer | Kova bazlı ayrım: `dbBypassUntil: Map<bucket, number>`. Davranış değiştirdiği ve ölçülmüş ihtiyaç kanıtı olmadığı için **bu turda yapılmadı** (Tur 8 adayı) |
| **P1** | `full_setup.sql:23` | `CREATE TYPE public.meal_type AS ENUM (...)` — `IF NOT EXISTS` yok → dosya **ikinci kez** çalıştırılırsa hata verir. Yeni kurulum içindir (README zaten öyle diyor), ama "hata varsa devam et" yanılgısına açık | Düşük | `DO $$ BEGIN ... EXCEPTION WHEN duplicate_object THEN NULL; END $$;` ile sarmalamak. **A1r2'den beri biliniyor, kapsam dışı bırakıldı** |
| **P2** | `food_nutrition.nova_score` | `smallint`, **CHECK yok** → `0`, `99`, `-5` yazılabilir. A2r5 istemci tarafında 1-4'e çekiyor ama DB kapısı yok. `nutri_score` de allow-list'siz (A-E) | Bozuk veri analitik ekranına akar | `CHECK (nova_score BETWEEN 1 AND 4)` + `CHECK (nutri_score IN ('A'..'E') OR nutri_score IS NULL)`. **Eklenmedi**: mevcut satırlar `NOT VALID` olmadan doğrulanamaz ve proje frozen. Canlıya almadan önce `SELECT DISTINCT nova_score, nutri_score FROM food_nutrition` |
| **P2** | `meal_entries.calculated_*` | `kcal/protein/carbs/fat` negatif olabilir (yalnızca `amount_g_ml` kontrol ediliyor). `food_nutrition` için bu turda kısıt eklendi, öğün tarafı **eklenmedi** | A2r4'ün "0'a çevirme" sınıfının negatif hâli | `CHECK (calculated_kcal >= 0 AND ...)` — aynı gerekçeyle canlı veri doğrulaması gerekiyor |
| **P2** | `profiles` | `height_cm`, `current_weight_kg`, `target_weight_kg`, `daily_water_target_ml`, `weigh_in_frequency_days` için **aralık CHECK'i yok** (yalnızca `numeric(5,x)` tip sınırı). `weigh_in_frequency_days = 0` → `check-reminders`'ta `daysSinceReminder >= 0` her koşuda tetiklenir | Sınır dışı değerler UI'ya yansır | `CHECK (height_cm BETWEEN 80 AND 260)` vb. — `calculate-macros` zaten aralık doğruluyor, DB katmanı ince |
| **P2** | `chat_messages.metadata` | `jsonb NOT NULL DEFAULT '{}'` ama **şema doğrulaması yok** → istenmeyen anahtarlar yazılabilir | Düşük | `CHECK (jsonb_typeof(metadata) = 'object')` |
| **P3** | `functions/check-reminders/index.ts:28` | `RATE_LIMIT = {300 sn, 2}` **global** (`rateLimitKey("check-reminders", req, "internal")`). İki paralel cron'da biri sürekli 200 + "atlandı" alır | Operasyonel | Tur 2'den kalan, kasıtlı (tek global cron) |
| **P3** | `functions/check-reminders/index.ts:37` | `generateMotivationalMessage()` profil başına değil, koşu başına **bir kez** çağrılıyor → tüm kullanıcılara aynı mesaj | Kişiselleşmemiş | Tur 1'den kalan |

## Görev 3 — Şema borcu envanteri (ölçüm)

**Tablo envanteri** (`public`, 16 tablo): `chat_messages`, `chat_threads`,
`favorite_foods`, `food_nutrition`, `foods`, `meal_entries`,
`notification_preferences`, `notifications`, `profiles`, `push_subscriptions`,
`rate_limits`, `recent_foods`, `user_roles`, `user_settings`,
`water_entries`, `weight_entries`. Tamamı RLS açık, tamamı `authenticated`'a
komut bazlı GRANT'li, `anon`'a **hiçbir** yetki yok.

### Kullanılmayan / az kullanılan tablo ve kolonlar (grep ile ölçüldü)

| Tablo / kolon | Durum | Kanıt |
|---|---|---|
| `notification_preferences` | **Yazan hiçbir istemci yok** (A2r5/A4r6 doğrulaması) | `grep -rn "notification_preferences" flutter_app/lib src \| grep -iE "insert\|upsert\|update("` → **boş**. Yalnızca `data_transfer_repository.dart` (yedek) ve `check-reminders` **okuyor**. Sonuç: sunucu tarafı satır yoksa `water`/`daily_log`/`weekly_summary` bildirimlerini sessizce kapatıyor. **Bu turda A4r7 arayüzü ekliyor → kapsam dışı bırakıldı** |
| `favorite_foods` | Yalnızca **yedek/geri yükleme** yazıyor (`data_transfer_repository.dart:781`, `src/lib/import/backupRestore.ts:334`). Normal akışta **hiçbir yol yazmıyor** — iki istemci de favorileri `meal_entries`'ten hesaplıyor (`FoodRepository.favorites()` → son 200 öğün) | A4r6 raporu ile aynı ölçüm. **A4r7 arayüzü ekliyor** |
| `recent_foods` | Aynı durum (`data_transfer_repository.dart:793`) ve **tamamen türetilebilir** (son 50 öğün = sorgu) | A4r6: "`recent_foods` kaldırılabilir". Bu turda **dokunulmadı** (ürün kararı) |
| `user_roles` | Hiçbir istemci **okumuyor bile**; RLS'te yalnızca SELECT var, yazma yolu kapalı. `public.has_role()` fonksiyonu **hiçbir yerden çağrılmıyor** (`grep has_role` → migration + full_setup dışında 0) | Rol yükseltme koruması çalışıyor; tablo ölü ama **güvenlik açığı değil**. Silinmesi önerilmez (şema borcu) |
| `user_settings` | Flutter'da `UserSettingsRepository._table = 'user_settings'` — **var**; ama `DataTransferRepository` dışında yazan yok. Web'de yalnızca `types.ts`'te tanımlı | Kullanımda |
| `profiles.auto_recalculate_macros` | 3 istemci noktasında geçiyor | Kullanımda |
| `foods.image_url` | **Yazan hiçbir yol yok.** Yalnızca `food.dart:85` (model) + yedek (`data_transfer_repository.dart:1010`, `backupImport.ts:868`). `recognize-food/index.ts:104` ve `ai-chat/index.ts:163` geçen `image_url` **OpenAI API gövdesi**, DB kolonu değil | **4-A kararı: şimdilik bir şey yapma** |
| `meal_entries.photo_url` | `diary_repository.dart:276` **yazıyor** (`photoUrl` parametresi), ama `recognition_confirm_dialog.dart:27` yorumu "hiçbir zaman ayarlanmaz (storage yükleme yok)" diyor → **gerçekte hep NULL** | A2r5 bulgusu, **4-A kararı: dokunulmadı** |
| `profiles.avatar_url` | Modelde var, **yazan UI yok** | Düşük |
| `foods.verified` | Hiçbir yol **yazmıyor**; `data_transfer_repository.dart:983` yorumu "sistem tarafından türetilir" diyor ama tetikleyen yok | Ölü kolon |
| `chat_messages.pending_action` / `action_status` | `ai-chat` **yazıyor**, arayüz onaylamıyor (Tur 6'da yol açık) | Tur 6 kapsamı |

**Kullanılmayan tablo yok** (0 tablo). Silme/drop **önerilmiyor** — ürün kararı.

### Eksik CHECK kısıtları (eklenenler ve önerilenler)

| Kısıt | Durum |
|---|---|
| `food_nutrition_values_non_negative` | ✅ **eklendi** (kcal/protein/carbs/fat + fiber/sugar/salt/saturated_fat/trans_fat) |
| `notification_preferences_hours_range` | ✅ zaten var (`20260927120000`) |
| `meal_entries_amount_positive` / `water_entries_amount_positive` / `weight_entries_weight_range` | ✅ zaten var |
| `notifications_type_allowlist` | ✅ zaten var |
| `profiles.gender/goal/activity_level` | ✅ zaten var (`CHECK ... IN (...)`) |
| `profiles_timezone_is_valid_iana` | ✅ A1r4 ekledi |
| `food_nutrition.nova_score` 1-4, `nutri_score` A-E | ❌ **önerildi, eklenmedi** (canlı veri doğrulaması gerek) |
| `meal_entries.calculated_*` >= 0 | ❌ **önerildi, eklenmedi** (aynı gerekçe) |
| `profiles.height_cm` / `current_weight_kg` / `daily_water_target_ml` aralıkları | ❌ **önerildi, eklenmedi** |
| `chat_messages.metadata` JSON nesnesi | ❌ **önerildi, eklenmedi** (düşük) |

### Eksik index'ler — hangileri eklendi, hangileri neden eklenmedi

**RLS `auth.uid() = user_id` süzgeci**: 13 tablonun **hepsi** zaten
indeksliydi (`UNIQUE` kısıtları dahil — ölçüldü, `EXISTS (SELECT 1 FROM
pg_index ...)` ile tek tek doğrulandı). Tek istisna `foods.created_by`.

| # | Index | Neden | Ölçüm (Postgres 16.15) |
|---|---|---|---|
| **I-1** | `foods (created_by)` | ⭐ **RLS süzgeci indekssizdi.** `foods` DELETE/UPDATE politikaları `USING (created_by = auth.uid())` → RLS koşulu plana `created_by = ...` olarak ekleniyor, indeks yoksa tablo taranıyor | 5.000 satır, 1 eşleşen: indekssiz `Seq Scan, Rows Removed by Filter: 5000, 0.90 ms` → indeksli `Index Scan, Index Cond, 0.20 ms` (**4.5×**; fark tablo büyüdükçe doğrusaldır) |
| **I-2** | `meal_entries (user_id, created_at DESC) WHERE deleted_at IS NULL` | ⭐ **İki istemcinin de en sık çalıştığı sorgu.** Flutter `FoodRepository.favorites()`/`.recents()`, web `useFavoriteFoods`/`useRecentFoods` → hepsi `.eq('user_id').is('deleted_at', null).order('created_at', desc).limit(200/50)`. Mevcut `idx_meal_entries_user_date (user_id, entry_date)` bu deseni **karşılamıyor** (sıralama `created_at`) | 20.000 öğün: indekssiz `Seq Scan + Top-N Sort, 311 buffer, 7.49 ms` → indeksli `Index Scan, 6 buffer, 0.06 ms` (**125×**) |
| **I-3** | `recent_foods (user_id, last_used_at DESC)` | `UNIQUE(user_id, food_id)` `user_id`'yi indeksliyor ama **`last_used_at` hiçbir indekste değil** (ölçüldü: `pg_index` taramasında 0). Yedekten sonra sıralı listeleme Seq Scan gözleniyor | Plan gözlemi (düşük maliyetli, düşük risk) |
| — | `water_entries` / `weight_entries` kısmi index | **EKLENMEDİ.** Aynı desen var ama `ORDER BY`'ları `entry_date` ve mevcut `(user_id, entry_date)` indeksi **zaten** tam karşılıyor. Analitik sorguda `deleted_at` filtresi bitmap taramada 2671 satır / 313 buffer (ölçüldü) → ayrı indeks **kanıtlanmadı** | Ölçüldü |
| — | `chat_messages (thread_id, created_at DESC, id DESC) WHERE deleted_at IS NULL` | **EKLENMEDİ.** Sayfalama imleci `.eq('thread_id').lt('created_at', cursor).order('created_at', desc).order('id', desc)` — mevcut `idx_chat_messages_thread_created (thread_id, created_at DESC)` **yeterli** (`EXPLAIN` ile doğrulandı: `Index Scan` kullanılıyor). Kanıtsız index = index şişmesi | Ölçüldü |

**`CREATE INDEX CONCURRENTLY` neden kullanılmadı:** Postgres'te transaction
içinde çalışamayan komuttur; Supabase her migration'ı **tek transaction'da**
çalıştırır → `CONCURRENTLY` migration'da imkânsız. `CREATE INDEX IF NOT
EXISTS` zaten idempotensi sağlar ve proje frozen (canlı veri yok) olduğu
için kilit süresi önemsizdir.

## `foods` CASCADE kararı — `created_by IS NULL` riski

**Risk: yok.** Gerekçe ölçümle desteklendi:

1. CASCADE yalnızca `auth.users` satırı silindiğinde tetiklenir.
   `created_by IS NULL` olan bir gıdanın **hiçbir** `auth.users` satırıyla
   bağı yoktur, dolayısıyla hiçbir hesap silme işleminde tetiklenmez.
2. FK `created_by` üzerinde `ON DELETE CASCADE`; Postgres'te CASCADE
   tetikleyicisi **parent satırı hedefler**, NULL FK değeri hiçbir zaman
   eşleşmez.
3. Migration, çalışmadan **önce** `created_by IS NULL` satır sayısını
   `NOTICE` ile raporlar ve **hiçbir satırı değiştirmez** (boş veritabanında
   ölçüldü: `sahipli: 0, sahipsiz (NULL/seed): 0`).
4. `foods_created_by_fkey` migration'da yalnızca gerçekten `SET NULL`
   (`confdeltype='n'`) ise değiştirilir; zaten `CASCADE` ise dokunulmaz,
   başka bir davranış ise `WARNING` basılır (ürün kararını ezmez).
5. `full_setup.sql` aynı değeri **tablo tanımında** verir ve aynı
   `COMMENT` ile belgeler → parite `diff` = boş.
6. **Kanıt** (`tests/foods_cascade.sql`, iki yolda da): A'nın gıdası +
   `food_nutrition` silinir; **B'nin öğünü `food_id=NULL` ile kalır**;
   **seed gıdası + besin kaydı + B'nin seed favorisi sağlam kalır**.

**Etki zinciri (ölçüldü):**

| Silinen | `foods` | `food_nutrition` | `favorite_foods` | `recent_foods` | `meal_entries` |
|---|---|---|---|---|---|
| `auth.users` (sahibi) | **silinir** | **silinir** | **silinir** | **silinir** | `food_id → NULL`, satır **korunur** |
| `foods` (bir kullanıcı gıdayı silerse) | silinir | **silinir** | **silinir** | **silinir** | `food_id → NULL`, satır **korunur** |
| `foods` (`created_by IS NULL` seed) | **korunur** | korunur | korunur | korunur | korunur |

## Yeni testler (100 → 115 Deno + 4 SQL dosyası)

- `delete_account_test.ts` — 19 → **34** (+15): şema sözleşmesi
  tutarlılığı · `DATA_TABLES ⊆ SCHEMA_TABLES` · `DIRECT_USER_FK_TABLES`
  (`foods` dahil, `rate_limits` hariç) · `FOODS_DEPENDENT_TABLES` ·
  `FK_DELETION_RULES` tek kural · `isSafeDeletionOrder` · indeks adları ·
  `isAlreadyDeletedAuthError` **6 senaryo** (User not found ✔ / snake_case ✔ /
  "schema not found" ✘ / "session not found" ✘ / RLS ✘ / bilinmeyen ✘ / boş+404 ✔ /
  dolu+404 ✘) · geniş kalıp kaynak testi.
- `tests/schema_contract.sql` — **yeni, 10 kontrol**.
- `tests/foods_cascade.sql` — **yeni, 2 kontrol / 4 iddia**.
- `tests/account_deletion_scope.sql` — 6 adım, adım 3 genişletildi.

## Doğrulama kanıtları

| Komut | Sonuç |
|---|---|
| `deno check functions/` (`supabase/`'dan) | **0 hata** (23 dosya) |
| `deno test --allow-env --allow-read --allow-net functions/` | **115 passed / 0 failed / 1 ignored** (Tur 4'te 100) |
| Migration ad denetimi (CI adımının birebir komutu) | ✓ **17** migration adı geçerli ve kronolojik sıralı |
| **17 migration sıfırdan** Postgres 16.15'e sıralı | **0 hata** (yalnızca `20260111080533` `pg_cron`/`pg_net` eklentisi yok diye atlandı) |
| `20260928300000` **3× üst üste** | **0 hata** (`NOTICE: ... foods.created_by=zaten ON DELETE CASCADE`, `3/3 index kuruldu`) |
| `full_setup.sql` sıfırdan | **0 hata**, **55 politika** |
| `tests/schema_contract.sql` | **10/10** migration yolu **ve** `full_setup.sql` yolu |
| `tests/foods_cascade.sql` | **2/2** iki yolda (4 iddia kanıtlandı) |
| `tests/account_deletion_scope.sql` | **6/6** iki yolda |
| `tests/rls_policies.sql` | **49 test / 0 başarısız** iki yolda |
| **Parite `diff` (migration vs `full_setup`)** | FK (20), CHECK (14), **kolon**, **index (39)**, politika (55) → **BİREBİR AYNI** |
| **Negatif test — yeni tablo** | `a1r5_probe` eklendi → `SEMA SOZLESMESI TESTI BASARISIZ` ✔ sonra temizlendi |
| **Negatif test — yeni engelleyici FK** | `chat_threads→notifications` eklendi → `FK sira kurali eskimis` ✔ sonra temizlendi |
| **Negatif test — `full_setup` ayrışması** | `foods_cascade.sql` `full_setup`'ta `meal_entries_food_id_fkey` ihlaliyle **kırmızı** oldu → düzeltildi → yeşil |

**Migration uygulama yöntemi** (A1r2/A1r3/A1r4 ile aynı): `supabase` CLI
kurulu değil → `docker exec a1r5-pg psql` ile shim'li Postgres 16'ya elle,
sıralı uygulandı. Shim `/tmp/opencode/a1r2/bootstrap.sql` (A1r2'den).

## Doğrulayamadığım şeyler (açıkça)

1. **Gerçek Supabase Auth'e karşı test yapılmadı.** `auth.admin.deleteUser()`
   ve `isAlreadyDeletedAuthError` kalıpları GoTrue'nun **kaynak kodundan
   ve hata dokümanından** türetildi, canlıda denenmedi. En büyük belirsizlik:
   farklı GoTrue sürümlerinin "kullanıcı yok" hatası `User not found`
   yerine başka bir metin dönebiliyor. Bu durumda davranış **güvenli yöne**
   gider (idempotent başarı yerine istisna → kısmi silme mesajı → kullanıcı
   "Tekrar Dene" der). Canlıya almadan önce bir kez silme denemesi önerilir.
2. **Edge function'lar uçtan uca çalışmadı** — `supabase functions serve` yok.
3. **Canlı veri dağılımı bilinmiyor** (proje frozen). `food_nutrition`'daki
   negatif değer, `nova_score`/`nutri_score` değerleri, `foods.created_by IS
   NULL` satır sayısı ölçülmedi. Migration `food_nutrition` için negatif
   değer bulursa **görünür hata** ile durur (sessiz düzeltme değil).
4. **Index kazançları boş veritabanında ölçüldü** (5.000–20.000 sentetik
   satır). Gerçek dağılımda planlayıcı farklı karar verebilir; indeksler
   yine de **doğru** deseni hedeflediği için güvenli.
5. **CI'da ilk çalıştırılmadı** — `.github/workflows/supabase.yml`
   **A6'nın alanı**, dokunulmadı. Yeni SQL testleri CI'a **eklenmedi**
   (`supabase start` gerektiriyor, bkz. "Sonraki öneriler").

## AKTARIM (başka alan)

### → A4r7 (favori arayüzü + yemek silme) — ⭐ **ÇAPRAZ ETKİ**

**Bu turda `foods` silme davranışı DEĞİŞMEDİ** (`favorite_foods`/
`recent_foods` → `foods` FK'si `20260111041204`'ten beri `NOT NULL` +
`CASCADE` idi). Yani **bugün de** şu var:

> Bir kullanıcı `foods` tablosundan bir gıdayı silerse (RLS politikası
> `USING (created_by = auth.uid())` → yalnızca **kendi eklediği** gıdayı
> silebilir), o gıdaya bağlı **`favorite_foods` ve `recent_foods` satırları
> CASCADE ile KAYBOLUR**, `meal_entries.food_id` `NULL` olur ama öğün satırı
> kalır.

Bu, favoriye ekleme/çıkarma arayüzü eklenirken **görünür** olacaktır:

1. **Kaydedilmiş favorilerin sessizce kaybolması.** Kullanıcı "Yıllık
   alışveriş listemi sildim" derse favori listesinden de gıdalar düşer.
   A4r7'nin favori arayüzü eklediği listede gıda adı `foods.name`'den
   geliyorsa (`favorites()` sorgusu `meal_entries` join'iyle okuyor),
   **favori de listeden düşer** — çünkü iki istemci de favorileri
   `meal_entries`'ten **hesaplıyor**, `favorite_foods`'ten okumuyor.
2. **Tavsiye:** favori arayüzü eklenirken (a) "gıdamı sil" akışına bir
   onay adımı, (b) en azından silinen gıdanın favorilerde olduğunu
   söyleyen bir mesaj düşünülmeli. Alternatif: gıda silmeyi **mantıksal**
   yapmak (`foods.deleted_at` — kolon bugün **yok**, bu yüzden fiziksel
   silme zorunlu).
3. **A4r7'nin favorileri `favorite_foods`'e yazmaya başlaması** durumunda
   etki **daha da büyür**: geri yüklenen favoriler artık fiziksel silmeden
   etkilenmez ama aynı zamanda **akışın kalıcılığı** `foods`'a bağlanır.

### → A2 (veri katmanı) — `favorite_foods`/`recent_foods` yazma yolu

`FOODS_DEPENDENT_TABLES` (`favorite_foods`, `recent_foods`, `meal_entries`)
sözleşmede kayıtlı. Favori yazma yolu eklenirse **`food_id` zorunlu** ve
gıda mevcut olmalıdır (mevcut CHECK'ler aynen geçerli).

### → A6 (CI) — yeni SQL testleri

`supabase/tests/schema_contract.sql` ve `foods_cascade.sql` CI'a
`supabase start` ile bağlanabilir. Migration ad denetimi adımı
(`.github/workflows/supabase.yml:117`) **yeni dosyayı otomatik kapsıyor**
(17 migration, ad/biçim denetimi geçti).

### → Ana ajan — `plans/` senkronluğu

`URUN-KARARLARI.md` **3-A uygulandı** (kapatılabilir) · **1-A ve 2-A bu
turda A4r7'nin kapsamında** · **4-A uygulanmadı** (dokunulmadı).
`OPS-tur1-security.md`'ye eklenecek: yeni migration
`20260928300000` deploy adımı, `full_setup.sql`'in
`meal_entries.food_id` parite düzeltmesi (yeni kurulum yapan varsa
`full_setup` kullanmıyorsa etkisiz), hesap silmede kullanıcının eklediği
gıdaların da silindiği bilgilendirmesi.

## Sonraki öneriler (Tur 8)

1. **`dbBypassUntil` kova bazlı ayrım** (`Map<bucket, number>`) — A1r2'den
   kalan tek `rate_limit.ts` riski, davranış değiştirdiği için ölçülmüş
   ihtiyaç kanıtı ister.
2. `food_nutrition.nova_score` 1-4 / `nutri_score` A-E CHECK'i (canlı veri
   doğrulamasından sonra) + `meal_entries.calculated_*` >= 0.
3. `foods.verified` kolonu: **yazan hiçbir yol yok** → ya tetikleyici
   yazılsın ya da kolon düşülsün (ürün kararı, silme önerilmiyor).
4. `user_roles` + `public.has_role()` tamamen ölü → rol tablosu güvenlik
   açığı değil ama şema borcu; `has_role()`'ı kullanan bir admin yolu yoksa
   ikisi de düşülebilir (ürün kararı).
5. `supabase/tests/*.sql` dosyalarını CI'a `supabase start` ile bağlamak
   (A6 + Docker bağımlılığı; A1r4'ten kalan).
6. `full_setup.sql` `CREATE TYPE` idempotansiyası (`IF NOT EXISTS` deseni).
7. `check-reminders` için Supabase dashboard cron'u: `*/5 * * * *` +
   `INTERNAL_FUNCTION_TOKEN` başlığı (A1r3'ten kalan).
