import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dio_client.dart';

/// Whether the API is currently answering "we are down for maintenance".
///
/// Set by the Dio interceptor the moment any request comes back 503, because
/// a maintenance window is not a failure of the screen somebody happens to be
/// on - it is every screen at once. The router reads this and holds the whole
/// app on the maintenance page rather than letting them walk from one broken
/// screen to the next.
final maintenanceProvider = NotifierProvider<MaintenanceNotifier, bool>(MaintenanceNotifier.new);

class MaintenanceNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void reportUnavailable() {
    if (!state) state = true;
  }

  /// Asks the API whether it is back yet.
  ///
  /// Any answer that is not another 503 means it is - a 401 is the server
  /// telling us to sign in, which it can only do while it is running. Only a
  /// 503, or no answer at all, keeps us here.
  Future<bool> recheck() async {
    try {
      await ref.read(dioClientProvider).get('/me');
      state = false;
      return true;
    } on DioException catch (e) {
      final status = e.response?.statusCode;

      // No response at all is a network problem, not proof the window has
      // ended - staying put is the honest answer.
      if (status == null || status == 503) return false;

      state = false;
      return true;
    }
  }
}
