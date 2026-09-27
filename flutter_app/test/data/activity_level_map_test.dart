import 'package:calorix/core/constants/app_constants.dart';
import 'package:calorix/data/activity_level_map.dart';
import 'package:flutter_test/flutter_test.dart';

/// `ActivityLevel` ↔ `profiles.activity_level` sözleşmesinin birim testleri.
///
/// Sözleşme kaynağı **migration'daki CHECK kısıtıdır**, elle yazılmış bir
/// listeden değil:
///
/// ```sql
/// -- supabase/migrations/20260111041204_db829bb7-56ca-465d-bc88-c9fa6c7b3649.sql:39
/// activity_level TEXT CHECK (activity_level IN
///   ('sedentary','light','moderate','active','very_active'))
/// ```
///
/// Web karşılığı: `src/lib/constants.ts` → `activityLevelToDb` /
/// `activityLevelFromDb` (A5).
void main() {
  group('activityLevelToDb — enum değerleri CHECK kısıtına uyar', () {
    // Birebir tablo: Dart enum adı → DB dizesi.
    const expected = <ActivityLevel, String>{
      ActivityLevel.sedentary: 'sedentary',
      ActivityLevel.light: 'light',
      ActivityLevel.moderate: 'moderate',
      ActivityLevel.active: 'active',
      ActivityLevel.veryActive: 'very_active',
    };

    test('her enum degeri beklenen DB dizesine eslenir', () {
      for (final e in ActivityLevel.values) {
        expect(
          activityLevelToDb(e),
          expected[e],
          reason: '$e için DB değeri yanlış',
        );
      }
    });

    test('CHECK kisitindaki bes degerin tamami uretilebilir', () {
      final produced = ActivityLevel.values.map(activityLevelToDb).toSet();
      expect(produced, ActivityLevelMap.dbValueSet);
      expect(produced.length, 5);
    });

    test('camelCase enum adi ASLA DB degerine sizmaz (asil hata)', () {
      // `ActivityLevel.name` doğrudan gönderilirse CHECK ihlali olur.
      // 5 değerin 4'ü (`sedentary`…`active`) `.name` ile aynı; ayrımı
      // **yalnızca `veryActive` yaratır** — asıl hata o tek satırdır.
      for (final e in ActivityLevel.values) {
        final db = activityLevelToDb(e);
        expect(ActivityLevelMap.dbValueSet.contains(db), isTrue);
        expect(db, isNot(contains(RegExp(r'[A-Z]'))), reason: '$e icin buyuk harf sizdi');
      }
      expect(activityLevelToDb(ActivityLevel.veryActive), 'very_active');
      expect(
        activityLevelToDb(ActivityLevel.veryActive),
        isNot(ActivityLevel.veryActive.name),
        reason: '`.name` gönderilirse CHECK ihlali olur',
      );
    });
  });

  group('activityLevelFromDb — gidiş-dönüş (round-trip)', () {
    test('her enum degeri DB degerine yazilip geri okununca ayni deger doner', () {
      for (final e in ActivityLevel.values) {
        final db = activityLevelToDb(e);
        expect(
          activityLevelFromDb(db),
          e,
          reason: '$e round-trip kaybı: "$db" → farklı enum',
        );
      }
    });

    test('her DB degeri bir enum degerine eslenir', () {
      for (final db in ActivityLevelMap.dbValues) {
        expect(
          ActivityLevelMap.dbValueSet.contains(db),
          isTrue,
          reason: 'dbValues içindeki "$db" dbValueSet içinde değil',
        );
        // `moderate` fallback ile aynı değer olduğu için burada ayırt
        // edilemez; onun round-trip kanıtı yukarıdaki testte var.
        if (db == 'moderate') continue;
        expect(
          activityLevelFromDb(db),
          isNot(ActivityLevelMap.fallback),
          reason: '"$db" fallback\'e düştü — eşleme kaybı',
        );
      }
    });
  });

  group('küme bütünlüğü — kayıp/ekstra değer yok', () {
    test('ActivityLevel.values ile DB deger kumesi birebir eslesir', () {
      final fromEnum = ActivityLevel.values.map(activityLevelToDb).toSet();
      expect(
        fromEnum.difference(ActivityLevelMap.dbValueSet),
        isEmpty,
        reason: 'Enum’dan gelen ama DB kısıtında olmayan değer var',
      );
      expect(
        ActivityLevelMap.dbValueSet.difference(fromEnum),
        isEmpty,
        reason: 'DB kısıtında olup enum’dan üretilemeyen değer var',
      );
      expect(ActivityLevelMap.dbValues.length, fromEnum.length);
    });

    test('dbValues listesi kume ile ayni (tek kaynak tutarliligi)', () {
      expect(ActivityLevelMap.dbValues.toSet(), ActivityLevelMap.dbValueSet);
    });

    test('toDb her zaman CHECK kisiti icinde bir dize uretir', () {
      for (final e in ActivityLevel.values) {
        expect(
          ActivityLevelMap.dbValueSet.contains(activityLevelToDb(e)),
          isTrue,
        );
      }
    });
  });

  group('activityLevelFromDb — toleranslı davranış (çökmez)', () {
    test('null / bos dize / yalnizca bosluk → fallback', () {
      expect(activityLevelFromDb(null), ActivityLevel.moderate);
      expect(activityLevelFromDb(''), ActivityLevel.moderate);
      expect(activityLevelFromDb('   '), ActivityLevel.moderate);
    });

    test('DB degerinde tanimsiz degerler fallbacke duser (cokme yok)', () {
      for (final bogus in <Object>[
        'veryActive', // eski Flutter hatasının bıraktığı değer
        'VERY_ACTIVE',
        'extra_active',
        '0',
        'true',
        'Hareketsiz', // çeviri metni
        42,
        true,
        <String>['sedentary'],
      ]) {
        expect(
          activityLevelFromDb(bogus),
          ActivityLevel.moderate,
          reason: '$bogus fallback\'e düşmeli',
        );
      }
    });

    test('benzersiz tum girislerde istisna firlatmaz', () {
      final inputs = <Object?>[
        null,
        '',
        ' ',
        'very_active',
        'veryActive',
        '???',
        0,
        -1,
        double.nan,
        const <String, dynamic>{'a': 1},
        Object(),
      ];
      for (final i in inputs) {
        expect(
          () => activityLevelFromDb(i),
          returnsNormally,
          reason: '$i çökmeye yol açtı',
        );
      }
    });

    test('cevrimici (web) sozlesmesiyle ayni varsayilan kullanilir', () {
      // src/lib/constants.ts: activityLevelFromDb → 'moderate'
      expect(ActivityLevelMap.fallback, ActivityLevel.moderate);
    });
  });
}
