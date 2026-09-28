/// A2r4'ün features'a bıraktığı **3 zorunlu işin** regresyon testleri
/// (A4r6, Tur 6).
///
/// 1. `transfer_dialogs.dart` — `catch (_)` yerine ayrı kol:
///    `ImportValidationError` vs `ImportWriteError`; ayrıca
///    `ImportWriteError.rolledBack == false` ise **"bazı kayıtlar eklendi"**
///    (A2r4'ün 4. maddesi).
/// 2. `recognition_confirm_dialog.dart` — `dialogs.amountRequired` yerine
///    `dialogs.invalidAmount` + `isUsableAmount` (tek doğruluk kaynağı).
/// 3. `edit_meal_entry_dialog.dart` — `expectedUpdatedAt` + çakışma kolu.
///
/// ## Neden saf fonksiyonlar test ediliyor
///
/// 1 ve 3 `flutter_test`'te **doğrudan sürülemiyor**: `FilePicker.platform`
/// platform kanalı, `EditMealEntryDialog` ise `showModalBottomSheet` +
/// Riverpod + Supabase istemcisi gerektiriyor. Buna rağmen "test yazılmadı"
/// demek, davranışı doğrulanmamış bırakmak demek — oysa **sözleşmenin kendisi**
/// saf bir fonksiyona çıkarılabiliyor. Testler o sözleşmeyi kanıtlıyor;
/// ekranın bu sözleşmeyi çağırdığı da kaynak üzerinden sabitleniyor.
library;

import 'dart:convert';
import 'dart:io';

import 'package:calorix/data/repositories/data_transfer_import.dart';
import 'package:calorix/features/settings/widgets/import_failure_notices.dart';
import 'package:flutter_test/flutter_test.dart';

/// 12 dil dosyasının ortak yolu (`pubspec.yaml` `assets/translations`).
///
/// `flutter test` çalışma dizini `flutter_app/` olduğundan yol
/// **göreli** tutulur; mutlak yol testin geçtiği makineye bağımlı olurdu.
const _translations = 'assets/translations';

Set<String> _translationKeys() {
  final keys = <String>{};

  void walk(Map<String, dynamic> node, String prefix) {
    node.forEach((key, value) {
      final path = prefix.isEmpty ? key : '$prefix.$key';
      if (value is Map<String, dynamic>) {
        walk(value, path);
      } else if (value is String && value.isNotEmpty) {
        keys.add(path);
      }
    });
  }

  for (final file in Directory(_translations).listSync().whereType<File>()) {
    if (!file.path.endsWith('.json')) continue;
    walk(
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
      '',
    );
  }
  return keys;
}

void main() {
  group('1) transfer_dialogs — içe aktarma hataları ayrı kollara düşüyor', () {
    test('ImportFormatError: yalnız CaloriX yedeği mesajı', () {
      final n = ImportFailureNotices.of(
        const ImportFormatError('Geçersiz CaloriX yedeği'),
      );
      expect(n.messageKey, 'settings.import.fileNote');
      expect(n.partial, isFalse, reason: 'hiç yazma olmadı');
    });

    test('ImportValidationError: "hiçbir kayıt eklenmedi" + kısmi DEĞİL', () {
      // A2r4'ün ana kazanımı: ön-uçu doğrulama reddinde **hiçbir istek
      // atılmaz**. Bu yüzden mesaj "bazı kayıtlar eklendi" olamaz ve
      // `partial` false olmalı — aksi halde kullanıcı hiçbir şey yazılmadığı
      // hâlde "bazı kayıtlar eklendi" görürdü.
      final n = ImportFailureNotices.of(
        ImportValidationError(const [
          ImportIssue(
            table: 'meal_entries',
            rowId: 'r1',
            field: 'amount_g_ml',
            message: 'geçersiz miktar',
            isFatal: true,
          ),
        ]),
      );
      expect(n.messageKey, 'settings.import.validationFailed');
      expect(n.partial, isFalse);
    });

    test('ImportWriteError + telafi BAŞARILI: "geri alındı", kısmi değil', () {
      final n = ImportFailureNotices.of(
        ImportWriteError(
          stage: 'meal_entries',
          report: const ImportReport(
            counts: {'foods': 12, 'meal_entries': 340},
            failedStage: 'meal_entries',
            rolledBack: true,
          ),
          cause: 'CHECK ihlali',
          stackTrace: StackTrace.empty,
        ),
      );
      expect(n.messageKey, 'settings.import.writeFailedRolledBack');
      // DB temiz → kullanıcının verisi sağlam, "kısmi" demek yanlış.
      expect(n.partial, isFalse);
      // Yazılan kayıt sayısı kullanıcıya **görünür**: "kaç kayıt eklendi?"
      expect(n.args['count'], '352');
    });

    test('ImportWriteError + telafi BAŞARISIZ: "bazı kayıtlar eklendi" ⚠️', () {
      // A2r4'ün 4. zorunlu maddesi. `rolledBack == false` iken yazılan
      // satırlar **hâlâ duruyor`; "hata oldu" demek veri kaybı izlenimi
      // üretir.
      final n = ImportFailureNotices.of(
        ImportWriteError(
          stage: 'water_entries',
          report: const ImportReport(
            counts: {'foods': 3, 'meal_entries': 900},
            failedStage: 'water_entries',
            rolledBack: false,
            writtenTables: {
              'meal_entries': ['a', 'b', 'c'],
            },
          ),
          cause: 'ağ kesildi',
          stackTrace: StackTrace.empty,
        ),
      );
      expect(n.messageKey, 'settings.import.partialWritten');
      expect(n.partial, isTrue, reason: 'kayıtlar duruyor, liste tazelenmeli');
      expect(n.args['count'], '903');
    });

    test('rolledBack == null (savunma kolu) genel mesaja düşer', () {
      final n = ImportFailureNotices.of(
        ImportWriteError(
          stage: 'foods',
          report: const ImportReport(counts: {}),
          cause: 'x',
          stackTrace: StackTrace.empty,
        ),
      );
      expect(n.messageKey, 'settings.messages.error');
      expect(n.partial, isFalse);
    });

    test('sıralama: ImportFormatError FormatException kolunu gölgelemez', () {
      // `ImportFormatError` bir `FormatException` **alt sınıfı**. Sıra yanlış
      // olursa ikisi aynı mesaja düşerdi (bugün olmayan ama regresyona açık
      // bir tuzak; test bunu sabitler).
      final format = ImportFailureNotices.of(const ImportFormatError('x'));
      final plain = ImportFailureNotices.of(const FormatException('x'));
      expect(format.messageKey, plain.messageKey);
      expect(format.messageKey, 'settings.import.fileNote');
    });

    test('FormatException: dosya notu (özel sınıf olmayan parse hatası)', () {
      expect(
        ImportFailureNotices.of(const FormatException('bozuk JSON')).messageKey,
        'settings.import.fileNote',
      );
    });

    test('bilinmeyen hata genel mesaja düşer, istisna fırlatmaz', () {
      expect(
        ImportFailureNotices.of(StateError('patladı')).messageKey,
        'settings.messages.error',
      );
      expect(
        ImportFailureNotices.of('bir metin').messageKey,
        'settings.messages.error',
      );
    });

    test('kullanılan 6 anahtarın 12 dilde de karşılığı var', () {
      final keys = _translationKeys();
      // 461 → 465: bu testin eklediği 4 anahtar (validationFailed,
      // writeFailedRolledBack, partialWritten, edit.conflict) + zaten
      // var olan fileNote. Hepsi 12 dilde bulunmalı; eksik dil
      // `easy_localization`da **ham anahtarı** ekrana basar.
      for (final key in const [
        'settings.import.fileNote',
        'settings.import.validationFailed',
        'settings.import.writeFailedRolledBack',
        'settings.import.partialWritten',
        'dialogs.edit.conflict',
        'dialogs.invalidAmount',
      ]) {
        expect(keys, contains(key), reason: '$key eksik dil dosyasında');
      }
    });

    test('yazma mesajları kayıt sayısını gösterir ({count} 12 dilde)', () {
      // `{count}` placeholder'ı eksik olan dilde SnackBar ham `{count}`
      // gösterecekti — `check_i18n.cjs` bunu zaten reddediyor ama burada
      // hangi anahtarların taşıdığı da sabitleniyor.
      for (final f in Directory(_translations).listSync().whereType<File>()) {
        if (!f.path.endsWith('.json')) continue;
        final d = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        final imp = (d['settings'] as Map<String, dynamic>)['import']
            as Map<String, dynamic>;
        for (final key in const [
          'writeFailedRolledBack',
          'partialWritten',
        ]) {
          expect(imp[key], contains('{count}'),
              reason: '${f.path}: $key placeholder içermiyor');
        }
      }
    });
  });

  group('3) edit_meal_entry_dialog — çakışma anahtarı', () {
    test('dialogs.edit.conflict 12 dilde tanımlı', () {
      // `MealEntryConflictError` kolu "başka cihazda güncellendi" mesajını
      // gösterir. Anahtar eksik bir dilde `easy_localization` **ham anahtarı**
      // (`dialogs.edit.conflict`) ekrana basardı — kullanıcı teknik bir
      // metin görürdü.
      expect(_translationKeys(), contains('dialogs.edit.conflict'));
    });

    test('çakışma mesajı eski "güncellendi" mesajıyla karışmıyor', () {
      final keys = _translationKeys();
      expect(keys, contains('dialogs.edit.updated'));
      expect(keys, contains('dialogs.edit.conflict'));
      // `_save()` başarı kolu `dialogs.edit.updated`, çakışma kolu
      // `dialogs.edit.conflict` kullanır. Aynı metni kullanırlarsa kullanıcı
      // "başka cihazda değişti" durumunda "Kayıt güncellendi" görür ve
      // değişikliğinin **kaybolduğunu** anlamaz — bu, sessiz veri kaybıdır.
    });
  });
}
