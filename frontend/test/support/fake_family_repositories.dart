import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/family/data/family_auth_repository.dart';
import 'package:edutrack_app/features/family/data/family_device_storage.dart';
import 'package:edutrack_app/features/family/data/family_repository.dart';
import 'package:edutrack_app/features/family/data/models/family_account.dart';
import 'package:edutrack_app/features/family/data/models/family_day.dart';
import 'package:edutrack_app/features/family/data/models/family_records.dart';

const aarav = FamilyChild(id: 11, firstName: 'Aarav', lastName: 'Sharma', className: 'Class 6 A', rollNumber: '4');
const diya = FamilyChild(id: 12, firstName: 'Diya', lastName: 'Sharma', className: 'Class 3 B', rollNumber: '9');

FamilyAccount familyAccount({List<FamilyChild> children = const [aarav], String? phone = '+91 80 4000 1234'}) {
  return FamilyAccount(
    id: 5,
    name: 'Meera Sharma',
    mobile: '+919876543210',
    schoolName: 'Greenfield School',
    currencyCode: 'INR',
    children: children,
    schoolPhone: phone,
    schoolEmail: 'office@greenfield.example',
    schoolAddress: 'MG Road, Pune',
  );
}

FamilyToday familyToday({
  bool isOpen = true,
  String? holiday,
  AttendanceMark mark = AttendanceMark.present,
  String? remarks,
  TodayBus? bus,
  NextFee? fee,
  List<TodayPeriod> periods = const [],
}) {
  return FamilyToday(
    date: DateTime(2026, 11, 9),
    isOpen: isOpen,
    holidayName: holiday,
    attendance: isOpen ? TodayAttendance(mark: mark, remarks: remarks) : null,
    bus: bus,
    fee: fee,
    periods: periods,
    breaks: const [],
  );
}

AttendanceMonth attendanceMonth({List<AttendanceDay>? days, double? rate = 92.5}) {
  return AttendanceMonth(
    month: DateTime(2026, 11),
    today: DateTime(2026, 11, 9),
    days:
        days ??
        [
          for (var day = 1; day <= 30; day++)
            AttendanceDay(
              date: DateTime(2026, 11, day),
              kind: day > 9
                  ? DayKind.future
                  : day == 4
                  ? DayKind.absent
                  : day == 7 || day == 8
                  ? DayKind.closed
                  : DayKind.present,
              holiday: null,
              remarks: day == 4 ? 'Fever' : null,
            ),
        ],
    monthSummary: AttendanceSummary(workingDays: 7, present: 6, absent: 1, leave: 0, rate: rate),
    yearSummary: const AttendanceSummary(
      workingDays: 124,
      markedDays: 120,
      notMarked: 4,
      present: 108,
      absent: 10,
      leave: 2,
      rate: 90.0,
      label: '2026-27',
    ),
  );
}

FamilyNotice familyNotice({
  int id = 1,
  bool read = false,
  String? title = 'Sports day',
  String category = 'announcement',
}) {
  return FamilyNotice(
    id: id,
    category: category,
    title: title,
    body: 'Sports day is on Friday on the big field. Please send your child in sports clothes.',
    studentName: 'Aarav Sharma',
    createdAt: DateTime(2026, 11, 9, 8, 30),
    read: read,
  );
}

/// The parent's screens' data, in memory.
class FakeFamilyRepository implements FamilyRepository {
  FakeFamilyRepository({
    FamilyToday? today,
    AttendanceMonth? month,
    SchoolCalendar? calendar,
    List<FamilyNotice>? notices,
    this.failTodayWith,
    this.failSaveWith,
  }) : todayFor = {aarav.id: today ?? familyToday()},
       month = month ?? attendanceMonth(),
       calendarValue =
           calendar ??
           SchoolCalendar(
             month: DateTime(2026, 11),
             today: DateTime(2026, 11, 9),
             closedWeekdays: const ['saturday', 'sunday'],
             holidays: [
               SchoolHoliday(
                 name: 'Guru Nanak Jayanti',
                 type: 'religious',
                 start: DateTime(2026, 11, 24),
                 end: DateTime(2026, 11, 24),
               ),
             ],
             upcoming: [
               SchoolHoliday(
                 name: 'Guru Nanak Jayanti',
                 type: 'religious',
                 start: DateTime(2026, 11, 24),
                 end: DateTime(2026, 11, 24),
               ),
             ],
           ),
       noticeList = notices ?? [familyNotice()];

  final Map<int, FamilyToday> todayFor;
  AttendanceMonth month;
  SchoolCalendar calendarValue;
  List<FamilyNotice> noticeList;
  Failure? failTodayWith;
  Failure? failSaveWith;
  FamilyNotificationSettings settingsValue = const FamilyNotificationSettings(
    attendance: true,
    transport: true,
    fee: true,
    result: true,
    notices: true,
  );

  final List<int> todayAskedFor = [];
  final List<String> monthsAskedFor = [];
  final List<int> markedRead = [];
  int markAllReadCalls = 0;
  final List<(String, bool)> saved = [];

  @override
  Future<FamilyToday> today(int childId) async {
    todayAskedFor.add(childId);
    if (failTodayWith != null) throw failTodayWith!;
    return todayFor[childId] ?? familyToday();
  }

  @override
  Future<AttendanceMonth> attendance(int childId, String month) async {
    monthsAskedFor.add(month);
    return this.month;
  }

  @override
  Future<SchoolCalendar> calendar(String month) async => calendarValue;

  @override
  Future<NoticesPage> notices({int page = 1}) async =>
      NoticesPage(notices: noticeList, unreadCount: noticeList.where((n) => !n.read).length, hasMore: false);

  @override
  Future<void> markRead(int noticeId) async => markedRead.add(noticeId);

  @override
  Future<void> markAllRead() async => markAllReadCalls++;

  @override
  Future<FamilyNotificationSettings> settings() async => settingsValue;

  @override
  Future<FamilyNotificationSettings> saveSetting(String key, bool value) async {
    if (failSaveWith != null) throw failSaveWith!;
    saved.add((key, value));
    settingsValue = settingsValue.withValue(key, value);
    return settingsValue;
  }
}

/// The family sign-in, in memory.
class FakeFamilyAuthRepository implements FamilyAuthRepository {
  FakeFamilyAuthRepository({this.account, this.device, this.failWith});

  /// Who `restore` finds signed in; null for nobody.
  FamilyAccount? account;
  FamilyDevice? device;
  Failure? failWith;

  final List<Map<String, String>> setups = [];
  final List<Map<String, String>> logins = [];
  int logouts = 0;

  @override
  Future<FamilyDevice?> registeredDevice() async => device;

  @override
  Future<String?> lastMobile() async => device?.mobile;

  @override
  Future<FamilyAccount> setup({required String mobile, required String setupCode, required String passcode}) async {
    setups.add({'mobile': mobile, 'setup_code': setupCode, 'passcode': passcode});
    if (failWith != null) throw failWith!;
    return account = familyAccount();
  }

  @override
  Future<FamilyAccount> login({required String mobile, required String passcode}) async {
    logins.add({'mobile': mobile, 'passcode': passcode});
    if (failWith != null) throw failWith!;
    return account = familyAccount();
  }

  @override
  Future<FamilyAccount?> restore() async => account;

  @override
  Future<void> logout() async {
    logouts++;
    account = null;
  }

  @override
  Future<void> forgetSession() async => account = null;
}
