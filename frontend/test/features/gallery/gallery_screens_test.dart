import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/utils/photo_picker.dart';
import 'package:edutrack_app/core/utils/picked_file.dart';
import 'package:edutrack_app/core/widgets/signed_in_image.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/classes/application/class_section_picker_provider.dart';
import 'package:edutrack_app/features/gallery/application/gallery_providers.dart';
import 'package:edutrack_app/features/gallery/data/gallery_models.dart';
import 'package:edutrack_app/features/gallery/data/gallery_repository.dart';
import 'package:edutrack_app/features/gallery/presentation/gallery_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/session_users.dart';
import '../family/family_app_test.dart' show onePixelPng;

/// Events and photos as the school posts them (docs/mobile-apps-review.md,
/// M12, 8.6).
class FakeGalleryRepository implements GalleryRepository {
  final List<GalleryEventDraft> created = [];
  final List<String> uploaded = [];
  final List<int> removedPhotos = [];
  final List<int> deleted = [];
  Failure? failUploadWith;
  int photoCount = 2;

  GalleryEvent event({int id = 5, bool canChange = true, int? photos}) => GalleryEvent(
    id: id,
    schoolId: 1,
    title: 'Annual Day',
    date: DateTime(2026, 11, 20),
    dateLabel: '11/20/2026',
    description: 'Our 25th year on stage.',
    postedBy: 'Meera Joshi',
    canChange: canChange,
    photos: [
      for (var i = 1; i <= (photos ?? photoCount); i++)
        GalleryPhoto(id: i, url: '/gallery-photos/$i', thumbUrl: '/gallery-photos/$i?size=thumb'),
    ],
  );

  @override
  Future<PaginatedResponse<GalleryEvent>> list({int page = 1}) async =>
      PaginatedResponse(items: [event()], currentPage: 1, lastPage: 1, total: 1, perPage: 15);

  @override
  Future<GalleryEvent> get(int id) async => event(id: id);

  @override
  Future<GalleryEvent> create(GalleryEventDraft draft) async {
    created.add(draft);
    return event(id: 9, photos: 0);
  }

  @override
  Future<GalleryEvent> update(int id, GalleryEventDraft draft) async => event(id: id);

  @override
  Future<void> delete(int id) async => deleted.add(id);

  @override
  Future<GalleryEvent> addPhoto(int eventId, PickedFile file) async {
    if (failUploadWith != null) throw failUploadWith!;
    uploaded.add(file.name);
    photoCount++;
    return event(id: eventId);
  }

  @override
  Future<void> removePhoto(int photoId) async {
    removedPhotos.add(photoId);
    photoCount--;
  }
}

Future<FakeGalleryRepository> pump(WidgetTester tester, Widget screen, {UserRole role = UserRole.schoolAdmin}) async {
  final fake = FakeGalleryRepository();
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        galleryRepositoryProvider.overrideWithValue(fake),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: sessionUser(role))),
        classSectionPickerProvider.overrideWith(
          (ref, arg) async => const [
            ClassSectionOption(id: 10, label: 'Grade 8 A', classTeacherId: 999),
            ClassSectionOption(id: 11, label: 'Grade 8 B'),
          ],
        ),
        signedInImageProvider.overrideWith((ref, url) async => onePixelPng),
        photoPickerProvider.overrideWithValue((source) async => const PickedFile(name: 'stage.jpg', bytes: [1, 2, 3])),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => Scaffold(body: screen),
            ),
            GoRoute(
              path: '/gallery/:id',
              builder: (context, state) =>
                  Scaffold(body: GalleryEventScreen(eventId: int.parse(state.pathParameters['id']!))),
            ),
            GoRoute(
              path: '/gallery',
              builder: (context, state) => const Scaffold(body: Text('the list')),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets('lists events with who sees them and how many photos', (tester) async {
    await pump(tester, const GalleryEventsScreen());

    expect(find.text('Annual Day'), findsOneWidget);
    expect(find.text('11/20/2026 · Parents of the whole school · 2 photos'), findsOneWidget);
  });

  testWidgets('an admin posts to the whole school by default', (tester) async {
    final fake = await pump(tester, const GalleryEventsScreen());

    await tester.tap(find.byKey(const Key('gallery-new')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gallery-save')));
    await tester.pumpAndSettle();
    expect(find.text('Give the event a name.'), findsOneWidget);
    expect(fake.created, isEmpty);

    await tester.enterText(find.byKey(const Key('gallery-title')), 'Sports Day');
    await tester.tap(find.byKey(const Key('gallery-save')));
    await tester.pumpAndSettle();

    expect(fake.created.single.title, 'Sports Day');
    expect(fake.created.single.classSectionId, isNull);
    // Straight on to adding its photos.
    expect(find.byType(GalleryEventScreen), findsOneWidget);
  });

  testWidgets('a teacher is offered only their own class, and must choose it', (tester) async {
    final fake = await pump(tester, const GalleryEventsScreen(), role: UserRole.teacher);

    await tester.tap(find.byKey(const Key('gallery-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('gallery-title')), 'Class picnic');
    await tester.tap(find.byKey(const Key('gallery-save')));
    await tester.pumpAndSettle();
    expect(find.text('Choose your class.'), findsOneWidget);
    expect(fake.created, isEmpty);

    await tester.tap(find.byKey(const ValueKey('gallery-audience-0')));
    await tester.pumpAndSettle();
    expect(find.text('Parents of the whole school'), findsNothing);
  });

  testWidgets('adds a photo from the phone and says so', (tester) async {
    final fake = await pump(tester, const GalleryEventScreen(eventId: 5));

    expect(find.text('2 of 20 photos'), findsOneWidget);
    await tester.tap(find.byKey(const Key('gallery-add-photo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gallery-source-camera')));
    await tester.pumpAndSettle();

    expect(fake.uploaded, ['stage.jpg']);
    expect(find.text('Photo added'), findsOneWidget);
    expect(find.text('3 of 20 photos'), findsOneWidget);
  });

  testWidgets("the server's refusal of a photo is shown", (tester) async {
    final fake = await pump(tester, const GalleryEventScreen(eventId: 5));
    fake.failUploadWith = const Failure(code: 'GALLERY_REFUSED', message: 'The photo must be a JPEG or PNG image.');

    await tester.tap(find.byKey(const Key('gallery-add-photo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gallery-source-photos')));
    await tester.pumpAndSettle();

    expect(find.text('The photo must be a JPEG or PNG image.'), findsOneWidget);
  });

  testWidgets('removing a photo asks first', (tester) async {
    final fake = await pump(tester, const GalleryEventScreen(eventId: 5));

    await tester.tap(find.byKey(const Key('gallery-remove-1')));
    await tester.pumpAndSettle();
    expect(find.text('Remove this photo?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('gallery-confirm')));
    await tester.pumpAndSettle();

    expect(fake.removedPhotos, [1]);
    expect(find.text('Photo removed'), findsOneWidget);
  });

  testWidgets('a full event cannot take another photo', (tester) async {
    final fake = await pump(tester, const GalleryEventScreen(eventId: 5));
    fake.photoCount = galleryMaxPhotos;
    await tester.tap(find.byKey(const Key('gallery-remove-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Read again with 20 photos.
    final container = ProviderScope.containerOf(tester.element(find.byType(GalleryEventScreen)));
    await container.read(galleryEventProvider(5).notifier).refresh();
    await tester.pumpAndSettle();

    expect(find.text('This event has the most photos it can hold (20).'), findsOneWidget);
    expect(tester.widget<ButtonStyleButton>(find.byKey(const Key('gallery-add-photo'))).onPressed, isNull);
  });

  testWidgets('someone who may not change it sees only the photos', (tester) async {
    final fake = FakeGalleryRepository();
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          galleryRepositoryProvider.overrideWithValue(_ReadOnly(fake)),
          authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.teacher))),
          signedInImageProvider.overrideWith((ref, url) async => onePixelPng),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: GalleryEventScreen(eventId: 5)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('gallery-add-photo')), findsNothing);
    expect(find.byKey(const Key('gallery-delete')), findsNothing);
    expect(find.byKey(const Key('gallery-remove-1')), findsNothing);
  });

  testWidgets('deleting the event asks first', (tester) async {
    final fake = await pump(tester, const GalleryEventScreen(eventId: 5));

    await tester.tap(find.byKey(const Key('gallery-delete')));
    await tester.pumpAndSettle();
    expect(find.text('Delete Annual Day?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(fake.deleted, isEmpty);

    await tester.tap(find.byKey(const Key('gallery-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gallery-confirm')));
    await tester.pumpAndSettle();

    expect(fake.deleted, [5]);
    expect(find.text('the list'), findsOneWidget);
  });
}

class _ReadOnly extends FakeGalleryRepository {
  _ReadOnly(this._inner);

  final FakeGalleryRepository _inner;

  @override
  Future<GalleryEvent> get(int id) async => _inner.event(id: id, canChange: false);
}
