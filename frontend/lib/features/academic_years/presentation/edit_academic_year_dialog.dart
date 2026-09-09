import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../application/academic_year_list_notifier.dart';
import '../data/models/academic_year.dart';

class EditAcademicYearDialog extends ConsumerStatefulWidget {
  const EditAcademicYearDialog({super.key, required this.academicYear});

  final AcademicYear academicYear;

  @override
  ConsumerState<EditAcademicYearDialog> createState() => _EditAcademicYearDialogState();
}

class _EditAcademicYearDialogState extends ConsumerState<EditAcademicYearDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.academicYear.name);

  late DateTime? _startDate = widget.academicYear.startDate;
  late DateTime? _endDate = widget.academicYear.endDate;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _startDate : _endDate) ?? DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => isStart ? _startDate = picked : _endDate = picked);
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;
    if (_startDate == null || _endDate == null) {
      setState(() => _errorMessage = 'Both a start and end date are required.');
      return;
    }
    if (!_endDate!.isAfter(_startDate!)) {
      setState(() => _errorMessage = 'The end date must be after the start date.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(academicYearListNotifierProvider.notifier)
          .updateAcademicYear(
            widget.academicYear,
            name: _nameController.text.trim(),
            startDate: _startDate,
            endDate: _endDate,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Academic year updated.')));
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
    final dateFormat = DateFormat.yMMMd();

    return AlertDialog(
      title: Text('Edit ${widget.academicYear.name}'),
      content: SizedBox(
        width: 420,
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
                  decoration: const InputDecoration(labelText: 'Name (e.g. 2026-27)'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: () => _pickDate(isStart: true),
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Start date'),
                    child: Text(_startDate == null ? 'Select a date' : dateFormat.format(_startDate!)),
                  ),
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: () => _pickDate(isStart: false),
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'End date'),
                    child: Text(_endDate == null ? 'Select a date' : dateFormat.format(_endDate!)),
                  ),
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
