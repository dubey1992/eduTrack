import 'package:flutter/material.dart';

import '../../data/models/import_result.dart';

/// Every row of an uploaded file that needs fixing, and why.
///
/// A list rather than a sentence because this is read with the spreadsheet
/// open: each entry names a line number the person can go straight to.
class ImportRowErrors extends StatelessWidget {
  const ImportRowErrors({super.key, required this.errors});

  final List<ImportRowError> errors;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.all(12),
        itemCount: errors.length,
        separatorBuilder: (_, _) => const Divider(height: 16),
        itemBuilder: (context, index) {
          final error = errors[index];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Row ${error.row}', style: const TextStyle(fontWeight: FontWeight.w600)),
              for (final message in error.messages) Text(message),
            ],
          );
        },
      ),
    );
  }
}
