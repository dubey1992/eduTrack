import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../attendance/data/attendance_repository.dart';
import '../../auth/application/auth_notifier.dart';
import '../../today/application/today_notifier.dart';
import '../data/models/saved_register.dart';
import '../data/register_store.dart';

/// Registers waiting to be sent, registers the server turned down, and
/// whether sending is going on or failing for want of signal.
class RegisterQueueState {
  const RegisterQueueState({
    this.waiting = const [],
    this.unsent = const [],
    this.sending = false,
    this.offline = false,
  });

  /// Oldest first - the order they are sent in.
  final List<SavedRegister> waiting;
  final List<UnsentRegister> unsent;
  final bool sending;

  /// The last attempt could not reach the server.
  final bool offline;

  SavedRegister? waitingFor(int sectionId, String date) {
    for (final register in waiting) {
      if (register.isFor(sectionId, date)) return register;
    }
    return null;
  }

  UnsentRegister? unsentFor(int sectionId, String date) {
    for (final register in unsent) {
      if (register.isFor(sectionId, date)) return register;
    }
    return null;
  }

  RegisterQueueState copyWith({
    List<SavedRegister>? waiting,
    List<UnsentRegister>? unsent,
    bool? sending,
    bool? offline,
  }) {
    return RegisterQueueState(
      waiting: waiting ?? this.waiting,
      unsent: unsent ?? this.unsent,
      sending: sending ?? this.sending,
      offline: offline ?? this.offline,
    );
  }
}

final registerQueueProvider = NotifierProvider<RegisterQueue, RegisterQueueState>(RegisterQueue.new);

/// The class register, offline-tolerant (docs/teacher-app.md, T2) - the bus
/// app's trip-mark queue (my_trip/application/trip_mark_queue.dart) for a
/// whole register at a time.
///
/// A register is saved on the phone before anything else, so Submit is
/// instant and survives the app being closed. Sending starts at once; with
/// no signal it is tried again after 5, 15, 30 and then every 60 seconds,
/// and whenever the app comes back to the front. The server takes a second
/// send of the same teacher's same marks as done, so a resend after a lost
/// answer is harmless. A register it refuses - somebody else took it, a
/// closed day, too late - cannot succeed by retrying and moves to "not
/// sent" with the server's own reason.
class RegisterQueue extends Notifier<RegisterQueueState> {
  static const retryDelays = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];

  Timer? _retryTimer;
  int _failures = 0;
  late Future<void> _loaded;

  RegisterStore get _store => ref.read(registerStoreProvider);

  int? get _me => ref.read(authNotifierProvider).value?.id;

  /// Completes once the registers saved on the phone have been read, so a
  /// screen opened straight after the app starts sees them.
  Future<void> get ready => _loaded;

  @override
  RegisterQueueState build() {
    ref.onDispose(() => _retryTimer?.cancel());
    _loaded = _load();
    return const RegisterQueueState();
  }

  Future<void> _load() async {
    final waiting = await _store.readWaiting();
    final unsent = await _store.readUnsent();
    if (!ref.mounted) return;

    state = state.copyWith(waiting: [...waiting, ...state.waiting], unsent: [...unsent, ...state.unsent]);
    if (waiting.isNotEmpty) unawaited(flush());
  }

  /// Saves [register] on the phone and sends it. Completes once it has
  /// either landed or been kept for later - never throws for want of signal.
  Future<void> submit(SavedRegister register) async {
    await _loaded;
    if (!ref.mounted) return;

    state = state.copyWith(
      waiting: [
        for (final r in state.waiting)
          if (!r.isFor(register.classSectionId, register.date)) r,
        register,
      ],
      // A fresh attempt replaces an old refusal for the same register.
      unsent: [
        for (final r in state.unsent)
          if (!r.isFor(register.classSectionId, register.date)) r,
      ],
    );
    await _store.saveWaiting(state.waiting);
    await _store.saveUnsent(state.unsent);
    await flush();
  }

  /// Tries now rather than waiting out the back-off.
  Future<void> retryNow() async {
    _retryTimer?.cancel();
    _failures = 0;
    await flush();
  }

  /// Puts a refusal away once it has been read.
  Future<void> dismiss(String clientId) async {
    state = state.copyWith(
      unsent: [
        for (final r in state.unsent)
          if (r.clientId != clientId) r,
      ],
    );
    await _store.saveUnsent(state.unsent);
  }

  /// Sends the signed-in person's waiting registers, oldest first.
  Future<void> flush() async {
    await _loaded;
    final me = _me;
    if (!ref.mounted || state.sending || me == null) return;

    final mine = [
      for (final r in state.waiting)
        if (r.userId == me) r,
    ];
    if (mine.isEmpty) return;

    _retryTimer?.cancel();
    state = state.copyWith(sending: true);

    try {
      for (final register in mine) {
        await _send(register);
      }
      _failures = 0;
      if (ref.mounted) state = state.copyWith(sending: false, offline: false);
    } on Failure catch (failure) {
      if (failure.code != 'NETWORK_ERROR') debugPrint('Sending a register failed: ${failure.code}');
      _scheduleRetry();
    } catch (error) {
      // A bug rather than a lost signal - but the register is still kept.
      debugPrint('Sending a register failed unexpectedly: $error');
      _scheduleRetry();
    }
  }

  Future<void> _send(SavedRegister register) async {
    try {
      await ref
          .read(attendanceRepositoryProvider)
          .submit(classSectionId: register.classSectionId, attendanceDate: register.date, records: register.records);
      await _settle(register);
    } on Failure catch (failure) {
      if (failure.code == 'NETWORK_ERROR') rethrow;
      await _settle(register, refusedBecause: failure.message);
    }
    // Today's card reads "taken" or "not sent" from the server and this
    // queue; ask it again now either has changed.
    if (ref.mounted) ref.invalidate(todayProvider);
  }

  Future<void> _settle(SavedRegister register, {String? refusedBecause}) async {
    if (!ref.mounted) return;

    state = state.copyWith(
      waiting: [
        for (final r in state.waiting)
          if (r.clientId != register.clientId) r,
      ],
      unsent: refusedBecause == null ? state.unsent : [...state.unsent, UnsentRegister.of(register, refusedBecause)],
    );
    await _store.saveWaiting(state.waiting);
    if (refusedBecause != null) await _store.saveUnsent(state.unsent);
  }

  void _scheduleRetry() {
    if (!ref.mounted) return;

    _failures++;
    state = state.copyWith(sending: false, offline: true);

    final delay = retryDelays[min(_failures, retryDelays.length) - 1];
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, flush);
  }
}

/// A fresh id for a register saved on this phone.
String newRegisterClientId() {
  final random = Random.secure();
  return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}
