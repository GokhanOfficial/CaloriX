import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/about/about_page.dart';
import '../../features/add/add_page.dart';
import '../../features/analytics/analytics_page.dart';
import '../../features/auth/auth_page.dart';
import '../../features/chat/chat_page.dart';
import '../../features/dashboard/dashboard_page.dart';
import '../../features/not_found/not_found_page.dart';
import '../../features/onboarding/onboarding_page.dart';
import '../../features/settings/settings_page.dart';

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

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.dashboard,
    // TODO(Faz 1): auth redirect — oturum yoksa /auth, onboarding
    // tamamlanmamışsa /onboarding. Şimdilik tüm route'lar açık
    // (veritabanı deaktif olduğundan auth akışı canlı test edilemiyor).
    routes: [
      GoRoute(
        path: AppRoutes.auth,
        builder: (context, state) => const AuthPage(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingPage(),
      ),
      GoRoute(
        path: AppRoutes.dashboard,
        builder: (context, state) => const DashboardPage(),
      ),
      GoRoute(
        path: AppRoutes.add,
        builder: (context, state) => const AddPage(),
      ),
      GoRoute(
        path: AppRoutes.analytics,
        builder: (context, state) => const AnalyticsPage(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: AppRoutes.chat,
        builder: (context, state) => const ChatPage(),
      ),
      GoRoute(
        path: AppRoutes.about,
        builder: (context, state) => const AboutPage(),
      ),
    ],
    errorBuilder: (context, state) => const NotFoundPage(),
  );
});
