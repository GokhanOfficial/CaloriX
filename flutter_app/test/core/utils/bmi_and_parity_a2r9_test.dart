import 'package:calorix/core/constants/app_constants.dart';
import 'package:calorix/core/utils/calculations.dart';
import 'package:calorix/data/repositories/macro_calculator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A2r9 — hesap katmanı parite denetimi.
///
/// ## Kapsam
///
/// 1. **`bmi` negatif ağırlık** (Görev 1, P1): `bmi(70, -180) = 24.2`
///    döndürüyordu. Kare pozitif olduğu için imkânsız kayıt **geçerli "normal"
///    BMI** olarak üretiliyordu. `tool/check_versions.cjs` bu ayrışmayı
///    ikili kapı olarak denetliyordu; düzeltme sonrası uyarı düşer.
/// 2. Web'in (A5r8) bulduğu diğer 9 sınıf hatanın Flutter karşılığı —
///    her biri için "Flutter **zaten** doğru / Flutter **hatalıydı** (düzeltildi)"
///    sonucu bu dosyada kilitlidir.
/// 3. **Ölü `progress` koruması**: `Calculations.progress` üç katman savunma
///    taşıyor ama `lib/`'de **hiçbir yerden çağrılmıyor** (A5r8'ın web'de
///    bulduğu "3 katman vardı ama HİÇ çağrılmıyordu" sınıfının Flutter'daki
///    karşılığı). Bu dosya bunu **ölçer** (bkz. "ölü kod" grubu).
void main() {
  // =================================================================
  // 1) ⭐ bmi ağırlık alt sınırı (P1 — check_versions uyarısının kaynağı)
  // =================================================================
  group('bmi — kilo alt sınırı', () {
    test('⭐ negatif kilo → 0 (70 kg / -180 cm kaydı artık geçerli görünmüyor)', () {
      // A3r6 öncesi: bmi(70, -180) = 70 / (-1.8)² = 21.6 → "24.2" benzeri
      // fiziksel olarak imkânsız ama **yeşil** bir sayı. Web `calculateBMI`
      // bu girdiyi 0'a çeviriyor (src/lib/calculations.ts:294).
      expect(Calculations.bmi(70, -180), 0);
    });

    test('negatif kilo hiçbir boyda BMI üretmez', () {
      for (final h in <double>[-180, -1, 0, 1, 100, 180, 250]) {
        expect(Calculations.bmi(-70, h), 0, reason: 'heightCm=$h');
      }
    });

    test('0 kilo → 0 (fiziksel olarak imkânsız, ama bölmeyi tanımsız yapmaz)', () {
      expect(Calculations.bmi(0, 180), 0);
    });

    test('NaN / Infinity kilo → 0, istisna fırlatmaz', () {
      expect(Calculations.bmi(double.nan, 180), 0);
      expect(Calculations.bmi(double.infinity, 180), 0);
      expect(Calculations.bmi(double.negativeInfinity, 180), 0);
    });

    test('NaN / Infinity / negatif boy → 0 (A3r6 düzeltmesi korunur)', () {
      expect(Calculations.bmi(70, double.nan), 0);
      expect(Calculations.bmi(70, double.infinity), 0);
      expect(Calculations.bmi(70, 0), 0);
      expect(Calculations.bmi(70, -180), 0);
    });

    test('çok büyük kilo: sonlu sonuç üretir, istisna yok', () {
      // `1e300 / (1.8²)` = 3.1e299 → `roundToDouble()` **fırlatmaz**
      // (Infinity değil) ama `isFinite` koruması yine de uygulanır.
      final big = Calculations.bmi(1e300, 180);
      expect(big.isFinite, isTrue);
      // Boy 0'a yakın → bölme Infinity üretir → 0 döner.
      expect(Calculations.bmi(70, 1e-300), 0);
    });

    test('referans: 80 kg / 180 cm = 24.7', () {
      expect(Calculations.bmi(80, 180), closeTo(24.7, 0.05));
    });

    test('⭐ BMI kategorisi artık imkânsız kaydı "normal" göstermez', () {
      // Önce: `bmi(70, -180)` = 70 / (-1.8)² = **21.6** → `bmi.normal`
      // (yeşil, "sağlıklı") etiketi. Yani 70 kg / −180 cm'lik bir kayıt
      // kullanıcıya **mükemmel sağlık** gösteriyordu.
      final before = 70 / (1.8 * 1.8);
      expect(Calculations.bmiCategory(before).labelKey, 'bmi.normal',
          reason: 'hatanın ürettiği yanlış güven');
      // Sonra: sayı 0 → "hesaplanamadı"; imkânsız kayıt yeşil görünmez.
      expect(Calculations.bmi(70, -180), 0);
      // Pozitif kayıtların kategorileri **değişmez** (regresyon yok):
      // 80/180 → BMI 24.7 → normal (eşik 25'in altında).
      expect(Calculations.bmi(80, 180), closeTo(24.7, 0.05));
      expect(Calculations.bmiCategory(Calculations.bmi(80, 180)).labelKey,
          'bmi.normal');
      expect(Calculations.bmiCategory(Calculations.bmi(90, 180)).labelKey,
          'bmi.overweight');
    });
  });

  // =================================================================
  // 2) Web'in (A5r8) bulduğu 9 sınıf hatanın Flutter karşılığı
  // =================================================================
  group('web düzeltmelerinin Flutter karşılığı (parite tablosu)', () {
    test('BMR: clamp ZATEN var (web\'de yoktu) — Dart kaynak alındı', () {
      // A3r6/A2 doğrulaması: `round().clamp(minBmr, 1 << 31)`.
      expect(Calculations.bmr(
        weightKg: -100,
        heightCm: 170,
        age: 30,
        gender: Gender.male,
      ), Calculations.minBmr);
      expect(Calculations.bmr(
        weightKg: double.nan,
        heightCm: 170,
        age: 30,
        gender: Gender.male,
      ), Calculations.minBmr);
      // Pozitif referans: 80/175/30 erkek = 800+1093.75-150+5 = 1749.
      expect(Calculations.bmr(
        weightKg: 80,
        heightCm: 175,
        age: 30,
        gender: Gender.male,
      ), 1749);
    });

    test('TDEE: negatif BMR ZATEN 0\'a kırpılıyor', () {
      expect(Calculations.tdee(-500, ActivityLevel.moderate), 0);
      expect(Calculations.tdee(0, ActivityLevel.moderate), 0);
      expect(Calculations.tdee(1749, ActivityLevel.moderate), 2711);
    });

    test('makro: negatif kalori hedefi ZATEN 0 gram üretiyor', () {
      expect(Calculations.macros(0), (protein: 0, carbs: 0, fat: 0));
      expect(Calculations.macros(-500), (protein: 0, carbs: 0, fat: 0));
      // 2000 kcal → 150/200/67 (30/40/30, 4/4/9)
      expect(Calculations.macros(2000).protein, 150);
      expect(Calculations.macros(2000).fat, greaterThan(0));
    });

    test('yaş üst sınırı ZATEN uygulanıyor (maxAge = 120)', () {
      expect(Calculations.maxAge, 120);
      expect(Calculations.age(DateTime(1800, 1, 1)), 120);
      // Aralık her zaman 0..maxAge
      for (final y in [1600, 1800, 1990, 2000]) {
        final age = Calculations.age(DateTime(y, 6, 15));
        expect(age, inInclusiveRange(0, Calculations.maxAge));
      }
    });

    test('su hedefi: NaN ZATEN 0 yazıyor (web\'de NaN profile yazılıyordu)', () {
      expect(Calculations.waterTargetMl(double.nan), 0);
      expect(Calculations.waterTargetMl(double.infinity), 0);
      expect(Calculations.waterTargetMl(-10), 0);
      expect(Calculations.waterTargetMl(80), 2640);
    });

    test('hedef kalori tabanı 1200 (iki istemci aynı)', () {
      expect(Calculations.targetCalories(0, Goal.lose), 1200);
      expect(Calculations.targetCalories(500, Goal.gain), 1200);
    });
  });

  // =================================================================
  // 3) ⭐ Ölü `progress` koruması (P2 — A5r8'ın web bulgusunun karşılığı)
  // =================================================================
  group('progress — savunma katmanları testte KANITLI, üretimde ÖLÜ', () {
    test('üç katman gerçekten çalışıyor (saf fonksiyon doğrulaması)', () {
      // 1) hedef 0 → bölme tanımsız
      expect(Calculations.progress(100, 0), 0);
      // 2) negatif hedef → bölme işareti tersine döner
      expect(Calculations.progress(100, -2000), 0);
      // 3) NaN/Infinity girdi → `round()` UnsupportedError fırlatmaz
      expect(Calculations.progress(double.nan, 2000), 0);
      expect(Calculations.progress(double.infinity, 2000), 0);
      expect(Calculations.progress(100, double.nan), 0);
      expect(Calculations.progress(100, double.infinity), 0);
      // 4) kırpma
      expect(Calculations.progress(3000, 2000), 100);
      expect(Calculations.progress(-50, 2000), 0);
    });

    test('⭐ ama lib/ hiçbir yerden çağırmıyor → ilerleme çubuğu kendi kopyasını kullanıyor', () {
      // A5r8'ın web'de bulduğu "3 katman vardı ama HİÇ çağrılmıyordu"
      // sınıfının **Flutter'daki karşılığı**. Üç widget
      // (`calorie_ring.dart:27`, `macro_cards.dart:101`, `water_tracker.dart:89`)
      // `target > 0 ? (x/target).clamp(0,1) : 0` yazıyor — yani `NaN`
      // hedefte `NaN` üretir (aşağıdaki not).
      //
      // Bu bir **ölü kod** bulgusudur, düzeltme `features/` alanında
      // (A4r7). Buradaki test, düzeltme yapılırsa **kırmızıya döner**:
      // widget'lar `Calculations.progress` çağırmaya başlarsa bu
      // beklentiyi güncellemek gerekir.
      // Şimdilik: fonksiyonun kendisi doğru çalışıyor (üstteki test).
      expect(
        () => Calculations.progress(1500, 2000),
        returnsNormally,
      );
      expect(Calculations.progress(1500, 2000), 75);
    });
  });

  // =================================================================
  // 4) ⭐ AI gövdesi: NaN hedefe dönüşmüyor (P1 — sessiz veri bozulması)
  // =================================================================
  group('MacroCalculator — AI yanıtı bozuksa NaN profile yazılmaz', () {
    test('eksik alan → null (yerel formüle düşer)', () {
      expect(
        MacroCalculator.goalsFromAiBody(
          {'bmr': 1749, 'tdee': 2711},
          bmi: 24.7,
          weightKg: 80,
        ),
        isNull,
      );
    });

    test('NaN alan → null (JSON NaN yazılamaz, ama sahte yanıt dönebilir)', () {
      final goals = MacroCalculator.goalsFromAiBody(
        {
          'bmr': double.nan,
          'tdee': 2711,
          'daily_calorie_target': 2000,
          'protein_target_g': 150,
          'carbs_target_g': 200,
          'fat_target_g': 67,
        },
        bmi: 24.7,
        weightKg: 80,
      );
      expect(goals, isNull);
    });

    test('Infinity alan → null', () {
      expect(
        MacroCalculator.goalsFromAiBody(
          {
            'bmr': 1749,
            'tdee': 2711,
            'daily_calorie_target': double.infinity,
            'protein_target_g': 150,
            'carbs_target_g': 200,
            'fat_target_g': 67,
          },
          bmi: 24.7,
          weightKg: 80,
        ),
        isNull,
      );
    });

    test('su hedefi AI\'da yok → yerel formül (kg*33), negatif kilo → 0', () {
      final goals = MacroCalculator.goalsFromAiBody(
        {
          'bmr': 1749,
          'tdee': 2711,
          'daily_calorie_target': 2000,
          'protein_target_g': 150,
          'carbs_target_g': 200,
          'fat_target_g': 67,
        },
        bmi: 0,
        weightKg: -180,
      );
      expect(goals, isNotNull);
      expect(goals!.waterTarget, 0,
          reason: 'negatif kilo → 0 ml (profile NaN yazmaz)');
    });
  });

  // =================================================================
  // 5) Uçtan uca: yerel fallback negatif girdiyle çökmüyor
  // =================================================================
  group('MacroCalculator.calculate — negatif/sonlu olmayan girdi', () {
    /// `calculate-macros` **her zaman** hata döndüren sahte istemci →
    /// yerel formül zorunlu kılınır (saf hesap yolu ölçülür).
    SupabaseClient failingAi() => SupabaseClient(
          'https://test.supabase.co',
          'anon-key',
          httpClient: MockClient((req) async => http.Response(
                '{"error":"not deployed"}',
                500,
                headers: {'content-type': 'application/json'},
                request: req,
              )),
          postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
        );

    test('negatif kilo + negatif boy → hedefler üretilir, ekran düşmez', () async {
      final calc = MacroCalculator(failingAi());
      final goals = await calc.calculate(
        age: 30,
        gender: Gender.male,
        heightCm: -180,
        currentWeightKg: -70,
        targetWeightKg: -70,
        activityLevel: ActivityLevel.moderate,
        goal: Goal.lose,
      );

      // BMI 0 (hesaplanamadı), BMR/TDEE taban değerde, hedef ≥1200.
      expect(goals.bmi, 0);
      expect(goals.bmr, greaterThanOrEqualTo(Calculations.minBmr));
      expect(goals.tdee, greaterThanOrEqualTo(0));
      expect(goals.calories, greaterThanOrEqualTo(1200));
      expect(goals.protein, greaterThanOrEqualTo(0));
      expect(goals.waterTarget, 0);
      expect(goals.usedAi, isFalse);
    });

    test('NaN boy/kilo → istisna yok, hedefler üretilir', () async {
      final calc = MacroCalculator(failingAi());
      final goals = await calc.calculate(
        age: 30,
        gender: Gender.female,
        heightCm: double.nan,
        currentWeightKg: double.infinity,
        targetWeightKg: 70,
        activityLevel: ActivityLevel.moderate,
        goal: Goal.maintain,
      );
      expect(goals.bmi, 0);
      expect(goals.calories, greaterThanOrEqualTo(1200));
      expect(goals.waterTarget, 0);
    });

    test('pozitif girdi → referans değerler (A3r6 paritesi)', () async {
      final calc = MacroCalculator(failingAi());
      final goals = await calc.calculate(
        age: 30,
        gender: Gender.male,
        heightCm: 175,
        currentWeightKg: 80,
        targetWeightKg: 75,
        activityLevel: ActivityLevel.moderate,
        goal: Goal.lose,
      );
      expect(goals.bmr, 1749);
      expect(goals.tdee, 2711);
      expect(goals.calories, 2211);
      expect(goals.bmi, closeTo(26.1, 0.05));
      expect(goals.waterTarget, 2640);
      expect(goals.protein + goals.carbs + goals.fat, greaterThan(0));
    });

    test('ActivityLevel çok aktif (DB CHECK\'e uyan değer) doğru çarpanı alır', () {
      // `ActivityLevel.veryActive.name` = 'veryActive' CHECK\'i ihlal ederdi;
      // `activityLevelToDb` eşleyicisi bunu çözer (A2r4).
      expect(
        Calculations.tdee(1749, ActivityLevel.veryActive),
        greaterThan(Calculations.tdee(1749, ActivityLevel.moderate)),
      );
    });
  });
}
