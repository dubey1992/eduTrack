import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/models/country_dial_code.dart';
import '../../../core/widgets/phone_number_field.dart';
import '../data/guardian_repository.dart';
import '../data/models/guardian_link.dart';

/// Adds a guardian to a student, or edits one (docs/parent-student-app.md, F0).
///
/// A mobile number another student's guardian already has links that same
/// person - the parent of a sibling - rather than making a copy of them.
class GuardianFormDialog extends ConsumerStatefulWidget {
  const GuardianFormDialog({super.key, required this.studentId, this.link});

  final int studentId;

  /// The guardian being edited; null to add one.
  final GuardianLink? link;

  @override
  ConsumerState<GuardianFormDialog> createState() => _GuardianFormDialogState();
}

class _GuardianFormDialogState extends ConsumerState<GuardianFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.link?.name ?? '');
  late final _mobile = TextEditingController(text: _spaced(widget.link?.mobile));
  late final _email = TextEditingController(text: widget.link?.email ?? '');
  late GuardianRelationship _relationship = widget.link?.relationship ?? GuardianRelationship.guardian;
  late bool _primary = widget.link?.isPrimary ?? false;
  bool _saving = false;
  String? _problem;

  bool get _editing => widget.link != null;

  /// "+919876543210", as a guardian's number is kept, written the way the
  /// phone field reads it: "+91 9876543210".
  static String _spaced(String? mobile) {
    if (mobile == null) return '';

    final codes = [...CountryDialCode.common]..sort((a, b) => b.dialCode.length.compareTo(a.dialCode.length));
    for (final country in codes) {
      if (mobile.startsWith(country.dialCode) && !mobile.startsWith('${country.dialCode} ')) {
        return '${country.dialCode} ${mobile.substring(country.dialCode.length)}';
      }
    }

    return mobile;
  }

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    _email.dispose();
    super.dispose();
  }

  String? _blankToNull(String value) => value.trim().isEmpty ? null : value.trim();

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _problem = null;
    });

    final repository = ref.read(guardianRepositoryProvider);
    final mobile = _blankToNull(_mobile.text);

    try {
      if (_editing) {
        await repository.update(
          widget.studentId,
          widget.link!.id,
          name: _name.text.trim(),
          mobile: mobile,
          email: _blankToNull(_email.text),
          relationship: _relationship,
          isPrimary: _primary,
        );
      } else {
        await repository.add(
          widget.studentId,
          name: _name.text.trim(),
          mobile: mobile,
          email: _blankToNull(_email.text),
          relationship: _relationship,
          isPrimary: _primary,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on Failure catch (failure) {
      final fieldErrors = failure.validationErrors.values;
      setState(() => _problem = fieldErrors.isEmpty ? failure.message : fieldErrors.first.first);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final link = widget.link;

    return AlertDialog(
      title: Text(_editing ? 'Edit guardian' : 'Add a guardian'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, minWidth: 440),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (link != null && link.children > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      '${link.name} is a guardian of ${link.children} students here. '
                      'Changes to their name, number or email apply to all of them.',
                      key: const Key('guardian-siblings-note'),
                    ),
                  ),
                TextFormField(
                  key: const Key('guardian-name'),
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name'),
                  textCapitalization: TextCapitalization.words,
                  validator: (value) {
                    final name = value?.trim() ?? '';
                    if (name.isEmpty) return 'Enter the guardian\'s name.';
                    if (name.length > 150) return 'Keep the name to 150 characters.';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                PhoneNumberField(controller: _mobile, label: 'Mobile (they sign in with it)'),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('guardian-email'),
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'Email (optional)'),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    if (email.isEmpty) return null;
                    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) return 'Enter a valid email address.';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<GuardianRelationship>(
                  key: const Key('guardian-relationship'),
                  initialValue: _relationship,
                  decoration: const InputDecoration(labelText: 'Relationship'),
                  items: [
                    for (final relationship in GuardianRelationship.values)
                      DropdownMenuItem(value: relationship, child: Text(relationship.label)),
                  ],
                  onChanged: (value) => setState(() => _relationship = value ?? _relationship),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  key: const Key('guardian-primary'),
                  contentPadding: EdgeInsets.zero,
                  value: _primary,
                  // A primary contact stops being one when another becomes it.
                  onChanged: link?.isPrimary == true ? null : (value) => setState(() => _primary = value),
                  title: const Text('Primary contact'),
                  subtitle: const Text('Alerts and the student\'s record use this guardian.'),
                ),
                if (_problem != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _problem!,
                      key: const Key('guardian-problem'),
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(
          key: const Key('guardian-save'),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving...' : (_editing ? 'Save' : 'Add guardian')),
        ),
      ],
    );
  }
}
