import 'dart:convert';
import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../../data/models/profile.dart';
import '../../data/repositories/diary_repository.dart';
import '../constants/app_constants.dart';
import '../utils/num_parsing.dart';
import 'widget_settings.dart';
import 'widget_strings.dart';

/// Teşvik metninin en erken görüntülenme saati — bu saatten önce gün daha
/// "yeni" sayılır ve widget boş günü teşvikle kutsamaz.
const int kEncouragementStartHour = 11;

/// Dart↔Kotlin veri kanalı anahtar sözleşmesi — native taraf (HomeWidget
/// SharedPreferences'ı) bu anahtarlarla okur. Değerler **birebir eşleşmeli**;
/// değişiklik iki tarafı birlikte gerektirir.
abstract final class WidgetKeys {
  // Ortak
  static const state = 'widget.state'; // "ready" | "signedOut" | "noConfig"
  static const date = 'widget.date'; // yyyy-MM-dd
  static const updatedAt = 'widget.updatedAt'; // int epoch ms
  static const locale = 'widget.locale';

  // daily.*
  static const dCalories = 'daily.calories';
  static const dTarget = 'daily.target';
  static const dRemaining = 'daily.remaining';
  static const dPermille = 'daily.progressPermille'; // 0..1000
  static const dProtein = 'daily.protein';
  static const dProteinT = 'daily.proteinTarget';
  static const dCarbs = 'daily.carbs';
  static const dCarbsT = 'daily.carbsTarget';
  static const dFat = 'daily.fat';
  static const dFatT = 'daily.fatTarget';
  static const dWater = 'daily.water';
  static const dWaterT = 'daily.waterTarget';
  static const dWeightText = 'daily.weightText';
  static const dHasMeals = 'daily.hasMeals';
  static const dEncText = 'daily.encouragementText';
  static const dShowMacros = 'daily.showMacros';
  static const dShowWater = 'daily.showWater';
  static const dShowWeight = 'daily.showWeight';

  // weekly.*
  static const wValues = 'weekly.values'; // JSON int[], 7 öğe (eski→bugün)
  static const wLabels = 'weekly.labels'; // JSON String[], 7 öğe (eski→bugün)
  static const wTodayIdx = 'weekly.todayIndex';
  static const wTarget = 'weekly.target';
  static const wAvg = 'weekly.avg';
  static const wOnTarget = 'weekly.daysOnTarget';
  static const wShowAvg = 'weekly.showAvg';
  static const wShowOnTarget = 'weekly.showDaysOnTarget';

  // Metin paketi (str.*)
  static const sDailyTitle = 'str.dailyTitle';
  static const sWeeklyTitle = 'str.weeklyTitle';
  static const sSignedOut = 'str.signedOut';
  static const sStale = 'str.staleHint';
  static const sRemaining = 'str.remaining';
  static const sKcal = 'str.kcal';
  static const sAvg = 'str.avg';
  static const sOnTarget = 'str.onTarget';
  static const sQuickAdd = 'str.quickAdd';
}

/// Günlük özet snapshot'ı — tüm değerler native taraf için önceden
/// yuvarlanmıştır (Kotlin'de ek hesap yok, yalnızca görüntüleme).
///
/// Hedefler profilden, profil yoksa [AppConstants] varsayılanlarından gelir.
/// `remaining` hiçbir zaman negatif olmaz; `permille` 0..1000 aralığına
/// kırpılır (hedef aşımı ilerleme çubuğunu taşmaz).
Map<String, Object> buildDailySnapshot({
  required DailyData daily,
  required Profile? profile,
  required WidgetSettings settings,
  required WidgetStrings strings,
  required DateTime now,
  required String localeCode,
}) {
  final totals = daily.totals;
  final target = (profile?.dailyCalorieTarget ?? AppConstants.defaultCalories)
      .round();
  final consumed = totals.calories.round();
  final remaining = math.max(0, target - consumed);
  final permille = target > 0
      ? (consumed / target * 1000).clamp(0, 1000).round()
      : 0;
  final hasMeals = daily.mealEntries.isNotEmpty;
  final weightKg = daily.latestWeight?.weightKg;

  return {
    WidgetKeys.state: 'ready',
    WidgetKeys.date: formatEntryDate(now),
    WidgetKeys.updatedAt: now.millisecondsSinceEpoch,
    WidgetKeys.locale: localeCode,
    WidgetKeys.dCalories: consumed,
    WidgetKeys.dTarget: target,
    WidgetKeys.dRemaining: remaining,
    WidgetKeys.dPermille: permille,
    WidgetKeys.dProtein: totals.protein.round(),
    WidgetKeys.dProteinT:
        (profile?.proteinTargetG ?? AppConstants.defaultProtein).round(),
    WidgetKeys.dCarbs: totals.carbs.round(),
    WidgetKeys.dCarbsT: (profile?.carbsTargetG ?? AppConstants.defaultCarbs)
        .round(),
    WidgetKeys.dFat: totals.fat.round(),
    WidgetKeys.dFatT: (profile?.fatTargetG ?? AppConstants.defaultFat).round(),
    WidgetKeys.dWater: daily.totalWater.round(),
    WidgetKeys.dWaterT:
        (profile?.dailyWaterTargetMl ?? AppConstants.defaultWater).round(),
    WidgetKeys.dWeightText: weightKg == null
        ? ''
        : '${weightKg.toStringAsFixed(1)} kg',
    WidgetKeys.dHasMeals: hasMeals,
    WidgetKeys.dEncText:
        encouragementText(
          s: strings,
          hasMeals: hasMeals,
          enabled: settings.encouragementEnabled,
          now: now,
        ) ??
        '',
    // Ayna: native taraf görünürlüğü Dart ayarlarından okur.
    WidgetKeys.dShowMacros: settings.showMacros,
    WidgetKeys.dShowWater: settings.showWater,
    WidgetKeys.dShowWeight: settings.showWeight,
    ...buildStringPack(strings),
  };
}

/// Haftalık grafik snapshot'ı — bugün dahil son 7 günün kayan penceresi
/// (eski→bugün). Boş günler 0 ile temsil edilir.
Map<String, Object> buildWeeklySnapshot({
  required List<Map<String, dynamic>> mealRows,
  required Profile? profile,
  required WidgetSettings settings,
  required WidgetStrings strings,
  required DateTime now,
  required String localeCode,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final values = weeklyCalorieValues(mealRows: mealRows, today: today);
  final labels = weeklyLabels(today: today, localeCode: localeCode);
  final target = (profile?.dailyCalorieTarget ?? AppConstants.defaultCalories)
      .round();

  // Ortalama yalnızca kayıt girilen günlere bölünür (analitik parity).
  final loggedDays = values.where((v) => v > 0).toList();
  final avg = loggedDays.isEmpty
      ? 0
      : (loggedDays.fold<int>(0, (sum, v) => sum + v) / loggedDays.length)
            .round();

  // "Hedefte" bandı: hedefin %90–110'u (sınırlar dahil) — tam sayı
  // aritmetiğiyle kıyaslanır ki kayan nokta hatası sınır günleri kaybetmesin.
  final daysOnTarget = values
      .where(
        (v) =>
            v > 0 &&
            target > 0 &&
            v * 10 >= target * 9 &&
            v * 10 <= target * 11,
      )
      .length;

  return {
    WidgetKeys.state: 'ready',
    WidgetKeys.date: formatEntryDate(now),
    WidgetKeys.updatedAt: now.millisecondsSinceEpoch,
    WidgetKeys.locale: localeCode,
    WidgetKeys.wValues: jsonEncode(values),
    WidgetKeys.wLabels: jsonEncode(labels),
    WidgetKeys.wTodayIdx: 6, // pencerenin son öğesi her zaman bugün
    WidgetKeys.wTarget: target,
    WidgetKeys.wAvg: avg,
    WidgetKeys.wOnTarget: daysOnTarget,
    WidgetKeys.wShowAvg: settings.weeklyShowAvg,
    WidgetKeys.wShowOnTarget: settings.weeklyShowDaysOnTarget,
    ...buildStringPack(strings),
  };
}

/// `signedOut` / `noConfig` durumları — tüm daily/weekly anahtarlarına
/// güvenli varsayılanlar + metin paketi. Native taraf hiçbir anahtar için
/// null beklememeli; bu sayede eski sürüm kalıntıları üzerine yazılır.
Map<String, Object> buildStateSnapshot({
  required String state,
  required WidgetStrings strings,
  required DateTime now,
  required String localeCode,
}) {
  const defaults = WidgetSettings();
  return {
    WidgetKeys.state: state,
    WidgetKeys.date: formatEntryDate(now),
    WidgetKeys.updatedAt: now.millisecondsSinceEpoch,
    WidgetKeys.locale: localeCode,
    WidgetKeys.dCalories: 0,
    WidgetKeys.dTarget: 0,
    WidgetKeys.dRemaining: 0,
    WidgetKeys.dPermille: 0,
    WidgetKeys.dProtein: 0,
    WidgetKeys.dProteinT: 0,
    WidgetKeys.dCarbs: 0,
    WidgetKeys.dCarbsT: 0,
    WidgetKeys.dFat: 0,
    WidgetKeys.dFatT: 0,
    WidgetKeys.dWater: 0,
    WidgetKeys.dWaterT: 0,
    WidgetKeys.dWeightText: '',
    WidgetKeys.dHasMeals: false,
    WidgetKeys.dEncText: '',
    WidgetKeys.dShowMacros: defaults.showMacros,
    WidgetKeys.dShowWater: defaults.showWater,
    WidgetKeys.dShowWeight: defaults.showWeight,
    WidgetKeys.wValues: jsonEncode(List<int>.filled(7, 0)),
    WidgetKeys.wLabels: jsonEncode(List<String>.filled(7, '')),
    WidgetKeys.wTodayIdx: 6,
    WidgetKeys.wTarget: 0,
    WidgetKeys.wAvg: 0,
    WidgetKeys.wOnTarget: 0,
    WidgetKeys.wShowAvg: defaults.weeklyShowAvg,
    WidgetKeys.wShowOnTarget: defaults.weeklyShowDaysOnTarget,
    ...buildStringPack(strings),
  };
}

/// Önceden çevrilmiş metin paketi — widget'ların gösterdiği tüm sabit
/// metinler. 12 ayrı native `strings.xml` yerine tek kaynak.
Map<String, Object> buildStringPack(WidgetStrings strings) => {
  WidgetKeys.sDailyTitle: strings.dailyTitle,
  WidgetKeys.sWeeklyTitle: strings.weeklyTitle,
  WidgetKeys.sSignedOut: strings.signedOut,
  WidgetKeys.sStale: strings.staleHint,
  WidgetKeys.sRemaining: strings.remaining,
  WidgetKeys.sKcal: strings.kcal,
  WidgetKeys.sAvg: strings.avg,
  WidgetKeys.sOnTarget: strings.onTarget,
  WidgetKeys.sQuickAdd: strings.quickAdd,
};

/// Gün içi teşvik metni — yalnızca teşvik açıksa, gün henüz boşsa ve saat
/// [kEncouragementStartHour]'ı geçtiyse. Saate göre varyant: `< 12` sabah,
/// `< 18` öğleden sonra, else akşam.
String? encouragementText({
  required WidgetStrings s,
  required bool hasMeals,
  required bool enabled,
  required DateTime now,
}) {
  if (!enabled || hasMeals || now.hour < kEncouragementStartHour) return null;
  if (now.hour < 12) return s.encMorning;
  if (now.hour < 18) return s.encAfternoon;
  return s.encEvening;
}

/// Kayan 7 günlük kalori serisi (bugün dahil, eski→bugün): `entry_date`
/// başına `calculated_kcal` toplamı, kayıt olmayan günler 0.
List<int> weeklyCalorieValues({
  required List<Map<String, dynamic>> mealRows,
  required DateTime today,
}) {
  final byDate = <String, double>{};
  for (final row in mealRows) {
    // `as String` / `as num` elle yazılmış ya da beklenmeyen bir sütun tipinde
    // geldiğinde `TypeError` fırlatıyor ve **haftalık widget'ın tamamını**
    // düşürüyordu. Bozuk satır atlanır; diğer günler grafiğe girer.
    final date = row['entry_date'];
    if (date is! String || date.isEmpty) continue;
    final kcal = numOr(row['calculated_kcal']);
    byDate[date] = (byDate[date] ?? 0) + kcal;
  }
  return [
    for (var i = 6; i >= 0; i--)
      (byDate[formatEntryDate(today.subtract(Duration(days: i)))] ?? 0).round(),
  ];
}

/// Kayan 7 günün kısa gün adları (`DateFormat.E`, eski→bugün).
/// `initializeDateFormatting(localeCode)` çağrısı **çağıranın** sorumluluğudur.
List<String> weeklyLabels({
  required DateTime today,
  required String localeCode,
}) {
  final fmt = DateFormat.E(localeCode);
  return [
    for (var i = 6; i >= 0; i--) fmt.format(today.subtract(Duration(days: i))),
  ];
}

/// "Bugün hiç öğün yok" anlık bildirimi (nudge) gönderilmeli mi?
///
/// Koşullar: nudge açıksa, bugün öğün yoksa, saat planlanan nudge anına
/// ermişse ve bugün için daha önce gönderilmemişse ([lastNudgeDate]
/// `yyyy-MM-dd`, [formatEntryDate] ile aynı biçim).
bool shouldSendNudge({
  required WidgetSettings settings,
  required bool hasMealsToday,
  required DateTime now,
  required String? lastNudgeDate,
}) {
  if (!settings.nudgeEnabled || hasMealsToday) return false;
  if (lastNudgeDate == formatEntryDate(now)) return false;
  final hour = _clampHour(settings.nudgeHour);
  final minute = _clampMinute(settings.nudgeMinute);
  final scheduled = DateTime(now.year, now.month, now.day, hour, minute);
  return !now.isBefore(scheduled);
}

/// Gece yarısı–23:59 arasına kırpar.
///
/// `nudgeHour: 99` kalıcı ayarda `DateTime(y, m, d, 99, 0)` **ertesi güne**
/// normalize olur; `!now.isBefore(scheduled)` her zaman true olur ve bildirim
/// **her gün** tetiklenir. `reminder_settings.dart` bu kırpmayı zaten
/// yapıyor; widget ayarları kendi kalıcı anahtarlarını okuduğu için aynı
/// savunma burada da gerekli.
int _clampHour(int hour) => hour < 0 ? 0 : (hour > 23 ? 23 : hour);

/// 0–59 arasına kırpar.
int _clampMinute(int minute) => minute < 0 ? 0 : (minute > 59 ? 59 : minute);
