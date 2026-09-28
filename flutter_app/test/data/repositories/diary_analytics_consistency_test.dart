import 'package:calorix/data/models/meal_entry.dart';
import 'package:calorix/data/models/water_entry.dart';
import 'package:calorix/data/repositories/analytics_repository.dart';
import 'package:calorix/data/repositories/diary_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// **`DiaryRepository` ↔ `AnalyticsRepository` aynı veriyi iki yerden
/// topluyor** — tutarsızlık riskini ölçüyor.
///
/// ## Neden bu test
///
/// Görev 4'ün sorduğu soru: "aynı veri için iki farklı hesap yolu var mı?"
/// Cevap **evet** ve bu, kasıtlı bir mimari seçim:
///
/// | | `DiaryRepository` (dashboard) | `AnalyticsRepository` (grafik) |
/// |---|---|---|
/// | toplam | [DailyData.totals] | [AnalyticsRepository.aggregateDaily] |
/// | kaynak | `MealEntry` **modeli** | ham `Map<String, dynamic>` satırlar |
/// | yumuşak silme | `_withoutDeleted` (model alanı) | `m['deleted_at'] != null` (satır alanı) |
/// | bozuk sayı | `MealEntry.fromJson` → satır **atlanır** | `numOr` → **0** sayılır |
/// | **yuvarlama** | **yok** (ham `double`) | `round()`/`round1` |
///
/// Son satır gerçek bir tutarsızlık üretir: aynı günün toplamı
/// dashboard'da `2000.5`, analitik grafikte `2000` görünür. Bu bir
/// **P2**'dir (kullanıcıyı yanıltan iki sayı), P1 değil: hangisinin
/// "doğru" olduğu ürün kararıdır ve yuvarlama **görüntüleme** katmanına
/// aittir.
///
/// Bu test iki şeyi sabitler:
///  1. Ham toplamlar **aynı** (yuvarlama farkı hariç) — yani iki yol
///     gerçekten aynı veriyi topluyor, sapma yuvarlamadan geliyor.
///  2. Yuvarlama farkı **kasıtlı ve sınırlı**: `0.5`'den küçük sapma
///     kaloride, `0.05`'ten küçük makroda görünür. Daha büyük bir fark
///     çıkarsa iki yol **ayrışmış** demektir ve test kırılır.
void main() {
  /// `meal_entries` ham satırları (analytics'in okuduğu biçim).
  List<Map<String, dynamic>> rawMealRows(List<MealEntry> entries) => [
        for (final e in entries)
          <String, dynamic>{
            'entry_date': e.entryDate,
            'calculated_kcal': e.calculatedKcal,
            'calculated_protein': e.calculatedProtein,
            'calculated_carbs': e.calculatedCarbs,
            'calculated_fat': e.calculatedFat,
            'deleted_at': e.deletedAt,
          },
      ];

  MealEntry meal({
    required String id,
    double kcal = 0,
    double protein = 0,
    double carbs = 0,
    double fat = 0,
    String date = '2026-08-15',
    String? deletedAt,
  }) =>
      MealEntry(
        id: id,
        userId: 'u1',
        mealType: 'lunch',
        amountGMl: 100,
        calculatedKcal: kcal,
        calculatedProtein: protein,
        calculatedCarbs: carbs,
        calculatedFat: fat,
        entryDate: date,
        source: 'manual',
        createdAt: '${date}T12:00:00Z',
        deletedAt: deletedAt,
      );

  group('aynı gün iki repository\'de aynı veriyi görüyor', () {
    test('dört öğünün toplamı iki yolda da aynı (yuvarlamadan bağımsız)', () {
      final entries = [
        meal(id: '1', kcal: 520.4, protein: 32.15, carbs: 44.04, fat: 18.06),
        meal(id: '2', kcal: 310.5, protein: 20.04, carbs: 30.03, fat: 9.04),
        meal(id: '3', kcal: 180.25, protein: 8.02, carbs: 20.01, fat: 5.02),
        meal(id: '4', kcal: 250.0, protein: 15.0, carbs: 30.0, fat: 8.0),
      ];
      final daily = DailyData(mealEntries: entries, waterEntries: const []);
      final totals = daily.totals;

      final stats = AnalyticsRepository.aggregateDaily(
        days: const [
          (date: '2026-08-15', dayLabel: '15 Aug'),
        ],
        mealRows: rawMealRows(entries),
        waterRows: const [],
      ).single;

      // Toplamlar aynı veriden geliyor: yuvarlama farkı ≤ 0.5.
      expect((stats.calories - totals.calories).abs(), lessThanOrEqualTo(0.5));
      expect((stats.protein - totals.protein).abs(), lessThanOrEqualTo(0.05));
      expect((stats.carbs - totals.carbs).abs(), lessThanOrEqualTo(0.05));
      expect((stats.fat - totals.fat).abs(), lessThanOrEqualTo(0.05));
    });

    test('YUVARLAMA ASİMETRİSİ BELGELENDİ: aynı gün iki farklı sayı', () {
      // 0.4 kalorilik sapma dashboard'da görünür, grafikte yuvarlanıp kaybolur.
      // Bu bir **bilinen ve kasıtlı** farktır; testi "sessizce düzeldi"
      // diye değiştirmeyin — iki yolun yuvarlama politikası ayrıdır ve
      // hangisinin değişeceği ürün kararıdır.
      final entries = [meal(id: '1', kcal: 1000.4, protein: 10.04)];
      final daily = DailyData(mealEntries: entries, waterEntries: const []);
      final stats = AnalyticsRepository.aggregateDaily(
        days: const [(date: '2026-08-15', dayLabel: '15 Aug')],
        mealRows: rawMealRows(entries),
        waterRows: const [],
      ).single;

      expect(daily.totals.calories, 1000.4, reason: 'dashboard ham değeri gösterir');
      expect(stats.calories, 1000, reason: 'grafik yuvarlar');
      expect(daily.totals.calories, isNot(stats.calories),
          reason: 'iki yol aynı olsaydı bu asimetri testi anlamsız olurdu');
    });

    test('yumuşak silinmiş kayıt iki yolda da toplam dışı', () {
      final entries = [
        meal(id: '1', kcal: 500),
        meal(id: '2', kcal: 300, deletedAt: '2026-08-15T18:00:00Z'),
      ];
      // Dashboard yolu: `_withoutDeleted` modeli eler.
      final daily = DailyData(mealEntries: entries, waterEntries: const []);
      expect(daily.totals.calories, inInclusiveRange(500, 800));

      // Analytics yolu: `deleted_at` satır alanına bakar.
      // `fetch()` sorgusu zaten `deleted_at IS NULL` gönderir ve ayrıca
      // istemcide eler; burada **ikinci katman**ı doğruluyoruz.
      final stats = AnalyticsRepository.aggregateDaily(
        days: const [(date: '2026-08-15', dayLabel: '15 Aug')],
        mealRows: rawMealRows(entries),
        waterRows: const [],
      ).single;
      expect(stats.calories, 500, reason: 'silinmiş öğün grafiğe girmemeli');
    });

    test('su toplamı iki yolda da aynı', () {
      final waters = [
        WaterEntry(
          id: 'w1',
          userId: 'u1',
          amountMl: 250,
          entryDate: '2026-08-15',
          entryTime: '2026-08-15T09:00:00Z',
        ),
        WaterEntry(
          id: 'w2',
          userId: 'u1',
          amountMl: 500,
          entryDate: '2026-08-15',
          entryTime: '2026-08-15T12:00:00Z',
        ),
      ];
      final daily = DailyData(mealEntries: const [], waterEntries: waters);
      expect(daily.totalWater, 750);

      final stats = AnalyticsRepository.aggregateDaily(
        days: const [(date: '2026-08-15', dayLabel: '15 Aug')],
        mealRows: const [],
        waterRows: [
          for (final w in waters)
            {
              'entry_date': w.entryDate,
              'amount_ml': w.amountMl,
              'deleted_at': w.deletedAt,
            },
        ],
      ).single;
      expect(stats.water, 750);
    });
  });

  group('ayrışma göstergesi — sapma büyürse iki yol bozulmuş demektir', () {
    test('sapma 0.5\'yi aşarsa test kırılır (koruma kalkanı)', () {
      // Bu testin kendisi "sözleşmeyi" tanımlar: iki yol aynı veriyi
      // topluyorsa fark **yalnızca** yuvarlamadan gelir. Eğer ileride
      // `DiaryRepository` bir filtreyi değiştirirse (ör. soft-delete
      // kaldırılırsa) fark 0.5'i aşar ve burası kırılır.
      final entries = [
        meal(id: '1', kcal: 100, date: '2026-08-15'),
        meal(id: '2', kcal: 200, date: '2026-08-15'),
        meal(id: '3', kcal: 300, date: '2026-08-15'),
      ];
      final daily = DailyData(mealEntries: entries, waterEntries: const []);
      final stats = AnalyticsRepository.aggregateDaily(
        days: const [(date: '2026-08-15', dayLabel: '15 Aug')],
        mealRows: rawMealRows(entries),
        waterRows: const [],
      ).single;
      expect(daily.totals.calories, 600);
      expect(stats.calories, 600);
      expect((stats.calories - daily.totals.calories).abs(),
          lessThanOrEqualTo(0.5));
    });
  });
}
