import '../constants/app_constants.dart';

/// Tek bir öğünün hatırlatıcı ayarı — aç/kapa durumu ve saat.
class MealReminder {
  const MealReminder({
    this.enabled = false,
    this.hour = 8,
    this.minute = 30,
  });

  final bool enabled;
  final int hour;
  final int minute;

  MealReminder copyWith({bool? enabled, int? hour, int? minute}) =>
      MealReminder(
        enabled: enabled ?? this.enabled,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
      );
}

/// Öğün bildirimlerinin kullanacağı hatırlatıcı öğünler.
const List<MealType> reminderMeals = [
  MealType.breakfast,
  MealType.lunch,
  MealType.dinner,
];
