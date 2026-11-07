import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/status_badge.dart';
import '../application/guardians_notifier.dart';
import '../data/models/guardian_link.dart';
import 'family_access_dialog.dart';
import 'guardian_form_dialog.dart';

/// A student's guardians, for the school office (docs/parent-student-app.md,
/// F0): who they are, which one is the primary contact, and from here their
/// sign-in to the Family app.
class GuardiansDialog extends ConsumerWidget {
  const GuardiansDialog({super.key, required this.studentId, required this.studentName});

  final int studentId;
  final String studentName;

  Future<void> _openForm(BuildContext context, WidgetRef ref, [GuardianLink? link]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => GuardianFormDialog(studentId: studentId, link: link),
    );
    if (saved != true) return;

    await ref.read(guardiansProvider(studentId).notifier).refresh();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(link == null ? 'Guardian added.' : 'Guardian updated.')));
  }

  Future<void> _unlink(BuildContext context, WidgetRef ref, GuardianLink link) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Remove ${link.name}?',
      message: link.children > 1
          ? '${link.name} stays a guardian of their other children here.'
          : '${link.name} will no longer be a guardian of $studentName, and can no longer sign in to the Family app.',
      confirmLabel: 'Remove',
      isDestructive: true,
    );
    if (!confirmed || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(guardiansProvider(studentId).notifier).unlink(link);
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('${link.name} removed.')));
    } on Failure catch (failure) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guardians = ref.watch(guardiansProvider(studentId));

    return AlertDialog(
      title: Text('Guardians · $studentName'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 520, maxWidth: 520, maxHeight: 460),
        child: AsyncValueView<List<GuardianLink>>(
          value: guardians,
          onRetry: () => ref.read(guardiansProvider(studentId).notifier).refresh(),
          isEmpty: (links) => links.isEmpty,
          emptyBuilder: (context) => const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No guardian on record yet. Add one so the school can reach the family.'),
          ),
          data: (context, links) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final link in links)
                  _GuardianRow(
                    link: link,
                    onEdit: () => _openForm(context, ref, link),
                    onRemove: () => _unlink(context, ref, link),
                    onFamilyApp: () => showDialog<void>(
                      context: context,
                      builder: (_) => FamilyAccessDialog(studentId: studentId, link: link),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          key: const Key('guardians-add'),
          onPressed: () => _openForm(context, ref),
          icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
          label: const Text('Add guardian'),
        ),
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
      ],
    );
  }
}

class _GuardianRow extends StatelessWidget {
  const _GuardianRow({required this.link, required this.onEdit, required this.onRemove, required this.onFamilyApp});

  final GuardianLink link;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  final VoidCallback onFamilyApp;

  @override
  Widget build(BuildContext context) {
    final muted = context.appColors.muted;
    final details = [
      link.relationship.label,
      link.mobile ?? 'No mobile number',
      if (link.email != null) link.email!,
      if (link.children > 1) 'Guardian of ${link.children} students here',
    ];

    return ListTile(
      key: Key('guardian-row-${link.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Row(
        children: [
          Flexible(child: Text(link.name, overflow: TextOverflow.ellipsis)),
          if (link.isPrimary) ...[
            const SizedBox(width: 8),
            const StatusBadge(label: 'Primary contact', tone: BadgeTone.info),
          ],
        ],
      ),
      subtitle: Text(details.join(' · '), style: TextStyle(color: muted)),
      trailing: Wrap(
        spacing: 2,
        children: [
          IconButton(
            key: Key('guardian-family-${link.id}'),
            tooltip: 'Family app sign-in',
            icon: Icon(link.hasFamilyAccount ? Icons.phonelink_lock_outlined : Icons.phone_android_outlined, size: 20),
            onPressed: onFamilyApp,
          ),
          IconButton(
            key: Key('guardian-edit-${link.id}'),
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: onEdit,
          ),
          IconButton(
            key: Key('guardian-remove-${link.id}'),
            tooltip: 'Remove',
            icon: const Icon(Icons.person_remove_outlined, size: 20),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
