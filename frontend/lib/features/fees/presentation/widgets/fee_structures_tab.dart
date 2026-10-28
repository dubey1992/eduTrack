import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../academic_years/data/models/academic_year.dart';
import '../../application/fee_setup_providers.dart';
import '../../data/models/fee_structure.dart';
import '../../data/money_text.dart';
import 'fee_structure_dialog.dart';

enum FeeStructureKind { classFee, routeFee }

/// One group a fee is set for: a class of the year, or a bus route.
class FeeGroup {
  const FeeGroup({required this.id, required this.name});

  final int id;
  final String name;
}

/// Class Fees or Bus Route Fees for one academic year: each class (or route)
/// with the fees set for it, and the way to add, change and publish them.
class FeeStructuresTab extends ConsumerWidget {
  const FeeStructuresTab({
    super.key,
    required this.kind,
    required this.schoolId,
    required this.year,
    required this.canManage,
  });

  final FeeStructureKind kind;
  final int? schoolId;
  final AcademicYear year;
  final bool canManage;

  FeeYearQuery get _query => (schoolId: schoolId, academicYearId: year.id);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = kind == FeeStructureKind.classFee
        ? ref
              .watch(feeClassesProvider(_query))
              .whenData(
                (classes) => [
                  for (final schoolClass in (List.of(classes)..sort((a, b) => a.level.compareTo(b.level))))
                    FeeGroup(id: schoolClass.id, name: schoolClass.name),
                ],
              )
        : ref
              .watch(feeRoutesProvider(schoolId))
              .whenData((routes) => [for (final route in routes) FeeGroup(id: route.id, name: route.name)]);

    return AsyncValueView<List<FeeGroup>>(
      value: groups,
      onRetry: () => kind == FeeStructureKind.classFee
          ? ref.invalidate(feeClassesProvider(_query))
          : ref.invalidate(feeRoutesProvider(schoolId)),
      isEmpty: (groups) => groups.isEmpty,
      emptyBuilder: (context) => _Empty(
        message: kind == FeeStructureKind.classFee
            ? 'There are no classes in ${year.name} yet. Add them under Classes & Sections, then set their fees here.'
            : 'There are no active bus routes yet. Add them under Transport, then set their fees here.',
      ),
      data: (context, groups) => AsyncValueView<List<FeeStructure>>(
        value: ref.watch(feeStructuresProvider(_query)),
        onRetry: () => ref.invalidate(feeStructuresProvider(_query)),
        data: (context, structures) => _List(
          kind: kind,
          groups: groups,
          structures: structures,
          year: year,
          schoolId: schoolId,
          canManage: canManage,
        ),
      ),
    );
  }
}

class _List extends ConsumerStatefulWidget {
  const _List({
    required this.kind,
    required this.groups,
    required this.structures,
    required this.year,
    required this.schoolId,
    required this.canManage,
  });

  final FeeStructureKind kind;
  final List<FeeGroup> groups;
  final List<FeeStructure> structures;
  final AcademicYear year;
  final int? schoolId;
  final bool canManage;

  @override
  ConsumerState<_List> createState() => _ListState();
}

class _ListState extends ConsumerState<_List> {
  bool _publishingAll = false;

  List<FeeStructure> _feesOf(FeeGroup group) => [
    for (final structure in widget.structures)
      if ((widget.kind == FeeStructureKind.classFee ? structure.schoolClassId : structure.transportRouteId) == group.id)
        structure,
  ];

  Future<void> _publishAll(int drafts) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Publish all $drafts draft fee${drafts == 1 ? '' : 's'}?',
      message:
          'Every class and bus route fee still in draft for ${widget.year.name} becomes final. Students are '
          'charged from published fees.',
      confirmLabel: 'Publish all',
    );
    if (!confirmed || !mounted) return;

    setState(() => _publishingAll = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final count = await ref
          .read(feeSetupActionsProvider)
          .publishAll(academicYearId: widget.year.id, schoolId: widget.schoolId);
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('$count fee${count == 1 ? '' : 's'} published.')));
    } catch (error) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(error is Failure ? error.message : 'Publishing failed. Try again.')));
    } finally {
      if (mounted) setState(() => _publishingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Drafts across the whole year, both tabs: "Publish all" publishes them all.
    final drafts = widget.structures.where((structure) => structure.isDraft).length;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (widget.canManage && drafts > 0) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _publishingAll ? null : () => _publishAll(drafts),
              icon: _publishingAll
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.publish_outlined),
              label: Text(
                drafts == 1
                    ? 'Publish 1 draft for ${widget.year.name}'
                    : 'Publish all $drafts drafts for ${widget.year.name}',
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        for (final group in widget.groups) ...[
          _GroupCard(
            kind: widget.kind,
            group: group,
            fees: _feesOf(group),
            year: widget.year,
            schoolId: widget.schoolId,
            canManage: widget.canManage,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _GroupCard extends ConsumerWidget {
  const _GroupCard({
    required this.kind,
    required this.group,
    required this.fees,
    required this.year,
    required this.schoolId,
    required this.canManage,
  });

  final FeeStructureKind kind;
  final FeeGroup group;
  final List<FeeStructure> fees;
  final AcademicYear year;
  final int? schoolId;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = context.appColors.muted;
    // One school, one currency: every fee of a year carries the same code.
    final total = fees.fold<int>(0, (sum, fee) => sum + (centsOf(fee.amount) ?? 0)) / 100;
    // A route has one fee at most - its Transport fee.
    final canAdd = canManage && (kind == FeeStructureKind.classFee || fees.isEmpty);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.name, style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      fees.isEmpty
                          ? 'No fees set for ${year.name}.'
                          : 'Total for the year: ${formatCurrency(total, fees.first.currencyCode)}',
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                  ],
                ),
                if (canAdd)
                  TextButton.icon(
                    onPressed: () => showFeeStructureDialog(
                      context,
                      kind: kind,
                      group: group,
                      year: year,
                      schoolId: schoolId,
                      takenHeadIds: {for (final fee in fees) fee.feeHeadId},
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Add fee'),
                  ),
              ],
            ),
            for (final fee in fees) ...[
              const Divider(height: 24),
              _FeeRow(fee: fee, kind: kind, group: group, year: year, schoolId: schoolId, canManage: canManage),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeeRow extends ConsumerStatefulWidget {
  const _FeeRow({
    required this.fee,
    required this.kind,
    required this.group,
    required this.year,
    required this.schoolId,
    required this.canManage,
  });

  final FeeStructure fee;
  final FeeStructureKind kind;
  final FeeGroup group;
  final AcademicYear year;
  final int? schoolId;
  final bool canManage;

  @override
  ConsumerState<_FeeRow> createState() => _FeeRowState();
}

class _FeeRowState extends ConsumerState<_FeeRow> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await action();
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(done)));
    } catch (error) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(error is Failure ? error.message : 'That did not work. Try again.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publish() async {
    final fee = widget.fee;
    final confirmed = await confirmDialog(
      context,
      title: 'Publish ${fee.feeHeadName} for ${widget.group.name}?',
      message: 'It becomes final for ${widget.year.name}. Students are charged from published fees.',
      confirmLabel: 'Publish',
    );
    if (!confirmed || !mounted) return;

    await _run(
      () => ref.read(feeSetupActionsProvider).publishStructure(fee.id),
      '${fee.feeHeadName} for ${widget.group.name} published.',
    );
  }

  Future<void> _delete() async {
    final fee = widget.fee;
    final confirmed = await confirmDialog(
      context,
      title: 'Delete this draft?',
      message: '${fee.feeHeadName} for ${widget.group.name} is removed. It was never published.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    await _run(() => ref.read(feeSetupActionsProvider).deleteStructure(fee.id), 'Draft deleted.');
  }

  @override
  Widget build(BuildContext context) {
    final fee = widget.fee;
    final muted = context.appColors.muted;
    final count = fee.installments.length;

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(fee.feeHeadName, style: const TextStyle(fontWeight: FontWeight.w700)),
                StatusBadge(label: fee.status.label, tone: fee.isDraft ? BadgeTone.warning : BadgeTone.success),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${formatCurrency(double.parse(fee.amount), fee.currencyCode)} · ${fee.frequency.label} · '
              '$count installment${count == 1 ? '' : 's'}',
              style: TextStyle(color: muted, fontSize: 13),
            ),
          ],
        ),
        if (widget.canManage)
          Wrap(
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (_busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => showFeeStructureDialog(
                        context,
                        kind: widget.kind,
                        group: widget.group,
                        year: widget.year,
                        schoolId: widget.schoolId,
                        existing: fee,
                      ),
                child: const Text('Edit'),
              ),
              if (fee.isDraft) ...[
                TextButton(onPressed: _busy ? null : _publish, child: const Text('Publish')),
                IconButton(
                  onPressed: _busy ? null : _delete,
                  tooltip: 'Delete draft',
                  icon: Icon(Icons.delete_outline, color: context.appColors.danger),
                ),
              ],
            ],
          )
        else
          TextButton(
            onPressed: () => showFeeStructureDialog(
              context,
              kind: widget.kind,
              group: widget.group,
              year: widget.year,
              schoolId: widget.schoolId,
              existing: fee,
              readOnly: true,
            ),
            child: const Text('View'),
          ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.appColors.muted),
        ),
      ),
    );
  }
}
