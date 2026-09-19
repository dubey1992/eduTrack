import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/file_picker.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/phone_number_field.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/presentation/change_password_dialog.dart';
import '../../auth/presentation/signed_in_devices_dialog.dart';
import '../application/profile_notifier.dart';
import '../data/models/profile.dart';
import 'change_email_dialog.dart';

/// The largest photo the server accepts.
const _maxPhotoBytes = 2 * 1024 * 1024;

const _photoExtensions = ['.jpg', '.jpeg', '.png'];

/// Where two columns start to fit side by side.
const _twoColumnWidth = 900.0;

/// The signed-in user's own page: their name, mobile, home address, photo
/// and sign-in email, plus the work details the school keeps about them.
/// Every role has it, the Super Admin included; it is opened from the header.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileState = ref.watch(profileNotifierProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'My Profile'),
        Expanded(
          child: AsyncValueView<Profile>(
            value: profileState,
            onRetry: () => ref.read(profileNotifierProvider.notifier).load(),
            data: (context, profile) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: _ProfileLayout(profile: profile),
            ),
          ),
        ),
      ],
    );
  }
}

/// Two columns where there is room, one where there is not.
class _ProfileLayout extends StatelessWidget {
  const _ProfileLayout({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final photo = _PhotoCard(profile: profile);
    final details = _DetailsCard(profile: profile);
    final email = _EmailCard(email: profile.email, keptBySchool: profile.signsInWithPasscode);
    final work = profile.employment == null ? null : _WorkCard(profile: profile, employment: profile.employment!);
    final security = _SecurityCard(hasPassword: !profile.signsInWithPasscode);
    const gap = SizedBox(height: 16);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _twoColumnWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              photo,
              gap,
              details,
              gap,
              email,
              if (work != null) ...[gap, work],
              gap,
              security,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [photo, gap, email, gap, security],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  details,
                  if (work != null) ...[gap, work],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A titled card, the shape every section on this page shares.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _PhotoCard extends ConsumerStatefulWidget {
  const _PhotoCard({required this.profile});

  final Profile profile;

  @override
  ConsumerState<_PhotoCard> createState() => _PhotoCardState();
}

class _PhotoCardState extends ConsumerState<_PhotoCard> {
  bool _busy = false;
  String? _error;

  /// Checks what the server would refuse anyway, so a too-big photo is not
  /// uploaded only to be turned away.
  static String? _problemWith(PickedFile file) {
    final name = file.name.toLowerCase();
    if (!_photoExtensions.any(name.endsWith)) return 'The photo must be a JPEG or PNG image.';
    if (file.bytes.length > _maxPhotoBytes) return 'The photo must be 2 MB or smaller.';
    return null;
  }

  Future<void> _upload() async {
    if (_busy) return;

    final PickedFile? file;
    try {
      file = await pickFile(accept: '.jpg,.jpeg,.png,image/jpeg,image/png');
    } catch (error) {
      debugPrint('Picking a profile photo failed: $error');
      if (mounted) setState(() => _error = 'The photo could not be read. Try another file.');
      return;
    }
    if (file == null || !mounted) return;

    final problem = _problemWith(file);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    await _run(
      () => ref.read(profileNotifierProvider.notifier).uploadPhoto(bytes: file!.bytes, fileName: file.name),
      success: 'Photo updated.',
    );
  }

  Future<void> _remove() async {
    if (_busy) return;

    final confirmed = await confirmDialog(
      context,
      title: 'Remove photo?',
      message: 'Your initials will be shown instead.',
      confirmLabel: 'Remove photo',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    await _run(() => ref.read(profileNotifierProvider.notifier).removePhoto(), success: 'Photo removed.');
  }

  Future<void> _run(Future<void> Function() change, {required String success}) async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      await change();
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(success)));
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) setState(() => _error = failure.validationErrors['photo']?.first ?? failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final colors = context.appColors;

    return _ProfileCard(
      title: 'Photo',
      child: Column(
        children: [
          UserAvatar(photoUrl: profile.photoUrl, name: profile.name, radius: 56),
          const SizedBox(height: 16),
          if (canPickFile)
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const Key('profile-upload-photo'),
                  onPressed: _busy ? null : _upload,
                  icon: const Icon(Icons.upload_outlined, size: 18),
                  label: const Text('Upload photo'),
                ),
                if (profile.photoUrl != null) _removeButton(),
              ],
            )
          else ...[
            Text(
              'Photos can be uploaded from the web app for now.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: colors.muted),
            ),
            if (profile.photoUrl != null) ...[const SizedBox(height: 8), _removeButton()],
          ],
          if (_busy) ...[const SizedBox(height: 12), const LinearProgressIndicator()],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.danger),
            ),
          ],
        ],
      ),
    );
  }

  Widget _removeButton() {
    return OutlinedButton.icon(
      key: const Key('profile-remove-photo'),
      onPressed: _busy ? null : _remove,
      icon: const Icon(Icons.delete_outline, size: 18),
      label: const Text('Remove photo'),
    );
  }
}

class _DetailsCard extends ConsumerStatefulWidget {
  const _DetailsCard({required this.profile});

  final Profile profile;

  @override
  ConsumerState<_DetailsCard> createState() => _DetailsCardState();
}

class _DetailsCardState extends ConsumerState<_DetailsCard> {
  final _formKey = GlobalKey<FormState>();
  late final _firstNameController = TextEditingController(text: widget.profile.firstName);
  late final _lastNameController = TextEditingController(text: widget.profile.lastName);
  late final _mobileController = TextEditingController(text: widget.profile.mobile ?? '');
  late final _addressController = TextEditingController(text: widget.profile.address ?? '');

  bool _saving = false;
  String? _error;
  Map<String, List<String>> _fieldErrors = const {};

  @override
  void initState() {
    super.initState();
    // Save follows what is typed, so it lights up only once something differs.
    for (final controller in _controllers) {
      controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  List<TextEditingController> get _controllers => [
    _firstNameController,
    _lastNameController,
    _mobileController,
    _addressController,
  ];

  void _onChanged() => setState(() {});

  bool get _changed {
    final profile = widget.profile;
    return _firstNameController.text.trim() != profile.firstName ||
        _lastNameController.text.trim() != profile.lastName ||
        _mobileController.text.trim() != (profile.mobile ?? '') ||
        (profile.hasStaffRecord && _addressController.text.trim() != (profile.address ?? ''));
  }

  String? _serverError(String field) => _fieldErrors[field]?.first;

  static String? _nameProblem(String? value, String label) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return '$label is required';
    if (text.length > 100) return '$label must be 100 characters or fewer';
    return null;
  }

  Future<void> _save() async {
    if (_saving || !_changed || !_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(profileNotifierProvider.notifier)
          .updateDetails(
            firstName: _firstNameController.text.trim(),
            lastName: _lastNameController.text.trim(),
            mobile: _mobileController.text.trim(),
            address: widget.profile.hasStaffRecord ? _addressController.text.trim() : null,
          );
      messenger
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Profile updated.')));
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) {
        setState(() {
          _fieldErrors = failure.validationErrors;
          // A message already shown under a field is not repeated below.
          _error = _fieldErrors.isEmpty ? failure.message : null;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final mobileError = _serverError('mobile');

    return _ProfileCard(
      title: 'My details',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('profile-first-name'),
              controller: _firstNameController,
              decoration: InputDecoration(labelText: 'First name', errorText: _serverError('first_name')),
              validator: (v) => _nameProblem(v, 'First name'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('profile-last-name'),
              controller: _lastNameController,
              decoration: InputDecoration(labelText: 'Last name', errorText: _serverError('last_name')),
              validator: (v) => _nameProblem(v, 'Last name'),
            ),
            const SizedBox(height: 12),
            PhoneNumberField(key: const Key('profile-mobile'), controller: _mobileController, label: 'Mobile'),
            if (mobileError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 12),
                child: Text(mobileError, style: TextStyle(fontSize: 12, color: colors.danger)),
              ),
            if (widget.profile.hasStaffRecord) ...[
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('profile-address'),
                controller: _addressController,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(labelText: 'Home address', errorText: _serverError('address')),
                validator: (v) => (v ?? '').trim().length > 500 ? 'Home address must be 500 characters or fewer' : null,
              ),
            ],
            if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: TextStyle(color: colors.danger))],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                key: const Key('profile-save'),
                onPressed: _saving || !_changed ? null : _save,
                child: _saving
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmailCard extends StatelessWidget {
  const _EmailCard({required this.email, this.keptBySchool = false});

  /// Null when there is no address on record (a Bus Attendant added without one).
  final String? email;

  /// A Bus Attendant: no password to confirm a change with, so the school
  /// office keeps the address.
  final bool keptBySchool;

  Future<void> _change(BuildContext context) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => ChangeEmailDialog(currentEmail: email ?? ''),
    );
    if (changed != true || !context.mounted) return;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('Email changed. Other devices have been signed out.')));
  }

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: context.appColors.muted);

    return _ProfileCard(
      title: keptBySchool ? 'Email' : 'Sign-in email',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (email == null)
            Text('No email on record', key: const Key('profile-email'), style: muted)
          else
            SelectableText(email!, key: const Key('profile-email')),
          const SizedBox(height: 12),
          if (keptBySchool)
            Text(
              'You sign in with your mobile number and passcode. Your school office keeps your email address.',
              style: muted,
            )
          else
            OutlinedButton.icon(
              key: const Key('profile-change-email'),
              onPressed: () => _change(context),
              icon: const Icon(Icons.alternate_email, size: 18),
              label: const Text('Change email'),
            ),
        ],
      ),
    );
  }
}

/// What the school keeps about the user's job. Shown, never edited here.
class _WorkCard extends StatelessWidget {
  const _WorkCard({required this.profile, required this.employment});

  final Profile profile;
  final Employment employment;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(fontSize: 13, color: context.appColors.muted);

    return _ProfileCard(
      title: 'Work details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoRow(label: 'Employee ID', value: employment.employeeId),
          _InfoRow(label: 'Department', value: employment.departmentName ?? '-'),
          _InfoRow(label: 'Designation', value: employment.designation ?? '-'),
          _InfoRow(label: 'Joining date', value: employment.joiningDateLabel ?? employment.joiningDate ?? '-'),
          _InfoRow(label: 'Role', value: profile.roleLabel),
          _InfoRow(label: 'School', value: profile.schoolName ?? '-'),
          const SizedBox(height: 8),
          Text("These are kept by your school's administrators.", style: muted),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(color: context.appColors.muted)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _SecurityCard extends StatelessWidget {
  const _SecurityCard({required this.hasPassword});

  /// False for a Bus Attendant, who signs in with a passcode instead.
  final bool hasPassword;

  @override
  Widget build(BuildContext context) {
    return _ProfileCard(
      title: 'Security',
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          if (hasPassword)
            OutlinedButton.icon(
              onPressed: () => showDialog(context: context, builder: (_) => const ChangePasswordDialog()),
              icon: const Icon(Icons.lock_outline, size: 18),
              label: const Text('Change password'),
            ),
          OutlinedButton.icon(
            onPressed: () => showDialog(context: context, builder: (_) => const SignedInDevicesDialog()),
            icon: const Icon(Icons.devices_outlined, size: 18),
            label: const Text('Signed-in devices'),
          ),
        ],
      ),
    );
  }
}
