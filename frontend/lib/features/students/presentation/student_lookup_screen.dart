import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/models/user_role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/application/auth_notifier.dart';
import '../data/models/student.dart';
import '../data/student_repository.dart';
import 'widgets/student_photo_field.dart';

/// What was typed into the search box; empty is the whole list the server
/// lets this person see.
final studentLookupQueryProvider = NotifierProvider.autoDispose<StudentLookupQuery, String>(StudentLookupQuery.new);

class StudentLookupQuery extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query.trim();
}

/// The first page of matching active students. The server decides whose:
/// a teacher gets their own class, the office the school
/// (StudentPolicy, services.py) - nothing here can widen that.
final studentLookupProvider = FutureProvider.autoDispose<List<Student>>((ref) async {
  final query = ref.watch(studentLookupQueryProvider);
  final page = await ref
      .read(studentRepositoryProvider)
      .listPage(search: query.isEmpty ? null : query, status: 'active', page: 1, perPage: 30);
  return page.items;
}, retry: (retryCount, error) => null);

/// Opens the phone's dialler. Swappable in tests.
typedef StudentDialler = Future<bool> Function(Uri uri);

final studentDiallerProvider = Provider<StudentDialler>(
  (ref) =>
      (uri) => launchUrl(uri),
);

/// "Find a student" in the Staff app (docs/mobile-apps-review.md, 7.4): by
/// name or admission number, with the guardian one tap away.
class StudentLookupScreen extends ConsumerStatefulWidget {
  const StudentLookupScreen({super.key});

  @override
  ConsumerState<StudentLookupScreen> createState() => _StudentLookupScreenState();
}

class _StudentLookupScreenState extends ConsumerState<StudentLookupScreen> {
  /// Waits for a pause in typing, so each key is not a request.
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _typed(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) ref.read(studentLookupQueryProvider.notifier).set(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final students = ref.watch(studentLookupProvider);
    final query = ref.watch(studentLookupQueryProvider);
    final colors = context.appColors;
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.staffStudents)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              key: const Key('student-lookup-search'),
              autofocus: true,
              onChanged: _typed,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: l10n.staffNameOrAdmission),
            ),
          ),
          Expanded(
            child: AsyncValueView<List<Student>>(
              value: students,
              onRetry: () => ref.invalidate(studentLookupProvider),
              isEmpty: (list) => list.isEmpty,
              emptyBuilder: (context) => Center(
                key: const Key('student-lookup-empty'),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    query.isEmpty ? l10n.staffNoStudentsToShow : l10n.staffNoStudentMatches(query),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.muted),
                  ),
                ),
              ),
              data: (context, list) => ListView.separated(
                key: const Key('student-lookup-list'),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) => _StudentCard(student: list[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentCard extends ConsumerWidget {
  const _StudentCard({required this.student});

  final Student student;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final mobile = student.guardianMobile;
    final role = ref.watch(authNotifierProvider).value?.role;
    final l10n = context.l10n;

    return Card(
      key: Key('student-lookup-${student.id}'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UserAvatar(photoUrl: student.photoUrl, name: student.name, radius: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        student.name,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        [
                          ?student.classSectionName,
                          if (student.rollNumber != null) l10n.staffRoll('${student.rollNumber}'),
                          l10n.staffAdmissionShort(student.admissionNumber),
                        ].join(' · '),
                        style: TextStyle(color: colors.muted),
                      ),
                    ],
                  ),
                ),
                if (mayChangePhoto(role))
                  TextButton.icon(
                    key: Key('student-lookup-photo-${student.id}'),
                    onPressed: () => _editPhoto(context),
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: Text(l10n.staffPhoto),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text(l10n.staffGuardian(student.guardianName))),
                if (mobile != null && mobile.trim().isNotEmpty)
                  TextButton.icon(
                    key: Key('student-lookup-call-${student.id}'),
                    onPressed: () => _call(context, ref, mobile),
                    icon: const Icon(Icons.call_outlined, size: 18),
                    label: Text(l10n.staffCall),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Who is offered the photo here (docs/student-photos.md, D3): a teacher -
  /// the list only ever holds their own section, as its class teacher - and
  /// the school's administrators. The server decides either way.
  static bool mayChangePhoto(UserRole? role) =>
      role == UserRole.teacher ||
      role == UserRole.schoolAdmin ||
      role == UserRole.groupAdmin ||
      role == UserRole.superAdmin;

  Future<void> _editPhoto(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.staffStudentsPhoto(student.name), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              // The sheet's own ref: the card behind can be rebuilt while it is open.
              Consumer(
                builder: (context, sheetRef, _) =>
                    StudentPhotoField(student: student, onChanged: (_) => sheetRef.invalidate(studentLookupProvider)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _call(BuildContext context, WidgetRef ref, String mobile) async {
    final opened = await ref.read(studentDiallerProvider)(Uri(scheme: 'tel', path: mobile.replaceAll(' ', '')));
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.staffDiallerFailed)));
    }
  }
}
