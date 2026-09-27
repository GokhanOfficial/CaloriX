import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_constants.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../features/about/about_page.dart';
import '../../features/add/add_page.dart';
import '../../features/analytics/analytics_page.dart';
import '../../features/analytics/macro_focus.dart';
import '../../features/auth/auth_page.dart';
import '../../features/chat/chat_page.dart';
import '../../features/dashboard/dashboard_page.dart';
import '../../features/not_found/not_found_page.dart';
import '../../features/onboarding/onboarding_page.dart';
import '../../features/settings/settings_page.dart';
import '../../shared/widgets/app_shell.dart';

/// Route yolları — web (React Router) ile birebir aynı path'ler.
abstract final class AppRoutes {
  static const auth = '/auth';
  static const onboarding = '/onboarding';
  static const dashboard = '/';
  static const add = '/add';
  static const analytics = '/analytics';
  static const settings = '/settings';
  static const chat = '/chat';
  static const about = '/about';
}

/// Router'ı auth/onboarding durumuna göre yönlendiren birleşik durum.
///
/// Üç durum:
///  - `loading`  → oturum/profil henüz çözülmedi (splash benzeri bekletme)
///  - diğerleri  → hedef route hesaplanır
sealed class _RouteDecision {
  const _RouteDecision();
}

final class _RouteLoading extends _RouteDecision {
  const _RouteLoading();
}

final class _RouteReady extends _RouteDecision {
  const _RouteReady(this.location);

  /// Kullanıcının gitmesi gereken kanonik konum (null = istenen route'a izin ver).
  final String? location;
}

/// Auth + profil durumunu izleyip hedef route'u hesaplar.
final _routeDecisionProvider = Provider<_RouteDecision>((ref) {
  final authAsync = ref.watch(authStateProvider);

  // Oturum stream'i henüz ilk değeri vermediyse beklet.
  if (authAsync.isLoading && !authAsync.hasValue) {
    return const _RouteLoading();
  }

  final user = ref.watch(currentUserProvider);

  // 1) Oturum yok → /auth
  if (user == null) {
    return const _RouteReady(AppRoutes.auth);
  }

  // PASSWORD_RECOVERY → /auth (yeni şifre formu)
  final isRecovery = ref.watch(passwordRecoveryProvider).valueOrNull ?? false;
  if (isRecovery) {
    return const _RouteReady(AppRoutes.auth);
  }

  // 2) Oturum var → profil/onboarding durumuna bak
  final profileAsync = ref.watch(profileProvider);
  return profileAsync.when(
    loading: () => const _RouteLoading(),
    error: (_, _) {
      // Profil okunamadı. İki farklı kök neden var:
      //  - profil **yok** (yeni kullanıcı) → onboarding akışı,
      //  - profil var ama okuma başarısız (ağ kesintisi, tablo yok) →
      //    onboarding'e zorlamak kullanıcıyı tamamlanmış akışa geri
      //    atıp verisini ezme riskine sokar.
      // Belirsizlikte **hiçbir yöne zorlamayız**: mevcut route'ta kalıp
      // yeniden denemeye izin ver (PASSWORD_RECOVERY / auth zaten yukarıda
      // ele alınıyor). Kullanıcı /onboarding'e gitmek isterse yönlendirme
      // engellenmez — `target: null` yalnızca otomatik çekmeyi kapatır.
      return const _RouteReady(null);
    },
    data: (profile) {
      final done = profile?.isOnboardingComplete ?? false;
      return _RouteReady(done ? null : AppRoutes.onboarding);
    },
  );
});

final appRouterProvider = Provider<GoRouter>((ref) {
  // redirect içinde provider'ı okumak için ref'i yakala.
  final router = GoRouter(
    initialLocation: AppRoutes.dashboard,
    refreshListenable: _RouterRefresh(ref),
    redirect: (context, state) {
      final decision = ref.read(_routeDecisionProvider);

      // Karar henüz hazır değilse yönlendirme yapma (mevcut route'ta kal).
      if (decision is _RouteLoading) return null;

      final target = (decision as _RouteReady).location;
      final goingTo = state.matchedLocation;

      // Serbest (girişli + onboarding tamamlı): /auth veya /onboarding'de
      // kaldıysa → /dashboard'a çek. Bu, onboarding "Kaydet" sonrası
      // `ref.invalidate(profileProvider)` + `context.go` race'ini kökten
      // çözer: invalidate → _routeDecisionProvider target=null →
      // _RouterRefresh notifyListeners → redirect goingTo=/onboarding +
      // target==null → /dashboard. Login sonrası /auth'ta kalanı da taşır.
      if (target == null) {
        if (goingTo == AppRoutes.auth || goingTo == AppRoutes.onboarding) {
          return AppRoutes.dashboard;
        }
        return null;
      }

      // Auth'a gitmesi gerekiyorsa ve zaten auth'ta değilse → auth.
      if (target == AppRoutes.auth && goingTo != AppRoutes.auth) {
        return AppRoutes.auth;
      }
      // Onboarding'e gitmesi gerekiyorsa ve orada değilse → onboarding.
      if (target == AppRoutes.onboarding && goingTo != AppRoutes.onboarding) {
        return AppRoutes.onboarding;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.auth,
        builder: (context, state) => const AuthPage(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingPage(),
      ),
      // 5 ana sekme — web `Layout.tsx` karşılığı alt navigasyon kabuğu.
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.dashboard,
            builder: (context, state) => const DashboardPage(),
          ),
          GoRoute(
            path: AppRoutes.add,
            builder: (context, state) {
              final meal =
                  state.extra is MealType ? state.extra as MealType : null;
              return AddPage(initialMealType: meal);
            },
          ),
          GoRoute(
            path: AppRoutes.analytics,
            builder: (context, state) {
              final macro = MacroFocus.fromName(
                state.uri.queryParameters['macro'],
              );
              return AnalyticsPage(focusedMacro: macro);
            },
          ),
          GoRoute(
            path: AppRoutes.chat,
            builder: (context, state) => const ChatPage(),
          ),
          GoRoute(
            path: AppRoutes.settings,
            builder: (context, state) => const SettingsPage(),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.about,
        builder: (context, state) => const AboutPage(),
      ),
    ],
    errorBuilder: (context, state) => const NotFoundPage(),
  );
  // GoRouter dinleyici/abonelik kayıtları tutar; provider iptal edilirse
  // (container dispose, test) kapatılmalı — aksi halde sızıntı.
  ref.onDispose(router.dispose);
  return router;
});

/// Riverpod dinlemesini go_router `refreshListenable`'a bağlayan köprü.
///
/// `ref.listen` zaten provider ömrüne bağlıdır (kendi kendine iptal edilir),
/// bu yüzden ek bir kapatma gerekmez; sınıf yalnızca `notifyListeners`
/// adaptörüdür.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(_routeDecisionProvider, (_, _) => notifyListeners());
  }
}
