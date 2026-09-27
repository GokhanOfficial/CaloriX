import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/auth_repository.dart';

/// Şifre değiştir diyaloğu — web ile aynı: başlıklar sabit Türkçe,
/// validasyon mesajları `auth.validation.*` çevirilerinden.
///
/// Min 6 karakter + eşleşme; `authRepositoryProvider.updatePassword`.
class PasswordDialog extends ConsumerStatefulWidget {
  const PasswordDialog({super.key});

  static Future<void> show(BuildContext context, WidgetRef ref) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: const PasswordDialog(),
      ),
    );
  }

  @override
  ConsumerState<PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends ConsumerState<PasswordDialog> {
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  bool _obscure = true;

  @override
  void dispose() {
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_new.text.length < 6) {
      messenger.showSnackBar(
        SnackBar(content: Text('auth.validation.passwordLength'.tr())),
      );
      return;
    }
    if (_new.text != _confirm.text) {
      messenger.showSnackBar(
        SnackBar(content: Text('auth.validation.passwordMismatch'.tr())),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final err = await ref
          .read(authRepositoryProvider)
          .updatePassword(_new.text);
      if (!mounted) return;
      if (err != null) {
        messenger.showSnackBar(
          SnackBar(content: Text('settings.messages.error'.tr())),
        );
        return;
      }
      // Önce SnackBar, sonra pop: `pop` sonrasında bu dialog'un context'i
      // kullanılamaz hale geliyordu.
      messenger.showSnackBar(
        SnackBar(content: Text('settings.messages.passwordChanged'.tr())),
      );
      Navigator.of(context).pop();
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text('settings.messages.error'.tr())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('auth.changePassword.title'.tr(),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('auth.changePassword.subtitle'.tr(),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          TextField(
            controller: _new,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'auth.changePassword.newLabel'.tr(),
              hintText: 'auth.validation.passwordLength'.tr(),
              suffixIcon: IconButton(
                icon: Icon(_obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                tooltip: 'auth.changePassword.toggleVisibility'.tr(),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirm,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'auth.changePassword.confirmLabel'.tr(),
              hintText: 'auth.changePassword.confirmHint'.tr(),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: Text('common.cancel'.tr()),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('common.save'.tr()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
