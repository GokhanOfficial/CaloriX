import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../data/repositories/auth_repository.dart';

/// Web `AuthPage.tsx` karşılığı — 4 görünüm:
/// auth (giriş/kayıt), forgot-password, pending-verification, reset-password.
enum _AuthView { auth, forgotPassword, pendingVerification, resetPassword }

class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({super.key});

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  final _formKey = GlobalKey<FormState>();

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();

  bool _isLoading = false;
  _AuthView _view = _AuthView.auth;
  String _pendingEmail = '';
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _displayNameCtrl.dispose();
    super.dispose();
  }

  AuthRepository get _auth => ref.read(authRepositoryProvider);

  // ---- yardımcılar -------------------------------------------------------

  void _toast(String message, {bool isError = false}) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? scheme.error : null,
      ),
    );
  }

  String? _validateEmail(String? v) {
    final value = (v ?? '').trim();
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
    if (!ok) return 'auth.validation.invalidEmail'.tr();
    return null;
  }

  String? _validatePassword(String? v) {
    if ((v ?? '').length < 6) return 'auth.validation.passwordLength'.tr();
    return null;
  }

  void _setLoading(bool v) => setState(() => _isLoading = v);

  // ---- aksiyonlar --------------------------------------------------------

  Future<void> _handleSignIn() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _setLoading(true);
    final err = await _auth.signIn(_emailCtrl.text.trim(), _passwordCtrl.text);
    _setLoading(false);
    if (!mounted) return;

    if (err != null) {
      final msg = err.message;
      if (msg.contains('Invalid login credentials')) {
        _toast('auth.validation.invalidLogin'.tr(), isError: true);
      } else if (msg.contains('Email not confirmed')) {
        _toast('auth.validation.emailNotConfirmed'.tr(), isError: true);
        setState(() {
          _pendingEmail = _emailCtrl.text.trim();
          _view = _AuthView.pendingVerification;
        });
      } else {
        _toast(msg, isError: true);
      }
      return;
    }
    // Başarılı girişte router redirect dashboard'a taşır.
  }

  Future<void> _handleSignUp() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _setLoading(true);
    final err = await _auth.signUp(
      _emailCtrl.text.trim(),
      _passwordCtrl.text,
      displayName:
          _displayNameCtrl.text.trim().isEmpty ? null : _displayNameCtrl.text.trim(),
    );
    _setLoading(false);
    if (!mounted) return;

    if (err != null) {
      final msg = err.message;
      if (msg.contains('User already registered')) {
        _toast('auth.validation.userAlreadyRegistered'.tr(), isError: true);
      } else if (msg.contains('Password should be')) {
        _toast('auth.validation.passwordLength'.tr(), isError: true);
      } else {
        _toast(msg, isError: true);
      }
      return;
    }
    _toast('auth.messages.verificationSent'.tr());
    setState(() {
      _pendingEmail = _emailCtrl.text.trim();
      _view = _AuthView.pendingVerification;
    });
  }

  Future<void> _handleForgotPassword() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _setLoading(true);
    final err = await _auth.resetPassword(_emailCtrl.text.trim());
    _setLoading(false);
    if (!mounted) return;

    if (err != null) {
      _toast(err.message, isError: true);
    } else {
      _toast('auth.messages.resetEmailSent'.tr());
      setState(() => _view = _AuthView.auth);
    }
  }

  Future<void> _handleResetPassword() async {
    final newPw = _newPasswordCtrl.text;
    if (newPw.length < 6) {
      _toast('auth.validation.passwordLength'.tr(), isError: true);
      return;
    }
    if (newPw != _confirmPasswordCtrl.text) {
      _toast('auth.validation.passwordMismatch'.tr(), isError: true);
      return;
    }
    _setLoading(true);
    final err = await _auth.updatePassword(newPw);
    _setLoading(false);
    if (!mounted) return;

    if (err != null) {
      _toast(err.message, isError: true);
    } else {
      _toast('auth.messages.passwordUpdated'.tr());
      context.go(AppRoutes.dashboard);
    }
  }

  Future<void> _handleResendVerification() async {
    _setLoading(true);
    final err = await _auth.resendVerificationEmail();
    _setLoading(false);
    if (!mounted) return;
    if (err != null) {
      _toast(err.message, isError: true);
    } else {
      _toast('auth.messages.verificationSent'.tr());
    }
  }

  Future<void> _handleSignOutAndBack() async {
    await _auth.signOut();
    if (!mounted) return;
    setState(() {
      _view = _AuthView.auth;
      _pendingEmail = '';
    });
  }

  // ---- görünümler --------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // PASSWORD_RECOVERY eventi → reset-password görünümü
    ref.listen(passwordRecoveryProvider, (_, next) {
      if (next.valueOrNull ?? false) {
        setState(() => _view = _AuthView.resetPassword);
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: switch (_view) {
                _AuthView.pendingVerification => _buildPendingVerification(),
                _AuthView.resetPassword => _buildResetPassword(),
                _AuthView.forgotPassword => _buildForgotPassword(),
                _AuthView.auth => _buildMainAuth(),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _logo({double size = 80}) => Column(
        children: [
          Image.asset('assets/images/logo.png', width: size, height: size),
          const SizedBox(height: 12),
          Text(
            'common.appName'.tr(),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ],
      );

  Widget _buildMainAuth() {
    return Column(
      children: [
        _logo(size: 96),
        const SizedBox(height: 8),
        Text(
          'auth.tagline'.tr(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
        const SizedBox(height: 24),
        Card(
          child: DefaultTabController(
            length: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    TabBar(
                      tabs: [
                        Tab(text: 'auth.signInTab'.tr()),
                        Tab(text: 'auth.signUpTab'.tr()),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _textField(
                      controller: _emailCtrl,
                      label: 'auth.email'.tr(),
                      icon: Icons.mail_outline,
                      keyboardType: TextInputType.emailAddress,
                      validator: _validateEmail,
                    ),
                    const SizedBox(height: 16),
                    _textField(
                      controller: _passwordCtrl,
                      label: 'auth.password'.tr(),
                      icon: Icons.lock_outline,
                      obscure: _obscure,
                      validator: _validatePassword,
                      suffix: IconButton(
                        icon: Icon(
                            _obscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () =>
                            setState(() => _view = _AuthView.forgotPassword),
                        child: Text('auth.forgotPassword'.tr()),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _textField(
                      controller: _displayNameCtrl,
                      label: 'auth.nameOptional'.tr(),
                      icon: Icons.person_outline,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: _isLoading ? null : _handleSignIn,
                            child: _isLoading
                                ? const _Spinner()
                                : Text('auth.signIn'.tr()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isLoading ? null : _handleSignUp,
                            child: Text('auth.signUp'.tr()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'common.healthDisclaimer'.tr(),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildForgotPassword() {
    return Column(
      children: [
        _logo(),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextButton.icon(
                    onPressed: () => setState(() => _view = _AuthView.auth),
                    icon: const Icon(Icons.arrow_back),
                    label: Text('common.back'.tr()),
                    style: TextButton.styleFrom(
                        alignment: Alignment.centerLeft),
                  ),
                  Text('auth.forgotPasswordTitle'.tr(),
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text('auth.forgotPasswordDesc'.tr(),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.outline)),
                  const SizedBox(height: 20),
                  _textField(
                    controller: _emailCtrl,
                    label: 'auth.email'.tr(),
                    icon: Icons.mail_outline,
                    keyboardType: TextInputType.emailAddress,
                    validator: _validateEmail,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _isLoading ? null : _handleForgotPassword,
                    child: _isLoading
                        ? const _Spinner()
                        : Text('auth.sendResetLink'.tr()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPendingVerification() {
    return Column(
      children: [
        _logo(),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.mark_email_read_outlined,
                    size: 48, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 12),
                Text('auth.pendingVerification.title'.tr(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'auth.pendingVerification.description'
                      .tr(args: [_pendingEmail]),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'auth.pendingVerification.spamNote'.tr(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _handleResendVerification,
                  icon: _isLoading
                      ? const _Spinner()
                      : const Icon(Icons.refresh),
                  label: Text('common.resend'.tr()),
                ),
                TextButton.icon(
                  onPressed: _handleSignOutAndBack,
                  icon: const Icon(Icons.arrow_back),
                  label:
                      Text('auth.pendingVerification.differentAccount'.tr()),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResetPassword() {
    return Column(
      children: [
        _logo(),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('auth.resetPasswordTitle'.tr(),
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text('auth.resetPasswordDesc'.tr(),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.outline)),
                const SizedBox(height: 20),
                _textField(
                  controller: _newPasswordCtrl,
                  label: 'auth.newPassword'.tr(),
                  icon: Icons.lock_outline,
                  obscure: _obscure,
                ),
                const SizedBox(height: 16),
                _textField(
                  controller: _confirmPasswordCtrl,
                  label: 'auth.confirmPassword'.tr(),
                  icon: Icons.lock_outline,
                  obscure: _obscure,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _isLoading ? null : _handleResetPassword,
                  child: _isLoading
                      ? const _Spinner()
                      : Text('auth.updatePassword'.tr()),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    bool obscure = false,
    Widget? suffix,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      validator: validator,
      enabled: !_isLoading,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: suffix,
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
}
