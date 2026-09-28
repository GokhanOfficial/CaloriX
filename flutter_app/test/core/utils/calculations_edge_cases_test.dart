import 'package:calorix/core/constants/app_constants.dart';
import 'package:calorix/core/utils/calculations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Kenar durum testleri — mevcut `calculations_test.dart` nominal değerleri
/// (parity) doğruluyor; burada sıfır/negatif/aşırı girdilerin üretim
/// güvenliği denetleniyor.
void main() {
  group('Calculations.bmr — sıfır ve negatif girdi', () {
    test('0 kilo / 0 boy → minBmr\'a kırpılır (negatif BMR üretilmez)', () {
      // 10*0 + 6.25*0 - 5*30 = -150; erkek: -145, kadın: -311.
      // Ham sonuç negatif; `minBmr` (0) alt sınırı uygulanır — aksi
      // hâlde TDEE/goal hesapları çarpık değerlerle çalışırdı.
      expect(
        Calculations.bmr(weightKg: 0, heightCm: 0, age: 30, gender: Gender.male),
        Calculations.minBmr,
      );
      expect(
        Calculations.bmr(
          weightKg: 0,
          heightCm: 0,
          age: 30,
          gender: Gender.female,
        ),
        Calculations.minBmr,
      );
    });

    test('aşırı yaş BMR\'ı düşürür ama negatife indirmez', () {
      // 200 yaş: 800 + 1125 - 1000 + 5 = 930 (erkek, pozitif kalır).
      expect(
        Calculations.bmr(
          weightKg: 80,
          heightCm: 180,
          age: 200,
          gender: Gender.male,
        ),
        930,
      );
      // 200 yaş kadın: 800 + 1125 - 1000 - 161 = 764.
      expect(
        Calculations.bmr(
          weightKg: 80,
          heightCm: 180,
          age: 200,
          gender: Gender.female,
        ),
        764,
      );
    });

    test('negatif kilo negatif BMR üretir ama kırpılır', () {
      // -80 kg erkek: -800 + 1125 - 150 + 5 = 180 → pozitif.
      expect(
        Calculations.bmr(
          weightKg: -80,
          heightCm: 180,
          age: 30,
          gender: Gender.male,
        ),
        180,
      );
      // -200 kg, 0 boy, 200 yaş → kesin negatif → minBmr.
      expect(
        Calculations.bmr(
          weightKg: -200,
          heightCm: 0,
          age: 200,
          gender: Gender.male,
        ),
        Calculations.minBmr,
      );
    });

    test('sonuç daima minBmr üstündedir (dejenere girdi taraması)', () {
      final inputs = <(double, double, int)>[
        (0, 0, 0), (-1, -1, 500), (0, 0, 999), (-999, 0, 999),
      ];
      for (final (w, h, a) in inputs) {
        final bmr = Calculations.bmr(
          weightKg: w,
          heightCm: h,
          age: a,
          gender: Gender.male,
        );
        expect(bmr, greaterThanOrEqualTo(Calculations.minBmr));
      }
    });

    test('ondalık kayan değerler yuvarlanır (yarım yukarı)', () {
      // 70.7*10 = 707, 175*6.25 = 1093.75, -5*35 = -175 → 1625.75 + 5 = 1630.75
      // → 1631 (round yarımden büyüğe).
      expect(
        Calculations.bmr(
          weightKg: 70.7,
          heightCm: 175,
          age: 35,
          gender: Gender.male,
        ),
        1631,
      );
    });
  });

  group('Calculations.tdee — negatif BMR çarpanı', () {
    test('minBmr kırpmasından geçen değerler ile çalışır', () {
      // bmr() artık negatif döndürmediği için üretim akışında negatif
      // TDEE oluşmaz; yine de saf fonksiyon davranışı sabitlenir.
      expect(Calculations.tdee(Calculations.minBmr, ActivityLevel.sedentary), 0);
      expect(Calculations.tdee(2000, ActivityLevel.sedentary), 2400);
    });
  });

  group('Calculations.targetCalories — güvenlik sınırı', () {
    test('negatif TDEE bile 1200 tabanına çekilir', () {
      expect(Calculations.targetCalories(-500, Goal.maintain), 1200);
      expect(Calculations.targetCalories(-500, Goal.gain), 1200);
    });

    test('sınırın tam kendisi korunur (1200 dokunulmaz)', () {
      // 1700 - 500 = 1200 → 1200 (eşik dahil).
      expect(Calculations.targetCalories(1700, Goal.lose), 1200);
      // 1699 - 500 = 1199 → 1200'e yükseltilir.
      expect(Calculations.targetCalories(1699, Goal.lose), 1200);
    });
  });

  group('Calculations.macros — negatif calorie hedefi', () {
    test('negatif hedefte makro sıfırlanır (negatif gramaj üretilmez)', () {
      // Hedef zaten targetCalories ile ≥1200'e çekildiği için buraya
      // negatif değer ancak bozuk veriyle gelir; sıfır güvenli dönüştür.
      final m = Calculations.macros(-1000);
      expect(m.protein, 0);
      expect(m.carbs, 0);
      expect(m.fat, 0);
    });

    test('0 hedef sıfır verir', () {
      final m = Calculations.macros(0);
      expect(m.protein, 0);
      expect(m.carbs, 0);
      expect(m.fat, 0);
    });
  });

  group('Calculations.bmi — bölen sıfır', () {
    // `heightCm == 0` → 70/0 = Infinity; eski davranış
    // `(Infinity*10).round()` ile UnsupportedError fırlatıyordu.
    // `MacroCalculator.calculate` bu çağrıyı try bloğunun DIŞINDA
    // yaptığı için ekran düşüyordu. Artık 0.0 döner.
    test('0 boy istisna fırmlatmaz, 0.0 döner', () {
      expect(Calculations.bmi(70, 0), 0.0);
    });

    test('NaN/Infinity boy 0.0 döner', () {
      expect(Calculations.bmi(70, double.nan), 0.0);
      expect(Calculations.bmi(70, double.infinity), 0.0);
    });

    test('Infinity kilo 0.0 döner', () {
      expect(Calculations.bmi(double.infinity, 180), 0.0);
    });

    test('negatif boy 0.0 döner (fiziksel olarak imkânsız kayıt)', () {
      // Tur 6 düzeltmesi: eski davranış `-180 → hM²=3.24 → 70/3.24 = 21.6`
      // döndürüyordu, yani boyu **-180 cm** olan bir kayıt geçerli bir BMI
      // gibi görünüyordu. `heightCm <= 0` artık 0'a düşüyor.
      expect(Calculations.bmi(70, -180), 0.0);
      expect(Calculations.bmi(70, -1), 0.0);
    });

    test('NaN kilo 0.0 döner', () {
      expect(Calculations.bmi(double.nan, 180), 0.0);
    });

    test('0 kilo → 0.0 (bölen geçerli)', () {
      expect(Calculations.bmi(0, 180), 0.0);
    });

    test('sonuç asla NaN değildir (tüm girdiler)', () {
      for (final w in [0.0, -5.0, 70.0, double.nan, double.infinity]) {
        for (final h in [0.0, -180.0, 175.0, double.nan]) {
          expect(Calculations.bmi(w, h).isNaN, isFalse);
        }
      }
    });
  });

  group('Calculations.bmiCategory — uç değerler', () {
    test('negatif BMI → underweight', () {
      expect(Calculations.bmiCategory(-1).labelKey, 'bmi.underweight');
    });

    test('çok yüksek BMI → obese', () {
      expect(Calculations.bmiCategory(1000).labelKey, 'bmi.obese');
    });

    test('renk adları eşiklerle tutarlı', () {
      expect(Calculations.bmiCategory(10).color, 'info');
      expect(Calculations.bmiCategory(20).color, 'success');
      expect(Calculations.bmiCategory(27).color, 'warning');
      expect(Calculations.bmiCategory(35).color, 'destructive');
    });
  });

  group('Calculations.waterTargetMl — negatif kilo', () {
    test('negatif kilo 0\'a kırpılır (negatif ml hedefi gösterilmez)', () {
      // Tur 6 düzeltmesi: eski davranış `-330` döndürüyordu ve bu değer
      // profile yazılıp su ilerleme çubuğunda "−330 ml" olarak
      // gösterilebiliyordu. Negatif su hedefi fiziksel olarak anlamsızdır.
      expect(Calculations.waterTargetMl(-10), 0);
      expect(Calculations.waterTargetMl(0), 0);
    });

    test('NaN/Infinity kilo istisna fırlatmaz', () {
      // `.round()` NaN'da `UnsupportedError` fırlatıyordu; `MacroCalculator`
      // bunu `_safeInt` ile sarıyordu ama doğrudan çağıranlar
      // (`personal_info_dialog.dart` akışı) yakalanmayan hata alıyordu.
      expect(Calculations.waterTargetMl(double.nan), 0);
      expect(Calculations.waterTargetMl(double.infinity), 0);
    });
  });

  group('Calculations.progress — negatif hedef/negatif tüketim', () {
    test('negatif hedefte sonuç 0\'a kırpılır (negatif yüzde gösterilmez)', () {
      // 100/-50 = -200 ham oran; alt sınır 0.
      expect(Calculations.progress(100, -50), 0);
    });

    test('negatif tüketim 0\'a kırpılır', () {
      // -100/2000 = -5 → 0.
      expect(Calculations.progress(-100, 2000), 0);
    });

    test('tüketim hedefe eşit → 100', () {
      expect(Calculations.progress(2000, 2000), 100);
    });

    test('sonuç daima 0..100 aralığında', () {
      for (final c in [-500.0, 0.0, 500.0, 5000.0]) {
        for (final t in [-200.0, 0.0, 100.0, 2000.0]) {
          final p = Calculations.progress(c, t);
          expect(p, inInclusiveRange(0, 100));
        }
      }
    });
  });

  group('Calculations.age — gelecek doğum tarihi ve aşırı yaş', () {
    test('gelecek tarih 0\'a kırpılır (negatif yaş yok)', () {
      final now = DateTime.now();
      final future = DateTime(now.year + 5, now.month, now.day);
      expect(Calculations.age(future), 0);
    });

    test('aşırı yaş maxAge\'e kırpılır', () {
      final now = DateTime.now();
      final ancient = DateTime(now.year - 300, now.month, now.day);
      expect(Calculations.age(ancient), Calculations.maxAge);
    });

    test('bugün doğan → 0', () {
      final now = DateTime.now();
      expect(Calculations.age(now), 0);
    });

    test('sonuç daima 0..maxAge aralığında', () {
      final now = DateTime.now();
      for (final offset in [-500, -1, 0, 1, 30, 120, 121, 500]) {
        final age = Calculations.age(DateTime(now.year + offset, now.month, now.day));
        expect(age, inInclusiveRange(0, Calculations.maxAge));
      }
    });
  });

  group('enum çeviri anahtarları — karşılığı olan JSON anahtarı', () {
    // Bu anahtarlar doğrudan `.tr()` çağrısı olmadan (labelKey.tr()) kullanılır;
    // kaynak JSON'da karşılıkları olmadan UI'da ham anahtar görünür.
    test('ActivityLevel.labelKey', () {
      expect(
        ActivityLevel.values.map((e) => e.labelKey),
        containsAll([
          'settings.goals.activity.sedentary',
          'settings.goals.activity.light',
          'settings.goals.activity.moderate',
          'settings.goals.activity.active',
          'settings.goals.activity.very_active',
        ]),
      );
    });

    test('Goal/Gender/MealType labelKey önekleri tutarlı', () {
      for (final g in Goal.values) {
        expect(g.labelKey, startsWith('settings.goals.goal.'));
      }
      for (final g in Gender.values) {
        expect(g.labelKey, startsWith('settings.personalInfo.'));
      }
    });
  });

  group('AppConstants — sürüm/makro tutarlılığı', () {
    // NOT: `AppConstants.appVersion` (lib/core/constants/app_constants.dart)
    // pubspec ile ve `defaultFat` ile `Calculations.macros()` arasındaki
    // sapma `tool/check_versions.cjs` ile denetlenir. İkisi de
    // lib/core/** alanında (A3) olduğu için burada FAIL eden assertion
    // yazılmaz — sapma düzeltilene kadar bu blok yalnızca pozitif
    // değişmezleri doğrular. Ayrıntı: RAPOR-A6 AKTARIM bölümü.

    test('varsayılan hedefler pozitif', () {
      expect(AppConstants.defaultCalories, greaterThan(0));
      expect(AppConstants.defaultProtein, greaterThan(0));
      expect(AppConstants.defaultCarbs, greaterThan(0));
      expect(AppConstants.defaultFat, greaterThan(0));
      expect(AppConstants.defaultWater, greaterThan(0));
    });

    test('varsayılan protein/karb hedefleri hesaplanan değerle uyumlu', () {
      // 2000 kcal: P = 2000*0.30/4 = 150, C = 2000*0.40/4 = 200.
      final m = Calculations.macros(AppConstants.defaultCalories);
      expect(m.protein, AppConstants.defaultProtein);
      expect(m.carbs, AppConstants.defaultCarbs);
    });

    test('waterQuickAdd hedefin altında, pozitif ve artan sırada', () {
      final q = AppConstants.waterQuickAdd;
      expect(q, isNotEmpty);
      expect(q.every((v) => v > 0), isTrue);
      expect(q, orderedEquals([...q]..sort()));
      expect(q.last, lessThan(AppConstants.defaultWater));
    });

    test('updateManifestUrl resmi GitHub releases adresine işaret eder', () {
      expect(
        AppConstants.updateManifestUrl,
        startsWith('https://github.com/'),
      );
      expect(AppConstants.updateManifestUrl, endsWith('latest.json'));
    });
  });
}
