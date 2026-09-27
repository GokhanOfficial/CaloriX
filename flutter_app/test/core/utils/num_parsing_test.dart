import 'dart:math';

import 'package:calorix/core/utils/num_parsing.dart';
import 'package:calorix/data/repositories/chat_repository.dart';
import 'package:calorix/data/repositories/diary_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// `lib/core/utils/num_parsing.dart` ortak yardımcılarının birim testleri.
///
/// Bu dosya, `analytics_repository` / `macro_calculator` (sayı okuyucuları) ve
/// `diary_repository` / `chat_repository` (`yyyy-MM-dd`) içinde **ikişer kopya**
/// olarak bulunan mantığın tek uygulamaya taşındığını kanıtlar.
void main() {
  group('numOr / numOrNull — bozuk sayı okuma', () {
    test('int ve double düzgün okunur', () {
      expect(numOr(42), 42.0);
      expect(numOr(42.5), 42.5);
      expect(numOr(0), 0.0);
      expect(numOr(-3), -3.0);
      expect(numOrNull(7), 7.0);
    });

    test('null / String / bool okunamaz sayılır', () {
      expect(numOr(null), 0);
      expect(numOr('12'), 0);
      expect(numOr(true), 0);
      expect(numOr(const <int>[1]), 0);
      expect(numOrNull(null), isNull);
      expect(numOrNull('12'), isNull);
    });

    test('NaN / Infinity geçersiz sayılır (round() istisnası kaynağı)', () {
      expect(numOr(double.nan), 0);
      expect(numOr(double.infinity), 0);
      expect(numOr(double.negativeInfinity), 0);
      expect(numOrNull(double.nan), isNull);
      expect(numOrNull(double.infinity), isNull);
    });

    test('fallback parametresi geçersiz değerlerde kullanılır', () {
      expect(numOr(null, fallback: -1), -1);
      expect(numOr(double.nan, fallback: 99), 99);
      // Geçerli değerde fallback'e dokunulmaz.
      expect(numOr(5, fallback: 99), 5);
    });

    test('dönen değer her zaman sonludur (round güvenli)', () {
      for (final v in <Object?>[null, 'x', 1, 2.5, double.nan, double.infinity]) {
        expect(numOr(v).isFinite, isTrue, reason: '$v sonlu olmalı');
        final n = numOrNull(v);
        if (n != null) expect(n.isFinite, isTrue, reason: '$v sonlu olmalı');
      }
    });
  });

  group('formatDateOnly — yyyy-MM-dd', () {
    test('dört haneli yıl, iki haneli ay/gün', () {
      expect(formatDateOnly(DateTime(2026, 8, 15)), '2026-08-15');
      expect(formatDateOnly(DateTime(2026, 1, 5)), '2026-01-05');
      expect(formatDateOnly(DateTime(2026, 12, 31, 23, 59)), '2026-12-31');
    });

    test('tek haneli yıl sıfırla doldurulur', () {
      expect(formatDateOnly(DateTime(1, 1, 1)), '0001-01-01');
    });

    test('günün saat bileşenleri dikkate alınmaz', () {
      expect(
        formatDateOnly(DateTime(2026, 3, 29, 0, 0, 1)),
        formatDateOnly(DateTime(2026, 3, 29, 23, 59, 59)),
      );
    });

    test('diary ve chat aynı sonucu üretir (kopya birleşti)', () {
      for (final d in <DateTime>[
        DateTime(2026, 2, 28),
        DateTime(2026, 2, 29, 12),
        DateTime(2027, 7, 4, 6, 30),
        DateTime(1999, 10, 1),
      ]) {
        expect(
          formatEntryDate(d),
          ChatRepository.localDateOnly(d),
          reason: '$d için iki kopya ayrıştı',
        );
        expect(formatEntryDate(d), formatDateOnly(d));
      }
    });
  });

  group('randomUuidV4 — RFC 4122 v4', () {
    final uuidV4 = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );

    test('200 üretilen değerin tamamı geçerli v4 biçiminde', () {
      for (var i = 0; i < 200; i++) {
        final id = randomUuidV4();
        expect(uuidV4.hasMatch(id), isTrue, reason: 'geçersiz UUID: $id');
      }
    });

    test('sürüm baytı 4, variant baytı 8/9/a/b', () {
      for (var i = 0; i < 200; i++) {
        final id = randomUuidV4();
        expect(id[14], '4', reason: 'sürüm nibble hatalı: $id');
        expect(
          '89ab'.contains(id[19]),
          isTrue,
          reason: 'variant nibble hatalı: $id',
        );
      }
    });

    test('versiyon/variant bitleri maskeleyerek sabitlenir', () {
      // Aynı tohum → aynı bayt dizisi; masking idiyse 6. ve 8. bayt
      // her zaman doğru kalan kısım korunur.
      final r = Random(42);
      for (var i = 0; i < 50; i++) {
        final id = randomUuidV4(random: r);
        expect(uuidV4.hasMatch(id), isTrue, reason: 'geçersiz UUID: $id');
      }
    });

    test('benzersizdir (1000 üretimde çakışma yok)', () {
      final set = <String>{};
      for (var i = 0; i < 1000; i++) {
        set.add(randomUuidV4());
      }
      expect(set.length, 1000);
    });
  });
}
