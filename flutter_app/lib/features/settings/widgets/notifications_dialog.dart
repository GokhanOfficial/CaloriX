import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/notifications/meal_reminder.dart';
import '../../../core/notifications/reminder_settings.dart';
import '../../../core/observability/app_logger.dart';
import '../../../data/models/profile.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/notification_preferences_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import 'server_notification_preferences_section.dart';
import 'weigh_in_frequency_input.dart';

/// Bildirim ayarları diyaloğu — web `saveNotifications` parity.
///
/// ## İki kaynak, tek ekran (A4r7, ürün kararı 2-A)
///
/// Kullanıcı **iki ayrı ayar ekranı görmemeli**. Bu ekranda iki bölüm
/// yan yana durur ve ikisi de "Kaydet" ile birlikte kaydedilir:
///
/// 1. **Profil seviyesi anahtarlar** (push/email master, tartılma sıklığı,
///    makro otomatik yeniden hesap) — `profiles` tablosu.
/// 2. **Sunucu hatırlatıcıları** (`water` / `daily_log` / `weekly_summary`) —
///    `notification_preferences` tablosu. (`goal_achieved` **gösterilmez**:
///    sunucu bu tipi hiç göndermiyor — A4r10, ürün kararı 2-B.)
/// 3. **Öğün hatırlatıcıları** — cihazda (`ReminderSettings`,
///    SharedPreferences + `NotificationService`).
///
/// ### ⭐ Öncelik kuralı (belgelenmiş karar)
///
/// **Sunucu yalnızca push/e-posta kanallarını yönetir; yerel bildirimler
/// cihazda kalır.** Gerekçe:
///
/// - `check-reminders` cron'u **sadece push/e-posta** üretir
///   (`send-notification`). Web'de bu tek çalışan kanaldır; tercihi
///   kaydetmeyen bir kullanıcıda `water`/`daily_log`/`weekly_summary`
///   **sessizce kapalı** kalır (`pref?.push_enabled` satır yoksa `false`).
/// - Öğün hatırlatıcıları **cihazda** zamanlanır; PWA/web'de cihaz
///   zamanlayıcısı yok, mobilde push aboneliği gerekir. Bu ikisini
///   sunucuya taşımak mevcut mimariyi bozar ve web'de çalışmaz.
/// - Dolayısıyla iki kaynak **birbirinin yerine geçmez**; sunucu
///   push/e-posta izinlerini, cihaz yerel zamanlamayı yönetir.
///   Çakışma (ayrışma) senaryosunda **cihaz kazanır** — çünkü öğün
///   hatırlatıcılarında sunucunun hiçbir karşılığı yoktur.
class NotificationsDialog extends ConsumerStatefulWidget {
  const NotificationsDialog({super.key, this.profile});

  final Profile? profile;

  static Future<void> show(
    BuildContext context,
    WidgetRef ref,
    Profile? profile,
  ) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: NotificationsDialog(profile: profile),
      ),
    );
  }

  @override
  ConsumerState<NotificationsDialog> createState() =>
      _NotificationsDialogState();
}

class _NotificationsDialogState extends ConsumerState<NotificationsDialog> {
  late bool _push = widget.profile?.pushNotificationsEnabled ?? true;
  late bool _email = widget.profile?.emailNotificationsEnabled ?? true;
  late final TextEditingController _frequency = TextEditingController(
    text: (widget.profile?.weighInFrequencyDays ?? kWeighInDefaultDays)
        .toString(),
  );
  late bool _autoRecalc = widget.profile?.autoRecalculateMacros ?? true;
  bool _saving = false;

  /// `weigh_in_frequency_days` alanının odak düğümü — doğrulama hatası
  /// oluştuğunda klavye/focus o alana taşınır (ekran okuyucu da hata
  /// metnini doğru yerde okur).
  final _frequencyFocus = FocusNode();

  /// `weigh_in_frequency_days` hatası (`null` = hata yok).
  ///
  /// ⭐ Ayrı bir alan tutulur çünkü "Kaydet" düğmesinin `onPressed`'ı
  /// `build` sırasında okunur: `setState` çağırmadan hata metnini
  /// yeniden hesaplamak zorundayız (düğmenin `enabled` durumu **anında**
  /// değişmeli, `form.validate()` yalnız düğmeye basıldığında çalışıyor).
  String? _frequencyError;

  /// Sunucu tercihleri. `{}` = henüz yüklenmedi (bkz. [_prefsLoaded]).
  ///
  /// Varsayılanlar `defaultServerPreference` ile gelir; DB'de satır
  /// **yoksa** kullanıcı sunucu tarafını bilmeden "kapalı" kalıyordu —
  /// bu yüzden kaydetme her zaman **beş tipin de** satırını yazar.
  Map<ServerNotificationType, NotificationPreference> _serverPrefs = {};

  /// `fetch` bitti mi? `false` ise **"Kaydet" düğmesi pasif**.
  ///
  /// ⭐ Neden gerekli (A4r7b): `_loadServerPrefs` `initState` içindeki
  /// `Future.microtask` ile koşuyor. Yükleme bitmeden "Kaydet" basılırsa
  /// `_serverPrefs` hâlâ `{}` → `upsertAll` **hiçbir şey yazmaz** → kullanıcı
  /// "Ayarlar güncellendi" görür ama `check-reminders`'ın `water`/`daily_log`/
  /// `weekly_summary` sessiz-kapalı davranışı **hiç değişmemiştir**. Yükleme
  /// hata verirse (ağ yok) kullanıcı yine de kaydedebilmeli — bu yüzden
  /// hata halinde de `_prefsLoaded = true` yapılır (varsayılanlarla kaydeder)
  /// ve ayrıca uyarı gösterilir.
  bool _prefsLoaded = false;

  @override
  void initState() {
    super.initState();
    // Sunucu tercihlerini arka planda yükle; ilk kare hemen görünür.
    Future.microtask(_loadServerPrefs);
  }

  Future<void> _loadServerPrefs() async {
    final user = ref.read(currentUserProvider);
    if (user == null) {
      if (mounted) setState(() => _prefsLoaded = true);
      return;
    }
    Map<ServerNotificationType, NotificationPreference> loaded;
    Object? failure;
    try {
      loaded = await ref
          .read(notificationPreferencesRepositoryProvider)
          .fetch(user.id);
    } catch (e) {
      // Oturum dışı/ağ hatası: ayar ekranı **çökmemeli** (PROTOKOL §2 P1).
      // Varsayılanlarla devam edilir; kaydetme yine de mümkündür.
      loaded = const {};
      failure = e;
    }
    if (!mounted) return;
    setState(() {
      _serverPrefs = {
        for (final type in ServerNotificationType.values)
          type: loaded[type] ?? defaultServerPreference(type),
      };
      _prefsLoaded = true;
    });
    if (failure != null) {
      // Sessizce varsayılan kaydetmek kullanıcıyı yanıltır: "push açık"
      // gördüğü halde yazılacak olan **kendi girdisi** değil.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('settings.notifications.server.loadFailed'.tr()),
        ),
      );
    }
  }

  @override
  void dispose() {
    _frequency.dispose();
    _frequencyFocus.dispose();
    super.dispose();
  }

  /// Bir sunucu tercihini **yerinde** günceller (anlık UI, kaydetmeye bağlı
  /// değil — "Kaydet" butonu her şeyi birlikte yollar).
  void _updateServerPref(
    ServerNotificationType type,
    NotificationPreference Function(NotificationPreference) update,
  ) {
    setState(() {
      _serverPrefs = {
        ..._serverPrefs,
        type: update(_serverPrefs[type] ?? defaultServerPreference(type)),
      };
    });
  }

  /// Tartılma sıklığı metnini doğrular ve `_frequencyError`'ı günceller.
  ///
  /// `onChanged`'te **her tuş vuruşunda** çalışır; bu yüzden hata mesajı
  /// yalnız "Kaydet"e basılınca değil, **anında** görünür. `_save` de
  /// aynı fonksiyonu çağırır (defansif: `onChanged` tetiklenmemiş olabilir).
  void _validateFrequency(String raw) {
    final next = isValidWeighInInput(raw) ? null : _frequencyErrorOf(raw);
    if (next == _frequencyError) return;
    setState(() => _frequencyError = next);
  }

  /// Geçersiz metin için **yerelleştirilmiş** hata metni.
  ///
  /// Boş giriş **hata değildir** (`DEFAULT 7` yazılır ve CHECK
  /// `IS NULL OR …` olduğu için geçerlidir); aralık dışı/çöp metin hatadır.
  static String? _frequencyErrorOf(String raw) =>
      isBlankWeighInInput(raw) ? null : _frequencyRangeMessage;

  /// "1-365 gün arasında bir değer girin" — hata `errorText`'inde **ve**
  /// `SnackBar`'da aynı metni gösterir (biri kalıcı, biri geçici); iki
  /// çağrıda kopyalamak yerine tek yerden üretilir.
  static String get _frequencyRangeMessage =>
      'settings.notifications.weighInFrequencyRange'.tr(
        namedArgs: {
          'min': '$kWeighInMinDays',
          'max': '$kWeighInMaxDays',
        },
      );

  /// "Kaydet"in etkin olması için gereken koşul.
  ///
  /// ⭐ A4r10 düzeltmesi: `weigh_in_frequency_days` alanı CHECK aralığı
  /// (1..365) dışındaysa düğme **pasif** olur. Düzeltme öncesi `0` yazılıp
  /// "Kaydet"e basıldığında `_save` **iki** yazma yolunu da (profil + sunucu
  /// bildirim tercihleri) tek `try` içinde çalıştırıyordu; CHECK reddi **tüm
  /// `_save`'i** düşürüyordu → kullanıcı push/e-posta tercihlerini de
  /// kaybediyor, üstelik hangi alandan kaynaklandığını öğrenemiyordu.
  bool get _canSave =>
      !_saving && _prefsLoaded && isValidWeighInInput(_frequency.text);

  Future<void> _save() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    // Son savunma: düğme pasif olsa bile `_save` doğrudan çağrılabilir
    // (düğmeye basmadan önce alan değişmiş olabilir) → sunucuya geçersiz
    // değer göndermek yerine kullanıcının girdiği yere dön.
    final raw = _frequency.text;
    if (!isValidWeighInInput(raw)) {
      setState(() => _frequencyError = _frequencyErrorOf(raw));
      _frequencyFocus.requestFocus();
      return;
    }
    final frequencyDays =
        parseWeighInFrequencyDays(raw) ?? kWeighInDefaultDays;

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);

    // Profil + sunucu tercihlerini birlikte kaydet; biri başarısız olursa
    // hata mesajı gösterilir ama **diğeri kaydedilmiş** olur (kısmi kayıt
    // en azından görünür; sessiz yutulmaz).
    try {
      await ref.read(profileRepositoryProvider).update(user.id, {
        'push_notifications_enabled': _push,
        'email_notifications_enabled': _email,
        // ⭐ A4r10: `int.tryParse(...) ?? 7` yerine **doğrulanmış** değer.
        // `?? 7` yalnız `null` üstüne düşerdi, `0` doğrudan DB'ye
        // gidiyordu (negatif değer `digitsOnly` ile zaten engelleniyordu)
        // → `profiles_weigh_in_frequency_days_range` CHECK'i (1..365)
        // reddediyor, **tüm `_save`** düşüyordu.
        'weigh_in_frequency_days': frequencyDays,
        'auto_recalculate_macros': _autoRecalc,
      });
      ref.invalidate(profileProvider);

      // Sunucu bildirim tercihleri `notification_preferences`'a yazılır
      // (yoksa `check-reminders` bu tipleri sessizce kapatıyordu).
      //
      // ⭐ **Master anahtarlar burada birleştirilir** (A4r8).
      // `send-notification/index.ts:423-424` `preference?.push_enabled ??
      // profile.push_notifications_enabled` okur ve `??` yalnız `NULL` üstüne
      // düştüğü için, satır bir kez yazıldıktan sonra **profil** master
      // anahtarı hiç okunmaz. Yukarıdaki "Push/E-posta Bildirimleri"
      // anahtarlarının ölü kalmasını önlemek için burada **AND** uygulanır:
      // master `false` ise hiçbir tip satırı `true` yazamaz.
      final effective = NotificationPreferencesRepository.applyMasterSwitches(
        _serverPrefs,
        masterPush: _push,
        masterEmail: _email,
      );
      await ref
          .read(notificationPreferencesRepositoryProvider)
          .upsertAll(user.id, effective.values);
      ref.invalidate(notificationPreferencesProvider);

      if (mounted) Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text('settings.messages.settingsSaved'.tr())),
      );
    } on ProfileFieldRangeError catch (e, s) {
      // ⭐ A4r10: A2r9'ın veri katmanı savunması **buraya** ulaştı. Bu
      // hata "ağ yok" değil, "senin girdiğin değer DB CHECK'i sağlamıyor"
      // demektir; genel hata mesajı (`settings.messages.error`) kullanıcıya
      // ne yapması gerektiğini söylemezdi ve **hangi alan** olduğunu
      // göstermezdi.
      AppLog.w('Profil alanı DB CHECK aralığı dışında', e, s);
      if (mounted) {
        setState(() => _frequencyError = _frequencyRangeMessage);
        _frequencyFocus.requestFocus();
      }
      messenger.showSnackBar(
        SnackBar(content: Text(_frequencyRangeMessage)),
      );
    } catch (e, s) {
      // Sessiz `catch (_)` **zorunlu log** olmadan bırakıldı: PROTOKOL §2
      // P1 "sessiz hata yutma"yı yasaklar. Kullanıcı yine de bilgilendirilir
      // ama hata artık **görünmez** değil.
      AppLog.w('Bildirim ayarları kaydedilemedi', e, s);
      messenger.showSnackBar(
        SnackBar(content: Text('settings.messages.error'.tr())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTime(MealType meal) async {
    final reminder = ref.read(reminderSettingsProvider).meals[meal]!;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: reminder.hour, minute: reminder.minute),
    );
    if (picked == null) return;
    await ref
        .read(reminderSettingsProvider.notifier)
        .setTime(meal, picked.hour, picked.minute);
  }

  String _formatTime(MealReminder reminder) =>
      '${reminder.hour.toString().padLeft(2, '0')}:'
      '${reminder.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final reminder = ref.watch(reminderSettingsProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'settings.notifications.title'.tr(),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'settings.notifications.desc'.tr(),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('settings.notifications.push'.tr()),
            value: _push,
            onChanged: (v) => setState(() => _push = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('settings.notifications.email'.tr()),
            value: _email,
            onChanged: (v) => setState(() => _email = v),
          ),
          const SizedBox(height: 8),
          // ⭐ A4r10: `TextField` → `TextFormField`.
          // * `inputFormatters: digitsOnly` **negatif** girişi zaten engelliyor
          //   ama `0`'ı engellemiyordu (CHECK alt sınırı 1).
          // * `LengthLimitingTextInputFormatter(3)` 365'i geçmeyi engeller:
          //   kullanıcı `9999` yazınca hata **göstermek** yerine yazımı
          //   sessizce kesiyor (yine de `_frequencyError` yine de çalışır,
          //   çünkü 3 haneli her sayı 1..365 değildir: `0`, `1x`, `99x`).
          // * `errorText` doğrulama **anında** görünür.
          TextFormField(
            focusNode: _frequencyFocus,
            controller: _frequency,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(3),
            ],
            onChanged: _validateFrequency,
            decoration: InputDecoration(
              labelText: 'settings.notifications.weighInFrequency'.tr(),
              suffixText: 'settings.notifications.days'.tr(),
              errorText: _frequencyError,
              helperText: 'settings.notifications.weighInFrequencyHint'.tr(
                namedArgs: {
                  'min': '$kWeighInMinDays',
                  'max': '$kWeighInMaxDays',
                },
              ),
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('settings.notifications.autoRecalculate'.tr()),
            value: _autoRecalc,
            onChanged: (v) => setState(() => _autoRecalc = v),
          ),
          // ⭐ Master anahtarların **aşağıdaki** her hatırlatıcıya da
          // uygulandığını metinle söyle (A4r8). Kullanıcı üstteki anahtarı
          // kapatıp aşağıda bir tipi açık bırakırsa ne olacağını bilmeli;
          // gerçek davranış da AND'dir
          // (`NotificationPreferencesRepository.applyMasterSwitches`).
          Text(
            'settings.notifications.server.channelNote'.tr(),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Divider(height: 32),
          // --- Sunucu hatırlatıcıları (hesaba kaydedilir) ---------------
          Text(
            'settings.notifications.server.title'.tr(),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'settings.notifications.server.desc'.tr(),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          ServerNotificationPreferencesSection(
            prefs: _serverPrefs,
            onChanged: _updateServerPref,
          ),
          const Divider(height: 32),
          Text(
            'settings.notifications.reminderTitle'.tr(),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            kIsWeb
                ? 'settings.notifications.webOnlyInApp'.tr()
                : 'settings.notifications.reminderDesc'.tr(),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          for (final meal in reminderMeals)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Text(
                meal.emoji,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              title: Text('meals.${meal.name}'.tr()),
              subtitle: Text(
                _formatTime(reminder.meals[meal]!),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              trailing: Switch(
                value: reminder.meals[meal]!.enabled,
                onChanged: (v) => ref
                    .read(reminderSettingsProvider.notifier)
                    .setEnabled(meal, v),
              ),
              onTap: () => _pickTime(meal),
            ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: Text('common.close'.tr()),
              ),
              const SizedBox(width: 8),
              FilledButton(
                // ⚠️ `_prefsLoaded` kapısı (A4r7b): yükleme bitmeden "Kaydet"
                // basılırsa `_serverPrefs` boştur ve **hiçbir sunucu tercihi
                // yazılmaz** → kullanıcı "Ayarlar güncellendi" görür ama
                // `check-reminders`'ın sessiz-kapalı davranışı durur.
                // `_saving` eski kapıyı korur (çift gönderim).
                //
                // ⭐ `_frequencyError` kapısı (A4r10): CHECK aralığı dışı
                // değerde **hiçbir şey gönderilmez** — profil **ve** sunucu
                // bildirim tercihleri birlikte kurtulur.
                onPressed: _canSave ? _save : null,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('common.save'.tr()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
