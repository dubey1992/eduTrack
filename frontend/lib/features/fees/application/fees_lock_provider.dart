import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/fee_repository.dart';
import '../data/models/fees_lock.dart';

/// The fee books' date lock for a school (docs/dashboard.md, D3). The key is
/// the school picked by whoever picks one; null is the user's own.
final feesLockProvider = FutureProvider.autoDispose.family<FeesLock, int?>(
  (ref, schoolId) => ref.read(feeRepositoryProvider).booksLock(schoolId: schoolId),
);
