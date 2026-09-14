import 'package:flutter/material.dart';

import '../../data/models/holiday.dart';
import '../../../../core/utils/date_format.dart';

/// The name / type / from / to fields shared by the Add and Edit holiday
/// dialogs. The dialog owns the state; this only renders and reports.
class HolidayFormFields extends StatelessWidget {
  const HolidayFormFields({
    super.key,
    required this.nameController,
    required this.type,
    required this.startDate,
    required this.endDate,
    required this.onTypeChanged,
    required this.onStartDateChanged,
    required this.onEndDateChanged,
  });

  final TextEditingController nameController;
  final HolidayType type;
  final DateTime startDate;
  final DateTime endDate;
  final ValueChanged<HolidayType> onTypeChanged;
  final ValueChanged<DateTime> onStartDateChanged;
  final ValueChanged<DateTime> onEndDateChanged;

  Future<void> _pickStart(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) onStartDateChanged(picked);
  }

  Future<void> _pickEnd(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: endDate.isBefore(startDate) ? startDate : endDate,
      firstDate: startDate,
      lastDate: DateTime(2100),
    );
    if (picked != null) onEndDateChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFormField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Holiday name'),
          maxLength: 100,
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<HolidayType>(
          initialValue: type,
          decoration: const InputDecoration(labelText: 'Type'),
          items: [for (final t in HolidayType.values) DropdownMenuItem(value: t, child: Text(t.label))],
          onChanged: (value) {
            if (value != null) onTypeChanged(value);
          },
        ),
        const SizedBox(height: 10),
        InkWell(
          onTap: () => _pickStart(context),
          child: InputDecorator(
            decoration: const InputDecoration(labelText: 'From'),
            child: Text(formatDate(startDate)),
          ),
        ),
        const SizedBox(height: 10),
        InkWell(
          onTap: () => _pickEnd(context),
          child: InputDecorator(
            decoration: const InputDecoration(labelText: 'To'),
            child: Text(formatDate(endDate)),
          ),
        ),
      ],
    );
  }
}
