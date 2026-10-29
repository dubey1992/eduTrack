import 'package:flutter/material.dart';

import '../../../../core/utils/date_format.dart';
import '../../data/models/school.dart';

/// What kind of account a school is - Demo, In Trial, Live or Testing
/// (docs/school-categories.md) - and, for a trial, the day it ends.
///
/// The end date only warns the Super Admin; the school keeps working.
class SchoolCategoryField extends StatelessWidget {
  const SchoolCategoryField({
    super.key,
    required this.category,
    required this.trialEndsOn,
    required this.onCategoryChanged,
    required this.onTrialEndsOnChanged,
    this.categoryError,
    this.trialEndsOnError,
    this.today,
  });

  /// Null until the Super Admin picks one: a new school is categorised on
  /// purpose, never by a default somebody did not notice.
  final SchoolCategory? category;
  final DateTime? trialEndsOn;
  final ValueChanged<SchoolCategory> onCategoryChanged;
  final ValueChanged<DateTime> onTrialEndsOnChanged;
  final String? categoryError;
  final String? trialEndsOnError;

  /// The first day a trial may end on; today unless a test says otherwise.
  final DateTime? today;

  static const _hints = {
    SchoolCategory.live: 'A paying customer. Counted in every platform figure.',
    SchoolCategory.trial: 'Trying the product. Counted, and you are warned as the trial ends.',
    SchoolCategory.demo: 'For showing the product. Not counted; sends SMS normally.',
    SchoolCategory.testing: 'For our own testing. Not counted, and never sends SMS or WhatsApp.',
  };

  Future<void> _pickEnd(BuildContext context) async {
    final now = today ?? DateTime.now();
    final first = DateTime(now.year, now.month, now.day);
    // An ended trial being edited keeps its date in view.
    final initial = trialEndsOn ?? first.add(const Duration(days: 30));
    final picked = await showDatePicker(
      context: context,
      firstDate: initial.isBefore(first) ? initial : first,
      lastDate: DateTime(now.year + 2, 12, 31),
      initialDate: initial,
      helpText: 'Trial ends on',
    );

    if (picked != null) onTrialEndsOnChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<SchoolCategory>(
          key: const Key('school-category'),
          initialValue: category,
          decoration: InputDecoration(labelText: 'Category', errorText: categoryError),
          items: [
            for (final option in SchoolCategory.values) DropdownMenuItem(value: option, child: Text(option.label)),
          ],
          validator: (value) => value == null ? 'Pick a category' : null,
          onChanged: (value) {
            if (value != null) onCategoryChanged(value);
          },
        ),
        if (category != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(_hints[category]!, style: muted),
          ),
        ],
        if (category == SchoolCategory.trial) ...[
          const SizedBox(height: 10),
          FormField<DateTime>(
            key: ValueKey('trial-ends-$trialEndsOn'),
            initialValue: trialEndsOn,
            validator: (_) => trialEndsOn == null ? 'Pick the day the trial ends' : null,
            builder: (field) => InkWell(
              key: const Key('school-trial-ends-on'),
              onTap: () => _pickEnd(context),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Trial ends on',
                  errorText: field.errorText ?? trialEndsOnError,
                  suffixIcon: const Icon(Icons.event, size: 18),
                ),
                child: Text(trialEndsOn == null ? 'Pick a date' : formatDate(trialEndsOn!)),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
