# RAPOR — A2r13-data (kurtarma + doğrulama) — 2026-09-28 — Tur 13

## Özet (5 madde)

1. **A2r12'nin commitlenmemiş işi kurtarıldı ve doğrulandı** (`a499866`, 16 dosya
   +1254/−13). İki iş de doğru bulundu: `foods` INSERT yolu ve öksüz öğün
   düzenlemesi. 12 dil çevirisi eksiksiz, `analyze` temiz, 26 test yeşil.
2. **`fetchDaily` P1'i kapatıldı** (`4630cf7`) — A4r11'in aktardığı "asıl kapsam
   daha geniş" yarı. Maliyet **Postgres 17'de ölçüldü ve sıfır bulundu**
   (medyan 0.0375 → 0.0370 ms, %−1.3 = gürültü). `foods(name)` embed'i eklendi,
   `MealEntry.foodName` + kaynak öncelikli `displayName`.
3. **Gece aralığı (Görev 1) zaten yapılmıştı** — `91439a3`'te A2r12 commit'li.
   Benim katkım: **parite kilitlenmedi**. A1r10/A2r12 testleri sunucu kuralını
   Dart'a kopyalayıp *kopyayı* test ediyordu → sunucu değişse test yeşil kalırdı.
   `9474909` ile test artık **sunucu kaynağını okuyor**; sarma dalını
   `return false` yaptım, test kırmızıya döndü, geri koydum.
4. **A2r12'nin iki işi için regresyon kilidi yazıldı** (12 test): yedek eşleşmesi
   etkisi (6) + gece aralığı sözleşmesi (6). Kod değişikliği yok.
5. **Dört negatif ölçüm + iki "yanlış yeşil" avı.** Testler kendi iddialarımın
   **üçünü** kırmızıya döndürdü (`(s+12)%24` formülü, `end==23` iddiası,
   `start=0` gece aralığı) — üçü de **testin** hatasıydı, düzeltildi.

## Commitler

| Hash | Stat | Kapsam |
|---|---|---|
| `a499866` | 16 dosya, +1254/−13 | A2r12'nin yarım işi: `foods` INSERT yolu + öksüz öğün düzenleme + 12 dil |
| `4630cf7` | 5 dosya, +864/−113 | `fetchDaily` `foods(name)` embed'i + `MealEntry.foodName` + 20 test |
| `9474909` | 2 dosya, +505 | A2r12 regresyon kilitleri (12 test) — kod değişikliği yok |

## ⭐ A2r12'nin `foods` INSERT yolu: şema/CHECK/RLS/idempotency doğrulaması

**Kaynak:** `supabase/migrations/20260111041204…:80-122` (CREATE TABLE),
`20260928300000:293-317` (`food_nutrition_values_non_negative`),
`20260928400000:67-95` (nova/nutri CHECK),
`20260927120000:227-247` (RLS), `:496` (UNIQUE index),
`20260822000000:19` (enum), `full_setup.sql:151-198, 417-438, 731-734`.

| Konu | Doğrulama | Sonuç |
|---|---|---|
| `source` enum | `20260822000000:19` → `('photo','text','manual')`; eski `'barcode'` **çıkarılmış** | A2r12'nin `_foodSources` **birebir** doğru |
| `created_by` | INSERT RLS `WITH CHECK (created_by = auth.uid())` (`:227-230`) | Yazılıyor, yoksa `42501` |
| `created_at`/`updated_at` | `DEFAULT now()` + BEFORE UPDATE trigger (`full_setup.sql:731-734`) | Gönderilmiyor, **doğru** (A2r5 hatası tekrarlanmadı) |
| Negatif besin | `food_nutrition_values_non_negative` (`20260928300000:309-315`) → `23514` | `ArgumentError` ile önden reddediliyor |
| NaN/Infinity | JSON'da gidince Postgres ayrıştıramaz | `_requireFiniteNonNegative` yakalıyor |
| `popularity_count`/`verified` | `idx_foods_popularity` arama sırası | Yazılmıyor, **doğru** |
| Idempotency | UNIQUE(lower(name), lower(COALESCE(brand,''))) → `23505` | `null` dönüyor ("zaten kayıtlı") |
| Yarım yazım | `food_nutrition` reddi → `deleteFood` ile geri silme | `AppLog`'a yazılıyor, **yutulmuyor** |
| Arama/listeleme | `search()`/`favorites()`/`frequentFoods()` zaten `created_by` seçiyor (A2r11), `nutrition == null` eliyor | Yeni gıda görünür, `canDelete == true` |

**Güvenli mi? Evet** — iki ödün verilebilir ama ikisi de kapatılmış:
`nova_score`/`nutri_score` **yazılmıyor** (NULL serbest, `20260928400000:89/:93`),
`fiber_g`/`sugar_g`/… nullable bırakılıyor.

### ⭐ Bulunan tek risk (P3, düzeltilmedi — kanıtı yazılı)

`23505` **genel** bir Postgres hata kodu. `createFood`'teki `if (e.code == '23505') return null`
yaklaşımı, ikinci yazmanın da aynı yanıtta `23505` vermesi hâlinde **çift kaydı
"zaten var" sanırdı**. `foods` INSERT'inde tek UNIQUE bu olduğu için **bugün
olanaksız** (ölçüldü: test `callCount == 1` ile istek sayısını kilitliyor).
Gelecekte iki isteği tek `Promise.all` yapılırsa **sessiz veri kaybı** olur.
Düzeltilmedi çünkü testi kırmadan **kanıtlamak** imkânsız; kod yorumuyla işaretlendi.

## Öksüz öğün düzenleme: davranış + yedek eşleşmesi etkisi

**Davranış (ölçüldü, 4 yol):**

| yol | `custom_name` | `_seedName` sonucu | Kaydet |
|---|---|---|---|
| Elle giriş | dolu | korunur | açık |
| AI tanıma | dolu (A4r11) | korunur | açık |
| Topluluk gıdası, gıda duruyor | NULL | `foods.name` seed edilir | **açık** (A2r13 sayesinde `displayName` gerçek ad) |
| Gıda silinmiş | NULL | `''` ("Bilinmeyen" yazılmaz) | kapalı + `dialogs.edit.nameMissing` ipucu |

`updateMealEntry` kısmi güncelleme → `food_id`/`source`/`photo_url`/`entry_date`/
`deleted_at` **korunur** (test `containsKey(...) == false` ile kilitli).

**⭐ Yedek eşleşmesi: BOZULMUYOR.** İki ayrı eşleşme var:

- `foods` ↔ `foods`: `lower(name)` (`_loadExistingKeys:566-584`).
  `foods.name`'e **hiçbir yazma yolu yok** (gıda adı değiştirme özelliği
  repoda yok) → dokunulmaz.
- `meal_entries` ↔ `meal_entries`: `entry_date|custom_name|meal_type`
  (`_mealKey:1937-1944`). A2r12 kurtarması `NULL` → `'Yoğurt'` yaptığı için
  anahtar **değişir**. Ama yedek `custom_name`'i de taşıdığı için
  **kendiliğinden tutarlı**: yedek→geri yükleme→yedek döngüsü aynı anahtarı verir.

**Bilinen yan etki (P3, kabul edildi):** Düzenlemeden **önce** alınan yedek,
`custom_name` NULL iken `2026-09-28||lunch` üretir; canlıda artık
`'Yoğurt'` var → eşleşmez → import öğünü **mükerrer** ekler. Bu **A2r5'in zaten
mevcut davranışı** (NULL ≠ ad); A2r12 kurtarması onu değiştirmedi, yalnız bir
veri düzeltmesi yaptı. Kilitli (`orphan_edit_backup_match_a2r13_test.dart`).

## Gece aralığı: yapıldı mı, neyi hizaladım

**Yapılmıştı** — A2r12 `91439a3` ile commit'li (diff'te görünmüyordu çünkü
brif A2r12'nin *commitlenmemiş* olduğu varsayımındaydı):
`end >= start ? end : 23` kaldırıldı → `_clamp(endHour, 0, 23, 21)`;
`endHourOptions` tam 0..23; `rangeNoNight` → `rangeDay`/`rangeNight` (12 dil).

**Benim hizaladığım: sözleşme kilidi.** `ff25bf7` ile gelen sunucu kuralı
(`helpers.ts:251-263`) doğrulandı:

```ts
if (s === e) return h === s;         // tek saat
if (s < e)  return h >= s && h <= e;  // gündüz
return h >= s || h <= e;              // gece (sarma)
```

A1r10/A2r12 testleri bu kuralı **Dart'a kopyalayıp kopyayı** test ediyordu →
kopya doğruysa yeşil, **sunucu değişse bile yeşil** kalırdı. Bu, bu dosyada
tespit ettiğim **yeni bir "yanlış yeşil" biçimi**. `9474909`'daki test
`helpers.ts`'i **okur**, karar ağacını çıkarır ve 24×24 saat çiftinde Dart
kopyasıyla karşılaştırır.

## ⭐ `fetchDaily` join'i: ölçüm + düzeltme

### Ölçüm (Postgres 17.6, `postgres:17-alpine` Docker, gerçek indeksler)

50.000 gıda · **9.000.000** öğün (10.000 kullanıcı × 90 gün × 10 öğün) ·
`meal_entries(user_id, entry_date)` + `foods_pkey` indeksleri · 200 koşu,
ilk 20'si ısınma → **n=180 medyan** (A2r11'in yöntemiyle aynı).

| varyant | medyan | p95 |
|---|---|---|
| A) join yok (`select=*`) | **0.0375 ms** | 0.0860 ms |
| B) `LEFT JOIN foods(name)` | **0.0370 ms** | 0.0862 ms |

Fark **−0.0005 ms (%−1.3)** = gürültü sınırında. Plan:
`Nested Loop Left Join` + `Index Scan using foods_pkey … rows=1 loops=10`
(öğün başına **bir** PK sondası). Ağır gün (70 öğün): 0.0310 vs 0.0310 ms.
İstek sayısı değişmedi (3: meals+water+weight) → **N+1 yok**.

> ⭐ Yani düzeltme **kanıtsız iyileştirme değil**: maliyet ölçüldü ve **sıfır**
> bulundu. Tek gerekçe doğruluk.

### Düzeltme

1. `fetchDaily` → `.select(mealEntrySelectWithFoodName)`: **açık** 17 kolon +
   `foods(name)`. Düz `select()` embed'i **açmaz**; `select=*` tüm gömülü
   nesneleri açardı (A4r11'in `select=*` tuzağı).
2. `MealEntry.foodName` — türetilmiş alan, `toJson`'a **yazılmaz**
   (`meal_entries.food_name` kolonu yok; ikinci kopya bayatlık üretirdi).
3. `fromJson`/`toJson` **elle**, `meal_entry.g.dart` **silindi** — `Profile`
   (A2r5) ile birebir aynı, daha önce kanıtlanmış yol.
4. `displayName` önceliği: `customName` → `foodName` → `"Bilinmeyen"`.
   A4r11'in kuralı korunur; beyaz boşluk `custom_name` JOIN adını **ezmez**.
5. 6 embed biçimi + 5 bozuk gövde tipi → **çökme yok** (`as Map` yerine tür denetimi).

### "Etkin test" denetimi (kendi yazdığım testler için)

- Kolon listesi **elle yazılmadı**: `MealEntry.fromJson` gövdesi **kaynak
  metinden okunur**, `json['…']` anahtarları çıkarılır, liste onunla karşılaştırılır.
  İkinci sabit yazılsaydı iki liste ayrışırdı (A5r10 tuzağı).
- `displayName` iddiası **sonucu** değil `foodName` **alanını** ham JSON'dan denetler.
- `fetchDaily` **uçtan uca** sahte PostgREST gövdesiyle çalıştırılır: kolon eksikse
  `fromJson` `TypeError` verirdi → test gerçekten okuma yapıyor.

## Negatif test ölçümleri (hepsi kırmızı görüldü, hepsi geri kondu)

| # | enjeksiyon | sonuç |
|---|---|---|
| 1 | `fetchDaily` → düz `.select()` | **1 kırmızı** / 18 yeşil (seçici) |
| 2 | `displayName`'den `foodName` dalı çıkarıldı | **3 kırmızı** (uçtan uca test dahil) |
| 3 | `displayName` önceliği ters çevrildi | **1 kırmızı** |
| 4 | `helpers.ts` sarma dalı → `return false` | **1 kırmızı** (sunucu **hiç** dokunulmadı, geri kondu) |
| 5 | `toRow` → eski `end >= start ? end : 23` | **2 kırmızı** |
| 6 | A4r11 ölçüm testi (join'i geri al) | **kırmızı** (`Expected '*' / Actual '…,foods(name)'`) |

## ⭐ "Yeşil test ≠ etkin test" — 3 yeni vaka (hepsi kendi testimde)

1. **Sarma dışı saat formülü.** `(s+12)%24` "pencere dışı saat" varsaydım;
   21→09 penceresi 13 saat olduğu için 9 **pencerede** → yanlış negatif.
   Düzeltme: formül yerine **arama** (`[for h if !serverSends(h)]`). ⭐ A4r3'ün
   "mantıklı görünen iddiayı test et" dersinin yeni biçimi: **ölçümü veriden türet**.
2. **`end == 23` iddiası.** "Gece aralığı 23'e çekilmemeli"yi `(0,23)` için de
   uyguladım; oysa 0→23 **doğru olarak** 23 yazmalı. İddi `s > e` dalına
   kapsandı.
3. **`start=0` gece aralığı.** "Her `start` için `end < start` seçilebilir"
   iddiası `start=0`'da **matematiksel olarak imkânsız**. Aralık `1..23`'e
   çekildi ve nedeni yazıldı.

Ayrıca **2 derleme hatası** (`testWidgets` saf async iş için → `!timersPending`,
`as Map` tip uyuşmazlığı) ve **4 lint** çıktı; hepsi düzeltildi.

## Doğrulama çıktıları

```
cd flutter_app && flutter analyze     → No issues found!
cd flutter_app && flutter test        → 00:41 +1156 ~1: All tests passed!
node tool/check_i18n.cjs              → ✓ 12 dil, 525 anahtar, 0 hata
node tool/check_versions.cjs          → ✓ 1.3.0+4 tutarlı
```

Test sayısı: **1081 → 1156** (+75: 26 A2r12 + 20 `fetchDaily` + 6 yedek + 6 gece
+ A4r11 ölçümü 1→skip, +17 diğer). `~1` = bilinçli `skip`'li tarihsel ölçüm.

## Bulunurlar (düzeltilmedi, gerekçe)

| Sev | Konu | Gerekçe |
|---|---|---|
| P3 | `createFood`'te `23505` **genel** kod → iki yazma tek istekte olursa çift kayıt "zaten var" sanılır | Bugün tek istek atılıyor, test `callCount == 1` ile kilitli. Kanıtlanamıyor |
| P3 | Düzenleme öncesi alınan yedek, kurtarılmış öğünü mükerrer ekler | A2r5'in kabul ettiği mevcut davranış (`NULL ≠ ad`); ürün kararı gerekir |
| P3 | `createFood`'un **arayüzü yok** (yalnız veri katmanı) | `add_manual_entry_dialog` zaten aynı formu sunuyor; yeni düğme 12 dil + ürün kararı ister |
| P2 | `supabase/**`'a ölçüm SQL'ini koyamadım (`tool/**` A6, `plans/**` benim değil) | Dosya içine özet olarak gömüldü; yeniden üretilebilir |
| P2 | Web PWA'da aynı `displayName` P1'i **yok mu?** | `src/**` A5'in alanı; `grep display_name` yalnız `profiles` buldu → muhtemelen A5 zaten düzeltmiş, doğrulanmadı |

## AKTARIM (başka alana)

- **`features/**` (A4)**: `createFood` veri katmanında hazır ama **UI yok**.
  "Yemeklerime kaydet" düğmesi ürün kararı gerektiriyor (12 dil).
- **`supabase/**` (A1)**: `foods` tablosunda `source = 'photo'|'text'|'manual'`
  enum'unun `'barcode'` değeri `20260822000000`'de çıkarılmış ama
  `recognition_confirm_dialog` yolları `'photo'` yazıyor — **kayıt kökeni**
  anlamı hâlâ doğru, sorun yok.
- **`ci` (A6)**: 2 ölçüm dosyası Postgres Docker gerektiriyor
  (`a2r13_fetchdaily_embed.sql`) — CI'da `services: postgres` gerekir.

## Sonraki öneriler (Tur 14)

1. `createFood` için **UI** (ürün kararı) — P1'in arayüzü hâlâ eksik.
2. `favorite_foods`/`recent_foods` **ölü tablo** sorunu (T5 ⭐ ürün kararı)
   hâlâ açık — A2r12'nin INSERT yolu bunu kısmen çözdü ama tabloya yazılmıyor.
3. `check_i18n.cjs` orphan ratchet'i (`ORPHAN_BASELINE = 63`) `rangeNoNight`
   anahtarı artık gerçek orphan → ratchet **güncellenmeli** (A6 alanı).
