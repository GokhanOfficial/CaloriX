import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/account_repository.dart';
import '../../../data/repositories/auth_repository.dart';
import '../account_local_cleanup.dart';

/// Hesap silme akışı — iki aşamalı onay (KVKK / Google Play zorunluluğu).
///
/// ## Akış
///
/// 1. **Uyarı diyaloğu** ([DeleteAccountDialog]) — ne silineceğini listeler,
///    "geri alınamaz" der ve iptal tek çıkış yoludur.
/// 2. **Parola doğrulama** — `TextFormField` + `AutofillHints.password`.
///    Parola **yalnızca** gövdeye gider, hiçbir yerde saklanmaz/loglanmaz.
/// 3. **Sonuç** — tam silme → `signOut()` + `/auth`; hata → türüne göre mesaj.
///
/// ## Neden iki aşama?
///
/// Google Play "Hesap Silme" politikası ve KVKK Madde 11, silmenin
/// **bilinçli** ve **onaylı** olmasını ister. Tek tıklamayla geri alınamaz
/// bir işlem, kazara veri kaybı üretir. Bu yüzden ikinci aşama zorunludur ve
/// ilk aşamadaki "Hesabımı Sil" düğmesi **parola girilmeden** hiçbir şey
/// yapmaz.
///
/// ## Sunucu sözleşmesi
///
/// Bkz. `data/repositories/account_repository.dart` sınıf dokümanı — hata
/// kodları (401/429/400/415/5xx), gövde (`{password}` yalnızca) ve kısmi
/// silme (`retryRecommended`) oradan okunmuştur.
class DeleteAccountDialog extends ConsumerStatefulWidget {
  const DeleteAccountDialog({super.key});

  /// Ayar listesinden açar.
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const DeleteAccountDialog(),
    );
  }

  @override
  ConsumerState<DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<DeleteAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _obscure = true;
  bool _submitting = false;

  @override
  void dispose() {
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  /// Parolayı boşaltır ve odağı alana döndürür.
  ///
  /// Hatalı denemeden sonra alanın temizlenmesi **güvenlik** gereğidir:
  /// kullanıcının yanlış parolayı tekrar tekrar göndermesi kotasını (2/saat)
  /// tüketir ve "boş gönderdim" sanrısı oluşturur.
  void _rejectAndRefocus() {
    _password.clear();
    setState(() {});
    _passwordFocus.requestFocus();
  }

  Future<void> _submit() async {
    if (_submitting) return; // çift gönderim engeli
    final password = _password.text.trim();
    if (password.isEmpty) {
      // Sunucu `requireString` ile de reddeder, ama boş isteği **göndermek**
      // 2/saatlik kotayı harcar. Doğrulama burada.
      _rejectAndRefocus();
      return;
    }

    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final router = ref.read(appRouterProvider);

    AccountDeletionResult result;
    try {
      result = await ref
          .read(accountRepositoryProvider)
          .deleteAccount(password: password);
    } on AccountDeletionException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(SnackBar(content: Text(_messageFor(e.kind))));
      // Parola hatalıysa alanı temizle + odak dön. Diğer hatalarda alan
      // **korunur**: kullanıcı aynı doğru parolayı tekrar deneyebilir
      // (ör. ağ hatası — parolayı yeniden yazdırmak işkence).
      if (e.kind == AccountDeletionErrorKind.wrongPassword) {
        _rejectAndRefocus();
      }
      return;
    } catch (_) {
      // Beklenmeyen hata: sınıf yoksa bile diyalog **kilitlenmez** —
      // kullanıcı tekrar deneyebilir.
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(
        SnackBar(content: Text('settings.deleteAccount.messages.failed'.tr())),
      );
      return;
    }

    // --- Sunucu **başarı** döndü (tam veya kısmi) --------------------
    //
    // `mounted` zorunluluğu: `await` sonrası `context`/`ref` kullanımı.
    if (!mounted) return;

    if (result.partial) {
      // Kısmi silme: `auth.admin.deleteUser()` BAŞARISIZ ⇒ **hesap hâlâ
      // duruyor**. "Başarıyla silindi" demek yanlış olur; kullanıcı yeniden
      // denemelidir. Düğme **yeniden etkinleşir**.
      setState(() => _submitting = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text('settings.deleteAccount.messages.partial'.tr()),
          duration: const Duration(seconds: 6),
        ),
      );
      _password.clear();
      return;
    }

    // Tam silme → oturumu düşür + cihazı temizle.
    //
    // Sıra önemlidir:
    //  1. `signOut()` — sunucu auth kaydını zaten sildi; çağırmak cihazdaki
    //     JWT'yi de atar ve router'ı `/auth`'a taşır.
    //  2. Yerel temizlik — oturum düştükten sonra yapılır, çünkü
    //     `dailyDataProvider` vb. `currentUserProvider`'a bağlı.
    //  3. `go('/auth')` — router redirect'i de buraya götürür ama
    //     açıkça çağırmak, `signOut` hata verirse bile kullanıcının
    //     giriş ekranında kaldığını garanti eder.
    await _finishDeletion(messenger: messenger, router: router);
  }

  /// Oturumu düşürür, cihazı temizler ve `/auth`'a yönlendirir.
  Future<void> _finishDeletion({
    required ScaffoldMessengerState messenger,
    required GoRouter router,
  }) async {
    await ref.read(authRepositoryProvider).signOut();
    if (!mounted) return;

    final cleanup = await ref.read(accountLocalCleanupProvider).run();
    if (!mounted) return;
    if (!cleanup.complete) {
      // Temizlik kısmen başarısız — kullanıcı **yeniden giriş yapamayacak**
      // ama bir sonraki girişte eski veriyi görebilir. Uyarı gösterilir.
      messenger.showSnackBar(
        SnackBar(
          content: Text('settings.deleteAccount.messages.localCleanup'.tr()),
          duration: const Duration(seconds: 6),
        ),
      );
    }
    if (!mounted) return;
    router.go(AppRoutes.auth);
  }

  /// Hata türü → kullanıcıya gösterilecek çeviri anahtarı.
  ///
  /// Sunucunun ham Türkçe metni **asla** gösterilmez: sunucu dili tek
  /// dildir, 12 dil arayüzde tutarsız olur ve sunucu mesajı bir tablo/kolon
  /// adı sızdırabilir. Burada yalnızca **anlam** taşınır.
  String _messageFor(AccountDeletionErrorKind kind) => switch (kind) {
        AccountDeletionErrorKind.wrongPassword =>
          'settings.deleteAccount.messages.wrongPassword'.tr(),
        AccountDeletionErrorKind.rateLimited =>
          'settings.deleteAccount.messages.rateLimited'.tr(),
        AccountDeletionErrorKind.invalidRequest =>
          'settings.deleteAccount.messages.invalidRequest'.tr(),
        AccountDeletionErrorKind.unauthorized =>
          'settings.deleteAccount.messages.unauthorized'.tr(),
        AccountDeletionErrorKind.network =>
          'settings.deleteAccount.messages.network'.tr(),
        AccountDeletionErrorKind.unknown =>
          'settings.deleteAccount.messages.failed'.tr(),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // WCAG: `AppColors.destructive` açık temada 4.30:1 (metin için yetersiz);
    // bu yüzden **tema semantik** rengi okunur (bkz. `app_theme.dart:103`).
    final destructive = theme.extension<AppSemanticColors>()?.destructive ??
        theme.colorScheme.error;
    final destructiveContainer =
        theme.colorScheme.errorContainer.withValues(alpha: 0.55);

    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: destructive, size: 32),
      title: Text(
        'settings.deleteAccount.title'.tr(),
        style: theme.textTheme.titleLarge?.copyWith(color: destructive),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('settings.deleteAccount.warning'.tr()),
            const SizedBox(height: 12),
            // Silinecek veriler — madde madde.
            for (final item in const [
              'settings.deleteAccount.data.meals',
              'settings.deleteAccount.data.water',
              'settings.deleteAccount.data.weight',
              'settings.deleteAccount.data.chat',
              'settings.deleteAccount.data.favorites',
              'settings.deleteAccount.data.settings',
              'settings.deleteAccount.data.notifications',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: TextStyle(color: destructive)),
                    Expanded(child: Text(item.tr())),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            // "Geri alınamaz" uyarısı — kırmızı zemin üzerinde koyu metin
            // yerine `onErrorContainer` (WCAG AA garantili).
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: destructiveContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.block, color: theme.colorScheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'settings.deleteAccount.irreversible'.tr(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Form(
              key: _formKey,
              child: AutofillGroup(
                child: TextFormField(
                  controller: _password,
                  focusNode: _passwordFocus,
                  // Parola yöneticisi autofill desteği — `auth_page.dart:314`
                  // ile birebir aynı (giriş yapılan mevcut parola).
                  autofillHints: const [AutofillHints.password],
                  obscureText: _obscure,
                  // Parola alanında otomatik düzeltme/öneri **kapalıdır**:
                  // `enableSuggestions` yanlışlıkla açık kalırsa iOS/Android
                  // klavyesi parolayı sözlüğe yazabilir.
                  enableSuggestions: false,
                  autocorrect: false,
                  enabled: !_submitting,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'settings.deleteAccount.passwordRequired'.tr()
                      : null,
                  decoration: InputDecoration(
                    labelText: 'settings.deleteAccount.passwordLabel'.tr(),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      tooltip: 'auth.changePassword.toggleVisibility'.tr(),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
              ),
            ),
            if (_submitting) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'settings.deleteAccount.deleting'.tr(),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          // Yükleme sırasında iptal **kapatılamaz**: kullanıcı istek
          // uçarken diyaloğu kapatırsa durum takibi kaybolur.
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: destructive,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('settings.deleteAccount.confirm'.tr()),
        ),
      ],
    );
  }
}
