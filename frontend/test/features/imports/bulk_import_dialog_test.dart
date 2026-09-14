import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/imports/data/import_repository.dart';
import 'package:edutrack_app/features/imports/data/models/import_result.dart';
import 'package:edutrack_app/features/imports/presentation/bulk_import_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';

/// The upload dialog: what it says before a file has been chosen, what it
/// does with a file the server refuses, and what it shows for one it accepts.
class _FakeImportRepository implements ImportRepository {
  String? importedType;
  int? importedSchoolId;
  String? downloadedType;

  @override
  Future<List<int>> downloadTemplate(String type) async {
    downloadedType = type;
    return const [1, 2, 3];
  }

  @override
  Future<ImportResult> import({
    required String type,
    required String fileName,
    required List<int> bytes,
    int? schoolId,
  }) async {
    importedType = type;
    importedSchoolId = schoolId;

    return const ImportResult(imported: 0, label: 'Students');
  }
}

void main() {
  Widget wrap(_FakeImportRepository imports, {required UserRole role, int? schoolId, VoidCallback? onImported}) {
    return ProviderScope(
      overrides: [
        importRepositoryProvider.overrideWithValue(imports),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(
            sessionOnRestore: AuthenticatedUser(id: 1, name: 'Admin', email: 'admin@example.com', role: role),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: BulkImportDialog(type: 'students', title: 'Students', schoolId: schoolId, onImported: onImported),
        ),
      ),
    );
  }

  testWidgets('says what the job is before anything has been chosen', (tester) async {
    await tester.pumpWidget(wrap(_FakeImportRepository(), role: UserRole.schoolAdmin));
    await tester.pumpAndSettle();

    expect(find.text('Bulk Upload Students'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Download template'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Choose file'), findsOneWidget);
    // Nothing to upload yet.
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Upload')).onPressed, isNull);
  });

  testWidgets('a super admin is told to pick a school before anything else', (tester) async {
    await tester.pumpWidget(wrap(_FakeImportRepository(), role: UserRole.superAdmin));
    await tester.pumpAndSettle();

    expect(
      find.text('Choose a school in the filter first - that is the school these records will be added to.'),
      findsOneWidget,
    );
  });

  testWidgets('a super admin who has picked one is not nagged', (tester) async {
    await tester.pumpWidget(wrap(_FakeImportRepository(), role: UserRole.superAdmin, schoolId: 4));
    await tester.pumpAndSettle();

    expect(
      find.text('Choose a school in the filter first - that is the school these records will be added to.'),
      findsNothing,
    );
  });

  testWidgets('a school admin is never asked which school', (tester) async {
    await tester.pumpWidget(wrap(_FakeImportRepository(), role: UserRole.schoolAdmin));
    await tester.pumpAndSettle();

    expect(
      find.text('Choose a school in the filter first - that is the school these records will be added to.'),
      findsNothing,
    );
  });

  testWidgets('fetches the template for its own kind of record', (tester) async {
    final imports = _FakeImportRepository();

    await tester.pumpWidget(wrap(imports, role: UserRole.schoolAdmin));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Download template'));
    await tester.pumpAndSettle();

    expect(imports.downloadedType, 'students');
  });

  testWidgets('shows what the server said when the template cannot be fetched', (tester) async {
    final imports = _FailingTemplateRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          importRepositoryProvider.overrideWithValue(imports),
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(
              sessionOnRestore: const AuthenticatedUser(
                id: 1,
                name: 'Admin',
                email: 'admin@example.com',
                role: UserRole.schoolAdmin,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: BulkImportDialog(type: 'students', title: 'Students'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Download template'));
    await tester.pumpAndSettle();

    expect(find.text('Could not reach the server. Check your connection and try again.'), findsOneWidget);
  });
}

class _FailingTemplateRepository implements ImportRepository {
  @override
  Future<List<int>> downloadTemplate(String type) async => throw Failure.network();

  @override
  Future<ImportResult> import({
    required String type,
    required String fileName,
    required List<int> bytes,
    int? schoolId,
  }) async => const ImportResult(imported: 0, label: 'Students');
}
