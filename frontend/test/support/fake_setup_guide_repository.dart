import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/setup_guide/data/models/setup_guide.dart';
import 'package:edutrack_app/features/setup_guide/data/setup_guide_repository.dart';

/// A school's setup guide, held in memory. [doneSteps] is how many of the six
/// are done, from the first.
class FakeSetupGuideRepository implements SetupGuideRepository {
  FakeSetupGuideRepository({this.doneSteps = 0, this.closed = false, this.failWith = const {}});

  int doneSteps;
  bool closed;

  /// Keyed by method name: {'show': ..., 'close': ..., 'addDepartments': ...}.
  final Map<String, Failure> failWith;

  final List<String> calls = [];
  List<String>? addedDepartments;

  static const _steps = [
    ('academic_year', 'Academic year', '/academic-years'),
    ('departments', 'Departments', '/departments'),
    ('classes', 'Classes & sections', '/classes'),
    ('subjects', 'Subjects', '/subjects'),
    ('staff', 'Teachers & staff', '/staff'),
    ('students', 'Students', '/students'),
  ];

  SetupGuide get guide => SetupGuide(
    schoolName: 'Sunrise Public School',
    closed: closed,
    done: doneSteps,
    total: 6,
    steps: [
      for (final (index, (key, title, path)) in _steps.indexed)
        SetupStep(
          key: key,
          title: title,
          detail: 'What $title means.',
          path: path,
          done: index < doneSteps,
          summary: index < doneSteps ? '$title summary' : null,
          blockedBy: key == 'classes' && doneSteps == 0 ? 'Add the academic year first.' : null,
        ),
    ],
    extras: const [SetupExtra(title: 'Holidays', path: '/holidays', detail: 'Days the school is closed.')],
  );

  Future<T> _call<T>(String name, T Function() answer) async {
    calls.add(name);
    if (failWith[name] != null) throw failWith[name]!;
    return answer();
  }

  @override
  Future<SetupGuide> show() => _call('show', () => guide);

  @override
  Future<SetupGuide> close() => _call('close', () {
    closed = true;
    return guide;
  });

  @override
  Future<SetupGuide> reopen() => _call('reopen', () {
    closed = false;
    return guide;
  });

  @override
  Future<List<DepartmentPreset>> departmentPresets() => _call(
    'departmentPresets',
    () => const [
      DepartmentPreset(name: 'Primary', selected: true),
      DepartmentPreset(name: 'Science', selected: true),
      DepartmentPreset(name: 'Arts', selected: false),
    ],
  );

  @override
  Future<QuickDepartmentsResult> addDepartments(List<String> names) => _call('addDepartments', () {
    addedDepartments = names;
    if (doneSteps == 1) doneSteps = 2;
    return QuickDepartmentsResult(created: names, skipped: const []);
  });
}
