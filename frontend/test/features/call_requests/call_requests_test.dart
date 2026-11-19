import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/call_requests/call_requests.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parents' call requests as the school sees them (docs/parent-student-app.md, F5).
class FakeCallRequestsRepository implements CallRequestsRepository {
  FakeCallRequestsRepository({this.failListWith, this.failMarkWith});

  Failure? failListWith;
  Failure? failMarkWith;
  final List<bool> listed = [];
  final List<(int, String?)> marked = [];

  static CallRequest request({int id = 1, bool called = false}) => CallRequest(
    id: id,
    studentName: 'Aarav Sharma',
    parentName: 'Meera Sharma',
    parentMobile: '+91 98765 43210',
    toOffice: false,
    reason: 'About the maths homework this week.',
    preferredTime: 'After 5 pm',
    called: called,
    teacherName: 'Neha Iyer',
    calledBy: called ? 'Neha Iyer' : null,
    outcomeNote: called ? 'Spoke to the mother.' : null,
  );

  @override
  Future<PaginatedResponse<CallRequest>> list({required bool open, int page = 1}) async {
    listed.add(open);
    if (failListWith != null) throw failListWith!;
    final items = [request(called: !open)];
    return PaginatedResponse(items: items, currentPage: 1, lastPage: 1, total: 1, perPage: 20);
  }

  @override
  Future<CallRequest> markCalled(int id, {String? note}) async {
    if (failMarkWith != null) throw failMarkWith!;
    marked.add((id, note));
    return request(id: id, called: true);
  }
}

Future<(FakeCallRequestsRepository, List<Uri>)> pump(WidgetTester tester, {FakeCallRequestsRepository? fake}) async {
  final repository = fake ?? FakeCallRequestsRepository();
  final dialled = <Uri>[];
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        callRequestsRepositoryProvider.overrideWithValue(repository),
        diallerProvider.overrideWithValue((uri) async {
          dialled.add(uri);
          return true;
        }),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: CallRequestsScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (repository, dialled);
}

void main() {
  testWidgets('opens on the parents waiting for a call, with what and when', (tester) async {
    final (fake, _) = await pump(tester);

    expect(fake.listed, [true]);
    expect(find.text('Meera Sharma'), findsOneWidget);
    expect(find.text('Good time: After 5 pm'), findsOneWidget);
    expect(find.text('To Neha Iyer'), findsOneWidget);
  });

  testWidgets('the number dials the parent', (tester) async {
    final (_, dialled) = await pump(tester);

    await tester.tap(find.byKey(const Key('call-request-dial-1')));
    await tester.pumpAndSettle();

    expect(dialled.single.toString(), 'tel:+919876543210');
  });

  testWidgets('marking it called sends the note and says the parent can see it', (tester) async {
    final (fake, _) = await pump(tester);

    await tester.tap(find.byKey(const Key('call-request-called-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('call-request-note')), 'Spoke to the mother.');
    await tester.tap(find.byKey(const Key('call-request-save')));
    await tester.pumpAndSettle();

    expect(fake.marked, [(1, 'Spoke to the mother.')]);
    expect(find.textContaining('Marked as called'), findsOneWidget);
  });

  testWidgets('a refusal stays in the dialog with the reason', (tester) async {
    final fake = FakeCallRequestsRepository(
      failMarkWith: const Failure(code: 'FORBIDDEN', message: 'This request was for another teacher.'),
    );
    await pump(tester, fake: fake);

    await tester.tap(find.byKey(const Key('call-request-called-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('call-request-save')));
    await tester.pumpAndSettle();

    expect(find.text('This request was for another teacher.'), findsOneWidget);
  });

  testWidgets('"Called" lists those done, with the school\'s note', (tester) async {
    final (fake, _) = await pump(tester);

    await tester.tap(find.text('Called'));
    await tester.pumpAndSettle();

    expect(fake.listed.last, false);
    expect(find.textContaining('Spoke to the mother.'), findsOneWidget);
    expect(find.byKey(const Key('call-request-called-1')), findsNothing);
  });

  testWidgets('a failed load says so and retries', (tester) async {
    final fake = FakeCallRequestsRepository(failListWith: Failure.network());
    await pump(tester, fake: fake);
    expect(find.text(Failure.network().message), findsOneWidget);

    fake.failListWith = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Meera Sharma'), findsOneWidget);
  });

  testWidgets('the Staff app shows them on a phone: the filter on its own row, nothing cut off', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [callRequestsRepositoryProvider.overrideWithValue(FakeCallRequestsRepository())],
        child: MaterialApp(
          theme: AppTheme.teacherLight(),
          home: const Scaffold(body: CallRequestsScreen(compact: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Call Requests'), findsNothing, reason: 'the app bar has the title');
    expect(find.byKey(const Key('call-requests-filter')), findsOneWidget);
    expect(find.text('Meera Sharma'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
