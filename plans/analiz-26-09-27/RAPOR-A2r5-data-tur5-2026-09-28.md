# RAPOR — A2r5 (veri katmanı) — 2026-09-28 — Tur 5

## Özet (5 madde)

1. **Favoriler sessizce kayboluyordu (P1, kullanıcı verisi)** — `exportData`
   `favorite_foods` + `recent_foods` + `notification_preferences` tablolarını
   yazıyordu, `importData` **hiçbirisini okumuyordu**. Kullanıcı yedeği geri
   yüklediğinde favorileri ve son kullanılanları yok oluyordu, bildirim
   tercihleri sıfırlanıyordu. Üç tablo da içe aktarıma eklendi (commit
   `850c63b`), `food_id` **ada göre** eşleşiyor, eşleşmeyen kayıt **atlanıp
   raporlanıyor** (ölümcül değil — gerekçesi aşağıda).
2. **Aynı sınıf hatanın ikinci örneği bulundu (P2, veri bozulması)** —
   `notification_preferences` de dışa aktarılıyor, içe aktarılmıyordu.
   Raporlamadan önce export kümesini `importTables` ile **küme olarak**
   karşılaştıran bir sözleşme testi yazıldı; iki istemcinin ayrışması artık
   derlenme/runtime hatasıyla değil, **kırılan testle** yakalanıyor.
3. **Uçtan uca round-trip testi (P1, "en değerli test")** —
   `backup_round_trip_test.dart` (19 test): tam bir günlük veri seti (90 öğün /
   40 su / 8 kilo / 2 gıda / 2 besin satırı / 2 favori / 2 son kullanılan /
   1 bildirim tercihi) → export → import → ikinci export → alan alan
   karşılaştırma. Sahte DB PostgREST davranışını taklit ediyor: `RETURNING id`,
   NOT NULL / FK / UNIQUE ihlalleri, `timestamptz` yazım biçimi, `PGRST102`.
4. **Test yazarken A2r4'ün kodunda iki gerçek hata bulundu** —
   (a) `food_nutrition.nova_score` geçersizde **`_count()`'un sayaç değeri**
   (1, 2, 3…) `nova_score` olarak **yazılıyordu**: sınıflandırılmamış gıda
   "1 = işlenmemiş" olarak kaydediliyordu. (b) `favorite_foods`/`recent_foods`
   için `created_at` kolonu sözleşmeye girecekti ama üretilmiyordu → toplu
   insert `StateError` ile **tüm import'u** düşürüyordu. 42 mevcut test ikisini
   de kaçırıyordu.
5. **`photo_url` kararı (Görev 3) — uygulama önerisi** — Araştırma sonucu:
   **hiçbir istemci `photo_url`'i hiçbir zaman yazmıyor** (`recognition_confirm_
   dialog.dart:238` açıkça `photoUrl: null`; web'de yazan yok). Yani "kırık
   görsel" senaryosu **bugün mümkün değil**; risk **gelecekte** bir fotoğraf
   yükleme özelliği gelirse oluşur. Bu yüzden **kod yazılmadı**, gerekçeli
   karar rapora bırakıldı (aşağıdaki karar bölümü).

---

## Düzeltilenler

| Sev | Dosya | Ne yapıldı | Doğrulama |
|---|---|---|---|
| **P1** | `data_transfer_repository.dart:1007-1075` | `favorite_foods` / `recent_foods` plan + yazma. `user_id` **her kayıtta** yazılır (RLS `WITH CHECK (auth.uid() = user_id)`, `full_setup.sql:332/337`). `food_id` yazılmaz → `PlannedRow.backupName` (gıda adı) üzerinden yeni gıda id'sine çevrilir. Dedup anahtarı **gıda adı** (`UNIQUE(user_id, food_id)`) — plan aşamasında, çünkü `food_id` import'ta yeni UUID alır. Telafi sıraya dahil (bağımlılık sırasının tersi). | 10 yeni test |
| **P1** | `data_transfer_repository.dart:1076-1130` | `notification_preferences` plan + yazma. `notification_type` DB CHECK allow-list'i (`20260927120000_...:411-413`), saat/ara CHECK'leri (`:415-423`) **önceden** doğrulanır; aralık dışı DB varsayılanına çekilir ve `coerced` sayacı artar. | 4 yeni test |
| **P1** | `data_transfer_repository.dart:625-659` | Varlık kontrolü: iki tablo `select('foods!inner(name)').eq('user_id', userId).inFilter('foods.name', …)` ile okunur (ad bazlı dedup, öğünlerle aynı desen). `notification_preferences` `inFilter('notification_type')`. | 2 yeni test |
| **P1** | `data_transfer_import.dart` | `ImportPlan`: `favorites`/`recents`/`notificationPrefs` listeleri, `favoriteNames`/`recentNames`/`notificationTypes` dedup kümeleri, `existingFavoriteNames`/`existingRecentNames`/`existingNotificationTypes`, `notificationTypeList` (`in` sorgusu için), `plannedRows`/`toString` güncellendi. | `flutter analyze` temiz |
| **P1** | `data_transfer_repository.dart:876-901` | `_linkedRows` — `food_id` çözülemeyen satır **sessizce atlanmaz**, `StateError` fırlatır (telafi devreye girer, kullanıcının günlüğü silinmez). | round-trip telafi testi |
| **P2** | `data_transfer_repository.dart:1051-1085` | **`nova_score` veri bozulması düzeltildi.** Eski: `_count(coerced, …)` — `_count` sayacın **değerini** döndürür, yani `nova_score = 1, 2, 3…` yazılıyordu. Yeni: `_novaScore()` → geçersiz/eksik → **NULL** + sayaç. | `nova_score` regresyon testi + round-trip içerik testi |
| **P2** | `data_transfer_repository.dart:1160-1180` | `_foodLinkRow` — `created_at` **her iki tabloda da** yazılır. Eksikken toplu `insert` sabit anahtar kümesi kuralını (`_uniform`/`PGRST102`) ihlal ediyor ve `StateError` ile tüm import'u düşürüyordu. | İlk yazımda round-trip testi bunu yakaladı |
| **P2** | `recognized_food.dart:82-124` | `numOr`/`numOpt` **sonlu olmayan** değerleri (NaN/Infinity) filtreler. `1e999` → `Infinity` üreten edge function yanıtı `forAmount()` içinde `UnsupportedError` fırlatıp **tanıma ekranını** düşürüyordu. `amount_g_ml ≤ 0` → 100. | 3 yeni test |
| **P2** | `recognized_food.dart:128-145` | `RecognitionResult.fromJson`: `e as Map<String, dynamic>` zorlaması yerine **satır başına eleme**. Tek bozuk eleman (`null`/dize/sayı) tüm listeyi ve ekranı düşürüyordu. | 2 yeni test |
| **P1** | `export_scoping_test.dart` | **Sözleşme testi**: export gövdesindeki tablo kümesi `importTables` ile **küme olarak** eşit olmalı (`version`/`exportedAt`/`profile` hariç) + her tablo gerçekten sorgulanıyor. Bu, favoriler kaybının **bir daha** olamamasını garanti eder. | 2 yeni test |
| **P1** | `import_atomicity_test.dart` | `importTables` beklentisi 8 tabloya güncellendi (kendi sözleşme testi). | — |

### Yeni test dosyaları

- **`backup_round_trip_test.dart` (19 test, ~1400 satır)** — uçtan uca
  yedek round-trip'i + favoriler/son kullanılanlar/bildirim sözleşmeleri +
  telafi. `FakeDb` PostgREST'i taklit eder: `RETURNING id` (deterministik
  sayaç), NOT NULL (`23502`) / FK (`23503`) / UNIQUE (`23505`) / CHECK
  (`23514`) ihlalleri, `PGRST102` (anahtar kümesi), `timestamptz` yazım
  biçimi (`…Z` ↔ `…+00:00`), `foods!inner(name)` embed'i, `is.null` /
  `eq.` / `in.` süzgeçleri, `timestamptz` alanlarda **`in` epoch karşılaştırması**.
- **`diary_analytics_consistency_test.dart` (5 test)** — Görev 4'ün
  "iki farklı hesap yolu var mı?" sorusunun ölçümü (aşağıdaki bulgu).
- `recognized_food_test.dart` (+5), `export_scoping_test.dart` (+2).

---

## Görev 1 — Favoriler/son kullanılanlar: gerekçeli karar

### `food_id` eşleşmezse karar: **ATLA ve RAPORLA (ölümcül DEĞİL)**

Şema (`full_setup.sql:185-203`, `20260111041204_…sql:261-282`):

```sql
CREATE TABLE public.favorite_foods (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  food_id UUID NOT NULL REFERENCES public.foods(id) ON DELETE CASCADE,  -- ← NOT NULL
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, food_id)
);
CREATE TABLE public.recent_foods (
  … food_id UUID NOT NULL REFERENCES public.foods(id) ON DELETE CASCADE,
  last_used_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  use_count INTEGER DEFAULT 1,
  UNIQUE(user_id, food_id)
);
```

**`food_id` nullable DEĞİL** — öğünlerdeki gibi "`null` bırak = manuel girdi"
fallback'i **yok**. Üç seçenek değerlendirildi:

| Seçenek | Sonuç | Gerekçe |
|---|---|---|
| **Ölümcül** | ❌ | Tek bir eski-kopmuş favori, kullanıcının **tüm günlüğünü** geri yükleyememesine yol açar. Favoriler geri getirmeye *çalışan* bir özelliktir; onu şart koşmak tersi etkiyi doğurur. Bu, P1'i P0'a yükseltirdi. |
| **Sessizce atla** | ❌ | Kullanıcı favorilerinin bir kısmı geri geldiğini sanır. A2r4'ün "sessiz veri kaybı yasağı"na doğrudan aykırı. |
| **Atla + `ImportReport.skipped` + `ImportIssue`** | ✅ **seçilen** | `food_nutrition`'ın gıdası yedekte yoksa zaten aynı davranış (`data_transfer_repository.dart:308`). Kullanıcı bilgilendirilir, geri kalan yedek **eksiksiz** geri gelir. |

**Eşleşme neden neredeyse her zaman başarılı?** `exportData` favorileri
kendi gıdalarıyla birlikte alır (`foods`: `.eq('created_by', userId)`) ve
`food_id` bir FK'dir (`ON DELETE CASCADE`). Yani eşleşmeme yalnızca **elle
düzenlenmiş** yedekte ya da gıdanın `foods`'tan silinmiş olmasında olur.
İkisi de "bu favori geri getirilemez" demektir — ölümcül hata değil.

**Eşleme anahtarı neden `id` değil de `ad`?** `food_id` import'ta **yeni**
bir UUID alır (DB `gen_random_uuid()`); yedekteki eski UUID DB'de yoktur.
Bu yüzden `meal_entries`/`food_nutrition` ile **aynı** desen kullanıldı: gıda
adı üzerinden eşleme, `RETURNING` sırası karışsa bile yanlış gıda yazılmaz.

**Varlık kontrolü neden `foods!inner(name)`?** `UNIQUE(user_id, food_id)`
demek `food_id` üzerinden; ama import'taki `food_id` henüz belli değil
(`foods` yazılabilir ya da mevcut olabilir). Bu yüzden iki tablo da kullanıcının
**kendi gıdaları** içinde ad bazından okunur. `.eq('user_id', userId)` filtresi
şart: `foods` RLS'i herkese açık (`USING (true)`, `full_setup.sql:284`).

### Doğrulama (testler)

- `user_id` her kayıtta yazılır, yedeğinki (`'başka-kullanici'`) yok sayılır
  → RLS `WITH CHECK` reddetmez.
- `food_id` yedekteki `'eski-id'` **değil**, `foods` tablosundaki yeni
  satırın id'sidir (sahte DB FK kontrolüyle kanıtlanır).
- Gıdası yedekte yoksa: `meal_entries` **yine de** yazılır (öğün kaybı yok),
  favori `skipped['favorite_foods'] = 1` + `isFatal: false` + okunabilir mesaj.
- Aynı gıda ikinci kayıt → `UNIQUE` ihlaline düşmeden atlanır.
- DB'de zaten favorilenen gıda → tekrar yazılmaz (varlık sorgusu
  `select` ve `user_id` parametreleri testle doğrulanır).
- `recent_foods.use_count` / `last_used_at` korunur; `use_count` geçersizse
  1'e çekilir ve **sayar**.
- **Round-trip:** 90 öğünlük yedeğin favorileri boş hesaba geri yüklendiğinde
  `counts['favorite_foods'] = 2`, `counts['recent_foods'] = 2` ve ikinci
  export'ta **gıda adları, `use_count`, `last_used_at`** birebir aynı.

---

## Görev 2 — Uçtan uca round-trip testi

`backup_round_trip_test.dart`. Kapsanan senaryolar:

| Test | Ne kanıtlıyor |
|---|---|
| `counts` ikinci export'ta **aynı** | 8 tablonun hepsi (90/40/8/2/2/2/2/1 satır) |
| Ölçülebilir alan **birebir** | 12 öğün kolonu + su `entry_time`/`amount_ml` + kilo + 12 besin kolonu (sayısal olarak — `import` `NUMERIC`'i dize yazıyor, Postgres sayı döndürüyor) |
| Favoriler/son kullanılanlar içerik eşitliği | gıda **adı** → `use_count`/`last_used_at` |
| Bildirim tercihleri | 8 kolon birebir |
| Yumuşak silinmiş kayıt **canlanmaz** | silinmiş öğün ne export'ta ne import sonrası |
| **İdempotlans** | aynı yedek aynı hesaba ikinci kez → `counts[t] == 0`, tablo sayıları değişmez |
| Telafi sırası | `favorite_foods` **önce** `foods`'tan silinir |

### Simetrik olmayan (asimetrik) senaryolar — bulunanlar

1. **`foods.created_at` kayboluyor (bilinçli, P3).** `foods` beyaz listesi
   kullanıcı/denetim alanlarını dışarıda bırakır (`verified`,
   `popularity_count`, `created_at`, `updated_at`). Gıda yeni `now()` alır.
   Kullanıcının verisini etkilemez (günlük kayıtların `created_at`'i **taşınır**,
   testle sabitli) ama yedek→geri yüklemede "hangi gıdayı ne zaman ekledim"
   bilgisi gider. **A2r4'ün kararı, korunuyor.** Test bunu **belgeliyor**
   (`isNot(...)` ile), yani ileride `_insertColumns['foods']` değişirse
   kırılacak.
2. **`timestamptz` yazım biçimi** (`…Z` ↔ `…+00:00`) — veri farkı değil,
   Postgres çıktı biçimi. Test damgaları **an** olarak karşılaştırır.
3. **`nova_score` round-trip** — yukarıdaki P2 hata. İlk export'ta `null`
   olan değer, import sonrası `1` idi. Bu aslında **veri kaybı değil,
   veri uydurma** idi ve düzeltildi.

---

## Görev 3 — `photo_url` karar önerisi (**kod yazılmadı**)

### Netleştirilmiş tablo/kolon/sınırlar

| Öğe | Değer | Kaynak |
|---|---|---|
| Kolon | `public.meal_entries.photo_url` **`TEXT`, nullable** | `full_setup.sql:119`, `20260111041204_…sql:143` |
| İkinci kolon | `public.foods.image_url` **`TEXT`, nullable** | `full_setup.sql:75` |
| Var olan tek bucket | `chat-attachments` — **`public = false`**, `file_size_limit = 10485760` (**10 MB**), MIME: `image/jpeg`, `image/png`, `image/webp`, `image/gif` | `full_setup.sql:672-680` |
| Bucket politikaları | `bucket_id = 'chat-attachments'` **AND** `(storage.foldername(name))[1] = auth.uid()::text` — yani `<user_id>/<dosya>` zorunlu | `full_setup.sql:687-695` |
| Ölçüm URL'si | `photo_url` **TEXT** olduğu için 2048 karakterlik bir URL'ye sığar; pratik sınır ~1-2 KB/görsel | tip tanımı |
| **Önemli düzeltme** | Görev metninde "25 MB sınırı var" yazıyordu — **yanlış**. Gerçek sınır **10 MB** (`chat-attachments` bucket'ı, `full_setup.sql:674`). Ölçüm görselleri için **hiçbir bucket yok**. | — |

### Bulgular

1. **Bugün `photo_url` hiçbir istemci tarafından yazılmıyor.**
   `recognition_confirm_dialog.dart:238` açıkça `photoUrl: null, // tanıma
   akışında hiçbir zaman ayarlanmaz`; web tarafında `photo_url` yazan hiçbir
   satır yok (sadece `backupImport.ts:192/988` **okuyor**). `RecognitionRepository`
   görseli storage'a **yüklemez** — base64 data URL olarak doğrudan edge
   function'a gönderir ve sonucu atar (`recognition_repository.dart:14-15`).
2. **Sonuç:** "geri yüklemede kırık görsel (404)" senaryosu **bugün
   mümkün değil**; `photo_url` her zaman `NULL`. Bu, bulguyu "veri bütünlüğü
   sorunu" olmaktan çıkarıp **gelecek bir özelliğin ön koşulu** haline
   getiriyor. Bu yüzden **kod yazılmadı** — mevcut kodda düzeltilecek bir
   hata yok, uydurma bir test de yazmak yanıltıcı olurdu.
3. `foods.image_url` da aynı durumda: `_foodRow` yedeğe **kopyalıyor**
   (`data_transfer_repository.dart:1010`) ama hiçbir yol yazmıyor. Aynı
   gelecekteki özellik riskine tabi.

### Karar önerisi (A4r5'e uygulama, A1'e şema)

**Önerilen karar: (B) + (A) karışımı — bucket'ı export'a girmeyen alan
olarak işaretle + geri yüklemede açıkça uyar.**

| | Seçenek | Değerlendirme |
|---|---|---|
| **A** | Görselleri export'a **base64** katmak | ❌ **Önermiyorum.** (1) 10 MB bucket sınırı × N ölçüm görseli = yedek dosyası yüzlerce MB, `JsonEncoder.withIndent` **tümünü bellekte** üretir (`exportData` `:163`) → **OOM**. (2) `importBatchSize`/Postgres parametre tavanı (65535) base64 için patlar. (3) Ölçüm görseli **veri değil, çıktı**; kullanıcı yedeğinde taşımak yedek boyutunu 50-100× büyütür. (4) `chat-attachments` bucket'ı **özel sohbet ekleri** için (`thread_id` klasör yapısı `:303`) — ölçüm görsellerini aynı kovaya koymak politika/izolasyon karışıklığı yaratır. |
| **B** | Geri yüklerken "görseller dahil değil" de | ✅ **Önerilen.** `ImportReport`'a `skipped`/`coerced` benzeri yeni bir alan (`media: 'not included in backup'`) ve `transfer_dialogs.dart`'da tek satır uyarı. **Sıfır veri kaybı iddiası** doğru olur. |
| **C** | Hiçbir şey yapma | ❌ Yapılmış sayılırsa ileride özellik eklenince **sessiz** bozulur. |

**Uygulama adımları (A4 alanı):**

1. **`DataTransferRepository` (veri, benim alanım — istenirse ayrı tur):**
   `exportData` gövdesine bir üst düzey anahtar ekle:
   ```dart
   'media': {
     'included': false,
     'reason': 'photo_url yalnızca URL taşır; Storage nesnesi yedeğe dahil değil',
     'columns': ['meal_entries.photo_url', 'foods.image_url'],
     'bucket': 'chat-attachments',   // referans için
   },
   ```
   Bu **ileride okunabilir** ve "bu sürüm görsel içermiyor" bilgisini veri
   olarak taşır. `importBackup` bu anahtarı yok sayabilir (geriye uyum).
2. **`transfer_dialogs.dart` (A4 alanı):** import sonrası `counts` özetine
   "Görseller dahil değil" satırı. İçerik sızdırmayan, sabit metin.
3. **İleride fotoğraf yükleme özelliği eklenirse (A1 + A4):** ayrı bucket
   (`meal-photos`), `public = false`, `file_size_limit` 5 MB, ayrı politika
   bloğu; `photo_url` yerine **`meal_attachments` tablosu**
   (`meal_entry_id`, `storage_path`, `mime`, `size`, `sha256`) önerilir —
   URL değil **yol** saklanır, 1 saatlik imzalı URL her açılışta yenilenir
   (`chat_repository.dart:325-362`'deki `_signAttachments` deseni zaten var).
   Base64 yedek ancak kullanıcı **açıkça** "görselleri de dahil et" derse ve
   dosya boyutu bir üst sınırın altındaysa.

**Boyut sınırı notu (A1'e):** Ölçüm görselleri için bucket yok; 10 MB
`chat-attachments` sınırı **sohbet ekleri** içindir ve ölçüm görsellerine
**uygulanmaz**.

---

## Görev 4 — Yeni av

| Sev | Dosya:satır | Bulgu | Etki | Durum |
|---|---|---|---|---|
| **P2** | `recognized_food.dart:83-93` (önce) | `numOr` NaN/Infinity filtrelemiyordu. Edge function `1e999` → `Infinity` döndürürse `forAmount()` içinde `(Infinity * 200).round()` → `UnsupportedError` | **Tanıma ekranı komple çöker** (P0'ya yakın ama ulaşması edge function'a bağlı) | ✅ **Düzeltildi** (`5a1c9f6`) |
| **P2** | `recognized_food.dart:133` (önce) | `e as Map<String, dynamic>` — tek bozuk eleman tüm listeyi düşürür | **Tanıma ekranı komple çöker** | ✅ **Düzeltildi** (`5a1c9f6`) |
| **P2** | `diary_repository.dart:53-62` ↔ `analytics_repository.dart:226-229` | **İki farklı toplam yolu, farklı yuvarlama.** `DailyData.totals` ham `double` döner; `aggregateDaily` `round()`/`round1` uygular. Aynı gün dashboard'da `1000.4`, grafikte `1000` | Kullanıcı iki ekranda iki farklı sayı görüyor (P2 — "kullanıcıyı yanıltan UI") | 📋 **Raporda** — testle sabitlendi, kod değişmedi (ürün kararı) |
| — | `analytics_repository.dart:240` | `computeAverages` `calories > 0` ile filtreliyor, `hasData` ise "öğün **veya** su" | Şüphelendi | ❌ **Hata değil** — `useAnalyticsData.ts:183-198` ile **birebir aynı**. Dokunulmadı. |
| — | `food_repository.dart:111-168` | `favorites` 200 / `recents` 50 satır sınırı; web'de de **aynen** 200/50 (`useFavoriteFoods.ts:59`, `useRecentFoods.ts:60`) | — | ❌ **Hata değil**, parity. Sınırsız büyüme yok (`limit` var). |
| — | `favorite_foods`/`recent_foods` **yazma yolu** | Flutter'da **hiç yok**; web'de de yok. İki istemci de favorileri/son kullanılanları `meal_entries`'ten **hesaplıyor** (son 200/50 kayıt) | Tablolar pratikte **hep boş** | ⚠️ **Bölüm 1'in önemi**: geri yüklenen favoriler bugün UI'da **görünmez**. Bkz. "Kalan riskler". |
| — | `data_transfer_repository.dart` (tüm yazma yolları) | `user_id` kapsam filtresi: `meal_entries`/`water_entries`/`weight_entries` yazma yollarında `user_id` **her kayıtta gövdeye yazılıyor** (RLS `WITH CHECK`) — kullanıcı değiştirilemez | ✅ | Doğrulandı |
| — | `chat_repository.dart:283-289`, `profile_repository.dart:34-38`, `user_settings_repository.dart:40-46` | UPDATE/upsert yollarında `.eq('user_id', userId)` **var** (`chat`: `thread_id` + `user_id`) | ✅ | Doğrulandı |
| — | `_rollback` (`:941-968`) | `DELETE` yanıtı **satır sayısıyla doğrulanmıyor**; yalnız istek atmama durumu `rolledBack = true` sayılıyor | P3 — RLS reddi durumunda `rolledBack` yanlış "true" dönebilir | 📋 Raporda (A2r6'ya) |
| — | `sanitizeFood` (`:1700`+) | Ölü kod (içe aktarma yolu kullanmıyor) | P3 | A2r4 notu — dokunulmadı |

**İki "hata değil" kararı önemli:** Görev 4 iki şeyi şüpheli buldu
(`computeAverages` böleni, favoriler limiti); ikisi de web ile **birebir
parity** ve sınırsız büyüme yok. Bunları "düzeltmek" iki istemciyi
ayrıştırırdı. Bunun yerine testlerle **sabitlendi**.

---

## AKTARIM

### A6r5'e (web) — `favorite_foods` / `recent_foods` aktarımı

`src/hooks/useDataExport.ts:81-82` favorileri/son kullanılanları
dışa aktarıyor, `importData` **okumuyor** → web'de de aynı veri kaybı.
**Dokunmadım** (sizin alanınız). Transfer notu: `TRANSFER-defteri.md`.

**Gözlem:** Tur 5'te paralel çalışan `src/lib/import/backupImport.ts` (1119
satır, commit `34fb23a`) + `backupRestore.ts` bu yolu **zaten** uygulamış
görünüyor (`backupImport.ts:139-150, 225-232, 748-761`;
`backupRestore.ts:164-174, 333-343`). **Kararlar tutarlı** — "eşleşmeyen
`food_id` → atla + raporla, ölümcül değil" (`backupImport.ts:402-423`).
Doğrulamak isterseniz şu üç noktayı kontrol edin:

1. **`user_id` her kayıtta yazılıyor mu?** Flutter tarafında RLS
   `WITH CHECK (auth.uid() = user_id)` (`full_setup.sql:332/337`) — kolon
   gövdeden düşerse (`defaultToNull: true`) **tüm import** 400 düşer.
   `backupRestore.ts:164-174` `upsertFoodLists`'e bakmalı.
2. **`notification_preferences` web'de de eklenmeli mi?** Flutter'da
   ekledim (`full_setup.sql:351-365`, `UNIQUE(user_id, notification_type)`,
   CHECK allow-list `20260927120000_…:411-423`). Web'de de aynı kayıp var.
   **Not:** Flutter UI'ı tür bazlı tercihleri henüz **yazmıyor**
   (`notifications_dialog.dart:17` — "Faz 5'te ele alınacak"), yani bu tablo
   şu an iki istemcide de hep boş. Yine de yedekte varsa geri yüklenmeli.
3. **`favorite_foods` FK'si `ON DELETE CASCADE`** — telafi sırası önemli:
   favoriler `foods`'tan **önce** silinmeli (Flutter'da `importTables.reversed`
   bunu veriyor; test `backup_round_trip_test.dart` "telafi sırası" ile
   sabitliyor).

### A4r5'e (features) — `photo_url` kararı
Yukarıdaki "Görev 3 → Karar önerisi" bölümü. Özet: (A) base64 **önerilmiyor**,
(B) "görseller dahil değil" uyarısı **öneriliyor**, (C) hiçbir şey yapma
**önerilmiyor**. `data` alanında gereken tek değişiklik export gövdesine
`media` anahtarı; `transfer_dialogs.dart` uyarısı sizin alanınızda.
Görev metnindeki "25 MB sınırı" **yanlıştır** — gerçek sınır
`chat-attachments` bucket'ında **10 MB** (`full_setup.sql:674`) ve ölçüm
görselleri için **hiç bucket yok**.

### A1'e (supabase) — bucket
Ölçüm görselleri için bucket **yok**. Fotoğraf yükleme özelliği eklenirse:
ayrı `meal-photos` bucket (private, 5 MB) + `meal_attachments` tablosu
(`storage_path` tutmak, `photo_url` değil). Politika deseni
`full_setup.sql:687-695`'ten kopyalanabilir. **Migration eklenirse yeni
dosya, mevcut dosyaları düzenleme** kuralı.

### A2r6'ya
1. `_rollback` `DELETE` **etkisini doğrulamıyor** (`data_transfer_repository.dart:941-968`).
2. `sanitizeFood` ölü kod.
3. `foods.created_at` yedeğe girmiyor (P3, kasıtlı).

---

## Doğrulama

```
$ cd flutter_app && flutter analyze
No issues found! (ran in 3.6s)

$ cd flutter_app && flutter test
00:20 +629: All tests passed!          (597 → 620 → 629)

$ node tool/check_versions.cjs
✓ Sürüm tutarlı: 1.3.0+4 (pubspec = AppConstants = CHANGELOG = README) ·
  web 1.1.0 (package.json = APP_VERSION) · varsayılan hedefler ve makro
  oranları iki istemcide aynı.

Testler /tmp dışında değil — flutter_app/test/data/** içinde.
```

## Commit'ler

| Hash | Stat |
|---|---|
| `850c63b` | `fix(data):` favoriler/son kullanılanlar/bildirim tercihleri geri yüklenmiyor + `nova_score` veri bozulması + round-trip testi · **5 dosya, +2003 / −11** |
| `5a1c9f6` | `fix(data):` tanıma sonucu bozuk elemanla çöküyor, analytics yuvarlama asimetrisi · **3 dosya, +291 / −6** |

## Sonraki öneriler (Tur 6 için)

1. **Favoriler tablosu ölü mü?** `favorite_foods`/`recent_foods` **hiçbir
   istemci tarafından yazılmıyor** — iki istemci de favorileri `meal_entries`'ten
   hesaplıyor. Yani:
   - Bugün için içe aktarımın **kullanıcıya görünür faydası yok** (geri
     yüklenen favori listede görünmez). Yine de doğru yazılması gerekir:
     tablo bir gün yazılmaya başlarsa (veya bir başka istemci yazarsa) elde
     veri olsun.
   - **Ürün kararı:** ya favoriler `meal_entries`'ten türetilmeye devam
     etmeli (bu durumda iki tablo DB'de **gereksiz**), ya da gerçek tablo
     haline gelmeli. Şu an ikisinin de olması **"hangi gerçek?"**
     belirsizliği yaratıyor. → **Ürün/A1 kararı.**
2. `_rollback` DELETE doğrulaması.
3. `DiaryRepository` ↔ `AnalyticsRepository` yuvarlama politikası
   (ürün kararı: dashboard da mı yuvarlasın?).
4. `foods.created_at` yedeğe girmesin mi (güncelleme sırası koruması)?
