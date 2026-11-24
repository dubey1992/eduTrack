import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/failure_text.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/photo_picker.dart';
import '../../../../core/utils/picked_file.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../data/models/student.dart';
import '../../data/student_repository.dart';

/// The largest photo the server accepts (school/student_photos.py) - more
/// than a profile photo's 2 MB, since class photos come off a camera.
const _maxPhotoBytes = 5 * 1024 * 1024;

const _photoExtensions = ['.jpg', '.jpeg', '.png'];

/// A student's photo in the Edit Student dialog (docs/student-photos.md):
/// the photo or the initials, and buttons to add, change or remove it.
///
/// A change is saved the moment it is made, like the photo on My Profile -
/// not with the rest of the form - so a photo is never lost to a form
/// error elsewhere. The server cuts it to a 3:4 passport shape.
///
/// Used in Edit Student on the web and in Find a student in the staff app,
/// where a class teacher sets photos for their own section (D3).
class StudentPhotoField extends ConsumerStatefulWidget {
  const StudentPhotoField({super.key, required this.student, this.onChanged});

  final Student student;

  /// The student as the server now has them, after each change - to update
  /// whatever list the student came from.
  final ValueChanged<Student>? onChanged;

  @override
  ConsumerState<StudentPhotoField> createState() => _StudentPhotoFieldState();
}

class _StudentPhotoFieldState extends ConsumerState<StudentPhotoField> {
  late Student _student = widget.student;
  bool _busy = false;
  String? _error;

  /// Checks what the server would refuse anyway, so a too-big photo is not
  /// uploaded only to be turned away.
  static String? _problemWith(AppLocalizations l10n, PickedFile file) {
    final name = file.name.toLowerCase();
    if (!_photoExtensions.any(name.endsWith)) return l10n.staffPhotoMustBeImage;
    if (file.bytes.length > _maxPhotoBytes) return l10n.staffStudentPhotoTooBig;
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
      if (mounted) setState(() => _error = context.l10n.staffPhotoUnreadable);
      return;
    }
    if (file == null || !mounted) return;

    final problem = _problemWith(context.l10n, file);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    await _run(
      () => ref.read(studentRepositoryProvider).uploadPhoto(_student.id, bytes: file!.bytes, fileName: file.name),
      success: context.l10n.staffPhotoSaved,
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
            title: Text(context.l10n.staffTakeAPhoto),
            onTap: () => Navigator.of(context).pop(PhotoSource.camera),
          ),
          ListTile(
            key: const Key('student-photo-gallery'),
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(context.l10n.staffChooseFromPhotosShort),
            onTap: () => Navigator.of(context).pop(PhotoSource.gallery),
          ),
        ],
      ),
    ),
  );

  Future<void> _remove() async {
    if (_busy) return;

    final l10n = context.l10n;
    final confirmed = await confirmDialog(
      context,
      title: l10n.staffRemovePhotoShortQ,
      message: l10n.staffStudentInitialsInstead(_student.name),
      confirmLabel: l10n.staffRemovePhoto,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    await _run(() => ref.read(studentRepositoryProvider).removePhoto(_student.id), success: l10n.staffPhotoRemoved);
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
      widget.onChanged?.call(updated);
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(success)));
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) {
        setState(() => _error = failure.validationErrors['photo']?.first ?? failure.localizedMessage(context));
      }
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
                    label: Text(hasPhoto ? context.l10n.staffChangePhoto : context.l10n.staffAddPhoto),
                  ),
                  if (hasPhoto)
                    TextButton.icon(
                      key: const Key('student-photo-remove'),
                      onPressed: _busy ? null : _remove,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: Text(context.l10n.staffRemove),
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
