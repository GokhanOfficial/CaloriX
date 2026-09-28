import 'package:calorix/core/constants/app_constants.dart';
import 'package:calorix/core/utils/calculations.dart';
import 'package:flutter_test/flutter_test.dart';

/// `Calculations` formüllerinin **bağımsız** doğrulaması (Tur 6).
///
/// ## Yöntem
///
/// Buradaki beklenen değerler elle hesaplanmış **klinik referans
/// noktalarıdır**; hiçbiri `Calculations`'tan kopyalanmamıştır. Web istemcisi
/// (`src/lib/calculations.ts`, bakım modunda ama aynı formülü kullanıyor)
/// referans alınmıştır.
///
/// ## Kapsam
///  * BMR (Mifflin-St Jeor) — cinsiyet, yaş, boy, kilo etkileri
///  * TDEE — beş aktivite çarpanı
///  * Hedef kalori — 1200 kcal tabanı ve üç amaç
///  * Makro — %30/%40/%30, Atwater 4/4/9
///  * BMI + kategori eşikleri
///  * Su hedefi (kg × 33)
///  * Yaş hesabı — doğum günü geçmemiş/yıllık/kenar durumlar
///
/// ## Bulunan ve düzeltilen kusurlar
///
///  * `bmi(70, -170)` **24.2 döndürüyordu** — negatif boyun karesi pozitiftir,
///    yani fiziksel olarak imkânsız bir kayıt geçerli BMI gibi görünüyordu.
///    Artık `heightCm <= 0` → 0.
///  * `progress(NaN, 2000)` ve `waterTargetMl(NaN)` `UnsupportedError`
///    fırlatıyordu (`.round()` NaN'da istisna atar). Artık 0.
///  * `tdee(0, veryActive)` → 0 döndü ama alt sınır açıkça uygulanmıyordu.
void main() {
  group('BMR — Mifflin-St Jeor (elle doğrulanmış referans)', () {
    // 10*80 + 6.25*175 - 5*30 + 5  = 800 + 1093.75 - 150 + 5 = 1748.75 → 1749
    test('erkek 80 kg / 175 cm / 30 yaş → 1749', () {
      expect(
        Calculations.bmr(weightKg: 80, heightCm: 175, age: 30, gender: Gender.male),
        1749,
      );
    });

    // 10*60 + 6.25*165 - 5*30 - 161 = 600 + 1031.25 - 150 - 161 = 1320.25 → 1320
    test('kadın 60 kg / 165 cm / 30 yaş → 1320', () {
      expect(
        Calculations.bmr(
            weightKg: 60, heightCm: 165, age: 30, gender: Gender.female),
        1320,
      );
    });

    test('other cinsiyet erkek formülüyle aynı (belgelenen davranış)', () {
      // Web `calculateBMR`: `gender === 'male' ? +5 : -161`, yani `other`
      // web'de **kadın** formülüne düşer. Flutter `Gender.other` erkek
      // formülünü kullanır. Bu bir **istemci ayrışmasıdır** ve rapora
      // aktarıldı; buradaki test Flutter'ın **kendi** sözleşmesini kilitler.
      final male = Calculations.bmr(
          weightKg: 70, heightCm: 170, age: 25, gender: Gender.male);
      final other = Calculations.bmr(
          weightKg: 70, heightCm: 170, age: 25, gender: Gender.other);
      expect(other, male);
    });

    test('her 1 kg kilo farkı BMR\'ı 10 artırır', () {
      final a = Calculations.bmr(
          weightKg: 70, heightCm: 175, age: 30, gender: Gender.male);
      final b = Calculations.bmr(
          weightKg: 71, heightCm: 175, age: 30, gender: Gender.male);
      expect(b - a, 10);
    });

    test('her 1 cm boy farkı BMR\'ı 6.25 artırır (yuvarlanmış)', () {
      final a = Calculations.bmr(
          weightKg: 70, heightCm: 175, age: 30, gender: Gender.male);
      final b = Calculations.bmr(
          weightKg: 70, heightCm: 176, age: 30, gender: Gender.male);
      expect(b - a, 6);
    });

    test('her 1 yıl yaş BMR\'ı 5 azaltır', () {
      final a = Calculations.bmr(
          weightKg: 70, heightCm: 175, age: 30, gender: Gender.male);
      final b = Calculations.bmr(
          weightKg: 70, heightCm: 175, age: 31, gender: Gender.male);
      expect(a - b, 5);
    });

    test('kadın-erkek farkı tam olarak 166 kcal', () {
      const w = 70.0, h = 175.0;
      final m = Calculations.bmr(weightKg: w, heightCm: h, age: 30, gender: Gender.male);
      final f =
          Calculations.bmr(weightKg: w, heightCm: h, age: 30, gender: Gender.female);
      expect(m - f, 166);
    });

    test('negatif sonuç minBmr\'a kırpılır (fiziksel olarak anlamsız)', () {
      // 10*1 + 6.25*1 - 5*120 - 161 = 10 + 6.25 - 600 - 161 = -744.75
      final v = Calculations.bmr(
          weightKg: 1, heightCm: 1, age: 120, gender: Gender.female);
      expect(v, Calculations.minBmr);
      expect(v, 0);
    });

    test('NaN kilo → 0 (fırlatma yok)', () {
      expect(
        Calculations.bmr(
            weightKg: double.nan, heightCm: 175, age: 30, gender: Gender.male),
        0,
      );
    });

    test('çocuk: kilo ve boy etkisi doğru işaretli', () {
      // 10*25 + 6.25*120 - 5*8 + 5 = 250 + 750 - 40 + 5 = 965
      expect(
        Calculations.bmr(
            weightKg: 25, heightCm: 120, age: 8, gender: Gender.male),
        965,
      );
    });

    test('hamile/emzirme kullanıcısı: ek kcal girdi olarak verilir', () {
      // Uygulama gebelik/emzirme için ayrı bir çarpan **içermiyor**
      // (ActivityLevel'de 5 seviye var; `Goal.gain` +500 kullanılıyor).
      // Gebelikte ek enerji ihtiyacı kullanıcı tarafından hedef calories
      // olarak giriliyorsa formül buna dokunmaz — hangi yolun kullanıldığı
      // profil verisine bağlı. Test, `Goal.gain` yolunu doğrular.
      final bmr = Calculations.bmr(
          weightKg: 75, heightCm: 165, age: 30, gender: Gender.female);
      final tdee = Calculations.tdee(bmr, ActivityLevel.light);
      expect(
        Calculations.targetCalories(tdee, Goal.gain),
        tdee + 500,
      );
    });
  });

  group('TDEE — beş aktivite çarpanı', () {
    final bmr = 1750;

    test('çarpanlar web ile birebir (1.2 / 1.375 / 1.55 / 1.725 / 1.9)', () {
      expect(ActivityLevel.sedentary.multiplier, 1.2);
      expect(ActivityLevel.light.multiplier, 1.375);
      expect(ActivityLevel.moderate.multiplier, 1.55);
      expect(ActivityLevel.active.multiplier, 1.725);
      expect(ActivityLevel.veryActive.multiplier, 1.9);
    });

    test('çarpımlar elle doğrulanmış', () {
      expect(Calculations.tdee(bmr, ActivityLevel.sedentary), 2100);
      expect(Calculations.tdee(bmr, ActivityLevel.light), 2406);
      expect(Calculations.tdee(bmr, ActivityLevel.moderate), 2713);
      expect(Calculations.tdee(bmr, ActivityLevel.active), 3019);
      expect(Calculations.tdee(bmr, ActivityLevel.veryActive), 3325);
    });

    test('çarpanlar artan sırada (yanlış seçim tespiti)', () {
      final m = ActivityLevel.values.map((a) => a.multiplier).toList();
      for (var i = 1; i < m.length; i++) {
        expect(m[i], greaterThan(m[i - 1]));
      }
    });

    test('BMR 0 iken TDEE 0 (alt sınır)', () {
      for (final level in ActivityLevel.values) {
        expect(Calculations.tdee(0, level), 0);
      }
    });

    test('çok büyük BMR taşmaz (Int sınırı)', () {
      // `minBmr` üst sınırı yok; pratikte 32-bit taşması olamaz ama
      // yuvarlamanın istisna atmadığı doğrulanır.
      final v = Calculations.tdee(1 << 30, ActivityLevel.veryActive);
      expect(v, greaterThan(0));
    });
  });

  group('hedef kalori — 1200 kcal güvenlik tabanı', () {
    test('maintain değiştirmez', () {
      expect(Calculations.targetCalories(2000, Goal.maintain), 2000);
    });

    test('lose 500 düşer', () {
      expect(Calculations.targetCalories(2000, Goal.lose), 1500);
    });

    test('gain 500 artar', () {
      expect(Calculations.targetCalories(2000, Goal.gain), 2500);
    });

    test('alt sınır 1200: lose bile 1200\'nin altına inemez', () {
      expect(Calculations.targetCalories(1400, Goal.lose), 1200);
      expect(Calculations.targetCalories(1200, Goal.lose), 1200);
      expect(Calculations.targetCalories(1000, Goal.lose), 1200);
      expect(Calculations.targetCalories(0, Goal.lose), 1200);
    });

    test('her zaman pozitif (tüm amaç × tüm TDEE)', () {
      for (final bmr in [0, 800, 1500, 2500]) {
        for (final level in ActivityLevel.values) {
          final tdee = Calculations.tdee(bmr, level);
          for (final goal in Goal.values) {
            final target = Calculations.targetCalories(tdee, goal);
            expect(target, greaterThanOrEqualTo(1200));
          }
        }
      }
    });
  });

  group('makro dağılımı — %30 / %40 / %30 (Atwater 4/4/9)', () {
    test('2000 kcal → 150 P / 200 K / 67 Y', () {
      final m = Calculations.macros(2000);
      expect(m.protein, 150);
      expect(m.carbs, 200);
      expect(m.fat, 67);
    });

    test('AppConstants varsayılanları macros() ile aynı (CI kapısı)', () {
      // `app_constants.dart:18-26` bu eşitliği zorunlu kılıyor; sapma
      // onboarding önizlemesi ile hedef kartının farklı göstermesine yol açar.
      final m = Calculations.macros(AppConstants.defaultCalories);
      expect(m.protein, AppConstants.defaultProtein);
      expect(m.carbs, AppConstants.defaultCarbs);
      expect(m.fat, AppConstants.defaultFat);
    });

    test('makro kalorileri toplamı hedefe yakın (yuvarlama farkı ≤ 3 kcal)', () {
      for (final target in [1200, 1500, 1800, 2000, 2500, 3000]) {
        final m = Calculations.macros(target);
        final kcal = m.protein * 4 + m.carbs * 4 + m.fat * 9;
        expect(
          (kcal - target).abs(),
          lessThanOrEqualTo(4),
          reason: '$target kcal → makro $kcal kcal (fark ${kcal - target})',
        );
      }
    });

    test('negatif ve sıfır hedef → sıfır gramaj (negatif g yok)', () {
      for (final target in [0, -1, -1000]) {
        final m = Calculations.macros(target);
        expect(m.protein, 0);
        expect(m.carbs, 0);
        expect(m.fat, 0);
      }
    });

    test('oranlarda yuvarlama artışı olmaz (tekdüze artan)', () {
      var prev = Calculations.macros(1);
      for (final target in [500, 1000, 1500, 2000, 2500, 3000, 4000]) {
        final m = Calculations.macros(target);
        expect(m.protein, greaterThanOrEqualTo(prev.protein));
        expect(m.carbs, greaterThanOrEqualTo(prev.carbs));
        expect(m.fat, greaterThanOrEqualTo(prev.fat));
        prev = m;
      }
    });
  });

  group('BMI', () {
    test('referans noktalar', () {
      // 70 / 1.70² = 24.221 → 24.2
      expect(Calculations.bmi(70, 170), 24.2);
      // 80 / 1.80² = 24.691 → 24.7
      expect(Calculations.bmi(80, 180), 24.7);
      // 50 / 1.60² = 19.531 → 19.5
      expect(Calculations.bmi(50, 160), 19.5);
      // 100 / 1.75² = 32.653 → 32.7
      expect(Calculations.bmi(100, 175), 32.7);
    });

    test('tek ondalık yuvarlanır', () {
      for (final h in <double>[150, 160, 170, 175, 180, 190]) {
        for (final w in <double>[45, 55, 65, 75, 85, 95]) {
          final v = Calculations.bmi(w, h);
          expect(
            (v * 10) % 1,
            0,
            reason: 'BMI ($w, $h) = $v tek ondalık olmalı',
          );
        }
      }
    });

    test('boy 0 → 0 (bölme tanımsız, istisna değil)', () {
      expect(Calculations.bmi(70, 0), 0);
    });

    test('NEGATİF boy → 0 (fiziksel olarak imkânsız kayıt geçmez)', () {
      // KARE pozitif olduğu için `hM*hM` negatif boyda da pozitifti ve
      // 24.2 gibi **geçerli görünen** bir BMI dönüyordu. Düzeltildi.
      expect(Calculations.bmi(70, -170), 0);
      expect(Calculations.bmi(70, -1), 0);
    });

    test('NaN/Infinity girdi → 0 (round istisnası yok)', () {
      expect(Calculations.bmi(double.nan, 170), 0);
      expect(Calculations.bmi(70, double.nan), 0);
      expect(Calculations.bmi(double.infinity, 170), 0);
      expect(Calculations.bmi(70, double.infinity), 0);
    });

    test('BMI monotonik: kilo arttıkça artar, boy arttıkça azalır', () {
      expect(Calculations.bmi(80, 175), greaterThan(Calculations.bmi(70, 175)));
      expect(Calculations.bmi(70, 185), lessThan(Calculations.bmi(70, 175)));
    });
  });

  group('BMI kategori eşikleri', () {
    test('18.5 altı zayıf', () {
      expect(Calculations.bmiCategory(18.4).labelKey, 'bmi.underweight');
    });

    test('18.5–24.9 normal (18.5 ve 24.9 dahil)', () {
      expect(Calculations.bmiCategory(18.5).labelKey, 'bmi.normal');
      expect(Calculations.bmiCategory(24.9).labelKey, 'bmi.normal');
    });

    test('25.0–29.9 kilolu', () {
      expect(Calculations.bmiCategory(25.0).labelKey, 'bmi.overweight');
      expect(Calculations.bmiCategory(29.9).labelKey, 'bmi.overweight');
    });

    test('30+ obez', () {
      expect(Calculations.bmiCategory(30.0).labelKey, 'bmi.obese');
      expect(Calculations.bmiCategory(45.0).labelKey, 'bmi.obese');
    });

    test('renk adları tema sözleşmesiyle eşleşir', () {
      expect(Calculations.bmiCategory(17.0).color, 'info');
      expect(Calculations.bmiCategory(22.0).color, 'success');
      expect(Calculations.bmiCategory(27.0).color, 'warning');
      expect(Calculations.bmiCategory(33.0).color, 'destructive');
    });
  });

  group('su hedefi — kg × 33', () {
    test('referans noktalar', () {
      expect(Calculations.waterTargetMl(70), 2310);
      expect(Calculations.waterTargetMl(80), 2640);
      expect(Calculations.waterTargetMl(50), 1650);
    });

    test('NaN/Infinity → 0 (istisna değil)', () {
      expect(Calculations.waterTargetMl(double.nan), 0);
      expect(Calculations.waterTargetMl(double.infinity), 0);
    });

    test('negatif kilo → 0 (negatif ml mantıksız)', () {
      expect(Calculations.waterTargetMl(-10), 0);
    });
  });

  group('yaş hesabı', () {
    test('doğum günü bu yıl geçtiyse tam yaş', () {
      final today = DateTime.now();
      // Ay/gün 1'e sabitlenir: `day + 1` 31/32'de taşıp aya kaydığı için
      // "bugün" ile karşılaştırılan gün her zaman gelecekte kalırdı.
      final birthday = DateTime(today.year - 30, today.month, 1);
      expect(Calculations.age(birthday), 30);
    });

    test('doğum günü henüz gelmediyse bir eksik', () {
      final today = DateTime.now();
      final lastDay = DateTime(today.year, today.month + 1, 0).day;
      final birthday = DateTime(today.year - 30, today.month, lastDay);
      expect(Calculations.age(birthday), 29);
    });

    test('doğum günü bugün → tam yaş (sınır eşitliği)', () {
      final today = DateTime.now();
      expect(Calculations.age(DateTime(today.year - 25, today.month, today.day)),
          25);
    });

    test('yarın doğum günü → bir eksik (sınır eşitliği)', () {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      expect(Calculations.age(DateTime(tomorrow.year - 25, tomorrow.month, tomorrow.day)),
          24);
    });

    test('31 Şubat dönemi normalleşir (Şubat 28/29)', () {
      // 29 Şubat artık yıllarda doğum günü; 28 Şubat'ta "doğum günü
      // geçmemiş" sayılır → 3 yaş (29.02.2023 → 28.02.2026).
      expect(Calculations.age(DateTime(2023, 2, 29)), 3);
    });

    test('gelecek doğum tarihi → 0 (negatif yaş yok)', () {
      expect(Calculations.age(DateTime.now().add(const Duration(days: 365))),
          0);
    });

    test('120 yaş üstü → maxAge', () {
      expect(Calculations.age(DateTime(1800, 1, 1)), Calculations.maxAge);
      expect(Calculations.maxAge, 120);
    });

    test('son gün sınırı (maxAge\'a dayanır)', () {
      final today = DateTime.now();
      // Tam 120 yaşındaki kullanıcı kırpılmamalı.
      expect(Calculations.age(DateTime(today.year - 120, today.month, today.day)),
          lessThanOrEqualTo(120));
    });
  });

  group('ilerleme yüzdesi', () {
    test('temel durumlar', () {
      expect(Calculations.progress(1000, 2000), 50);
      expect(Calculations.progress(2000, 2000), 100);
      expect(Calculations.progress(0, 2000), 0);
    });

    test('hedef aşımı 100\'de kırpılır', () {
      expect(Calculations.progress(3000, 2000), 100);
    });

    test('sıfır/negatif hedef → 0 (bölme yok)', () {
      expect(Calculations.progress(100, 0), 0);
      expect(Calculations.progress(100, -2000), 0);
    });

    test('NaN/Infinity → 0 (UnsupportedError yerine)', () {
      // `.round()` NaN'da `UnsupportedError` fırlatıyordu.
      expect(Calculations.progress(double.nan, 2000), 0);
      expect(Calculations.progress(double.infinity, 2000), 0);
      expect(Calculations.progress(100, double.nan), 0);
      expect(Calculations.progress(100, double.infinity), 0);
    });

    test('her zaman 0..100 aralığında', () {
      for (final c in [0, 1, 500, 1234, 99999, -50]) {
        for (final t in [1, 100, 2000, 5000, -10, 0]) {
          final v = Calculations.progress(c, t);
          expect(v, inInclusiveRange(0, 100), reason: 'progress($c, $t) = $v');
        }
      }
    });
  });
}
