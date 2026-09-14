import 'package:flutter/material.dart';

import '../../../core/utils/file_picker.dart';
import 'bulk_import_dialog.dart';

/// "Bulk Upload", next to the Add button on a list screen.
///
/// Hides itself where a file cannot be chosen at all - the Android build,
/// today - rather than offering a button that opens nothing.
class BulkImportButton extends StatelessWidget {
  const BulkImportButton({super.key, required this.type, required this.title, this.schoolId, this.onImported});

  final String type;
  final String title;
  final int? schoolId;
  final VoidCallback? onImported;

  @override
  Widget build(BuildContext context) {
    if (!canPickFile) return const SizedBox.shrink();

    return OutlinedButton.icon(
      onPressed: () => showDialog(
        context: context,
        builder: (_) => BulkImportDialog(type: type, title: title, schoolId: schoolId, onImported: onImported),
      ),
      icon: const Icon(Icons.upload_file, size: 18),
      label: const Text('Bulk Upload'),
    );
  }
}
