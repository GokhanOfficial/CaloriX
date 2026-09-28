# RAPOR — A4r11 (P0 düzeltme) — 2026-09-28 — Tur 12

Alan: `flutter_app/lib/features/**`, `flutter_app/lib/shared/**`, `flutter_app/test/**`
Commit: **`1b83c2c`** (tek commit, 5 dosya)

---

## Özet

1. **P0 doğrulandı ve düzeltildi.** `add_from_food_dialog.dart:90`
   `custom_name`'i yalnız `isCustom`'a bağlıyordu → kullanıcının kendi
   eklediği gıdanın öğünü silindikten sonra **adını** kaybediyordu.
   Düzeltme: `isCustom || canDelete`.
2. ⭐ **Kapsam brif sandığından AĞIR çıktı.** Gözlemlenen kayıp
   "silinince" değil: `fetchDaily` **`foods` join'i hiç yapmıyor**
   (ölçüldü, `select=%2A`) ve `displayName` yalnız `custom_name` okuduğu
   için **topluluk gıdaları da silinmeden "Bilinmeyen"** görünüyordu.
   Ad yazılmamıştı zaten. Düzeltilen kısım **kendi gıdanı** için
   (yani A4r10/A2r11'in zarar verdiği yol); kalan kısım ayrı bulgu →
   **AKTARIM**.
3. **`delete_food_button.dart:177`** → `!canDelete` ise düğme gizlenir
   (A2r11 aktarımı). A4r10'ın tooltip testi **bilinçli olarak kırıldı**
   (`foodId: 'f1'` + varsayılan `canDelete: false`) → onarıldı ve
   `canDelete: false → gizli` testi eklendi.
4. **Eski bozuk veri için migration GEREKMİYOR** — gerekçesi aşağıda
   (3 ayrı kanıt). Yine de DB envanteri `supabase/**` alanına bırakıldı.
5. **Testler 1067 → 1081 (+14)**, hepsi geçiyor; 3 ayrı **negatif ölçüm**
   yapıldı (kırmızı görüldü, geri kondu).

---

## 1) Davranış doğrulaması — `custom_name` hangi senaryoda dolu olmalı?

`meal_entries` şeması (`full_setup.sql:208-229`):
`food_id UUID REFERENCES foods(id) ON DELETE SET NULL`, `custom_name TEXT`
(**nullable**, CHECK yok).

Zincir **ölçüldü** (`fetchdaily_no_foods_join_measurement_a4r11_test.dart`):

```
GET /rest/v1/meal_entries?select=%2A&user_id=eq.u1&entry_date=…&deleted_at=is.null&order=created_at.asc
```

`select=%2A` = düz `select()`, **embed yok** →
`MealEntry` yalnız `meal_entries` kolonlarını görür →
`displayName` (`meal_entry.dart:89`) = `customName ?? 'Bilinmeyen'`.

| # | Senaryo | `food_id` | `canDelete` | Eski | Yeni | Gerekçe |
|---|---|---|---|---|---|---|
| 1 | Elle giriş (`add_manual_entry_dialog:78`) | NULL | – | ✅ ad | ✅ ad | `food_id` zaten NULL, ad şart. **Değişmedi** |
| 2 | AI tanıma (`source: photo/text`) | NULL (`:240` açıkça `null`) | – | ✅ ad | ✅ ad | Aynı. **Değişmedi** |
| 3 | **Kendi eklediği gıda** | var | **true** | ❌ **NULL** | ✅ **ad** | ⭐ **P0**: silinebilir → FK kırılır → ad gerekir |
| 4 | Topluluk/seed gıda | var | false | NULL | NULL | Silinemez → FK hiç kırılmaz → yazmak **gereksiz tekrar** (her öğünde gıda adı kopyası) |
| 5 | Başkasının gıdası | var | false | NULL | NULL | Aynı |

**Karar:** `canDelete` = `created_by == auth.uid()`
(`food_repository.dart:24-63`, A2r11'in ölçümü) = `deleteFood`'in RLS
süzgeciyle **birebir aynı** koşul. Yani "`custom_name` yaz" sorusu ile
"gıda silinebilir mi" sorusu **aynı sorunun iki yüzü**. Başka bir kural
(`source`, `isCustom`) ek koşul olurdu.

**"Gereksiz veri şişirir mi?" — evet, ölçülebilir:** `meal_entries`
`custom_name TEXT` her satırda gıda adının bir kopyası olurdu. 10.000 öğün
× ~20 bayt ≈ 200 KB; `idx_foods_name` gibi bir index de gereksizce
 şişerdi. Silinemeyen gıdalar için bu **saf tekrar**.

### ⭐ Dürüst düzeltme: bulgu brifden daha ağır

Brif: *"Gıda silinince `custom_name` de NULL → 'Bilinmeyen'."*
Gerçek: **`custom_name` silinmeden önce de NULL'dır** (senaryo 4/5) ve o
öğün **zaten** "Bilinmeyen" görünür. Yani 4. ve 5. senaryolarda
`custom_name`'i yazmamak **kalıcı** bir "Bilinmeyen" bırakır.
Bu, "seçicilik = veri kaybı" riski olduğu için ölçülmesi gerekti; ölçtüm.
Doğru davranış yine de aynı (community gıda için yazmamak), çünkü
alternatif olan `join` eklemek **veri katmanı alanı** (bkz. AKTARIM).

---

## 2) Düzeltilen yollar — kaç yol kontrol edildi?

`grep -E "addMealEntry|addManualEntry|customName"` ile **3 yazma yolu**
bulundu; **3'ü de** kontrol edildi:

| # | Yol | Yazma | Durum |
|---|---|---|---|
| 1 | `add_from_food_dialog.dart:90` | `foodId` + `customName` | ⭐ **DÜZELTİLDİ** (P0) |
| 2 | `add_manual_entry_dialog.dart:78` | `customName` (foodId yok) | ✅ **Doğru, değiştirilmedi** — `food_id` NULL, ad zaten dolu |
| 3 | `recognition_confirm_dialog.dart:241` | `customName` (`:240` `foodId: null`) | ✅ **Doğru, değiştirilmedi** — `food_id` **her zaman** null, ad zaten dolu |

**Ek kontrol edilen yol (yazmıyor ama aynı alanı tüketiyor):**
- `edit_meal_entry_dialog.dart:136` → `updateMealEntry({'custom_name': …})`.
  Bu yol `custom_name`'i **daima** yazar; `food_id`'yi korur
  (`:143` yorumu). Yani bir öğün elle düzenlenirse ad **kurtarılır** —
  kullanıcı için kısmi bir çıkış yolu. Düzeltme **gerektirmiyor** (zaten
  dolu yazıyor) ama AKTARIM'da not edildi (`:103`'te boş ad kaydetmeyi
  engelliyor, yani "Bilinmeyen"i adıyla değiştirebilir).
- `data_transfer_repository.dart:740` (yedek→geri yükleme): `custom_name`
  yedekten taşınır (`:1153`), `food_id` **ad üzerinden** yeniden eşlenir
  (`:740`). Düzeltmeyle üretilen satırlar yedekte de adını taşır → **geri
  yükleme de korur**. Ölçüm: `backup_round_trip_test.dart` hâlâ yeşil.
- `chat_message.dart`'ın `customName`'i **farklı** alan (chat action
  payload) → ilgisiz, dokunulmadı.

| Sev | Dosya | Ne yapıldı | Doğrulama |
|---|---|---|---|
| **P0** | `add_from_food_dialog.dart:90` | `isCustom` → `isCustom \|\| canDelete` | 5 senaryo testi + 3 negatif ölçüm |
| **P1** | `delete_food_button.dart:177` | `!canDelete` → `SizedBox.shrink()` | 3 kapı testi + 1 negatif ölçüm |
| **P2** | `delete_food_button.dart:40-47` | Sınıf dokümanı yeni kuralı anlatıyor | `flutter analyze` |

---

## 3) Eski bozuk veri — migration gerekiyor mu? **HAYIR**

Üç ayrı kanıt:

**(a) Projenin kendi kaydı.** `plans/analiz-26-09-27/PROTOKOL.md:10`:
> "Supabase projesi **frozen**, production verisi **yok**."

Bu yüzden `food_id IS NULL AND custom_name IS NULL` satırları **yok**.

**(b) Düzeltme öncesi kod böyle satır üretemezdi.** Eski kural
`custom_name = isCustom ? name : null` ve `custom_name` **nullable**'dı →
NULL yazan satır `food_id`'si **dolu** kalırdı, yani
`food_id IS NULL AND custom_name IS NULL` **kendiliğinden oluşamazdı**.
Bu kombinasyon yalnız (i) yedekten gelen bozuk satır veya (ii) elle
yazılmış bir kayıtla mümkün.

**(c) Yazma yollarının tamamı incelendi** (bölüm 2): 3 yolun 3'ü de
kontrol edildi; hiçbiri `(food_id NULL, custom_name NULL)` yazmıyor.

⚠️ **Kanıtın sınırı (dürüstlük):** (a) ve (c) **statik** kanıttır; canlı
DB'ye bağlanamadım. A1r8'in bulduğu `.gitignore`lu `supabase/.temp/`
gerçek proje kanıtı (`ref bzfnncensolirkqdohpq`, PG 17.6.1) olduğu için
"frozen" varsayımı **kendisi de doğrulanmamıştır** (A1r8, T8 P1).

**Bu yüzden migration YAZMADIM** (alan sahipliği `supabase/**` = A1) ama
**envanteri aktarıyorum** — tek sorgu, 10 saniye:

```sql
-- Bozuk satır envanteri (A4r11): food_id ve custom_name İKİSİ de NULL
SELECT count(*) AS bilinmeyen_ogun
  FROM public.meal_entries
 WHERE food_id IS NULL
   AND (custom_name IS NULL OR btrim(custom_name) = '')
   AND deleted_at IS NULL;

-- Kullanıcının kendi gıdası olup adı yazılmamış (P0'ın izi, silinmeden önce):
SELECT count(*) AS kendi_gidasi_adsiz_ogun
  FROM public.meal_entries m
  JOIN public.foods f ON f.id = m.food_id
 WHERE m.custom_name IS NULL
   AND m.deleted_at IS NULL
   AND f.created_by = m.user_id;   -- kullanıcının kendi gıdası
```

**Düzeltme `custom_name`'i doğru yere yazar; geriye dönük onarım
gerekmez**, çünkü (c) gereği böyle satır **yok**. Eğer sorgu beklenmedik
sayı döndürürse: `UPDATE … SET custom_name = f.name FROM foods f WHERE
f.id = meal_entries.food_id` (görünür, idempotent, satır silmez) —
A1'in alanı, tur 13'e bırakıldı.

**Tasarım notu (yedek/geri yükleme):** A2r5'in import'u `food_id`'yi
**ad üzerinden** yeniden eşliyor (`data_transfer_repository.dart:740`).
Düzeltme, kullanıcının gıdasını **adıyla** yazdığı için yedek→geri
yüklemede de eşleşme güçleniyor; `canDelete == false` gıdaların `food_id`'si
NULL yazılıyor (eşleşme yok → `custom_name` zaten dolu) → **geri yükleme
adı kaybetmiyor**. Ölçüm: `backup_round_trip_test.dart` yeşil.

---

## 4) `deleteFood` `canDelete` gizlemesi + kırılan test onarımı

**Kod** (`delete_food_button.dart:177`):
```dart
if (foodId == null || !widget.food.canDelete) return const SizedBox.shrink();
```
Gerekçe: `canDelete == false` → `created_by != auth.uid()` → RLS DELETE
(`full_setup.sql:424`) reddi. A4r10'da düğme topluluk gıdalarında da
görünüyordu; kullanıcı onay diyaloğunu doldurup "başarısız" alıyordu.
`add_page.dart`'in **4 bölümü** (`:286` + favoriler/recents/frequent)
aynı widget'ı kullandığı için otomatik düzeldi — 1 satır, 4 kapsam.

**⭐ Kırılan test onarıldı:** Brifin dediği gibi A4r10'ın tooltip/dialog
testleri **bilinçli olarak** kırıldı — `FoodItem.canDelete` varsayılanı
`false`, testler `foodId: 'f1'` kullanıyordu.
- **6 `FoodItem`** örneğine `canDelete: true` eklendi.
- Yeni test: **"topluluk/seed gıdasında (canDelete=false) düğme GİZLENİR"**
  → `find.byType(IconButton)` `findsNothing` **ve** tooltip yok.

**Ayrıca `EditMealEntryDialog` için bir uyarı (dokunmadım):** `food_id` dolu
bir öğünü açtığında `_nameController` **boş** açılır (`:79`
`e.customName ?? ''`) ve `_valid` (`:103`) ad dolu olmadıkça kaydı
engeller → kullanıcı öğünü kaydedemez, hatta adı girince öğünü
`food_id`'siyle birlikte DB gıdasından kopuklaştırmış olur. P2, tur 13.

---

## 5) ⭐ "Etkin test" doğrulaması (A4r7b / A4r10 / A5r10 sınıfı)

Bu turda 3 ayrı tuzak vardı; üçünü de kapatmaya çalıştım.

**(a) ⭐ A5r10 sınıfı — "test, hatayı düzelten katmandan geçiyor".**
Yazma testi `custom_name`'i **üretim kodunun bir fonksiyonundan geçirip**
sonucu denetlemiyor. `invocation.namedArguments[#customName]` ile
**ham** değeri alıp **doğrudan** `expect` ediyorum; `MealEntry`/`FoodItem`
dönüşümünden geçmiyor. `MealEntry.displayName` yalnız **ayrı** bir testte,
elle kurulmuş bir `MealEntry` üzerinden denetleniyor — yazma testi o
metottan geçmiyor.
**Kanıt:** negatif ölçüm 3 (aşağıda) — sabit yanlış ad yazılınca 4 test
kırmızı.

**(b) A4r7b sınıfı — "`tap` sessizce hiçbir şey yapıyordu".**
`_tapAdd`: (1) düğme bulunur, (2) `tester.getRect` ile **ekran içinde**
olduğu doğrulanır, (3) `rect.width > 0`, (4) basılır, (5) ⭐
**`expect(captured.calls, 1)`** — kayıt **gerçekten** oluştuğu kanıtlanır.
Son madde olmadan altındaki `customName` denetimleri `null` görüp
**yeşil kalırdı**. (A4r7b: 3 test hiçbir şey ölçmeden yeşildi.)

**(c) ⭐ Sabit metin tuzağı (yeni — dikkatimi çeken).** Düğme metni
`'Ekle'` yazınca test **kırmızı** oldu; gerçek metin `Yiyecek Ekle`
(`addFood.title`). Sabit metni doğru yazmak yerine **çeviri anahtarından**
türettim ve **sözleşme testi** ekledim:
`expect('Yiyecek Ekle', 'addFood.title'.tr())` → çeviri değişirse test
kırılır ama anlam kaybolmaz; sabit metin yazsaydım test sessizce
**yanlış düğmeye** basardı.

**(d) Ölçüm testi `foods` join yokluğunu gerçekten ölçtü.** İlk denemede
`expect(contains('select=*'))` **kırmızı** oldu (PostgREST `select=%2A`
URL-kodluyor). Bu, ölçümün "yeşil ama boş" olmadığının kanıtı: test gerçek
URL'i okuyup **gerçek** değerle karşılaştırıyor. `Uri.parse(...).queryParameters`
ile düzeltildi.

---

## 6) ⭐ Negatif test ölçümü (3 ayrı regresyon enjeksiyonu)

| # | Enjeksiyon | Sonuç (kırmızı görüldü) | Sonra |
|---|---|---|---|
| 1 | P0 geri alındı: `isCustom ? name : null` | **2 kırmızı**: "kendi eklediği gıda (canDelete=true)", "isCustom=false AMA canDelete=true" | ✅ geri kondu |
| 2 | `canDelete` kapısı geri alındı: `if (foodId == null)` | **2 kırmızı**: `a4r11` "canDelete=false → düğme YOK" + `a4r10` "seed gıdasında GİZLENİR" | ✅ geri kondu |
| 3 | `customName: 'SABIT YANLIS AD'` | **4 kırmızı**: 2 `canDelete=true` + manuel + tanıma | ✅ geri kondu |

⭐ **Seçicilik kanıtı (ölçüm 1'in asıl değeri):** P0 geri alınınca
**yalnız 2 test** kırmızı oldu; "topluluk gıdası → NULL", "manuel → ad",
"tanıma → ad" **yeşil kaldı**. Yani testler sadece **değişen** davranışı
ölçüyor, değişmeyeni **yanlışlıkla** kilitlemiyor.

⭐ **Ölçüm 3'ün değeri:** 4 test kırmızı olduğu için testler üretim kodunun
bir fonksiyonundan değil, **gerçek ham değerden** geçiyor (a5r10 tuzağı
kapalı).

---

## 7) Doğrulama çıktıları

```
$ cd flutter_app && flutter analyze
No issues found! (ran in 5.9s)                    # (dosya sayımı: exit 0)

$ cd flutter_app && flutter test
00:39 +1081: All tests passed!                    # 1067 → 1081 (+14)

$ node tool/check_i18n.cjs
✓ i18n bütünlüğü temiz: 12 dil, 523 anahtar, 345 Flutter kod anahtarı,
  2 dinamik kalıp, 345 React i18next anahtarı doğrulandı.
  orphan → ölü: 63/63 (ratchet korundu) · react canlı: 67

$ node tool/check_versions.cjs
✓ Sürüm tutarlı: 1.3.0+4 (pubspec = AppConstants = CHANGELOG = README) …
```

**Çeviri dosyasına dokunulmadı** (0 yeni anahtar; `DeleteFoodButton`'ın
mevcut `foodDelete.*` anahtarları kullanıldı → `check_i18n` orphan ratchet'i
63/63 korundu, artmadı).

---

## 8) Yeni testler (14)

**`test/features/add/orphan_meal_name_a4r11_test.dart`** (12)
| Grup | Test | Ölçtüğü |
|---|---|---|
| P0 karar | kendi eklediği gıda (canDelete=true) → **ad yazılır** | ⭐ P0 düzeltmesi |
| P0 karar | isCustom=false AMA canDelete=true → **ad yazılır** | ⭐ P0'ın tam senaryosu |
| P0 karar | topluluk/seed (canDelete=false) → **ad YAZILMAZ** | seçicilik (veri şişirme yok) |
| P0 karar | manuel giriş (isCustom=true) → ad yazılır | **değişmedi** |
| P0 karar | tanıma (isCustom=true) → ad yazılır | **değişmedi** |
| displayName | `food_id NULL + custom_name NULL` → "Bilinmeyen" | hatanın görünür yüzü |
| displayName | `food_id NULL + ad DOLU` → ad korunur | düzeltmenin sonucu |
| displayName | gıda silindikten sonra **kcal durur, ad korunur** | BOLA yok + ad var |
| sözleşme | düğme metni `addFood.title`'tan geliyor | sabit metin tuzağı |
| canDelete | `false` (varsayılan) → düğme **YOK** | kapı |
| canDelete | `true` → düğme **VAR** | kapı |
| canDelete | `foodId=null` → düğme **YOK** | regresyon koruması |

**`test/data/repositories/fetchdaily_no_foods_join_measurement_a4r11_test.dart`** (1)
| Test | Ölçtüğü |
|---|---|
| `fetchDaily` `meal_entries` sorgusu `foods` join **istemiyor** | ⭐ **KAPSAM ÖLÇÜMÜ** (kontrol `a4r11_test`'in sözünü kanıtlar) |

**`test/features/settings/notification_range_and_food_delete_a4r10_test.dart`** (+1)
| Test | Ölçtüğü |
|---|---|
| A4r11: topluluk/seed gıdasında (canDelete=false) düğme **GİZLENİR** | brifin istediği test |

---

## 9) AKTARIM

### ⭐ A2 (veri katmanı) — P0: dashboard gıda adını **`foods.name`'den hiç okumuyor**

Bu **benim alanım değil** (`lib/data/**` = A2) ve **düzeltmedim**.

**Bulgu (ölçüldü, `fetchdaily_no_foods_join_measurement_a4r11_test.dart`):**
`DiaryRepository.fetchDaily` (`diary_repository.dart:140-184`) düz
`.select()` atıyor; `foods` embed'i **yok**. `MealEntry.displayName`
(`meal_entry.dart:89`) = `customName ?? 'Bilinmeyen'`.

**Sonuç (brifden ağır):** Dashboard'da **`food_id`'si dolu** ama
`custom_name`'i NULL olan **her** öğün "Bilinmeyen" görünüyor — yani
`custom_name`'i `canDelete == false` için yazmamak, o satırlarda
**kalıcı** "Bilinmeyen" bırakır. Bu, Tur 11 öncesinden beri (v1.2.0)
süren bir davranıştır; `git show e99ba95` ile doğrulandı (`fetchDaily`
o zamandan beri `select()` idi).

**Neden `features/**` olarak çözemedim:** iki seçenek var ve ikisi de
veri katmanı:
1. **`fetchDaily`'e `foods(name)` embed'i eklemek** → `MealEntry`'ye
   `foodName` alanı + `displayName = foodName ?? customName ?? …`
   (json_serializable yeniden üretimi gerekir). Doğru çözüm.
2. **DB'de `foods` adını denormalize etmek** → `displayName` sorguya
   bağımlı olmaz ama her gıda güncellemesinde tüm öğünleri günceller
   gerek → pahalı, önerilmez.

**Ayrıca `source` kolonu:** AI tanıma `source: 'photo'|'text'` yazıyor
(`recognition_confirm_dialog.dart:239`) ama `check-reminders`/hiçbir yer
okumuyor (T10: "`goal_achieved` tipi kimse göndermiyor"un kardeşi) —
ayrı P2.

### ⭐ A2/A1 — Eski bozuk veri envanteri (migration **yazılmadı**, gerekçe bölüm 3)

Kanıt (a) "frozen" varsayımı, (b) eski kodun böyle satır üretememesi,
(c) 3 yazma yolunun da doğruluğu → **statik olarak migration gerekmiyor**.
Ama "frozen" varsayımının **kendisi** A1r8 tarafından doğrulanamamış
(gerçek proje kanıtı var). Envanter sorgusu bölüm 3'te; döndüğü sayı
0 değilse idempotent `UPDATE` gerekir → **A1'in alanı**.

### A6 — `EditMealEntryDialog` boş ad kilidi (P2, dokunmadım)

`edit_meal_entry_dialog.dart:79` → `food_id` dolu öğünde ad alanı **boş**
açılır; `:103` `_valid` boş adı reddeder → kullanıcı bu öğünü
**düzenleyip kaydedemez** ("Miktar" ve makrolar girilse bile). Adı girip
kaydederse öğün `food_id`'siyle birlikte gıdadan kopuklaşır. Düzeltme
`features/**` (benim alanım) ama tur 12'de 2 commit sınırı doluydu ve
P0'ya karışma riski taşıyordu → **tur 13**.

### PWA (`src/**`) — aynı P0 **yok**, doğrulandı

`src/components/dialogs/AddFromFoodDialog.tsx:93` →
`custom_name: food.name` **koşulsuz** yazıyor. Web istemcisi bu hatadan
**muaf**; web'de silme arayüzü de yok (T11). Dokunulmadı.

---

## 10) Kalan riskler

1. ⭐ **En büyük risk "Bilinmeyen"in tamamı çözülmedi.** Kendi gıdam
   düzeldi; **topluluk gıdası** eklenen öğünler hâlâ "Bilinmeyen" görünecek
   (A2'ye aktarıldı). Düzeltmem bunu **bilinçli olarak kabul etti** —
   alternatif `custom_name` şişirmekti, asıl çözüm `lib/data/**`.
2. **Kanıt statik.** Canlı DB'ye bağlanamadım; `supabase/.temp/` gerçek
   proje kanıtı olduğu için (A1r8) migration ihtimali **sıfır** değil.
   Envanter sorgusu bölüm 3'te.
3. **`canDelete` "silinebilir"in üst sınırı, alt sınırı değil.** Yarış
   durumunda (gıda başka cihazda silinmiş) `canDelete == true` ama
   `deleteFood` `false` döner → kullanıcıya ayrı mesaj gösterilir
   (A4r10'ın mevcut davranışı, korundu). `custom_name` yine de yazıldığı
   için öğün adını korur.
4. **`isCustom == true && canDelete == true`** yazılabilir (`FoodItem`
   const'ı engellemiyor) → ad yazılır, doğru davranış. Sadece ulaşılamaz
   bir kombinasyon; `recognized_food.dart:71` `toItem()` yalnız
   `isCustom: true` verir, `foodId` null → `DeleteFoodButton` zaten gizli.
5. **Performans etkisi ölçülmedi.** `fetchDaily` sorgusu **değişmedi**
   (ağ kapsamı `select=%2A` aynı); ek yalnız INSERT gövdesinde bir metin
   alanı. `meal_entries` yazma yolu darboğaz değil.
6. **Erişilebilirlik:** `canDelete` gizlemesi `tooltip`'ı da kaldırıyor →
   ekran okuyucu artık "Yemek sil: X" duymuyor (doğru: düğme yok).
   `Semantics` testi hâlâ `canDelete: true` ile yeşil.
7. **Web PWA'da yemek silme arayüzü hâlâ yok** (T11 kaydı) → aynı
   "Bilinmeyen" riski web'de **yok** çünkü `custom_name` koşulsuz yazılıyor.
8. **`full_setup.sql` çalışma ağacında başka bir ajanın değişikliği var**
   (`git status`: `M supabase/full_setup.sql`, `?? supabase/migrations/
   20260929010000_…cron…`) → dokunmadım, commit'im yalnız
   `flutter_app/{lib,test}` yollarını içeriyor.

---

## 11) Sonraki öneriler (tur 13)

1. **⭐ A2'ye:** `fetchDaily` → `foods(name)` embed + `MealEntry.foodName`
   + `displayName = foodName ?? customName ?? 'Bilinmeyen'`. Bu, "Bilinmeyen"in
   **kalıcı** kaynağını kapatır ve `custom_name`'in seçicilik kararını
   "sadece yedek" konumuna getirir (daha temiz mimari).
2. **A2'ye:** DB envanter sorgusunu (bölüm 3) çalıştır; döndüğü sayı ≠ 0 ise
   idempotent `UPDATE` migration'ı.
3. **A4r13 (benim alanım):** `edit_meal_entry_dialog` boş ad kilidi
   (bkz. AKTARIM).
4. **A4r13:** `displayName` "Bilinmeyen"i `common.food` çeviri anahtarına
   bağlasın (`meal_entry.dart:89` sabit Türkçe — 12 dilde yanlış gösteriliyor).
5. **A5'ye:** web'de `custom_name` koşulsuz yazıldığı için **veri şişirme**
   var (her topluluk gıdası öğünü ad kopyaları); 1 ile aynı seçicilik
   `UnifiedFoodDialog.tsx:293`'te de uygulanabilir — **ürün kararı** gerekir.
