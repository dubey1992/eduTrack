import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_notifier.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../widgets/splash_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _AuthRefreshNotifier(ref);
  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refreshNotifier,
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/', builder: (context, state) => const DashboardScreen()),
    ],
    redirect: (context, state) {
      final authState = ref.read(authNotifierProvider);
      final location = state.matchedLocation;

      if (authState.isLoading) {
        return location == '/splash' ? null : '/splash';
      }

      final isLoggedIn = authState.value != null;

      if (!isLoggedIn) {
        return location == '/login' ? null : '/login';
      }

      if (location == '/login' || location == '/splash') {
        return '/';
      }

      return null;
    },
  );
});

/// Bridges Riverpod's [authNotifierProvider] changes to go_router's
/// [Listenable]-based refresh mechanism, so navigation redirects re-run
/// whenever the session state changes (login, logout, restore).
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    _subscription = ref.listen<AsyncValue<Object?>>(
      authNotifierProvider,
      (previous, next) => notifyListeners(),
    );
  }

  late final ProviderSubscription<AsyncValue<Object?>> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}
