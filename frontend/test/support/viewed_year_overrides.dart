import 'package:edutrack_app/features/academic_years/application/viewed_year.dart';
import 'package:edutrack_app/features/academic_years/data/models/academic_year.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// The top bar's year for a test: none unless one is given, so a screen
/// lists as it did before the switch existed. Neither override reads who is
/// signed in or what this device remembers.
List<Override> viewedYearIs(AcademicYear? year) => [
  viewedYearProvider.overrideWith((ref) async => year),
  viewedYearIdProvider.overrideWith(() => _FixedYear(year?.id)),
];

class _FixedYear extends ViewedYearNotifier {
  _FixedYear(this._id);

  final int? _id;

  @override
  int? build() => _id;

  @override
  Future<void> choose(int? yearId) async => state = yearId;
}
