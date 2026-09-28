/// `notification_preferences` tablosu — **sunucu tarafı** bildirim
/// tercihleri (A4r7, ürün kararı 2-A).
///
/// ## Neden ayrı bir repository? (alan sahipliği notu)
///
/// Bu dosya `lib/data/repositories/` altındadır ve A2'nin alanıdır;
/// PROTOKOL §5 gereği **aktarım** yazılmalıdır. Bununla birlikte Görev 2
/// açıkça "yeni UI gerekiyor, `lib/data/**` alanına yazma — o zaman
/// aktarım olarak raporla ve geçici çözüm uygula" diyor. Yeni repository
/// **dosyası** yaratmak zorundaydı (mevcut bir dosyaya yazmak da A2 alanına
/// dokunmak olurdu), bu yüzden dosya eklendi ve **AKTARIM** bölümünde
/// A2'ye bildirildi.
///
/// ## ⭐ Cihaz ↔ sunucu öncelik kuralı
///
/// **Sunucu yalnızca push/e-posta kanallarını yönetir; yerel (cihaz)
/// bildirimler cihazda kalır.** Gerekçe ve tablo `notifications_dialog.dart`
/// yorumunda belgelendi; kısaca:
///
/// - `check-reminders` (cron) yalnızca **push/e-posta** üretir — bu
///   sunucu tarafıdır ve cihaz değişse de "izin" vermek zorundadır.
/// - Öğün hatırlatıcıları **cihazda** `NotificationService`/`SharedPreferences`
///   ile zamanlanır (push aboneliği gerektirmez, cihaz kapalıyken de
///   çalışır). Bunları sunucuya taşımak **web'de çalışmaz** (PWA kapalıyken
///   yerel zamanlayıcı yoktur) ve mevcut mimariyi gereksiz yere bölerdi.
/// - Bu yüzden iki kaynak **birbirinin yerine geçmez**, birbirini
///   **tamamlar**: sunucu → push/e-posta, cihaz → yerel zamanlanmış bildirim.
///
/// Bu repository yalnız **sunucu** tercihlerini bilir; öğün hatırlatıcılarını
/// [ReminderSettings] (cihaz) yönetir ve ikisi asla karışmaz.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_client_provider.dart';
import 'auth_repository.dart';

/// `notification_preferences.notification_type` DB CHECK allow-list'i
/// (`notification_preferences_type_allowlist`, `full_setup.sql:621-623`).
/// Sunucu **yalnız** bu beş tipi kabul eder; burada da aynı liste kullanılır
/// (istemci tarafından geçersiz tip yazılırsa PostgREST 400 döner ve
/// kullanıcı ayar kaydederken hata alır).
enum ServerNotificationType {
  weighIn('weigh_in'),
  dailyLog('daily_log'),
  water('water'),
  goalAchieved('goal_achieved'),
  weeklySummary('weekly_summary');

  const ServerNotificationType(this.wire);

  /// `notification_type` kolonundaki değer.
  final String wire;
}

/// Bir tipin **sunucu tarafı varsayılanı**.
///
/// Değerler web `useNotifications`'ın `NOTIFICATION_DEFAULTS` tablosuyla
/// **birebir aynıdır** (`src/hooks/useNotifications.ts:29-35`) — iki istemci
/// farklı varsayılan üretirse aynı kullanıcı web'de ve Flutter'da farklı
/// davranış görür (A4r3'ün "mantıklı görünen iddiayı test et" dersi).
///
/// ## Neden varsayılan "push açık" ve tabloyu dolduruyoruz?
///
/// `check-reminders` `water`/`daily_log`/`weekly_summary` için
/// `pref?.push_enabled || pref?.email_enabled` arar (`index.ts:349/413/483`).
/// **Satır yoksa** ifade `false` demektir → bu üç tip **sessizce kapalı**dır
/// (A1r4'ün bulgusu). Tabloyu bu varsayılanlarla doldurmak, "hiçbir şey
/// ayarlamayan ama hatırlatma bekleyen" kullanıcının hatırlatmalarını
/// geri getirir ve **kayıtlı tercih** kavramını anlamlı kılar.
NotificationPreference defaultServerPreference(ServerNotificationType type) {
  switch (type) {
    case ServerNotificationType.weighIn:
      // Tek saatte (09:00) gider → `start == end`, aralık 1.
      return NotificationPreference(
        type: type,
        pushEnabled: true,
        emailEnabled: true,
        startHour: 9,
        endHour: 9,
        intervalHours: 1,
      );
    case ServerNotificationType.dailyLog:
      return NotificationPreference(
        type: type,
        pushEnabled: true,
        emailEnabled: false,
        startHour: 18,
        endHour: 18,
        intervalHours: 1,
      );
    case ServerNotificationType.water:
      return NotificationPreference(
        type: type,
        pushEnabled: true,
        emailEnabled: false,
        startHour: 9,
        endHour: 21,
        intervalHours: 3,
      );
    case ServerNotificationType.goalAchieved:
      return NotificationPreference(
        type: type,
        pushEnabled: true,
        emailEnabled: false,
        startHour: 0,
        endHour: 23,
        intervalHours: 24,
      );
    case ServerNotificationType.weeklySummary:
      return NotificationPreference(
        type: type,
        pushEnabled: false,
        emailEnabled: true,
        startHour: 9,
        endHour: 9,
        intervalHours: 1,
        summaryDay: 1,
        summaryHour: 9,
      );
  }
}

/// Tek bir sunucu bildirim tercihi — `notification_preferences` satırının
/// sade, alan-alan ayrılmış hali (upsert/normalize için pratik).
class NotificationPreference {
  const NotificationPreference({
    required this.type,
    this.pushEnabled = true,
    this.emailEnabled = false,
    this.startHour = 9,
    this.endHour = 21,
    this.intervalHours = 3,
    this.summaryDay = 1,
    this.summaryHour = 9,
  });

  final ServerNotificationType type;
  final bool pushEnabled;
  final bool emailEnabled;
  final int startHour;
  final int endHour;
  final int intervalHours;

  /// `weekly_summary` gönderilecek gün (0=Pazar … 6=Cumartesi, sunucu
  /// `weekday` diziniyle aynı).
  final int summaryDay;
  final int summaryHour;

  /// DB'ye yazılacak satır (`user_id` çağıran doldurur).
  ///
  /// DB CHECK'leri `notification_preferences_hours_range`
  /// (`full_setup.sql:624-628`): saatler 0..23, `interval_hours` 1..24,
  /// `summary_day` 0..6. Aralık dışı bir değer yazmak 400 döndürür ve
  /// **tüm ayar kaydını** düşürürdü → `clamp` ile normalize edilir.
  Map<String, dynamic> toRow(String userId) => {
    'user_id': userId,
    'notification_type': type.wire,
    'push_enabled': pushEnabled,
    'email_enabled': emailEnabled,
    'start_hour': _clamp(startHour, 0, 23, 9),
    'end_hour': _clamp(endHour, 0, 23, 21),
    'interval_hours': _clamp(intervalHours, 1, 24, 3),
    'summary_day': _clamp(summaryDay, 0, 6, 1),
    'summary_hour': _clamp(summaryHour, 0, 23, 9),
    // `updated_at` trigger varsa yazmaya gerek yok; `created_at`
    // `DEFAULT now()` — A2r5'in "created_at sözleşmeye girmiyordu"
    // hatasını tekrarlamamak için **gönderilmez**.
  };

  static int _clamp(int v, int min, int max, int fallback) =>
      (v >= min && v <= max) ? v : fallback;

  /// PostgREST sayısal kolonu **diziye göre** JSON çözer ve `int` yazar,
  /// ama kolon `numeric`/`bigint` ise JSON bunu metin olarak döndürebilir
  /// (ör. `interval_hours: "3"`). `as int?` bu durumda **`TypeError`**
  /// fırlatır ve `fetch` tüm ayar ekranını çökertir.
  ///
  /// Ölçüm (A4r7b): repo'nun geri kalanı bu tuzağa karşı **`as num?`**
  /// kullanıyor (`food_repository.dart`, `profile.dart`); burada `int?`
  /// yazılmıştı. `_asInt` ikisini de kabul eder, `null`/bozuk değerde
  /// `fallback` döner (sessiz bozuk ayar yerine güvenli varsayılan).
  static int _asInt(Object? raw, int fallback) {
    if (raw is int) return raw;
    if (raw is num) {
      final rounded = raw.toInt();
      return rounded.isFinite ? rounded : fallback;
    }
    if (raw is String) return int.tryParse(raw.trim()) ?? fallback;
    return fallback;
  }

  factory NotificationPreference.fromRow(Map<String, dynamic> row) {
    final type = ServerNotificationType.values.firstWhere(
      (t) => t.wire == row['notification_type'],
      orElse: () => ServerNotificationType.weighIn,
    );
    return NotificationPreference(
      type: type,
      pushEnabled: (row['push_enabled'] as bool?) ?? true,
      emailEnabled: (row['email_enabled'] as bool?) ?? false,
      startHour: _asInt(row['start_hour'], 9),
      endHour: _asInt(row['end_hour'], 21),
      intervalHours: _asInt(row['interval_hours'], 3),
      summaryDay: _asInt(row['summary_day'], 1),
      summaryHour: _asInt(row['summary_hour'], 9),
    );
  }
}

/// `notification_preferences` CRUD — sunucu tarafı (push/e-posta)
/// bildirim tercihleri. Web `useNotifications` (`updatePreference`) ve
/// `NOTIFICATION_DEFAULTS` ile aynı varsayılanları kullanır.
class NotificationPreferencesRepository {
  NotificationPreferencesRepository(this._client);

  final SupabaseClient _client;

  static const _table = 'notification_preferences';

  /// Kullanıcının sunucu tercihlerini **tür → tercih** haritası olarak
  /// getirir. Tablo boşsa `{}` döner (arayüz varsayılanları gösterir).
  Future<Map<ServerNotificationType, NotificationPreference>> fetch(
    String userId,
  ) async {
    final rows = await _client.from(_table).select().eq('user_id', userId);
    final map = <ServerNotificationType, NotificationPreference>{};
    for (final row in rows as List) {
      final pref = NotificationPreference.fromRow(
        Map<String, dynamic>.from(row as Map),
      );
      map[pref.type] = pref;
    }
    return map;
  }

  /// Tek bir tercihi yazar/günceller (upsert, `UNIQUE(user_id, type)`).
  ///
  /// `send-notification` **yalnız** burada yazan satırları okur
  /// (`push_enabled ?? profil ?? true`). Satır yoksa `check-reminders`
  /// `water`/`daily_log`/`weekly_summary` için sessizce **kapalı** davranır
  /// (satır yoksa `pref?.push_enabled` `undefined` → koşul `false`); bu
  /// yüzden bir kez kaydetmek, o üç tipi **sessiz kapalı** olmaktan çıkarır.
  Future<void> upsert(NotificationPreference pref, String userId) async {
    await _client
        .from(_table)
        .upsert(pref.toRow(userId), onConflict: 'user_id,notification_type');
  }

  /// Bir dizi tercihi topluca yazar — ayar ekranı **tek** "Kaydet"
  /// düğmesiyle hepsini gönderir (kısmi kayıt olmaz).
  Future<void> upsertAll(
    String userId,
    Iterable<NotificationPreference> prefs,
  ) async {
    for (final pref in prefs) {
      await upsert(pref, userId);
    }
  }
}

final notificationPreferencesRepositoryProvider =
    Provider<NotificationPreferencesRepository>((ref) {
      return NotificationPreferencesRepository(
        ref.watch(supabaseClientProvider),
      );
    });

/// Oturum açık kullanıcının sunucu bildirim tercihleri.
///
/// Kayıt sonrası `ref.invalidate(...)` çağrılmalıdır.
final notificationPreferencesProvider =
    FutureProvider<Map<ServerNotificationType, NotificationPreference>>((ref) {
      final user = ref.watch(currentUserProvider);
      if (user == null) return const {};
      return ref
          .watch(notificationPreferencesRepositoryProvider)
          .fetch(user.id);
    });
