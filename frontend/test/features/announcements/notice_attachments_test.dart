import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/notice_attachment.dart';
import 'package:edutrack_app/core/network/dio_client.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/utils/picked_file.dart';
import 'package:edutrack_app/core/widgets/notice_attachment_chips.dart';
import 'package:edutrack_app/features/announcements/data/models/announcement.dart';
import 'package:edutrack_app/features/announcements/presentation/new_announcement_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_announcement_repository.dart';
import '../../support/fake_photo_dio.dart';
import 'announcement_test.dart' show openDialog, useDesktop;

/// Files on a notice (docs/mobile-apps-review.md, M9, 8.3): attaching up
/// to three in the compose form, and opening them from wherever the notice
/// is read.
void main() {
  /// The files the "person" picks, one per tap of Attach.
  List<Override> picking(List<PickedFile> files) {
    final queue = [...files];
    return [noticeFilePickerProvider.overrideWithValue(() async => queue.isEmpty ? null : queue.removeAt(0))];
  }

  const circular = PickedFile(name: 'circular.pdf', bytes: [37, 80, 68, 70, 45]);

  Future<void> fillIn(WidgetTester tester) async {
    await tester.enterText(find.widgetWithText(TextFormField, 'Announcement title'), 'Sports day');
    await tester.enterText(find.widgetWithText(TextFormField, 'Message'), 'Sports day is on Friday at 9 AM.');
  }

  group('the compose form', () {
    testWidgets('an attached file is uploaded at once and sent with the notice', (tester) async {
      useDesktop(tester);
      final fake = FakeAnnouncementRepository();
      await openDialog(tester, fake, overrides: picking([circular]));

      await tester.tap(find.byKey(const Key('announcement-attach')));
      await tester.pumpAndSettle();
      expect(fake.uploaded, ['circular.pdf']);
      expect(find.byKey(const Key('announcement-file-1')), findsOneWidget);

      await fillIn(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Publish'));
      await tester.pumpAndSettle();

      expect(fake.lastCall!['attachment_ids'], [1]);
      expect(fake.removed, isEmpty, reason: 'a sent file is not taken back');
    });

    testWidgets('a fourth file cannot be added', (tester) async {
      useDesktop(tester);
      final fake = FakeAnnouncementRepository();
      await openDialog(tester, fake, overrides: picking(List.filled(4, circular)));

      for (var i = 0; i < 3; i++) {
        await tester.ensureVisible(find.byKey(const Key('announcement-attach')));
        await tester.tap(find.byKey(const Key('announcement-attach')));
        await tester.pumpAndSettle();
      }

      expect(fake.uploaded.length, 3);
      expect(find.byKey(const Key('announcement-attach')), findsNothing);
    });

    testWidgets('a file of the wrong kind or too big is refused before uploading', (tester) async {
      useDesktop(tester);
      final fake = FakeAnnouncementRepository();
      await openDialog(
        tester,
        fake,
        overrides: picking([
          const PickedFile(name: 'notes.docx', bytes: [1]),
          PickedFile(name: 'scan.pdf', bytes: List.filled(5 * 1024 * 1024 + 1, 0)),
        ]),
      );

      await tester.tap(find.byKey(const Key('announcement-attach')));
      await tester.pumpAndSettle();
      expect(find.text('Attach a PDF, JPEG or PNG file.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('announcement-attach')));
      await tester.pumpAndSettle();
      expect(find.text('Each file must be 5 MB or smaller.'), findsOneWidget);
      expect(fake.uploaded, isEmpty);
    });

    testWidgets("the server's refusal of a file is shown as it said it", (tester) async {
      useDesktop(tester);
      final fake = FakeAnnouncementRepository()
        ..failUploadWith = const Failure(
          code: 'VALIDATION_ERROR',
          message: 'The given data was invalid.',
          details: {
            'errors': {
              'file': ['Attach a PDF, JPEG or PNG file.'],
            },
          },
        );
      await openDialog(tester, fake, overrides: picking([circular]));

      await tester.tap(find.byKey(const Key('announcement-attach')));
      await tester.pumpAndSettle();

      expect(find.text('Attach a PDF, JPEG or PNG file.'), findsOneWidget);
    });

    testWidgets('removing a file takes it back from the server', (tester) async {
      useDesktop(tester);
      final fake = FakeAnnouncementRepository();
      await openDialog(tester, fake, overrides: picking([circular]));
      await tester.tap(find.byKey(const Key('announcement-attach')));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle();

      expect(fake.removed, [1]);
      expect(find.byKey(const Key('announcement-file-1')), findsNothing);
    });

    testWidgets('cancelling takes back what was uploaded', (tester) async {
      useDesktop(tester);
      final fake = FakeAnnouncementRepository();
      await openDialog(tester, fake, overrides: picking([circular]));
      await tester.tap(find.byKey(const Key('announcement-attach')));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(fake.removed, [1]);
    });

    testWidgets('files need the in-app channel', (tester) async {
      useDesktop(tester);
      final fake = FakeAnnouncementRepository();
      await openDialog(tester, fake, overrides: picking([circular]));
      await tester.tap(find.byKey(const Key('announcement-attach')));
      await tester.pumpAndSettle();
      await fillIn(tester);

      await tester.tap(find.widgetWithText(FilterChip, 'In-app'));
      await tester.tap(find.widgetWithText(FilledButton, 'Publish'));
      await tester.pumpAndSettle();

      expect(find.text('Files are seen in the app. Turn on In-app to send them.'), findsOneWidget);
      expect(fake.lastCall, isNull);
    });

    testWidgets('where files cannot be picked, the button is not offered', (tester) async {
      useDesktop(tester);
      await openDialog(
        tester,
        FakeAnnouncementRepository(),
        overrides: [noticeFilePickerProvider.overrideWithValue(null)],
      );

      expect(find.byKey(const Key('announcement-attach')), findsNothing);
    });
  });

  group('reading a notice', () {
    const pdf = NoticeAttachment(
      id: 4,
      name: 'circular.pdf',
      contentType: 'application/pdf',
      sizeBytes: 245760,
      url: '/announcement-attachments/4',
    );
    const poster = NoticeAttachment(
      id: 5,
      name: 'poster.png',
      contentType: 'image/png',
      sizeBytes: 1468006,
      url: '/announcement-attachments/5',
    );

    Future<List<(String, String)>> pump(WidgetTester tester, {List<int>? bytes}) async {
      final handedOff = <(String, String)>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dioClientProvider.overrideWithValue(fakePhotoDio(bytes: bytes)),
            fileHandOffProvider.overrideWithValue((bytes, name, mime) async => handedOff.add((name, mime))),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: NoticeAttachmentChips(attachments: [pdf, poster])),
          ),
        ),
      );
      return handedOff;
    }

    test('the size reads in KB or MB', () {
      expect((pdf.sizeLabel, poster.sizeLabel), ('240 KB', '1.4 MB'));
    });

    test('a notice from an older server has no files', () {
      expect(NoticeAttachment.listFrom(null), isEmpty);
    });

    testWidgets('each file has a chip with its name and size', (tester) async {
      await pump(tester);

      expect(find.text('circular.pdf · 240 KB'), findsOneWidget);
      expect(find.text('poster.png · 1.4 MB'), findsOneWidget);
    });

    testWidgets('a PDF goes to download or the share sheet', (tester) async {
      final handedOff = await pump(tester, bytes: const [37, 80, 68, 70]);

      await tester.tap(find.byKey(const Key('notice-attachment-4')));
      await tester.pumpAndSettle();

      expect(handedOff, [('circular.pdf', 'application/pdf')]);
    });

    testWidgets('a picture opens in the app and can be saved from there', (tester) async {
      final handedOff = await pump(tester, bytes: const [1, 2, 3]);

      await tester.tap(find.byKey(const Key('notice-attachment-5')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notice-attachment-picture')), findsOneWidget);

      await tester.tap(find.byKey(const Key('notice-attachment-save')));
      await tester.pumpAndSettle();
      expect(handedOff, [('poster.png', 'image/png')]);
    });

    testWidgets('a file that cannot be fetched says so', (tester) async {
      final handedOff = await pump(tester);

      await tester.tap(find.byKey(const Key('notice-attachment-4')));
      await tester.pumpAndSettle();

      expect(handedOff, isEmpty);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    test('the list of notices carries each notice\'s files', () {
      final announcement = Announcement.fromJson({
        'id': 1,
        'school_id': 1,
        'title': 'Sports day',
        'body': 'Friday',
        'audience_type': 'all_school',
        'audience_label': 'All School',
        'channels': 'in_app',
        'attachments': [
          {'id': 4, 'name': 'circular.pdf', 'content_type': 'application/pdf', 'size_bytes': 10, 'url': '/x'},
        ],
      });

      expect(announcement.attachments.single.name, 'circular.pdf');
    });
  });
}
