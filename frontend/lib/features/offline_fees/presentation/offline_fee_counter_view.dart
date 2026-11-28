import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/module_access.dart';
import '../../../core/models/user_role.dart';
import '../../auth/application/auth_notifier.dart';
import '../../offline_records/data/offline_snapshot.dart';
import '../../offline_records/presentation/offline_records_views.dart';
import 'take_offline_payment_dialog.dart';

/// Students from the computer's copy, with the fee counter's "Take a
/// payment" for those who take fees (docs/offline-web.md, O4) - Students and
/// Student Fees both open on it while the internet is down.
class OfflineFeeCounterView extends ConsumerWidget {
  const OfflineFeeCounterView({super.key, required this.snapshot});

  final OfflineSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(authNotifierProvider).value;
    final takesFees =
        actor != null && actor.role != UserRole.superAdmin && actor.canManage(AppModules.fees) && snapshot.dues != null;

    return OfflineStudentsView(
      snapshot: snapshot,
      onTakePayment: takesFees
          ? (context, student) => showTakeOfflinePaymentDialog(context, snapshot: snapshot, student: student)
          : null,
    );
  }
}
