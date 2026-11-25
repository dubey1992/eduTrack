import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/family_repository.dart';
import '../data/models/family_meeting.dart';

/// One child's parent-teacher meetings ahead (docs/mobile-apps-review.md,
/// M12, 8.4), with booking, moving and cancelling.
final familyMeetingsProvider = AsyncNotifierProvider.autoDispose
    .family<FamilyMeetingsNotifier, List<FamilyMeeting>, int>(
      FamilyMeetingsNotifier.new,
      retry: (retryCount, error) => null,
    );

class FamilyMeetingsNotifier extends AsyncNotifier<List<FamilyMeeting>> {
  FamilyMeetingsNotifier(this.childId);

  final int childId;

  @override
  Future<List<FamilyMeeting>> build() => ref.read(familyRepositoryProvider).meetings(childId);

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  /// Books [slotId], moving an earlier booking for the same meeting. A
  /// [Failure] is rethrown for the screen to show; when someone else took
  /// the slot first the list is read again so the screen shows it taken.
  Future<void> book(int meetingId, int slotId) =>
      _change(() => ref.read(familyRepositoryProvider).bookMeeting(childId, meetingId, slotId));

  Future<void> cancel(int meetingId) =>
      _change(() => ref.read(familyRepositoryProvider).cancelMeeting(childId, meetingId));

  Future<void> _change(Future<FamilyMeeting> Function() request) async {
    try {
      final changed = await request();
      final current = state.value ?? const <FamilyMeeting>[];
      state = AsyncData([for (final meeting in current) meeting.id == changed.id ? changed : meeting]);
    } catch (_) {
      state = await AsyncValue.guard(build);
      rethrow;
    }
  }
}
