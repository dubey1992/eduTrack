import 'package:flutter/material.dart';

import '../../data/models/import_result.dart';

/// What an accepted file produced.
///
/// For staff this is the one and only time the generated passwords are
/// visible - they are hashed on the way into the database and never sent
/// again - so they are selectable text, ready to be copied and passed on.
class ImportSummary extends StatelessWidget {
  const ImportSummary({super.key, required this.result});

  final ImportResult result;

  @override
  Widget build(BuildContext context) {
    final withPasswords = result.withPasswords;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${result.imported} ${result.label.toLowerCase()} imported.'),
        if (withPasswords.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'These accounts were given a temporary password, shown here once. '
            'Pass each one on; they will be asked to change it when they first sign in.',
          ),
          const SizedBox(height: 12),
          for (final record in withPasswords)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(record.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  SelectableText('${record.email}  -  ${record.temporaryPassword}'),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
