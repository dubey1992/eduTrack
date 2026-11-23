import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/photo_picker.dart';
import '../../../../core/utils/picked_file.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../application/student_list_notifier.dart';
import '../../data/models/student.dart';

/// The largest photo the server accepts.
const _maxPhotoBytes = 2 * 1024 * 1024;

const _photoExtensions = ['.jpg', '.jpeg', '.png'];

/// A student's photo in the Edit Student dialog (docs/student-photos.md):
/// the photo or the initials, and buttons to add, change or remove it.
///
/// A change is saved the moment it is made, like the photo on My Profile -
/// not with the rest of the form - so a photo is never lost to a form
/// error elsewhere. The server cuts it to a 3:4 passport shape.
class StudentPhotoField extends ConsumerStatefulWidget {
  const StudentPhotoField({super.key, required this.student});

  final Student student;

  @override
  ConsumerState<StudentPhotoField> createState() => _StudentPhotoFieldState();
}

class _StudentPhotoFieldState extends ConsumerState<StudentPhotoField> {
  late Student _student = widget.student;
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

    // On a phone, the camera or the phone's photos; the web's file chooser
    // offers both by itself.
    final source = kIsWeb ? PhotoSource.gallery : await _askSource();
    if (source == null || !mounted) return;

    final PickedFile? file;
    try {
      file = await ref.read(photoPickerProvider)(source);
    } catch (error) {
      debugPrint('Picking a student photo failed: $error');
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
      () =>
          ref.read(studentListNotifierProvider.notifier).uploadPhoto(_student, bytes: file!.bytes, fileName: file.name),
      success: 'Photo saved.',
    );
  }

  Future<PhotoSource?> _askSource() => showModalBottomSheet<PhotoSource>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const Key('student-photo-camera'),
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.of(context).pop(PhotoSource.camera),
          ),
          ListTile(
            key: const Key('student-photo-gallery'),
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from photos'),
            onTap: () => Navigator.of(context).pop(PhotoSource.gallery),
          ),
        ],
      ),
    ),
  );

  Future<void> _remove() async {
    if (_busy) return;

    final confirmed = await confirmDialog(
      context,
      title: 'Remove photo?',
      message: "${_student.name}'s initials will be shown instead.",
      confirmLabel: 'Remove photo',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    await _run(() => ref.read(studentListNotifierProvider.notifier).removePhoto(_student), success: 'Photo removed.');
  }

  Future<void> _run(Future<Student> Function() change, {required String success}) async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await change();
      if (mounted) setState(() => _student = updated);
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
    final hasPhoto = _student.photoUrl != null;

    return Column(
      key: const Key('student-photo-field'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            UserAvatar(photoUrl: _student.photoUrl, name: _student.name, radius: 36),
            const SizedBox(width: 16),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const Key('student-photo-upload'),
                    onPressed: _busy ? null : _upload,
                    icon: Icon(kIsWeb ? Icons.upload_outlined : Icons.photo_camera_outlined, size: 18),
                    label: Text(hasPhoto ? 'Change photo' : 'Add photo'),
                  ),
                  if (hasPhoto)
                    TextButton.icon(
                      key: const Key('student-photo-remove'),
                      onPressed: _busy ? null : _remove,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Remove'),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (_busy) ...[const SizedBox(height: 10), const LinearProgressIndicator()],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            key: const Key('student-photo-error'),
            style: TextStyle(color: context.appColors.danger),
          ),
        ],
      ],
    );
  }
}
