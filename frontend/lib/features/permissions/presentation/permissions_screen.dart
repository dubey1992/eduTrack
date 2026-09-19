import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/horizontal_scroll_table.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_badge.dart';
import '../application/permissions_notifier.dart';
import '../data/models/permissions_matrix.dart';

/// The platform-wide roles & permissions matrix: one row per module, one
/// column per role, each cell None / View / Manage. The Super Admin edits
/// it; every other administrator reads it.
class PermissionsScreen extends ConsumerWidget {
  const PermissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matrixState = ref.watch(permissionsNotifierProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Permissions'),
        Expanded(
          child: AsyncValueView<PermissionsMatrix>(
            value: matrixState,
            onRetry: () => ref.read(permissionsNotifierProvider.notifier).load(),
            data: (context, matrix) => _MatrixEditor(matrix: matrix),
          ),
        ),
      ],
    );
  }
}

class _MatrixEditor extends ConsumerStatefulWidget {
  const _MatrixEditor({required this.matrix});

  final PermissionsMatrix matrix;

  @override
  ConsumerState<_MatrixEditor> createState() => _MatrixEditorState();
}

class _MatrixEditorState extends ConsumerState<_MatrixEditor> {
  /// Cells moved on screen and not yet saved: {role: {module: level}}. A
  /// cell put back to what the server has drops out again, so "dirty"
  /// means exactly "there is something to send".
  final LevelGrid _edits = {};

  bool _busy = false;
  String? _error;

  PermissionsMatrix get matrix => widget.matrix;

  bool get _isDirty => _edits.isNotEmpty;

  @override
  void didUpdateWidget(covariant _MatrixEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A saved or reset matrix is the new baseline; the edits it came from
    // are in it now (or were meant to go).
    if (!identical(oldWidget.matrix, widget.matrix)) _edits.clear();
  }

  PermissionLevel _shownLevel(String role, String module) {
    return _edits[role]?[module] ?? matrix.levelOf(role, module);
  }

  void _setLevel(String role, String module, PermissionLevel level) {
    setState(() {
      if (level == matrix.levelOf(role, module)) {
        _edits[role]?.remove(module);
        if (_edits[role]?.isEmpty ?? false) _edits.remove(role);
      } else {
        _edits.putIfAbsent(role, () => {})[module] = level;
      }
    });
  }

  void _discard() => setState(() {
    _edits.clear();
    _error = null;
  });

  Future<void> _run(Future<void> Function() action, String successMessage) async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);

    try {
      await action();
      if (!mounted) return;
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) setState(() => _error = failure.validationErrors['matrix']?.join(' ') ?? failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() {
    // A copy: the edits are cleared when the saved matrix arrives, which
    // happens before the fake or the API has finished reading them.
    final changes = {for (final role in _edits.entries) role.key: Map<String, PermissionLevel>.of(role.value)};
    return _run(() => ref.read(permissionsNotifierProvider.notifier).save(changes), 'Permissions saved.');
  }

  Future<void> _reset() async {
    final confirmed = await confirmDialog(
      context,
      title: 'Reset to defaults?',
      message:
          'Every role goes back to what it could do before the matrix was changed. Unsaved edits on this screen '
          'are dropped.',
      confirmLabel: 'Reset',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    await _run(() => ref.read(permissionsNotifierProvider.notifier).reset(), 'Permissions reset to defaults.');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final canEdit = matrix.canEdit;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The matrix decides whether a role may see or change a module; which records it reaches stays as it is '
            "(a teacher's own classes, a head's own department).",
            style: TextStyle(fontSize: 13, color: colors.muted),
          ),
          if (!canEdit) ...[
            const SizedBox(height: 6),
            Text(
              'Only the Super Admin can change the matrix.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.muted),
            ),
          ],
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: HorizontalScrollTable(child: _buildTable(context)),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              key: const Key('perm-error'),
              style: TextStyle(color: colors.danger),
            ),
          ],
          if (canEdit) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton(
                  key: const Key('perm-save'),
                  onPressed: _isDirty && !_busy ? _save : null,
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save changes'),
                ),
                OutlinedButton(
                  key: const Key('perm-discard'),
                  onPressed: _isDirty && !_busy ? _discard : null,
                  child: const Text('Discard'),
                ),
                TextButton(
                  key: const Key('perm-reset'),
                  onPressed: _busy ? null : _reset,
                  child: const Text('Reset to defaults'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTable(BuildContext context) {
    return DataTable(
      columnSpacing: 20,
      columns: [
        const DataColumn(label: Text('Module')),
        for (final role in matrix.roles) DataColumn(label: Text(role.label)),
      ],
      rows: [
        for (final module in matrix.modules)
          DataRow(
            cells: [
              DataCell(
                Tooltip(
                  message: module.description,
                  child: Text(module.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              for (final role in matrix.roles)
                DataCell(
                  _LevelCell(
                    key: Key('perm-${role.value}-${module.value}'),
                    level: _shownLevel(role.value, module.value),
                    defaultLevel: matrix.defaultOf(role.value, module.value),
                    options: matrix.levels,
                    onChanged: matrix.canEdit && !_busy ? (level) => _setLevel(role.value, module.value, level) : null,
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// One cell: a dropdown for the Super Admin, a plain chip for everybody
/// else. A cell that differs from its default is tinted and says so on hover.
class _LevelCell extends StatelessWidget {
  const _LevelCell({
    super.key,
    required this.level,
    required this.defaultLevel,
    required this.options,
    required this.onChanged,
  });

  final PermissionLevel level;
  final PermissionLevel defaultLevel;
  final List<PermissionLevel> options;

  /// Null makes the cell read-only.
  final ValueChanged<PermissionLevel>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final differs = level != defaultLevel;

    final Widget control;
    if (onChanged == null) {
      control = StatusBadge(
        label: level.label,
        tone: switch (level) {
          PermissionLevel.none => BadgeTone.neutral,
          PermissionLevel.view => BadgeTone.info,
          PermissionLevel.manage => BadgeTone.success,
        },
      );
    } else {
      control = DropdownButton<PermissionLevel>(
        value: level,
        isDense: true,
        underline: const SizedBox.shrink(),
        items: [for (final option in options) DropdownMenuItem(value: option, child: Text(option.label))],
        onChanged: (value) {
          if (value != null) onChanged!(value);
        },
      );
    }

    final cell = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: differs
          ? BoxDecoration(color: colors.warningContainer.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(6))
          : null,
      child: control,
    );

    if (!differs) return cell;

    return Tooltip(message: 'Default: ${defaultLevel.label}', child: cell);
  }
}
