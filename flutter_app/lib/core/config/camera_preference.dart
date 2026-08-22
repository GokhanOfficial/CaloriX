import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Varsayılan kamera tercihi — Faz 4'te yemek ekleme akışı kullanır.
///
/// Kullanıcı ayarlardan seçer; `shared_preferences` anahtarı `camera_preference`.
enum CameraPreference {
  /// Uygulama içi kamera (tam ekran deneyim).
  inApp('in_app'),

  /// Telefonun yerel kamera uygulaması / galeri seçici.
  native('native');

  const CameraPreference(this.value);

  /// shared_preferences'ta saklanan string değer.
  final String value;

  static CameraPreference fromValue(String? v) =>
      CameraPreference.values.firstWhere(
        (c) => c.value == v,
        orElse: () => CameraPreference.inApp,
      );
}

/// Kamera tercihini yönetir (varsayılan: uygulama içi).
class CameraPreferenceNotifier extends Notifier<CameraPreference> {
  static const prefsKey = 'camera_preference';

  @override
  CameraPreference build() {
    _load();
    return CameraPreference.inApp;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = CameraPreference.fromValue(prefs.getString(prefsKey));
  }

  Future<void> setPreference(CameraPreference pref) async {
    state = pref;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, pref.value);
  }
}

final cameraPreferenceProvider =
    NotifierProvider<CameraPreferenceNotifier, CameraPreference>(
        CameraPreferenceNotifier.new);
