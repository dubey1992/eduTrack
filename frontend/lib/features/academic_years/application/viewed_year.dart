import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/key_value_store.dart';
import '../../auth/application/auth_notifier.dart';
import '../data/models/academic_year.dart';
import '../data/academic_year_repository.dart';

/// The academic year the school's screens are showing (decided 2026-11-05):
/// one switch in the top bar, followed by Students, Classes, Class Tests,
/// Attendance, Fees, Reports and Analytics.
///
/// Null means "the current year" - what everybody sees until they choose
/// another, and what they go back to when the year they chose is deleted.
/// The choice is remembered on this device, per school.
final viewedYearIdProvider = NotifierProvider<ViewedYearNotifier, int?>(ViewedYearNotifier.new);

class ViewedYearNotifier extends Notifier<int?> {
  static String _key(int? schoolId) => 'viewed_academic_year_${schoolId ?? 'none'}';

  int? get _schoolId => ref.read(authNotifierProvider).value?.schoolId;

  @override
  int? build() {
    // Follows whoever is signed in: another school's year means nothing here.
    ref.watch(authNotifierProvider.select((user) => user.value?.schoolId));
    _restore();
    return null;
  }

  Future<void> _restore() async {
    try {
      final saved = await ref.read(keyValueStoreProvider).read(_key(_schoolId));
      final id = int.tryParse(saved ?? '');
      if (id != null && ref.mounted) state = id;
    } catch (error) {
      // Not remembered is not broken: the current year is shown.
      developer.log('Could not read the remembered year', name: 'academic_years', error: error);
    }
  }

  /// Shows [yearId] everywhere; the current year when it is null.
  Future<void> choose(int? yearId) async {
    state = yearId;
    final store = ref.read(keyValueStoreProvider);
    if (yearId == null) {
      await store.delete(_key(_schoolId));
    } else {
      await store.write(_key(_schoolId), '$yearId');
    }
  }
}

/// The school's years, newest first. Not retried on its own: the switch and
/// the screens that follow it simply show the current year meanwhile, and a
/// silent retry loop helps nobody.
final schoolYearsProvider = FutureProvider.autoDispose<List<AcademicYear>>((ref) async {
  final years = await ref.watch(academicYearRepositoryProvider).list();
  return [...years]..sort((a, b) => b.startDate.compareTo(a.startDate));
}, retry: (retryCount, error) => null);

/// The year in view: the one chosen, else the current one, else the latest.
/// Null only for a school with no years at all.
final viewedYearProvider = FutureProvider.autoDispose<AcademicYear?>((ref) async {
  final years = await ref.watch(schoolYearsProvider.future);
  final chosen = ref.watch(viewedYearIdProvider);

  return years.where((year) => year.id == chosen).firstOrNull ??
      years.where((year) => year.isCurrent).firstOrNull ??
      years.firstOrNull;
}, retry: (retryCount, error) => null);

/// Where a year sits against today's, for the switch's label.
enum YearStanding { past, current, next }

YearStanding standingOf(AcademicYear year, List<AcademicYear> years) {
  if (year.isCurrent) return YearStanding.current;
  final current = years.where((y) => y.isCurrent).firstOrNull;
  if (current == null) return YearStanding.current;

  return year.startDate.isBefore(current.startDate) ? YearStanding.past : YearStanding.next;
}

/// The whole of a year other than the current one, up to today - the
/// period Reports, Analytics and the dashboard's trends cover while it is in
/// view. Null for the current year, which keeps each screen's own default,
/// and for a year that has not begun, which has nothing to show yet.
({DateTime from, DateTime to})? yearPeriod(AcademicYear? year, DateTime today) {
  if (year == null || year.isCurrent || year.startDate.isAfter(today)) return null;

  return (from: year.startDate, to: year.endDate.isBefore(today) ? year.endDate : today);
}
