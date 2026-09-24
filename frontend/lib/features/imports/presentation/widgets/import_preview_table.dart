import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/horizontal_scroll_table.dart';
import '../../data/models/import_preview.dart';

/// The rows a file would import, before it imports them.
///
/// Read to answer one question - "is this the right spreadsheet, and did the
/// columns land where I meant them to" - so it shows the file as a table,
/// with the line numbers the spreadsheet itself uses.
class ImportPreviewTable extends StatelessWidget {
  const ImportPreviewTable({super.key, required this.preview});

  final ImportPreview preview;

  @override
  Widget build(BuildContext context) {
    final shown = preview.rows.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          preview.truncated
              ? '${preview.rowCount} rows in the file. The first $shown are shown.'
              : '${preview.rowCount} ${preview.rowCount == 1 ? 'row' : 'rows'} in the file.',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          'Nothing has been saved yet. Check the rows, then import.',
          style: TextStyle(color: context.appColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: SingleChildScrollView(
            child: HorizontalScrollTable(
              child: DataTable(
                columnSpacing: 18,
                columns: [
                  const DataColumn(label: Text('Row')),
                  for (final heading in preview.headings) DataColumn(label: Text(heading)),
                ],
                rows: [
                  for (final row in preview.rows)
                    DataRow(
                      cells: [
                        DataCell(Text('${row.row}')),
                        for (var index = 0; index < preview.headings.length; index++)
                          DataCell(Text(index < row.values.length ? (row.values[index] ?? '') : '')),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
