/// Yedek içe aktarma hatalarının **kullanıcıya gösterilecek sonucunu**
/// belirleyen saf eşleme — `transfer_dialogs.dart` bunu kullanır.
///
/// ## Neden ayrı dosya
///
/// `TransferDialogs.import` gövdesi `FilePicker.platform.pickFiles` ile
/// başlıyor; `flutter_test` bu platform kanalını sürdüremez, dolayısıyla
/// `catch` kolları içeriden test edilemiyordu. A2r4 bu yüzden "ayrı kol
/// ekle" dedi ama testle sabitleyemedi — ve A4r3'ün öğrendiği dersi
/// ("iddiayı test et") uygulamak için eşleme saflaştırıldı.
///
/// Buradaki sözleşme **arayüzün sorumluluğu**: veri katmanı (A2) hatanın
/// *ne olduğunu* söyler, arayüz (A4) bunu *ne söyleyeceğine* çevirir.
/// Testler bu çevirinin doğruluğunu kanıtlar; meseler `record`'ta taşınır
/// (çeviri anahtarı + `{count}` argümanı), böylece testler `easy_localization`
/// kurulumu gerektirmez.
///
/// ## Sözleşme (testle sabitli)
///
/// | Hata | `partial` | Anahtar |
/// |---|---|---|
/// | `ImportFormatError` | – (hiç yazma olmadı) | `settings.import.fileNote` |
/// | `ImportValidationError` | – (ön-uçu, **hiç yazma yok**) | `settings.import.validationFailed` |
/// | `ImportWriteError` + `rolledBack == true` | **false** (telafi başarılı, DB temiz) | `settings.import.writeFailedRolledBack` |
/// | `ImportWriteError` + `rolledBack == false` | **true** (kayıtlar duruyor!) | `settings.import.partialWritten` |
/// | diğer | – | `settings.messages.error` |
library;

import 'package:easy_localization/easy_localization.dart';

import '../../../data/repositories/data_transfer_import.dart';

/// Bir içe aktarma hatasının arayüz sonucu.
class ImportFailureNotice {
  const ImportFailureNotice({
    required this.messageKey,
    this.args = const {},
    this.duration = const Duration(seconds: 4),
    this.partial = false,
  });

  /// `easy_localization` anahtarı (`translationKey.tr(args: args)`).
  final String messageKey;

  /// `{count}` gibi adlandırılmış placeholder doldurmaları.
  final Map<String, String> args;

  /// SnackBar süresi. Uzun açıklamalar için uzatılır (okunabilirlik).
  final Duration duration;

  /// `true` ise **kayıt eklendi ve duruyor** (telafi başarısız). Bu, A2r4'ün
  /// 4. zorunlu maddesi: "bazı kayıtlar eklendi" mesajı.
  ///
  /// `false` ise ekleme ya hiç olmadı ya da tamamen geri alındı — bu iki
  /// durumu ayırmak, kullanıcının "yarısı geldi mi?" sorusunun tek yanıtıdır.
  final bool partial;

  /// `easy_localization` çağrısı. Numaralar `[count]` gibi
  /// `{placeholder}` desenine **doğrudan** gövdeye iliştirilir; 12 dilin
  /// hepsinde aynı İngilizce takma ad (`count`) kullanıldığı için
  /// `namedArgs` yerine tek liste yeterlidir ve çeviri dosyasında
  /// dil başına yeni isim uydurmak gerekmez.
  String translate() =>
      messageKey.tr(args: args.entries.map((e) => '${e.key}=${e.value}').toList());
}

/// A2'nin hata sınıflarını arayüz bildirimine eşler.
///
/// **Sıra önemli**: `ImportFormatError` bir `FormatException` **alt sınıfıdır**,
/// `ImportValidationError`/`ImportWriteError` ise `Exception`'dır; yine de
/// her biri kendi koluna düşecek şekilde ayrı ayrı test edilmiştir.
abstract final class ImportFailureNotices {
  static ImportFailureNotice of(Object error) {
    if (error is ImportValidationError) {
      // Ön-uçu reddi: **hiçbir istek atılmadı**. Sayı verilmez — mesajın
      // kendisi ("hiçbir kayıt eklenmedi") kullanıcının sorusunu yanıtlıyor;
      // ölümcül ihlal sayısını göstermek 12 dilde ek çeviri işi demek ve
      // kullanıcı için aksiyona dönük değil (dosyayı düzeltmesi gerekiyor).
      return const ImportFailureNotice(
        messageKey: 'settings.import.validationFailed',
        duration: Duration(seconds: 6),
      );
    }
    if (error is ImportWriteError) {
      // `e.addedAdded` = "N kayıt eklenmişti" (sunucu ayrıntısı taşımaz).
      final written = error.report.totalAdded;
      if (error.report.rolledBack == true) {
        return ImportFailureNotice(
          messageKey: 'settings.import.writeFailedRolledBack',
          args: {'count': '$written'},
          duration: const Duration(seconds: 6),
        );
      }
      if (error.report.rolledBack == false) {
        return ImportFailureNotice(
          messageKey: 'settings.import.partialWritten',
          args: {'count': '$written'},
          duration: const Duration(seconds: 8),
          partial: true,
        );
      }
      // `rolledBack == null` → yazma hatası yok (savunma kolu). Genel mesaj.
      return const ImportFailureNotice(messageKey: 'settings.messages.error');
    }
    if (error is ImportFormatError) {
      return const ImportFailureNotice(messageKey: 'settings.import.fileNote');
    }
    if (error is FormatException) {
      return const ImportFailureNotice(messageKey: 'settings.import.fileNote');
    }
    return const ImportFailureNotice(messageKey: 'settings.messages.error');
  }
}
