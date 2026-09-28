# ÖZET — Tur 4 ve 5 (2026-09-28)

## Tur 4
| Hash | Kapsam | Stat |
|---|---|---|
| `54b88d0` | `fix(security)` — CI'da edge function kapısı, damga hataları, push sınır off-by-one | 18 dosya, +2184/−47 |
| `4181404` | `docs(plans)` — A1r4 raporu | 1 dosya |
| `7f7cde0` | `fix(data)` — kısmi import imkânsız hale getirildi | 3 dosya, +2554/−322 |
| `befb5d9` | `fix(data)` — enum + eşzamanlılık + süzgeç | 7 dosya, +1061/−105 |
| `20c4707` | `docs(plans)` — A2r4 raporu | 1 dosya |
| `71e63b9` | `fix(flutter-core)` — APK sha256, tema kontrastı, gömülü sır koruması | 24 dosya, +1615/−118 |
| `c232528` | `build(flutter)` — `crypto` bağımlılığı açıkça bildirildi | 2 dosya |

## Tur 5
| Hash | Kapsam | Stat |
|---|---|---|
| `34fb23a` | `fix(web)` — yedek içe aktarımında kısmi yazma ve veri bozulması | 7 dosya, +1938/−261 |
| `cd6caa7` | `ci` — deno.lock takibi, tetikleme tüm branch'ler, web test kapısı | 7 dosya, +810/−4 |
| `aca7610` | `docs` — Tur 5 gerçek düzeltmeleri, VAPID istemci anahtarı, localStorage notu | 5 dosya, +207 |
| `850c63b` | `fix(data)` — favoriler/son kullanılanlar/bildirim tercihleri geri yüklenmiyordu | 5 dosya, +2003/−11 |
| `5a1c9f6` | `fix(data)` — tanıma sonucu bozuk elemanla çöküyor, analytics yuvarlama asimetrisi | 3 dosya, +291/−6 |
| `87c4f72` | `docs(plans)` — A2r5 raporu | 1 dosya |

## En kritik bulgular (Tur 4-5)

1. **Yedek/geri yükleme veri bozuluyordu (iki istemcide birden).**
   Kısmi import (yarısı yazılı, kullanıcı bilmiyor), besin alanının `0`'a
   çevrilmesi (**sessiz yanlış besin değeri**), `amount_ml` geçersizde `0` →
   DB CHECK 400 → öğünler yazıldıktan **sonra** ölüm, `deleted_at` dolu
   satırların **canlanması** (sildiği öğün geri geliyordu), `created_at` kaybı.
   Flutter'da 3 fazlı akış (doğrula → yaz → telafi), web'de aynı desen.
2. **4506 → 37 istek** (2000 kayıtlık yedek). `inFilter` 100'lük dilimleme +
   `importBatchSize = 500` (Postgres parametre tavanı 65535).
3. **`delete-account` kısmi silmede 200 "başarı"** dönüyordu (KVKK eksik silme).
4. **Push `MAX_PLAINTEXT_BYTES` off-by-one**: 3993-4058 baytlık pencerede
   uzun HTML'li haftalık özet **push'u sessizce kaybediyordu**.
5. **Favoriler/son kullanılanlar/bildirim tercihleri** dışa aktarılıyor ama
   içe aktarılmıyordu → yedekten geri yüklendiğinde **kayboluyordu**.
6. **Çakışma (race) koruması**: `updateMealEntry(expectedUpdatedAt:)`.
7. `nova_score` geçersizde sayaç değerini (1,2,3…) yazıyordu → gıda
   "işlenmemiş" sınıflanıyordu.
8. `favorite_foods`/`recent_foods` `created_at` sözleşmeye girmiyordu →
   toplu insert `StateError` ile **tüm import'u** düşürüyordu.
9. `RecognizedFood.numOr` NaN/Infinity filtrelemiyordu → **tanıma ekranı çöküyordu**.
10. **CI'da 54 edge test hiç çalışmıyordu** → `supabase.yml` eklendi.
11. `deno.lock` ölçümü: lock varken `supabase-js 2.117.2`, yokken `2.180.1` —
    aynı kod, iki farklı bağımlılık grafiği. Kökteki lock React'ın 70 npm
    bağımlılığını da içeriyordu → `supabase/deno.json` ile 8382 → 3285 bayt.
12. Web'de `useNotifications` hata halinde `console.error` + `return` →
    eski veri ekranda kalıyordu.

## Ölçümle alınan kararlar (tahmin değil)
- `deno.lock` **takip edilsin** (sürüm sürgüsü ölçüldü, cache faydası kanıtlandı).
- `strings.xml` **çeviri dosyası eklenmesin** — uygulama metinleri zaten Dart'tan
  (`str.*`) geliyor; 11 dil dosyası eklemek "widget'ım Almanca, içeriği
  Türkçe" gibi yarım deneyim verirdi.
- `flutter.yml` `push` → **tüm branch'ler** (`fix/...` push'unda CI tetiklenmiyordu).
- `amount_ml` **INTEGER kalsın** — arayüz `digitsOnly` ile tam sayı üretiyor,
  0.5 ml arayüzden ulaşılamıyor; `numeric(8,1)` geri dönüşsüz dönüşüm.
- `photo_url` yedeğe gömülmesin — hiçbir istemci bu kolonu **yazmıyor**,
  kırık görsel bugün mümkün değil; base64 ise `exportData`'nın bellekte
  JSON üretmesi nedeniyle OOM riski.

## ⭐ Ürün kararı bekleyenler (2 turdur)
1. **`favorite_foods`/`recent_foods` hiçbir istemci tarafından yazılmıyor.**
   İki istemci de favorileri `meal_entries`'ten hesaplıyor. Sonuç: geri yüklenen
   favoriler **bugün UI'da görünmez** ve iki tablo gereksiz. Hangisi gerçek?
2. **`foods` hesap silmede silinmiyor** (`created_by` FK `ON DELETE SET NULL`).
   Kullanıcının eklediği yiyecek topluluk verisiyle paylaşılıyor mu?
3. `photo_url` özelliği eklenirse ayrı bucket + tablo gerekecek.
4. `notification_preferences` UI'ı tür bazlı yazmıyor ("Faz 5" notu) → tablo hep boş.

## Doğrulama durumu
- `flutter analyze` → No issues found
- `flutter test` → **629/629** (Tur 1'de 143'tü, 2 kırıktı)
- `npm run build` → ✓ · `npm run lint` → 0 hata, 10 uyarı · `npm test` → 40/40
- `npx tsc` → exit 0
- `check_i18n.cjs` → ✓ 12 dil, 461 anahtar · `check_versions.cjs` → ✓
- `deno check` 22 dosya 0 hata · `deno test` 100/0
- 16 migration sıfırdan 0 hata · RLS 49/49 iki yol
