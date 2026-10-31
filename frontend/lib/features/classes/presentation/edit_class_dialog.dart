import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../application/school_class_list_notifier.dart';
import '../data/class_levels.dart';
import '../data/models/school_class.dart';
import 'class_level_field.dart';

class EditClassDialog extends ConsumerStatefulWidget {
  const EditClassDialog({super.key, required this.schoolClass});

  final SchoolClass schoolClass;

  @override
  ConsumerState<EditClassDialog> createState() => _EditClassDialogState();
}

class _EditClassDialogState extends ConsumerState<EditClassDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.schoolClass.name);
  late int? _level = widget.schoolClass.level;
  bool _levelPicked = true;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// "LKG" or "Class 7" says which year it is; a year picked by hand stays.
  void _nameChanged(String name) {
    if (_levelPicked) return;
    final inferred = classLevelFromName(name);
    if (inferred != _level) setState(() => _level = inferred);
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(schoolClassListNotifierProvider.notifier)
          .updateClass(widget.schoolClass, name: _nameController.text.trim(), level: _level);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Class updated.')));
        Navigator.of(context).pop();
      }
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) setState(() => _errorMessage = failure.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${widget.schoolClass.name}'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_errorMessage != null) ...[
                  Text(_errorMessage!, style: TextStyle(color: context.appColors.danger)),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Class name (e.g. Class 8 or LKG)'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                  onChanged: _nameChanged,
                ),
                const SizedBox(height: 10),
                ClassLevelField(
                  value: _level,
                  helperText: 'Sets the class order and where promotion moves students.',
                  onChanged: (value) => setState(() {
                    _level = value;
                    _levelPicked = true;
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
