import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../application/holiday_page_notifier.dart';
import '../data/models/holiday.dart';
import 'widgets/holiday_form_fields.dart';

class EditHolidayDialog extends ConsumerStatefulWidget {
  const EditHolidayDialog({super.key, required this.holiday});

  final Holiday holiday;

  @override
  ConsumerState<EditHolidayDialog> createState() => _EditHolidayDialogState();
}

class _EditHolidayDialogState extends ConsumerState<EditHolidayDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.holiday.name);

  late HolidayType _type = widget.holiday.type;
  late DateTime _startDate = DateTime.parse(widget.holiday.startDate);
  late DateTime _endDate = DateTime.parse(widget.holiday.endDate);

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(holidayPageNotifierProvider.notifier)
          .updateHoliday(
            widget.holiday,
            name: _nameController.text.trim(),
            type: _type,
            startDate: DateFormat('yyyy-MM-dd').format(_startDate),
            endDate: DateFormat('yyyy-MM-dd').format(_endDate),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Holiday updated.')));
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
      title: const Text('Edit Holiday'),
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
                HolidayFormFields(
                  nameController: _nameController,
                  type: _type,
                  startDate: _startDate,
                  endDate: _endDate,
                  onTypeChanged: (value) => setState(() => _type = value),
                  onStartDateChanged: (value) => setState(() {
                    _startDate = value;
                    if (_endDate.isBefore(_startDate)) _endDate = _startDate;
                  }),
                  onEndDateChanged: (value) => setState(() => _endDate = value),
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
