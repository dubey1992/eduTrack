import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/utils/picked_file.dart';
import '../data/models/photo_import.dart';
import '../data/student_photo_import_repository.dart';

/// The largest photo the server takes (school/student_photos.py).
const maxStudentPhotoBytes = 5 * 1024 * 1024;

/// One request carries at most this many files...
const photosPerBatch = 10;

/// ...and about this many bytes, whichever comes first: the live API runs as
/// CGI, which answers small requests reliably (docs/deployment.md).
const bytesPerBatch = 10 * 1024 * 1024;

enum BulkPhotoStep {
  /// Nothing chosen yet.
  choose,

  /// Asking the server what each file name matches.
  checking,

  /// Showing what will happen, before anything is sent.
  preview,

  /// Sending, a batch at a time.
  uploading,

  /// A batch failed; what was sent is kept, and the rest can be tried again.
  paused,

  /// Everything that could be sent has been.
  done,
}

@immutable
class BulkPhotoState {
  const BulkPhotoState({
    this.step = BulkPhotoStep.choose,
    this.files = const [],
    this.rows = const [],
    this.results = const [],
    this.sent = 0,
    this.error,
  });

  final BulkPhotoStep step;

  /// The chosen files, in the same order as [rows].
  final List<ChosenFile> files;
  final List<PhotoPreviewRow> rows;

  /// What the server did with each file sent so far.
  final List<PhotoUploadResult> results;

  /// How many of the files to send have been sent.
  final int sent;
  final String? error;

  /// The files that will be sent, by their place in [files].
  List<int> get toSend => [
    for (var i = 0; i < rows.length; i++)
      if (rows[i].status.uploads) i,
  ];

  int get heldBack => rows.length - toSend.length;

  int count(PhotoUploadStatus status) => results.where((result) => result.status == status).length;

  BulkPhotoState copyWith({
    BulkPhotoStep? step,
    List<ChosenFile>? files,
    List<PhotoPreviewRow>? rows,
    List<PhotoUploadResult>? results,
    int? sent,
    String? error,
    bool clearError = false,
  }) {
    return BulkPhotoState(
      step: step ?? this.step,
      files: files ?? this.files,
      rows: rows ?? this.rows,
      results: results ?? this.results,
      sent: sent ?? this.sent,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final bulkPhotoUploadProvider = NotifierProvider.autoDispose<BulkPhotoUploadNotifier, BulkPhotoState>(
  BulkPhotoUploadNotifier.new,
);

/// Student photos in bulk, by admission number (docs/student-photos.md, P2):
/// choose the photos, see what each one matches, then send them in small
/// batches with the progress showing.
class BulkPhotoUploadNotifier extends Notifier<BulkPhotoState> {
  /// Only a Super Admin names the school; for everybody else it is their own.
  int? _schoolId;

  @override
  BulkPhotoState build() => const BulkPhotoState();

  /// Asks the server what each chosen file's name matches. Nothing is sent
  /// but the names.
  Future<void> check(List<ChosenFile> files, {int? schoolId}) async {
    if (files.isEmpty || state.step == BulkPhotoStep.checking) return;
    _schoolId = schoolId;

    state = BulkPhotoState(step: BulkPhotoStep.checking, files: files);

    try {
      final rows = await ref.read(studentPhotoImportRepositoryProvider).preview([
        for (final file in files) file.name,
      ], schoolId: schoolId);

      // A file over the limit is caught here rather than sent to be
      // refused; the server would say the same.
      final checked = [
        for (var i = 0; i < rows.length; i++)
          i < files.length && files[i].size > maxStudentPhotoBytes && rows[i].status.uploads
              ? rows[i].tooLarge('The photo must be 5 MB or smaller.')
              : rows[i],
      ];

      state = state.copyWith(step: BulkPhotoStep.preview, rows: checked);
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      state = BulkPhotoState(error: failure.validationErrors['school_id']?.first ?? failure.message);
    }
  }

  /// Sends the matched files, a batch at a time, from wherever it got to -
  /// so after a failed batch the same call carries on.
  Future<void> upload() async {
    if (state.step != BulkPhotoStep.preview && state.step != BulkPhotoStep.paused) return;

    state = state.copyWith(step: BulkPhotoStep.uploading, clearError: true);
    final queue = state.toSend;
    final repository = ref.read(studentPhotoImportRepositoryProvider);

    while (state.sent < queue.length) {
      final batch = _nextBatch(queue, state.sent);

      try {
        final files = <({String name, List<int> bytes})>[];
        final unreadable = <PhotoUploadResult>[];

        for (final index in batch) {
          final file = state.files[index];
          try {
            files.add((name: file.name, bytes: await file.read()));
          } catch (error) {
            debugPrint('Reading ${file.name} failed: $error');
            unreadable.add(
              PhotoUploadResult(
                fileName: file.name,
                status: PhotoUploadStatus.skipped,
                reason: 'This file could not be read.',
              ),
            );
          }
        }

        final results = files.isEmpty ? <PhotoUploadResult>[] : await repository.upload(files, schoolId: _schoolId);
        if (!ref.mounted) return;

        state = state.copyWith(results: [...state.results, ...results, ...unreadable], sent: state.sent + batch.length);
      } catch (error) {
        if (!ref.mounted) return;
        final failure = error is Failure ? error : Failure.unknown(error.toString());
        state = state.copyWith(step: BulkPhotoStep.paused, error: failure.message);
        return;
      }
    }

    state = state.copyWith(step: BulkPhotoStep.done);
  }

  /// Up to [photosPerBatch] files and about [bytesPerBatch] bytes, always at
  /// least one file.
  List<int> _nextBatch(List<int> queue, int from) {
    final batch = <int>[];
    var bytes = 0;

    for (var i = from; i < queue.length && batch.length < photosPerBatch; i++) {
      final size = state.files[queue[i]].size;
      if (batch.isNotEmpty && bytes + size > bytesPerBatch) break;
      batch.add(queue[i]);
      bytes += size;
    }

    return batch;
  }

  /// Back to the start, to choose other photos.
  void reset() => state = const BulkPhotoState();
}
