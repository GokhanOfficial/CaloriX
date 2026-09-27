import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/data_transfer_repository.dart';

/// Veri dışa/içe aktarma — web `useDataExport` parity.
///
/// DB kapalıyken dosya seçimi/paylaşımı altyapısı çalışır; Supabase
/// sorguları tüm fazlar bitince canlı testte doğrulanır.
abstract final class TransferDialogs {
  /// İçe aktarılacak yedek dosyasının üst boyut sınırı (25 MB). `withData: true`
  /// ile dosya belleğe alındığı için sınırsız dosya OOM riski taşır.
  static const int _maxImportBytes = 25 * 1024 * 1024;

  /// Tüm veriyi JSON dosyasına yazip paylaşır (web `exportData`).
  static Future<void> export(BuildContext context, WidgetRef ref) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final messenger = ScaffoldMessenger.of(context);

    // Exporting durumunuSnackBar ile belirt.
    messenger.showSnackBar(
      SnackBar(content: Text('settings.items.exporting'.tr())),
    );

    try {
      final json = await ref
          .read(dataTransferRepositoryProvider)
          .exportData(user.id);
      final dir = await getTemporaryDirectory();
      final date =
          DateTime.now().toIso8601String().split('T').first; // yyyy-MM-dd
      final file = File('${dir.path}/calorix-backup-$date.json');
      await file.writeAsString(json);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'CaloriX backup',
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text('settings.messages.error'.tr())),
      );
    }
  }

  /// Dosya seçtirip içe aktarır (web `importData`).
  static Future<void> import(BuildContext context, WidgetRef ref) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final messenger = ScaffoldMessenger.of(context);

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    // `files.single` boş/çoklu sonuçta `StateError` fırlatıyordu.
    final picked = result.files.first;
    if (picked.bytes == null) return;
    if (picked.size > _maxImportBytes) {
      messenger.showSnackBar(
        SnackBar(content: Text('settings.messages.error'.tr())),
      );
      return;
    }

    messenger.showSnackBar(
      SnackBar(content: Text('settings.items.importing'.tr())),
    );

    try {
      final bytes = picked.bytes!;
      final jsonString = String.fromCharCodes(bytes);
      final counts = await ref
          .read(dataTransferRepositoryProvider)
          .importData(user.id, jsonString);

      final added = counts.values.fold<int>(0, (a, b) => a + b);
      messenger.showSnackBar(
        SnackBar(
            content: Text('${'settings.messages.settingsSaved'.tr()} '
                '($added)')),
      );
    } on FormatException {
      messenger.showSnackBar(
        SnackBar(content: Text('settings.import.fileNote'.tr())),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text('settings.messages.error'.tr())),
      );
    }
  }
}
