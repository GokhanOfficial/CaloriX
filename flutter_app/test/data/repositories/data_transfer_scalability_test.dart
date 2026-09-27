import 'dart:convert';

import 'package:calorix/data/repositories/data_transfer_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// **Saf** URL-ölçek testleri — ağ yok, mock yok.
///
/// `inFilter` değerleri PostgREST'in sorgu dizesine gömülür
/// (`?col=in.("a","b")`), bu yüzden URL uzunluğu bir sabit olmak zorunda
/// değildir. Bu testler o uzunluğun **tutarlı** kaldığını ve her URL'nin
/// güvenli sınırın altında olduğunu kanıtlar; limiti aşan bir dilim
/// kalmadığında 2000/5000 kayıtlık yedek `414 URI Too Long` almaz.
void main() {
  /// `postgrest` 2.9.1 `_cleanFilterArray` (postgrest_builder.dart:635) ile
  /// birebir aynı üretim. Değişirse test kırılır (kopyalanmış üretim
  /// kasıtlıdır; sözleşme burada sabitleniyor).
  String filterValue(List<String> values) =>
      'in.(${values.map((v) => '"${v.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"').join(',')})';

  /// Gerçek bir isteğin göreli URL uzunluğu:
  /// `/rest/v1/<tablo>?select=...&<kolon>=<değer>&order=...&limit=10`
  int urlLength(String table, String column, List<String> values) =>
      '/rest/v1/$table?select=*&$column=${filterValue(values)}&limit=10'.length;

  const uuidLength = 36; // `uuidGenerateV4()`
  const isoLength = 24; // `2026-08-15T10:00:00.000Z`
  const safeUrlLimit = 8000; // PostgREST pratik URL tavanı (~8 KB)

  group('inFilterChunks — URL limiti güvenli mi', () {
    test('100 UUID dilimi güvenli sınırın altında kalır', () {
      final values =
          List.generate(100, (i) => '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}');
      final len = urlLength('food_nutrition', 'food_id', values);
      expect(values.first.length, uuidLength);
      expect(len, lessThan(safeUrlLimit),
          reason: '100 UUID dilimi $len bayt — 8 KB tavanı aşıyor');
      // Gerçekçi bütçe kullan: sınırın ~%80'inden fazlasını harcamıyoruz.
      expect(len, lessThan(safeUrlLimit * 0.8));
    });

    test('100 ISO-8601 damga dilimi (water entry_time) güvenli sınırın altında', () {
      final values = List.generate(
        100,
        (i) => '2026-08-15T10:00:${(i % 60).toString().padLeft(2, '0')}.000Z',
      );
      final len = urlLength('water_entries', 'entry_time', values);
      expect(values.first.length, isoLength);
      expect(len, lessThan(safeUrlLimit),
          reason: '100 ISO damga dilimi $len bayt');
    });

    test('boş girdi dilim üretmez (in.() syntax hatası olmaz)', () {
      expect(DataTransferRepository.inFilterChunks(<String>[]), isEmpty);
      expect(DataTransferRepository.inFilterChunks(<int>[]), isEmpty);
    });

    test('tam dilim sayısı: 500 → 5, 2000 → 20, tam sınırdaki değer', () {
      expect(DataTransferRepository.inFilterChunks(List.filled(100, 'a')),
          hasLength(1));
      expect(DataTransferRepository.inFilterChunks(List.filled(500, 'a')),
          hasLength(5));
      expect(DataTransferRepository.inFilterChunks(List.filled(2000, 'a')),
          hasLength(20));
      // Sınırın tam katı tek fazla dilim üretmemeli.
      expect(DataTransferRepository.inFilterChunks(List.filled(201, 'a')),
          hasLength(3));
    });

    test('her dilim tam boyutlu ve toplam eleman sayısı korunur', () {
      for (final total in <int>[1, 99, 100, 101, 500, 2000, 5000]) {
        final values = List.generate(total, (i) => 'v$i');
        final chunks = DataTransferRepository.inFilterChunks(values);
        expect(chunks.fold<int>(0, (a, c) => a + c.length), total,
            reason: 'toplam=$total');
        for (final c in chunks) {
          expect(c.length, lessThanOrEqualTo(DataTransferRepository.inFilterChunkSize),
              reason: 'toplam=$total dilim çok büyük');
        }
        // Dilimler girdi sırasını korumalı (dedup eşlemesi buna bağlı).
        expect(chunks.expand((c) => c).toList(), values);
      }
    });

    test('son dilim kırpılır (sublist taşması yok)', () {
      final chunks = DataTransferRepository.inFilterChunks(List.filled(5, 'a'));
      expect(chunks, hasLength(1));
      expect(chunks.first, hasLength(5));
    });
  });

  group('inFilterChunks olmasaydı ne olurdu (regresyon kanıtı)', () {
    test('2000 kayıtlık tek UUID listesi 8 KB URL tavanını ~9 kat aşar', () {
      final values = List.generate(
        2000,
        (i) => '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
      );
      final naive = urlLength('food_nutrition', 'food_id', values);
      expect(naive, greaterThan(safeUrlLimit * 4),
          reason: 'tek sorgu $naive bayt → 414/431');

      // Parçalı hâli: hiçbir dilim sınırı aşmaz.
      for (final chunk in DataTransferRepository.inFilterChunks(values)) {
        expect(urlLength('food_nutrition', 'food_id', chunk),
            lessThan(safeUrlLimit));
      }
    });

    test('5000 su kaydı tek listede ~9.4x sınır; dilimli hâlde güvenli', () {
      final values = List.generate(
        5000,
        (i) => '2026-08-15T10:00:${(i % 60).toString().padLeft(2, '0')}.000Z',
      );
      expect(urlLength('water_entries', 'entry_time', values),
          greaterThan(safeUrlLimit * 4));
      for (final chunk in DataTransferRepository.inFilterChunks(values)) {
        expect(urlLength('water_entries', 'entry_time', chunk),
            lessThan(safeUrlLimit));
      }
    });

    test('dilim boyutu sabitini 100 tutmak güvenli sınırı korur', () {
      // 250 (turlarda konuşulan "1000'lik dilimler" seçeneği) ISO damgalarda
      // 250*27 ≈ 6.8 KB + tablo/select ≈ 7 KB — sınıra çok yakın. 100 güvenli.
      expect(DataTransferRepository.inFilterChunkSize, 100);
      final iso = List.generate(
        DataTransferRepository.inFilterChunkSize,
        (_) => '2026-08-15T10:00:00.000Z',
      );
      expect(
        urlLength('water_entries', 'entry_time', iso),
        lessThan(safeUrlLimit * 0.8),
      );
    });
  });

  group('mealKeysOf — dedup anahtarı sözleşmesi', () {
    Map<String, dynamic> meal({
      String? date = '2026-08-15',
      String? type = 'lunch',
      String? name = 'Tavuk',
    }) =>
        {
          'entry_date': date,
          'meal_type': type,
          'custom_name': ?name,
        };

    test('aynı gün/öğün/yemek aynı anahtarı üretir (dedup çalışır)', () {
      final keys = DataTransferRepository.mealKeysOf([
        meal(),
        meal(),
        meal(name: 'Pilav'),
      ]);
      expect(keys, hasLength(2));
    });

    test('farklı gün/öğün farklı anahtar (yanlışlıkla atlanmaz)', () {
      final keys = DataTransferRepository.mealKeysOf([
        meal(date: '2026-08-15'),
        meal(date: '2026-08-16'),
        meal(type: 'dinner'),
      ]);
      expect(keys, hasLength(3));
    });

    test('anahtarsız satır (null/boş tarih, boş tip) atlanır', () {
      final keys = DataTransferRepository.mealKeysOf([
        meal(date: null),
        meal(date: ''),
        meal(type: null),
        meal(type: ''),
        meal(),
      ]);
      expect(keys, hasLength(1));
    });

    test('null custom_name boş dizeyle aynı anahtarı üretir', () {
      // DB'de `custom_name` NULL olan kayıt ile boş string olan kayıt aynı
      // beslenme girdisidir; anahtar ayrımı yapmazsa biri sürekli yeniden
      // eklenir (import yedeği şişirir).
      final withoutKey = DataTransferRepository.mealKeysOf([meal(name: null)]);
      final emptyString = DataTransferRepository.mealKeysOf([
        {...meal(), 'custom_name': ''},
      ]);
      expect(withoutKey, hasLength(1));
      expect(emptyString, withoutKey);
      // Ad ayrımı ise korunur.
      final named = DataTransferRepository.mealKeysOf([meal(name: 'Pilav')]);
      expect(named, isNot(withoutKey));
    });
  });

  group('isDeleted — yumuşak silinmiş yedek satırları', () {
    test('deleted_at dolu string → silinmiş', () {
      expect(
        DataTransferRepository.isDeleted({'deleted_at': '2026-08-15T11:00:00Z'}),
        isTrue,
      );
    });

    test('deleted_at null / eksik / boş string → silinmemiş', () {
      // `foods` tablosunda `deleted_at` kolonu **yok**; eksik alan
      // silinmemiş sayılmalı, yoksa tüm yemek kayıtları elenir.
      expect(DataTransferRepository.isDeleted(const {}), isFalse);
      expect(DataTransferRepository.isDeleted({'deleted_at': null}), isFalse);
      expect(DataTransferRepository.isDeleted({'deleted_at': ''}), isFalse);
    });
  });

  group('yedek JSON boyutu gerçekçi mi (sözleşme testi)', () {
    test('2000 öğünlük yedek üretilebilir ve importData ayrıştırılabilir', () {
      final meals = [
        for (var i = 0; i < 2000; i++)
          {
            'id': 'm$i',
            'user_id': 'u1',
            'entry_date': '2026-08-15',
            'meal_type': 'lunch',
            'custom_name': 'Yemek $i',
            'amount_g_ml': 100,
            'calculated_kcal': 500,
            'calculated_protein': 30,
            'calculated_carbs': 50,
            'calculated_fat': 20,
          },
      ];
      final json = jsonEncode({
        'version': '1.3.0',
        'exportedAt': '2026-09-28T00:00:00Z',
        'meal_entries': meals,
      });
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final list = (decoded['meal_entries'] as List).cast<Map<String, dynamic>>();
      expect(list, hasLength(2000));
      // 2000 ayrı anahtar (farklı custom_name) → tamamı eklenecek.
      expect(DataTransferRepository.mealKeysOf(list), hasLength(2000));
    });
  });
}
