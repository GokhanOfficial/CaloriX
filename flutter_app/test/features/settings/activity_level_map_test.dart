import 'package:flutter_test/flutter_test.dart';

import 'package:calorix/core/constants/app_constants.dart';
import 'package:calorix/data/activity_level_map.dart';

/// Features tarafı (`onboarding_page`, `goals_dialog`, `personal_info_dialog`,
/// `weight_card`) `profiles.activity_level` alanını A2'nin tek doğruluk
/// kaynağından (`lib/data/activity_level_map.dart`) okuyup yazıyor.
///
/// DB CHECK kısıtı snake_case bekliyor, Dart enum adı camelCase:
/// `ActivityLevel.name` doğrudan yazılırsa "Çok Aktif" (`veryActive`)
/// seçimi CHECK ihlaliyle reddediliyor ve hedefler kaydedilmiyordu. Okuma
/// yönünde de hata vardı: `ActivityLevel.values.asNameMap()['very_active']`
/// `null` dönüp seviyeyi sessizce `moderate`'a düşürüyordu.
void main() {
  group('activityLevelToDb — DB CHECK listesine uygunluk', () {
    test('5 değerin tamamı DB sütununun kabul ettiği değerler', () {
      expect(activityLevelToDb(ActivityLevel.sedentary), 'sedentary');
      expect(activityLevelToDb(ActivityLevel.light), 'light');
      expect(activityLevelToDb(ActivityLevel.moderate), 'moderate');
      expect(activityLevelToDb(ActivityLevel.active), 'active');
      expect(activityLevelToDb(ActivityLevel.veryActive), 'very_active');
    });

    test('hiçbir enum değeri camelCase sızmıyor (regresyon)', () {
      for (final level in ActivityLevel.values) {
        expect(
          ActivityLevelMap.dbValueSet,
          contains(activityLevelToDb(level)),
          reason: '${level.name} DB tarafından reddedilir',
        );
        // Regresyon: `level.name` doğrudan yazılırsa `veryActive` gider.
        if (level == ActivityLevel.veryActive) {
          expect(level.name, isNot(activityLevelToDb(level)));
        }
      }
    });
  });

  group('activityLevelFromDb — okuma yönü', () {
    test('snake_case DB değerleri doğru enum\'a döner', () {
      expect(activityLevelFromDb('sedentary'), ActivityLevel.sedentary);
      expect(activityLevelFromDb('light'), ActivityLevel.light);
      expect(activityLevelFromDb('moderate'), ActivityLevel.moderate);
      expect(activityLevelFromDb('active'), ActivityLevel.active);
      expect(activityLevelFromDb('very_active'), ActivityLevel.veryActive);
    });

    test('null / boş / bilinmeyen → moderate (çökmez)', () {
      expect(activityLevelFromDb(null), ActivityLevel.moderate);
      expect(activityLevelFromDb(''), ActivityLevel.moderate);
      expect(activityLevelFromDb('extremely_active'), ActivityLevel.moderate);
    });

    test('eski hatalı okumanın sessiz kaybı kapatıldı', () {
      // `asNameMap()['very_active']` null dönüyordu → `moderate` fallback'i
      // tetikleniyor ve "Çok Aktif" kullanıcısı orta seviyeye düşüyordu.
      expect(ActivityLevel.values.asNameMap()['very_active'], isNull);
      expect(
        activityLevelFromDb('very_active'),
        isNot(ActivityLevel.moderate),
      );
    });
  });

  test('gidiş-dönüş: 5/5 enum için değişmez', () {
    for (final level in ActivityLevel.values) {
      expect(activityLevelFromDb(activityLevelToDb(level)), level);
    }
  });
}
