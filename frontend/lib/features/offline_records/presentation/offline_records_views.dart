import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/connection_status.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_format.dart';
import '../application/offline_records_notifier.dart';
import '../data/offline_snapshot.dart';

/// Shows [offline] instead of [online] while the server cannot be reached
/// and this computer keeps a copy to show (docs/offline-web.md, O2) -
/// otherwise [online], exactly as it always was.
class OfflineAware extends ConsumerWidget {
  const OfflineAware({super.key, required this.online, required this.offline});

  final Widget online;
  final Widget Function(OfflineSnapshot snapshot) offline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = ref.watch(connectionStatusProvider);
    final snapshot = ref.watch(offlineRecordsProvider).snapshot;
    if (connected || snapshot == null) return online;
    return offline(snapshot);
  }
}

/// "As of 9:40 AM today" - every offline screen says how old its copy is.
String offlineAsOf(DateTime generatedAt) {
  final now = DateTime.now();
  final sameDay = now.year == generatedAt.year && now.month == generatedAt.month && now.day == generatedAt.day;
  return sameDay
      ? 'As of ${formatDateTime(generatedAt).split(' ').skip(1).join(' ')} today'
      : 'As of ${formatDateTime(generatedAt)}';
}

class _OfflineHeader extends StatelessWidget {
  const _OfflineHeader({required this.title, required this.snapshot, required this.search, required this.onSearch});

  final String title;
  final OfflineSnapshot snapshot;
  final String search;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    final muted = context.appColors.muted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          '${offlineAsOf(snapshot.generatedAt)} - the copy kept on this computer. '
          'Changes need the connection.',
          key: const Key('offline-as-of'),
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: 420,
          child: TextField(
            key: const Key('offline-search'),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search'),
            onChanged: onSearch,
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// Students, read from the computer's copy.
class OfflineStudentsView extends StatefulWidget {
  const OfflineStudentsView({super.key, required this.snapshot, this.onTakePayment});

  final OfflineSnapshot snapshot;

  /// The fee counter's "Take a payment" (O4): offered on a student who owes
  /// something, to those who may take fees. Null hides it.
  final void Function(BuildContext context, OfflineStudent student)? onTakePayment;

  @override
  State<OfflineStudentsView> createState() => _OfflineStudentsViewState();
}

class _OfflineStudentsViewState extends State<OfflineStudentsView> {
  String _search = '';
  int? _classId;

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final shown = [
      for (final s in snapshot.students)
        if ((_classId == null || s.classSectionId == _classId) && s.matches(_search)) s,
    ];

    return ListView(
      key: const Key('offline-students'),
      padding: const EdgeInsets.all(20),
      children: [
        _OfflineHeader(
          title: 'Students',
          snapshot: snapshot,
          search: _search,
          onSearch: (value) => setState(() => _search = value),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('All classes'),
              selected: _classId == null,
              onSelected: (_) => setState(() => _classId = null),
            ),
            for (final c in snapshot.classes)
              ChoiceChip(
                label: Text(c.name),
                selected: _classId == c.id,
                onSelected: (_) => setState(() => _classId = c.id),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text('${shown.length} of ${snapshot.students.length}', style: TextStyle(color: context.appColors.muted)),
        const SizedBox(height: 8),
        if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No student matches.')),
          )
        else
          Card(
            child: Column(
              children: [
                for (final s in shown)
                  ListTile(
                    key: Key('offline-student-${s.id}'),
                    title: Text(s.name),
                    subtitle: Text(
                      [s.admissionNumber, ?s.className, if (s.rollNumber != null) 'Roll ${s.rollNumber}'].join(' · '),
                    ),
                    trailing: snapshot.duesOf(s.id).isEmpty ? null : const Icon(Icons.payments_outlined),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (dialogContext) => OfflineStudentDialog(
                        student: s,
                        snapshot: snapshot,
                        actions: [
                          if (widget.onTakePayment != null && snapshot.duesOf(s.id).isNotEmpty)
                            FilledButton.icon(
                              key: const Key('offline-take-payment'),
                              onPressed: () {
                                Navigator.of(dialogContext).pop();
                                widget.onTakePayment!(context, s);
                              },
                              icon: const Icon(Icons.payments_outlined),
                              label: const Text('Take a payment'),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One student from the copy: their guardian and, for fee roles, what they
/// still owe.
class OfflineStudentDialog extends StatelessWidget {
  const OfflineStudentDialog({super.key, required this.student, required this.snapshot, this.actions = const []});

  final OfflineStudent student;
  final OfflineSnapshot snapshot;

  /// Extra buttons - "Take a payment" on the fee counter (O4).
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final muted = context.appColors.muted;
    final dues = snapshot.duesOf(student.id);

    return AlertDialog(
      title: Text(student.name),
      content: SizedBox(
        width: 480,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(
              [
                student.admissionNumber,
                ?student.className,
                if (student.rollNumber != null) 'Roll ${student.rollNumber}',
              ].join(' · '),
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 12),
            if (student.guardianName != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.family_restroom_outlined),
                title: Text(student.guardianName!),
                subtitle: student.guardianMobile == null ? null : Text(student.guardianMobile!),
              ),
            if (snapshot.dues != null) ...[
              const SizedBox(height: 8),
              Text('Fees still owed', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              if (dues.isEmpty)
                Text('Nothing owed.', style: TextStyle(color: muted))
              else
                for (final due in dues)
                  ListTile(
                    key: Key('offline-due-${due.id}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${due.feeHead} - ${due.label}'),
                    subtitle: Text('Due ${formatIsoDate(due.dueDate)} · ${due.academicYear}'),
                    trailing: Text(
                      formatCurrency(double.parse(due.balance), due.currencyCode),
                      style: TextStyle(color: due.isOverdue ? context.appColors.danger : null),
                    ),
                  ),
            ],
            const SizedBox(height: 8),
            Text(offlineAsOf(snapshot.generatedAt), style: TextStyle(color: muted, fontSize: 12)),
          ],
        ),
      ),
      actions: [
        ...actions,
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}

/// Staff, read from the computer's copy.
class OfflineStaffView extends StatefulWidget {
  const OfflineStaffView({super.key, required this.snapshot});

  final OfflineSnapshot snapshot;

  @override
  State<OfflineStaffView> createState() => _OfflineStaffViewState();
}

class _OfflineStaffViewState extends State<OfflineStaffView> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final staff = widget.snapshot.staff ?? const <OfflineStaff>[];
    final shown = [
      for (final s in staff)
        if (s.matches(_search)) s,
    ];

    return ListView(
      key: const Key('offline-staff'),
      padding: const EdgeInsets.all(20),
      children: [
        _OfflineHeader(
          title: 'Teachers & Staff',
          snapshot: widget.snapshot,
          search: _search,
          onSearch: (value) => setState(() => _search = value),
        ),
        if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('Nobody matches.')),
          )
        else
          Card(
            child: Column(
              children: [
                for (final s in shown)
                  ListTile(
                    key: Key('offline-staff-${s.id}'),
                    title: Text(s.name),
                    subtitle: Text([s.employeeId, ?s.designation, ?s.department].join(' · ')),
                    trailing: s.mobile == null ? null : Text(s.mobile!),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
