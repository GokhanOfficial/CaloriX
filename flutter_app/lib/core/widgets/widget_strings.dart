import 'package:easy_localization/easy_localization.dart';

/// Ana ekran widget'larına native tarafa geçirilen önceden çevrilmiş metin
/// paketi.
///
/// Android'in her dil için ayrı `res/values-*/strings.xml` dosyaları tutmak
/// yerine metinler Flutter tarafında bir kez çevrilir ve veri kanalına
/// `str.*` anahtarlarıyla gömülür — native taraf yalnızca görüntüler. Böylece
/// 12 çeviri dosyası assets/translations'daki tek kaynakla senkron kalır.
class WidgetStrings {
  const WidgetStrings({
    required this.dailyTitle,
    required this.weeklyTitle,
    required this.remaining,
    required this.kcal,
    required this.avg,
    required this.onTarget,
    required this.quickAdd,
    required this.signedOut,
    required this.staleHint,
    required this.encMorning,
    required this.encAfternoon,
    required this.encEvening,
    required this.nudgeTitle,
    required this.nudgeBody,
  });

  /// Günlük özet widget başlığı — 'Günlük Özet'.
  final String dailyTitle;

  /// Haftalık grafik widget başlığı — 'Haftalık Grafik'.
  final String weeklyTitle;

  /// Kalori satırı eki — 'kalan'.
  final String remaining;

  /// Kalori birimi — 'kcal'.
  final String kcal;

  /// Haftalık ortalama etiketi — 'ort.'.
  final String avg;

  /// Hedefteki gün sayısı etiketi — 'gün hedefte'.
  final String onTarget;

  /// Hızlı ekle düğmesi — 'Ekle'.
  final String quickAdd;

  /// Çıkış yapılmış durum metni — 'Özetini görmek için giriş yap'.
  final String signedOut;

  /// Bayat veri ipucu — 'Veri güncel değil — uygulamayı aç'.
  final String staleHint;

  /// Teşvik metni — sabah varyantı.
  final String encMorning;

  /// Teşvik metni — öğleden sonra varyantı.
  final String encAfternoon;

  /// Teşvik metni — akşam varyantı.
  final String encEvening;

  /// Nudge bildirimi başlığı.
  final String nudgeTitle;

  /// Nudge bildirimi gövdesi.
  final String nudgeBody;

  /// Aktif dildeki çevirilerle paket oluşturur (`widgets.*` anahtarları).
  factory WidgetStrings.current() => WidgetStrings(
    dailyTitle: 'widgets.dailyTitle'.tr(),
    weeklyTitle: 'widgets.weeklyTitle'.tr(),
    remaining: 'widgets.remaining'.tr(),
    kcal: 'widgets.kcal'.tr(),
    avg: 'widgets.avg'.tr(),
    onTarget: 'widgets.onTarget'.tr(),
    quickAdd: 'widgets.quickAdd'.tr(),
    signedOut: 'widgets.signedOut'.tr(),
    staleHint: 'widgets.staleHint'.tr(),
    encMorning: 'widgets.encMorning'.tr(),
    encAfternoon: 'widgets.encAfternoon'.tr(),
    encEvening: 'widgets.encEvening'.tr(),
    nudgeTitle: 'widgets.nudgeTitle'.tr(),
    nudgeBody: 'widgets.nudgeBody'.tr(),
  );
}
