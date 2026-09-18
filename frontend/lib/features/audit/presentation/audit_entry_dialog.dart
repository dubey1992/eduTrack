import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/horizontal_scroll_table.dart';
import '../data/models/audit_entry.dart';

/// One audit entry in full: the facts of who, when and where, then every
/// field it changed.
class AuditEntryDialog extends StatelessWidget {
  const AuditEntryDialog({super.key, required this.entry, required this.showSchool});

  final AuditEntry entry;
  final bool showSchool;

  @override
  Widget build(BuildContext context) {
    final role = entry.roleLabel;

    return AlertDialog(
      title: Text(entry.actionLabel),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Fact(label: 'When', value: entry.whenLabel),
              _Fact(label: 'Who', value: role == null ? entry.actorLabel : '${entry.actorLabel} ($role)'),
              if (showSchool) _Fact(label: 'School', value: entry.schoolLabel),
              _Fact(label: 'Module', value: entry.moduleLabel),
              _Fact(label: 'Action', value: entry.actionLabel),
              _Fact(label: 'Record', value: entry.recordLabel),
              _Fact(label: 'IP', value: entry.ip ?? '-'),
              const Divider(height: 24),
              Text('Changes', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              _ChangesTable(entry: entry),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: TextStyle(color: context.appColors.muted)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _ChangesTable extends StatelessWidget {
  const _ChangesTable({required this.entry});

  final AuditEntry entry;

  static const _valueWidth = BoxConstraints(maxWidth: 240);

  @override
  Widget build(BuildContext context) {
    final shape = entry.changeShape;
    if (shape == AuditChangeShape.none) {
      return Text('No field changes recorded.', style: TextStyle(color: context.appColors.muted));
    }

    final changes = entry.changes;

    return HorizontalScrollTable(
      child: DataTable(
        headingRowHeight: 40,
        dataRowMaxHeight: double.infinity,
        columns: [
          const DataColumn(label: Text('Field')),
          if (shape == AuditChangeShape.beforeAndAfter) ...[
            const DataColumn(label: Text('Before')),
            const DataColumn(label: Text('After')),
          ] else
            const DataColumn(label: Text('Value')),
        ],
        rows: [
          for (final change in changes)
            DataRow(
              cells: [
                DataCell(Text(change.fieldLabel)),
                if (shape == AuditChangeShape.beforeAndAfter) ...[
                  DataCell(_value(change.before)),
                  DataCell(_value(change.after)),
                ] else
                  DataCell(_value(shape == AuditChangeShape.afterOnly ? change.after : change.before)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _value(String text) {
    return ConstrainedBox(
      constraints: _valueWidth,
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(text)),
    );
  }
}
