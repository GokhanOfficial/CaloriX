import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../../data/repositories/auth_repository.dart';

/// Oturum değişiminde Sentry kullanıcı bağlamını günceller.
///
/// Çıkışta bağlam temizlenir; yalnızca kullanıcı UUID'i gönderilir —
/// e-posta gibi PII asla (bkz. `main.dart`: `sendDefaultPii = false`).
///
/// Bu provider **build() içinde yan etki üretir**, bu yüzden `Provider`
/// yerine `ref.listen` kullanan ayrı bir başlatıcı (`_SentryUserScope`)
/// tercih edilir: Riverpod, provider'ın `build()`'ini her yeniden
/// hesaplandığında tekrar çalıştırabilir ve Sentry kapsamına aynı kullanıcı
/// defalarca yazılırdı. `ref.listen` yalnızca gerçek değişimde tetiklenir.
final sentryUserContextProvider = Provider<void>((ref) {
  ref.listen<User?>(currentUserProvider, (previous, next) {
    if (!Sentry.isEnabled) return;
    Sentry.configureScope(
      (scope) => scope.setUser(next == null ? null : SentryUser(id: next.id)),
    );
  });
});
