import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/school.dart';
import '../data/school_repository.dart';

/// One school, fetched by id.
///
/// Asked for rather than taken from the list: the page is reachable by its
/// own URL, so a reload - or a link somebody was sent - has no list in hand
/// to take a row from. The server scopes it, so an id outside the actor's
/// reach is a 404 here as it is everywhere else.
final schoolDetailProvider = FutureProvider.autoDispose.family<School, int>((ref, schoolId) {
  return ref.read(schoolRepositoryProvider).find(schoolId);
});
