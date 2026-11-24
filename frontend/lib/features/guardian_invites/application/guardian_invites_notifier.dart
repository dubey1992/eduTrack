import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paginated_response.dart';
import '../data/guardian_invites.dart';

/// Which requests the page lists - waiting ones by default, the work to do -
/// and which page.
final guardianInvitesFilterProvider =
    NotifierProvider<GuardianInvitesFilter, ({GuardianInviteStatus status, int page})>(GuardianInvitesFilter.new);

class GuardianInvitesFilter extends Notifier<({GuardianInviteStatus status, int page})> {
  @override
  ({GuardianInviteStatus status, int page}) build() => (status: GuardianInviteStatus.pending, page: 1);

  void show(GuardianInviteStatus status) => state = (status: status, page: 1);

  void goTo(int page) => state = (status: state.status, page: page);
}

final guardianInvitesProvider = FutureProvider.autoDispose<PaginatedResponse<GuardianInvite>>((ref) {
  final filter = ref.watch(guardianInvitesFilterProvider);
  return ref.watch(guardianInvitesRepositoryProvider).list(status: filter.status, page: filter.page);
});
