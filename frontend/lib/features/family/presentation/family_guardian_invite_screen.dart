import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/phone_number_field.dart';
import '../application/family_learning_notifiers.dart';
import '../application/family_session_notifier.dart';
import '../data/family_repository.dart';
import '../data/models/family_guardian_invite.dart';
import 'widgets/family_widgets.dart';

/// "Add a guardian" (docs/mobile-apps-review.md, M8, 8.5): a parent asks the
/// school to add another guardian of their child - often the other parent.
/// The school decides; nothing about the child is shared until it approves,
/// and then the school gives the new guardian their own set-up letter.
class FamilyGuardianInviteScreen extends ConsumerStatefulWidget {
  const FamilyGuardianInviteScreen({super.key});

  @override
  ConsumerState<FamilyGuardianInviteScreen> createState() => _FamilyGuardianInviteScreenState();
}

class _FamilyGuardianInviteScreenState extends ConsumerState<FamilyGuardianInviteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  String? _relationship;
  bool _sending = false;
  Map<String, String> _fieldErrors = {};
  String? _problem;

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending || !_formKey.currentState!.validate()) return;
    final child = ref.read(selectedChildProvider);
    if (child == null) return;

    setState(() {
      _sending = true;
      _fieldErrors = {};
      _problem = null;
    });
    final messenger = ScaffoldMessenger.of(context);

    try {
      await ref
          .read(familyRepositoryProvider)
          .askForGuardian(child.id, name: _name.text.trim(), mobile: _mobile.text.trim(), relationship: _relationship!);
      ref.invalidate(familyGuardianInvitesProvider(child.id));
      _name.clear();
      _mobile.clear();
      setState(() => _relationship = null);
      messenger.showSnackBar(const SnackBar(content: Text('Sent. The school will look at your request.')));
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _fieldErrors = {for (final entry in failure.validationErrors.entries) entry.key: entry.value.first};
        _problem = _fieldErrors.isEmpty ? failure.message : null;
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = ref.watch(selectedChildProvider);
    final colours = context.appColors;

    return Scaffold(
      appBar: AppBar(title: const Text('Add a guardian')),
      body: child == null
          ? const FamilyEmptyView(icon: Icons.family_restroom_rounded, title: 'No children to show')
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  Text(
                    'Ask the school to add another guardian of ${child.firstName}. Once the school agrees, it gives '
                    'them their own set-up letter, and they see what you see.',
                    style: TextStyle(color: colours.muted),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('family-guardian-name'),
                    controller: _name,
                    maxLength: 150,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(labelText: 'Their full name', errorText: _fieldErrors['name']),
                    validator: (value) => (value ?? '').trim().isEmpty ? 'Enter their name.' : null,
                  ),
                  PhoneNumberField(
                    key: const Key('family-guardian-mobile'),
                    controller: _mobile,
                    label: 'Their mobile number',
                    required: true,
                  ),
                  if (_fieldErrors['mobile'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(_fieldErrors['mobile']!, style: TextStyle(color: colours.danger, fontSize: 12)),
                    ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: const Key('family-guardian-relationship'),
                    initialValue: _relationship,
                    decoration: InputDecoration(
                      labelText: 'How they are related to ${child.firstName}',
                      errorText: _fieldErrors['relationship'],
                    ),
                    items: [
                      for (final entry in guardianRelationships.entries)
                        DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                    ],
                    onChanged: (value) => setState(() => _relationship = value),
                    validator: (value) => value == null ? 'Choose how they are related.' : null,
                  ),
                  if (_problem != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      key: const Key('family-guardian-problem'),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colours.warningContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(_problem!, style: TextStyle(color: colours.onWarningContainer)),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('family-guardian-send'),
                    onPressed: _sending ? null : _send,
                    child: _sending
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Ask the school'),
                  ),
                  const SizedBox(height: 24),
                  Text('Your requests', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _InviteList(childId: child.id),
                ],
              ),
            ),
    );
  }
}

class _InviteList extends ConsumerWidget {
  const _InviteList({required this.childId});

  final int childId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colours = context.appColors;

    return ref
        .watch(familyGuardianInvitesProvider(childId))
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) =>
              FamilyErrorView(error: error, onRetry: () => ref.invalidate(familyGuardianInvitesProvider(childId))),
          data: (invites) => invites.isEmpty
              ? Text('None yet.', style: TextStyle(color: colours.muted))
              : Column(
                  children: [
                    for (final invite in invites) ...[
                      FamilyCard(
                        key: Key('family-guardian-invite-${invite.id}'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${invite.name} · ${guardianRelationships[invite.relationship] ?? 'Other'}',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              invite.statusLabel,
                              style: TextStyle(
                                color: switch (invite.status) {
                                  'approved' => colours.success,
                                  'declined' => colours.danger,
                                  _ => colours.muted,
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
        );
  }
}
