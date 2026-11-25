import 'package:edutrack_app/features/gallery/data/gallery_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_family_repositories.dart';
import 'family_app_test.dart';

/// Events and photos in the Family app (docs/mobile-apps-review.md, M12, 8.6).
void main() {
  testWidgets('shows each event with its photos', (tester) async {
    await pumpFamilyApp(tester, goTo: '/gallery');

    expect(find.text('Annual Day'), findsOneWidget);
    expect(find.text('11/20/2026 · Whole school · 2 photos'), findsOneWidget);
  });

  testWidgets('an event opens its photos, and a photo opens full screen', (tester) async {
    await pumpFamilyApp(tester, goTo: '/gallery');

    await tester.tap(find.byKey(const Key('family-gallery-5')));
    await tester.pumpAndSettle();
    expect(find.text('Our 25th year on stage.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('gallery-photo-52')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('photo-viewer')), findsOneWidget);
    expect(find.text('Annual Day  2/2'), findsOneWidget);
    // A parent cannot remove anything.
    expect(find.byKey(const Key('gallery-remove-51')), findsNothing);
  });

  testWidgets('more than three photos show how many more', (tester) async {
    final data = FakeFamilyRepository()
      ..galleryValue = [
        GalleryEvent(
          id: 6,
          schoolId: 1,
          title: 'Class picnic',
          date: DateTime(2026, 11, 21),
          dateLabel: '11/21/2026',
          className: 'Class 6 A',
          photos: [for (var i = 1; i <= 5; i++) GalleryPhoto(id: i, url: '/p/$i', thumbUrl: '/p/$i?size=thumb')],
        ),
      ];
    await pumpFamilyApp(tester, data: data, goTo: '/gallery');

    expect(find.text('+2'), findsOneWidget);
    expect(find.text('11/21/2026 · Class 6 A · 5 photos'), findsOneWidget);
  });

  testWidgets('older events load a page at a time', (tester) async {
    final data = FakeFamilyRepository()
      ..olderGallery = [
        GalleryEvent(
          id: 4,
          schoolId: 1,
          title: 'Sports Day',
          date: DateTime(2026, 10, 2),
          dateLabel: '10/02/2026',
          photos: const [GalleryPhoto(id: 41, url: '/p/41', thumbUrl: '/p/41?size=thumb')],
        ),
      ];
    await pumpFamilyApp(tester, data: data, goTo: '/gallery');

    await tester.ensureVisible(find.byKey(const Key('family-gallery-more')));
    await tester.tap(find.byKey(const Key('family-gallery-more')));
    await tester.pumpAndSettle();

    expect(data.galleryPagesRead, [1, 2]);
    expect(find.text('Sports Day'), findsOneWidget);
    expect(find.byKey(const Key('family-gallery-more')), findsNothing);
  });

  testWidgets('nothing shared yet', (tester) async {
    final data = FakeFamilyRepository()..galleryValue = [];
    await pumpFamilyApp(tester, data: data, goTo: '/gallery');

    expect(find.text('No photos yet'), findsOneWidget);
  });

  testWidgets('More is the way in', (tester) async {
    await pumpFamilyApp(tester, goTo: '/more');
    await revealOnMore(tester, find.byKey(const Key('family-more-gallery')));
    await tester.tap(find.byKey(const Key('family-more-gallery')));
    await tester.pumpAndSettle();

    expect(find.text('Annual Day'), findsOneWidget);
  });
}
