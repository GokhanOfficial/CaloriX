# Faz 2 — Dashboard + Yemek Ekleme (Günlük Takip Çekirdeği)

> Master plan: `flutter-plan-master.md` | Web referansı: `src/pages/Index.tsx`, `src/pages/AddPage.tsx`, `src/hooks/useDailyData.ts`, `useFoodSearch.ts`, `useFavoriteFoods.ts`, `useRecentFoods.ts`

## Amaç
Günlük kalori/makro özeti, öğün ekleme (arama + favoriler + son yenilenler), su ve kilo girişi. AI/barkod Faz 4'te.

## 1. Modeller (`lib/data/models/`)
`supabase/types.ts` şemasından birebir:
- `Food` (foods), `FoodNutrition` (food_nutrition, food_id join)
- `MealEntry` (meal_entries: meal_type, serving, tarih)
- `WaterEntry`, `WeightEntry`
- `FavoriteFood`, `RecentFood`

## 2. Repository'ler
- `FoodRepository` — metin arama (web `useFoodSearch`'teki sorgu mantığı: isimde ilike, besin join'i), favori ekle/çıkar, recent listesini güncelle
- `DiaryRepository` — meal_entries CRUD (gün bazlı), water_entries ekle/sil (gün bazlı toplam), weight_entries ekle/listele
- Tüm tarih filtreleri web ile aynı gün-sınırı mantığını kullanır (kullanıcının yerel günü)

## 3. Dashboard (`features/dashboard/`) — `Index.tsx` karşılığı
- Üstte tarih seçici (önceki/sonraki gün, takvim)
- Kalori halkası: tüketilen / hedef (CircularProgressIndicator veya custom painter)
- Makro kartları: protein / karb / yağ (gram + hedef yüzdesi)
- Öğün grupları: kahvaltı / öğle / akşam / atıştırma (web'deki meal_type değerleriyle aynı string'ler)
- Su takibi: toplam ml + hızlı ekle butonları (+250ml vb., web'deki preset'lerle aynı)
- Kilo kartı: son kayıt + hızlı giriş dialogu
- Pull-to-refresh
- Alt navigasyon: `NavigationBar` (Material 3) — Dashboard / Ekle / Analitik / Chat / Ayarlar

## 4. Yemek Ekleme (`features/add/`) — `AddPage.tsx` karşılığı
- Arama çubuğu (debounce — web `useDebounce` karşılığı `Timer` ile)
- Sekmeler/listeler: **Arama sonuçları | Favoriler | Son yenilenler**
- Yemek kartı: isim, 100g başına besinler, porsiyon seçici (gram/adet, web'deki serving mantığı)
- Öğün tipi seçici → kaydet → dashboard'a dön + başarı SnackBar
- Sayfa üstünde AI aksiyonları için placeholder butonlar (Faz 4'te aktif): 📷 Fotoğraf, ⌨ Metinle tanı, ▦ Barkod

## 5. Provider'lar (`shared/providers/`)
- `selectedDateProvider` (StateProvider<DateTime>)
- `dailyDataProvider` — seçili günün tüm verisi (meal + water + weight + hedefler), web `useDailyData` karşılığı; ekleme/silme sonrası invalidate
- `favoriteFoodsProvider`, `recentFoodsProvider`

## Teslim kriterleri
- [ ] Gün değiştirme, öğün ekleme/silme, su ekleme, kilo girişi Android'de çalışıyor
- [ ] Web ile aynı hesapta: Flutter'da eklenen öğün web dashboard'unda görünüyor (ve tersi)
- [ ] Kalori/makro hesapları web ile birebir aynı sonucu veriyor (aynı gün için karşılaştır)
- [ ] Favorilere ekleme/çıkarma web ile senkron
- [ ] Unit test: DiaryRepository gün filtreleme + toplam hesapları
- [ ] `flutter test` yeşil
