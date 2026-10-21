import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/transport/data/transport_repository.dart';
import 'package:edutrack_app/features/transport/presentation/widgets/route_builder_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_map.dart';
import '../../support/fake_transport_repository.dart';

/// Drawing a route on the school's map (docs/maps.md).
///
/// The feature is the order: tap where each stop is, in the order the bus
/// takes them, and the list beside the map is the route. Two things carry
/// the weight - that a tap lands a stop at the end of the run, and that
/// **nothing is saved until Save**, because a route half-built in the
/// database is a mess somebody has to unpick.
const _admin = AuthenticatedUser(
  id: 5,
  name: 'Admin',
  email: 'admin@example.com',
  role: UserRole.schoolAdmin,
  schoolId: 7,
);

const _school = LatLng(28.6139, 77.2090);

Widget wrap(FakeTransportRepository fake, FakeMapRenderer renderer, {LatLng? at = _school}) {
  return ProviderScope(
    overrides: [
      transportRepositoryProvider.overrideWithValue(fake),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _admin)),
      ...mapIsAvailable(renderer),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: RouteBuilderMap(schoolId: 7, schoolAt: at, schoolName: 'Abbey Road School'),
      ),
    ),
  );
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1500, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Into drawing mode, where a tap on the map means something.
Future<void> startDrawing(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('new-route')));
  await tester.pumpAndSettle();
}

Future<void> dropStops(WidgetTester tester, FakeMapRenderer renderer, int count) async {
  for (var i = 0; i < count; i++) {
    renderer.tapAt(LatLng(28.62 + i * 0.01, 77.21));
    await tester.pumpAndSettle();
  }
}

void main() {
  group('before anybody starts', () {
    testWidgets('a tap on the map does nothing', (tester) async {
      // The map is for looking at until somebody says they are drawing.
      useDesktop(tester);
      final renderer = FakeMapRenderer();
      await tester.pumpWidget(wrap(FakeTransportRepository(), renderer));
      await tester.pumpAndSettle();

      expect(renderer.lastView?.onTap, isNull);
      expect(find.byKey(const Key('new-route')), findsOneWidget);
    });

    testWidgets('a school nobody has placed says so instead of offering a map', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeTransportRepository(), FakeMapRenderer(), at: null));
      await tester.pumpAndSettle();

      expect(find.textContaining('Place this school on the map first'), findsOneWidget);
      expect(find.byKey(const Key('new-route')), findsNothing);
    });
  });

  group('drawing', () {
    testWidgets('a tap drops a stop at the end of the run', (tester) async {
      useDesktop(tester);
      final renderer = FakeMapRenderer();
      await tester.pumpWidget(wrap(FakeTransportRepository(), renderer));
      await startDrawing(tester);

      expect(find.textContaining('Tap the map to drop the first stop'), findsOneWidget);

      await dropStops(tester, renderer, 2);

      expect(find.text('Stop 1'), findsOneWidget);
      expect(find.text('Stop 2'), findsOneWidget);
    });

    testWidgets('each stop gets a pin, and the run gets a line', (tester) async {
      useDesktop(tester);
      final renderer = FakeMapRenderer();
      await tester.pumpWidget(wrap(FakeTransportRepository(), renderer));
      await startDrawing(tester);
      await dropStops(tester, renderer, 3);

      expect(renderer.markersById.keys, containsAll(['school-7', 'draft-0', 'draft-1', 'draft-2']));
      expect(renderer.polylines.single.points.length, 3);
    });

    testWidgets('one stop is not a line', (tester) async {
      // Two points make a run; one is a place.
      useDesktop(tester);
      final renderer = FakeMapRenderer();
      await tester.pumpWidget(wrap(FakeTransportRepository(), renderer));
      await startDrawing(tester);
      await dropStops(tester, renderer, 1);

      expect(renderer.polylines, isEmpty);
    });

    testWidgets('a stop can be taken off again', (tester) async {
      useDesktop(tester);
      final renderer = FakeMapRenderer();
      await tester.pumpWidget(wrap(FakeTransportRepository(), renderer));
      await startDrawing(tester);
      await dropStops(tester, renderer, 2);

      await tester.tap(find.byTooltip('Remove').first);
      await tester.pumpAndSettle();

      expect(find.text('Stop 1'), findsNothing);
      expect(find.text('Stop 2'), findsOneWidget);
    });

    testWidgets('and moved up the order', (tester) async {
      useDesktop(tester);
      final renderer = FakeMapRenderer();
      await tester.pumpWidget(wrap(FakeTransportRepository(), renderer));
      await startDrawing(tester);
      await dropStops(tester, renderer, 2);

      expect(renderer.markersById['draft-0']?.infoWindow.title, '1. Stop 1');

      await tester.tap(find.byTooltip('Move up').last);
      await tester.pumpAndSettle();

      // The name stays with its stop; what changes is where in the run it
      // sits, which is what the map's own labels say.
      expect(renderer.markersById['draft-0']?.infoWindow.title, '1. Stop 2');
      expect(renderer.markersById['draft-1']?.infoWindow.title, '2. Stop 1');
    });

    testWidgets('cancelling throws the sketch away', (tester) async {
      useDesktop(tester);
      final renderer = FakeMapRenderer();
      final fake = FakeTransportRepository();
      await tester.pumpWidget(wrap(fake, renderer));
      await startDrawing(tester);
      await dropStops(tester, renderer, 2);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Stop 1'), findsNothing);
      expect(find.byKey(const Key('new-route')), findsOneWidget);
      expect(fake.lastCall, isNull);
    });
  });

  group('saving', () {
    testWidgets('the route and every stop go in one call', (tester) async {
      useDesktop(tester);
      final renderer = FakeMapRenderer();
      final fake = FakeTransportRepository();
      await tester.pumpWidget(wrap(fake, renderer));
      await startDrawing(tester);
      await dropStops(tester, renderer, 2);

      await tester.enterText(find.widgetWithText(TextField, 'Route name'), 'North Loop');
      await tester.tap(find.widgetWithText(FilledButton, 'Save route'));
      await tester.pumpAndSettle();

      final sent = fake.lastCall!;
      expect(sent['op'], 'createRoute');
      expect(sent['name'], 'North Loop');
      expect(sent['school_id'], 7);

      final stops = sent['stops'] as List;
      expect(stops.length, 2);
      expect(stops[0]['sequence_number'], 1);
      expect(stops[1]['sequence_number'], 2);
    });

    testWidgets('the order on screen is the order that is sent', (tester) async {
      useDesktop(tester);
      final renderer = FakeMapRenderer();
      final fake = FakeTransportRepository();
      await tester.pumpWidget(wrap(fake, renderer));
      await startDrawing(tester);
      await dropStops(tester, renderer, 2);

      await tester.tap(find.byTooltip('Move up').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Route name'), 'North Loop');
      await tester.tap(find.widgetWithText(FilledButton, 'Save route'));
      await tester.pumpAndSettle();

      final stops = fake.lastCall!['stops'] as List;
      expect(stops.map((stop) => stop['name']).toList(), ['Stop 2', 'Stop 1']);
      expect(stops.map((stop) => stop['sequence_number']).toList(), [1, 2]);
    });

    testWidgets('a route with no name is refused before the server sees it', (tester) async {
      useDesktop(tester);
      final renderer = FakeMapRenderer();
      final fake = FakeTransportRepository();
      await tester.pumpWidget(wrap(fake, renderer));
      await startDrawing(tester);
      await dropStops(tester, renderer, 1);

      await tester.tap(find.widgetWithText(FilledButton, 'Save route'));
      await tester.pumpAndSettle();

      expect(find.text('Give the route a name.'), findsOneWidget);
      expect(fake.lastCall, isNull);
    });

    testWidgets('a route with no stops is refused too', (tester) async {
      useDesktop(tester);
      final fake = FakeTransportRepository();
      await tester.pumpWidget(wrap(fake, FakeMapRenderer()));
      await startDrawing(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Route name'), 'North Loop');
      await tester.tap(find.widgetWithText(FilledButton, 'Save route'));
      await tester.pumpAndSettle();

      expect(find.textContaining('at least one stop'), findsOneWidget);
      expect(fake.lastCall, isNull);
    });

    testWidgets("the server's complaint about a stop is shown with the stops", (tester) async {
      // Each message names the stop it is about, so it belongs beside the
      // list rather than at the top of the screen.
      useDesktop(tester);
      final renderer = FakeMapRenderer();
      final fake = FakeTransportRepository()
        ..failWith = const Failure(
          code: 'VALIDATION_ERROR',
          message: 'The given data was invalid.',
          details: {
            'errors': {
              'stops': ['Two stops are called Stop 1.'],
            },
          },
        );
      await tester.pumpWidget(wrap(fake, renderer));
      await startDrawing(tester);
      await dropStops(tester, renderer, 2);

      await tester.enterText(find.widgetWithText(TextField, 'Route name'), 'North Loop');
      await tester.tap(find.widgetWithText(FilledButton, 'Save route'));
      await tester.pumpAndSettle();

      expect(find.text('Two stops are called Stop 1.'), findsOneWidget);
      // The sketch survives, so somebody can fix the stop rather than draw
      // the whole route again.
      expect(find.text('Stop 1'), findsOneWidget);
    });

    testWidgets('a failure that is not about the stops is still shown', (tester) async {
      useDesktop(tester);
      final renderer = FakeMapRenderer();
      final fake = FakeTransportRepository()..failWith = Failure.network();
      await tester.pumpWidget(wrap(fake, renderer));
      await startDrawing(tester);
      await dropStops(tester, renderer, 1);

      await tester.enterText(find.widgetWithText(TextField, 'Route name'), 'North Loop');
      await tester.tap(find.widgetWithText(FilledButton, 'Save route'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not reach the server'), findsOneWidget);
    });
  });
}
