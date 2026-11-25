import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paginated_response.dart';
import '../data/ptm_models.dart';
import '../data/ptm_repository.dart';

/// Whether the meetings list shows past meetings rather than those ahead.
final ptmShowPastProvider = NotifierProvider<PtmShowPast, bool>(PtmShowPast.new);

class PtmShowPast extends Notifier<bool> {
  @override
  bool build() => false;

  void show({required bool past}) => state = past;
}

/// The meetings ahead (or past): the school's for its admins, a class
/// teacher's own classes' for them.
final ptmMeetingsProvider = AsyncNotifierProvider.autoDispose<PtmMeetingsNotifier, PaginatedResponse<PtmMeeting>>(
  PtmMeetingsNotifier.new,
);

class PtmMeetingsNotifier extends AsyncNotifier<PaginatedResponse<PtmMeeting>> {
  @override
  Future<PaginatedResponse<PtmMeeting>> build() =>
      ref.read(ptmRepositoryProvider).list(past: ref.watch(ptmShowPastProvider));

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  /// Creates or changes a meeting; a [Failure] is rethrown for the form.
  Future<PtmMeeting> save(PtmMeetingDraft draft, {int? id}) async {
    final repository = ref.read(ptmRepositoryProvider);
    final saved = id == null ? await repository.create(draft) : await repository.update(id, draft);
    ref.invalidateSelf();
    return saved;
  }

  Future<void> cancelMeeting(int id) async {
    await ref.read(ptmRepositoryProvider).cancel(id);
    ref.invalidateSelf();
  }
}

/// The soonest meeting ahead, for the Staff app's Today card - none when
/// there is nothing ahead or it cannot be read: Today is not the place for
/// that error.
final ptmNextMeetingProvider = FutureProvider.autoDispose<PtmMeeting?>(
  (ref) async => (await ref.read(ptmRepositoryProvider).list(past: false)).items.where((m) => !m.cancelled).firstOrNull,
  retry: (retryCount, error) => null,
);

/// One meeting, for the heading of its class's slots.
final ptmMeetingProvider = FutureProvider.autoDispose.family<PtmMeeting, int>(
  (ref, id) => ref.read(ptmRepositoryProvider).get(id),
);

/// One class's slots in one meeting, with who booked each.
final ptmSlotsProvider = AsyncNotifierProvider.autoDispose.family<PtmSlotsNotifier, List<PtmSlot>, (int, int)>(
  PtmSlotsNotifier.new,
);

class PtmSlotsNotifier extends AsyncNotifier<List<PtmSlot>> {
  PtmSlotsNotifier(this.key);

  /// (meeting id, class section id).
  final (int, int) key;

  @override
  Future<List<PtmSlot>> build() => ref.read(ptmRepositoryProvider).slots(key.$1, key.$2);

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  /// Opens slots; returns how many new ones there are. A [Failure] is rethrown.
  Future<int> open({required String startsAt, required String endsAt, required int minutes}) async {
    final before = state.value?.length ?? 0;
    final slots = await ref
        .read(ptmRepositoryProvider)
        .openSlots(key.$1, key.$2, startsAt: startsAt, endsAt: endsAt, minutes: minutes);
    state = AsyncData(slots);
    ref.invalidate(ptmMeetingsProvider);
    return slots.length - before;
  }

  Future<void> remove(int slotId) async {
    await ref.read(ptmRepositoryProvider).removeSlot(slotId);
    state = AsyncData([
      for (final slot in state.value ?? const <PtmSlot>[])
        if (slot.id != slotId) slot,
    ]);
    ref.invalidate(ptmMeetingsProvider);
  }
}
