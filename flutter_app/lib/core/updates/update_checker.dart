import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import '../observability/app_logger.dart';
import 'update_manifest.dart';

/// Güncelleme kontrolünün UI'a yansıyan durumu.
sealed class UpdateStatus {
  const UpdateStatus();

  /// Kontrol sürüyor (ilk frame'de kısa süre görünür).
  const factory UpdateStatus.checking() = UpdateChecking;

  /// Zorunlu güncelleme — uygulama açılmamalı.
  const factory UpdateStatus.required(UpdateManifest manifest) =
      UpdateRequired;

  /// Opsiyonel güncelleme — atlanabilir.
  const factory UpdateStatus.optional(UpdateManifest manifest) =
      UpdateOptional;

  /// Güncel sürüm.
  const factory UpdateStatus.upToDate() = UpdateUpToDate;

  /// Karar verilemedi (ağ yok + cache yok) — uyarıyla aç.
  const factory UpdateStatus.unknown() = UpdateUnknown;
}

class UpdateChecking extends UpdateStatus {
  const UpdateChecking();
}

class UpdateRequired extends UpdateStatus {
  const UpdateRequired(this.manifest);
  final UpdateManifest manifest;
}

class UpdateOptional extends UpdateStatus {
  const UpdateOptional(this.manifest);
  final UpdateManifest manifest;
}

class UpdateUpToDate extends UpdateStatus {
  const UpdateUpToDate();
}

class UpdateUnknown extends UpdateStatus {
  const UpdateUnknown();
}

/// [UpdateManifest] indirir, cache'ler ve cihaz sürümüyle karşılaştırır.
///
/// Ağ hatasında karar SharedPreferences'taki son başarılı manifest'ten
/// verilir; o da yoksa [UpdateStatus.unknown] döner (uygulama uyarıyla
/// açılır — çevrimdışı kullanıcı kilitlenmez).
class UpdateChecker extends StateNotifier<UpdateStatus> {
  UpdateChecker({http.Client? client})
      : _client = client ?? http.Client(),
        super(const UpdateStatus.checking());

  static const cacheKey = 'update_manifest_cache';

  /// Manifest gövdesi için üst sınır (bayt). Gerçek `latest.json` ~1 KB'tır;
  /// 64 KB'ı aşan yanıt (yönlendirme yakalama, hatalı sunucu, MITM) reddedilir
  /// — `response.bodyBytes` sınırsız olarak belleğe alınıyordu.
  static const int maxManifestBytes = 64 * 1024;

  final http.Client _client;

  /// Test edilebilirlik için enjekte edilebilir cihaz build numarası.
  int? debugDeviceVersionCode;

  Future<void> check() async {
    if (kIsWeb) {
      // Web her zaman günceldir (deploy ile yaşar); kontrol gerekmez.
      state = const UpdateStatus.upToDate();
      return;
    }
    try {
      final response = await _client
          .get(Uri.parse(AppConstants.updateManifestUrl))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw http.ClientException('HTTP ${response.statusCode}');
      }
      if (response.bodyBytes.length > maxManifestBytes) {
        throw http.ClientException(
          'Manifest çok büyük (${response.bodyBytes.length} bayt)',
        );
      }
      final manifest = UpdateManifest.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cacheKey, response.body);
      state = await _decide(manifest);
    } catch (e, s) {
      // Ağ hatası beklenen bir durum; yine de tanılama için kaydedilir.
      AppLog.w('Güncelleme manifesti alınamadı, cache\'e dönülüyor', e, s);
      state = await _decideFromCache();
    }
  }

  Future<UpdateStatus> _decideFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(cacheKey);
    if (cached == null) return const UpdateStatus.unknown();
    try {
      final manifest = UpdateManifest.fromJson(
        jsonDecode(cached) as Map<String, dynamic>,
      );
      return await _decide(manifest);
    } catch (e, s) {
      AppLog.w('Cache\'li güncelleme manifesti bozuk', e, s);
      return const UpdateStatus.unknown();
    }
  }

  Future<UpdateStatus> _decide(UpdateManifest manifest) async {
    final deviceCode = debugDeviceVersionCode ??
        int.tryParse(
            (await PackageInfo.fromPlatform()).buildNumber) ??
        0;
    return switch (manifest.evaluate(deviceCode)) {
      UpdateDecision.required => UpdateRequired(manifest),
      UpdateDecision.optional => UpdateOptional(manifest),
      UpdateDecision.upToDate => const UpdateStatus.upToDate(),
    };
  }

  /// Opsiyonel güncellemenin "Daha sonra" ile kapatılması — bu sürüm bir
  /// daha hatırlatılmaz.
  Future<void> dismissOptional(int versionCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(dismissedCodeKey, versionCode);
  }

  /// [versionCode] daha önce kapatıldıysa true.
  Future<bool> isDismissed(int versionCode) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(dismissedCodeKey) == versionCode;
  }

  static const dismissedCodeKey = 'update_dismissed_code';
}

final updateCheckerProvider =
    StateNotifierProvider<UpdateChecker, UpdateStatus>(
  (ref) => UpdateChecker()..check(),
);
