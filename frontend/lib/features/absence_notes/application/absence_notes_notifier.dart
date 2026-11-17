import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paginated_response.dart';
import '../data/absence_notes.dart';

/// Which notes the page lists: the ones nobody has seen yet (the default -
/// the work to do), or the ones already seen.
final absenceNotesFilterProvider = NotifierProvider<AbsenceNotesFilter, ({bool unseen, int page})>(
  AbsenceNotesFilter.new,
);

class AbsenceNotesFilter extends Notifier<({bool unseen, int page})> {
  @override
  ({bool unseen, int page}) build() => (unseen: true, page: 1);

  void show({required bool unseen}) => state = (unseen: unseen, page: 1);

  void goTo(int page) => state = (unseen: state.unseen, page: page);
}

final absenceNotesProvider = FutureProvider.autoDispose<PaginatedResponse<StaffAbsenceNote>>((ref) {
  final filter = ref.watch(absenceNotesFilterProvider);
  return ref.watch(absenceNotesRepositoryProvider).list(unseenOnly: filter.unseen, page: filter.page);
});
