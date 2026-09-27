import 'package:calorix/core/constants/app_constants.dart';
import 'package:calorix/data/repositories/data_transfer_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Yedek içe aktarımında **beyaz liste** sözleşmesi.
///
/// `_stripIds` (kaldırıldı) **kara liste** uyguluyordu: yedekte tanınmayan
/// her kolon (`barcode`, `last_synced_at`, `sync_state`, `client_id`, eski web
/// istemcisinin eklediği alanlar) insert'e gönderilir ve PostgREST
/// `PGRST204` ile 400 döner. `importData` satır satır yazdığı için tek bozuk
/// kolon **tüm içe aktarmayı** durduruyordu ve kullanıcı yedeğin hiçbir
/// kısmını geri alamıyordu.
void main() {
  group('sanitizeFood — yalnız şema kolonları gönderilir', () {
    test('tanınmayan kolonlar düşürülür (PGRST204 koruması)', () {
      final out = DataTransferRepository.sanitizeFood({
        'id': 'f1',
        'name': 'Ev yapımı köfte',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
        'last_synced_at': '2026-01-01T00:00:00Z',
        'barcode': '8690504012345',
        'sync_state': 'synced',
        'client_id': 'abc',
        'dietary_fiber_g': 3.2,
      });
      expect(out.containsKey('id'), isFalse);
      expect(out.containsKey('created_at'), isFalse);
      expect(out.containsKey('updated_at'), isFalse);
      expect(out.containsKey('last_synced_at'), isFalse);
      expect(out.containsKey('barcode'), isFalse,
          reason: 'barcode kolonu 20260822000000 migration\'ıyla düşürüldü');
      expect(out.containsKey('sync_state'), isFalse);
      expect(out.containsKey('client_id'), isFalse);
      expect(out.containsKey('dietary_fiber_g'), isFalse);
      expect(out['name'], 'Ev yapımı köfte');
    });

    test('food_source enum dışı değer → manual (CHECK ihlali koruması)', () {
      // Eski yedeklerde `source='barcode'` olabilir; enum'dan düşürüldü.
      for (final bad in ['barcode', 'scanned', '', 42, null]) {
        final out = DataTransferRepository.sanitizeFood({
          'name': 'X',
          'source': bad,
        });
        expect(out['source'], 'manual', reason: 'source=$bad');
      }
    });

    test('geçerli source değerleri korunur', () {
      for (final ok in ['photo', 'text', 'manual']) {
        final out = DataTransferRepository.sanitizeFood({
          'name': 'X',
          'source': ok,
        });
        expect(out['source'], ok);
      }
    });

    test('source hiç yoksa DB varsayılanına bırakılır', () {
      final out = DataTransferRepository.sanitizeFood({'name': 'X'});
      // `foods.source` `NOT NULL DEFAULT 'manual'`; kolon yoksa DB doldurur,
      // ama açık yazmak güvenli.
      expect(out['source'], 'manual');
    });

    test('null alanlar düşürülür (DB varsayılanı/zorunlu değil)', () {
      final out = DataTransferRepository.sanitizeFood({
        'name': 'X',
        'brand': null,
        'image_url': null,
        'serving_size_g': 100,
      });
      expect(out.containsKey('brand'), isFalse);
      expect(out.containsKey('image_url'), isFalse);
      expect(out['serving_size_g'], 100);
    });
  });

  group('mealTypeDbValues — meal_type enum sözleşmesi', () {
    test('DB CHECK değerleriyle birebir', () {
      // PostgreSQL `meal_type` ENUM: breakfast | lunch | dinner | snack
      expect(DataTransferRepository.mealTypeDbValues,
          {'breakfast', 'lunch', 'dinner', 'snack'});
    });

    test('MealType enum değerleri kümeyle birebir (yeni enum → test kırılır)', () {
      expect(
        MealType.values.map((e) => e.name).toSet(),
        DataTransferRepository.mealTypeDbValues,
      );
    });

    test('DB dışı değer kümede yok (brunch/BRUNCH reddedilir)', () {
      for (final bad in ['brunch', 'BREAKFAST', 'snack ', '', 'öğle']) {
        expect(DataTransferRepository.mealTypeDbValues.contains(bad), isFalse,
            reason: bad);
      }
    });
  });
}
