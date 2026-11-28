import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/network/connection_status.dart';
import '../../auth/application/auth_notifier.dart';
import '../data/offline_records_store.dart';
import '../data/offline_snapshot.dart';

/// The trusted computer's copy of records for working offline
/// (docs/offline-web.md, O2, decided 2026-11-28).
///
/// The rules that keep it safe, all here:
/// - kept only when the person ticked "This is a school computer I trust" at
///   sign-in, and only where the school allows offline copies (/me);
/// - it belongs to that one person: anybody else signing in on the computer
///   finds nothing, and the earlier copy is wiped;
/// - never older than [maxAge] - the session's own idle limit - and wiped at
///   sign-out and when the server ends the session (auth_notifier);
/// - refreshed at sign-in, every [refreshEvery] while online, and when the
///   connection returns - never more often than the server allows.
class OfflineRecordsState {
  const OfflineRecordsState({this.trusted = false, this.snapshot, this.refreshing = false});

  final bool trusted;
  final OfflineSnapshot? snapshot;
  final bool refreshing;
}

final offlineRecordsProvider = NotifierProvider<OfflineRecordsNotifier, OfflineRecordsState>(
  OfflineRecordsNotifier.new,
);

class OfflineRecordsNotifier extends Notifier<OfflineRecordsState> {
  static const refreshEvery = Duration(minutes: 30);
  static const maxAge = Duration(days: 7);

  Timer? _timer;
  StreamSubscription<void>? _reconnected;

  OfflineRecordsStore get _store => ref.read(offlineRecordsStoreProvider);

  @override
  OfflineRecordsState build() {
    ref.onDispose(() {
      _timer?.cancel();
      _reconnected?.cancel();
    });
    if (!ref.read(offlineWorkProvider)) return const OfflineRecordsState();

    ref.listen(
      authNotifierProvider.select((auth) => auth.value?.id),
      (_, userId) => _load(userId),
      fireImmediately: true,
    );
    _reconnected = ref.read(connectionStatusProvider.notifier).onReconnected.listen((_) => refresh());
    _timer = Timer.periodic(refreshEvery, (_) => refresh());
    return const OfflineRecordsState();
  }

  /// After a sign-in: the tick on the sign-in form.
  Future<void> setTrusted(bool trusted) async {
    final user = ref.read(authNotifierProvider).value;
    if (!ref.read(offlineWorkProvider) || user == null) return;

    if (!trusted || !user.offlineCopies) {
      await _store.clear();
      state = const OfflineRecordsState();
      return;
    }
    await _store.trust(user.id);
    state = OfflineRecordsState(trusted: true, snapshot: state.snapshot);
    await refresh();
  }

  /// Asks the server for a fresh copy, when there is one to ask for.
  Future<void> refresh() async {
    final user = ref.read(authNotifierProvider).value;
    if (!state.trusted || user == null || !user.offlineCopies || state.refreshing) return;
    if (!ref.read(connectionStatusProvider)) return;

    state = OfflineRecordsState(trusted: true, snapshot: state.snapshot, refreshing: true);
    try {
      final json = await ref.read(offlineSnapshotApiProvider).fetch();
      await _store.save(json);
      if (!ref.mounted) return;
      state = OfflineRecordsState(trusted: true, snapshot: OfflineSnapshot.fromJson(json));
    } on Failure catch (failure) {
      // The school switched copies off: nothing may stay on the computer.
      if (failure.code == 'OFFLINE_COPIES_OFF') {
        await _store.clear();
        if (ref.mounted) state = const OfflineRecordsState();
        return;
      }
      debugPrint('The offline copy could not be refreshed: ${failure.code}');
      if (ref.mounted) state = OfflineRecordsState(trusted: true, snapshot: state.snapshot);
    }
  }

  /// At sign-out and when the server ends the session.
  Future<void> clear() async {
    await _store.clear();
    if (ref.mounted) state = const OfflineRecordsState();
  }

  Future<void> _load(int? userId) async {
    if (userId == null) {
      state = const OfflineRecordsState();
      return;
    }
    // Another person's copy is never shown, and never left behind.
    if (!await _store.isTrustedBy(userId)) {
      await _store.clear();
      if (ref.mounted) state = const OfflineRecordsState();
      return;
    }

    var snapshot = await _store.read();
    if (snapshot != null && DateTime.now().difference(snapshot.generatedAt) > maxAge) {
      await _store.clear();
      await _store.trust(userId);
      snapshot = null;
    }
    if (!ref.mounted) return;
    state = OfflineRecordsState(trusted: true, snapshot: snapshot);
    unawaited(refresh());
  }
}
