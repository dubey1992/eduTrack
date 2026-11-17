import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/family/data/family_auth_repository.dart';
import 'package:edutrack_app/features/family/data/family_device_storage.dart';
import 'package:edutrack_app/features/family/data/family_repository.dart';
import 'package:edutrack_app/features/family/data/models/family_admit_card.dart';
import 'package:edutrack_app/features/family/data/models/family_account.dart';
import 'package:edutrack_app/features/family/data/models/family_absence_note.dart';
import 'package:edutrack_app/features/family/data/models/family_bus.dart';
import 'package:edutrack_app/features/family/data/models/family_call_request.dart';
import 'package:edutrack_app/features/family/data/models/family_day.dart';
import 'package:edutrack_app/features/family/data/models/family_fees.dart';
import 'package:edutrack_app/features/family/data/models/family_learning.dart';
import 'package:edutrack_app/features/family/data/models/family_records.dart';

const aarav = FamilyChild(id: 11, firstName: 'Aarav', lastName: 'Sharma', className: 'Class 6 A', rollNumber: '4');
const diya = FamilyChild(id: 12, firstName: 'Diya', lastName: 'Sharma', className: 'Class 3 B', rollNumber: '9');

FamilyAccount familyAccount({
  List<FamilyChild> children = const [aarav],
  String? phone = '+91 80 4000 1234',
  FamilyFeatures features = FamilyFeatures.all,
}) {
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
    features: features,
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
  NoticeReply? reply,
}) {
  return FamilyNotice(
    id: id,
    category: category,
    title: title,
    body: 'Sports day is on Friday on the big field. Please send your child in sports clothes.',
    studentName: 'Aarav Sharma',
    createdAt: DateTime(2026, 11, 9, 8, 30),
    read: read,
    reply: reply,
  );
}

/// A notice asking about the museum trip, not yet answered for Aarav.
NoticeReply tripQuestion({bool? answer, bool open = true}) => NoticeReply(
  question: 'Can your child come on the trip to the science museum?',
  replyBy: DateTime(2026, 11, 12),
  open: open,
  children: [(studentId: aarav.id, name: 'Aarav', answer: answer, note: null)],
);

final term1 = SchoolTerm(id: 1, name: 'Term 1', start: DateTime(2026, 4, 1), end: DateTime(2026, 9, 30));
final term2 = SchoolTerm(id: 2, name: 'Term 2', start: DateTime(2026, 10, 1), end: DateTime(2027, 1, 31));

FamilyResults familyResults({bool showsAverage = false, bool reportAvailable = false, SchoolTerm? term}) {
  return FamilyResults(
    terms: [term2, term1],
    term: term ?? term2,
    showsClassAverage: showsAverage,
    subjects: [
      SubjectResults(
        subject: 'Mathematics',
        average: '90.00',
        grade: 'A',
        classAverage: showsAverage ? '71.50' : null,
        tests: [
          TestResult(
            id: 31,
            title: 'Fractions',
            type: 'class_test',
            date: DateTime(2026, 10, 20),
            maxMarks: '20.00',
            marksObtained: '18.00',
            isAbsent: false,
            percentage: '90.00',
            grade: 'A',
            remarks: null,
            classAverage: showsAverage ? '70.00' : null,
          ),
          TestResult(
            id: 32,
            title: 'Decimals',
            type: 'class_test',
            date: DateTime(2026, 11, 3),
            maxMarks: '20.00',
            marksObtained: null,
            isAbsent: true,
            percentage: null,
            grade: null,
            remarks: null,
            classAverage: null,
          ),
        ],
      ),
    ],
    remark: 'Aarav works hard and helps others.',
    reportAvailable: reportAvailable,
    reportFrom: DateTime(2027, 2, 1),
  );
}

const familyWeek = FamilyWeek(
  today: 'monday',
  days: [
    SchoolDay(
      day: 'monday',
      isHalfDay: false,
      periods: [
        WeekPeriod(startTime: '08:00', endTime: '08:40', subject: 'Mathematics', teacher: 'Ms Joshi'),
        WeekPeriod(startTime: '09:00', endTime: '09:40', subject: 'Science', teacher: 'Mr Rao'),
      ],
      breaks: [(name: 'Short break', startTime: '08:40', endTime: '09:00')],
    ),
    SchoolDay(
      day: 'saturday',
      isHalfDay: true,
      periods: [WeekPeriod(startTime: '08:00', endTime: '08:40', subject: 'Art', teacher: null)],
      breaks: [],
    ),
  ],
);

const familySyllabus = [
  SubjectSyllabus(subject: 'Science', total: 22, covered: 14, percent: 64, nextTopics: ['Light', 'Sound']),
];

/// A child's fees: one paid, one overdue and part paid, one due later, a
/// receipt and a cancelled one, and the school's own words on paying.
FamilyFees familyFees({HowToPay? howToPay, bool empty = false, double credit = 0}) => FamilyFees(
  yearName: empty ? null : '2026-27',
  currencyCode: 'INR',
  totals: empty ? null : const FeeTotals(charged: 15000, discount: 500, paid: 6000, balance: 8500, overdue: 3500),
  instalments: empty
      ? const []
      : [
          Instalment(
            id: 1,
            label: 'Term 1',
            dueDate: DateTime(2026, 6, 10),
            amount: 5000,
            discount: 0,
            paid: 5000,
            balance: 0,
            status: InstalmentStatus.paid,
          ),
          Instalment(
            id: 2,
            label: 'Term 2',
            dueDate: DateTime(2026, 10, 10),
            amount: 5000,
            discount: 500,
            paid: 1000,
            balance: 3500,
            status: InstalmentStatus.overdue,
          ),
          Instalment(
            id: 3,
            label: 'Term 3',
            dueDate: DateTime(2027, 1, 10),
            amount: 5000,
            discount: 0,
            paid: 0,
            balance: 5000,
            status: InstalmentStatus.due,
          ),
        ],
  receipts: empty
      ? const []
      : [
          FamilyReceipt(
            id: 11,
            number: 'RC-2026-0042',
            date: DateTime(2026, 6, 8),
            amount: 5000,
            currencyCode: 'INR',
            paymentMode: 'upi',
            cancelled: false,
          ),
          FamilyReceipt(
            id: 12,
            number: 'RC-2026-0077',
            date: DateTime(2026, 9, 2),
            amount: 300,
            currencyCode: 'INR',
            paymentMode: 'cash',
            cancelled: true,
          ),
        ],
  credit: credit,
  howToPay:
      howToPay ??
      const HowToPay(
        counterHours: 'Mon-Sat, 9 am to 1 pm',
        bankDetails: 'Greenfield School, A/c 1234567890, IFSC HDFC0001234',
        upiId: 'greenfield@okaxis',
        officePhone: '+91 80 4000 1234',
      ),
);

/// A child on the Baner Road bus: the pickup running (boarded, so it can be
/// followed), the drop not started; the office's number, and the
/// attendant's only when [withAttendant].
FamilyBus familyBus({
  bool live = true,
  String riderStatus = 'boarded',
  String tripStatus = 'in_progress',
  bool withAttendant = false,
  bool onList = true,
}) => FamilyBus(
  routeName: 'Baner Road',
  vehicleName: 'Bus 3',
  vehicleNumber: 'MH-12-AB-1234',
  stop: const BusStopInfo(
    name: 'Sakal Nagar',
    pickupTime: '07:35',
    dropTime: '14:10',
    location: GeoPoint(18.569, 73.786),
  ),
  officePhone: '+91 20 4000 1234',
  attendant: withAttendant ? (name: 'Ravi Kumar', mobile: '+91 90000 55555') : null,
  trips: [
    FamilyBusTrip(
      id: 1,
      direction: 'pickup',
      status: tripStatus,
      startedAt: '07:12',
      reachedStopAt: '07:37',
      riderStatus: onList ? riderStatus : null,
      boardedAt: riderStatus == 'boarded' ? '07:38' : null,
      isLive: live,
    ),
  ],
);

/// The bus 350 m from the child's stop, one stop before it, about 4 minutes away.
FamilyBusLive familyBusLive({bool stale = false, bool reached = false, int? eta = 240}) => FamilyBusLive(
  direction: 'pickup',
  position: BusPosition(point: const GeoPoint(18.566, 73.786), heading: 0, ageSeconds: stale ? 300 : 8, isStale: stale),
  routePath: null,
  yourStop: YourStop(
    name: 'Sakal Nagar',
    location: const GeoPoint(18.569, 73.786),
    reached: reached,
    stopsBefore: reached ? null : 1,
    distanceM: reached ? null : 350,
    etaSeconds: reached ? null : eta,
  ),
  nextStop: 'Baner Gaon',
);

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

  FamilyResults Function(int? termId) resultsFor = (termId) =>
      familyResults(term: termId == 1 ? term1 : term2, reportAvailable: termId == 1);
  Failure? failReportWith;
  final List<int?> resultsAskedFor = [];

  /// What the phone has saved, for a Home opened with no signal.
  ({FamilyToday today, DateTime at})? savedTodayValue;
  final List<int?> reportsAskedFor = [];

  final List<int> todayAskedFor = [];
  final List<String> monthsAskedFor = [];
  final List<int> markedRead = [];
  int markAllReadCalls = 0;
  final List<(String, bool)> saved = [];

  List<FamilyCallRequest> callRequestsValue = [
    FamilyCallRequest(
      id: 31,
      toOffice: false,
      reason: 'About the maths homework.',
      called: true,
      sentAt: DateTime(2026, 11, 2),
    ),
  ];
  Failure? failCallWith;
  final List<({bool toOffice, String reason, String? time})> callsAsked = [];
  final List<({int noticeId, int studentId, bool answer, String? note})> replies = [];
  Failure? failReplyWith;

  @override
  Future<List<FamilyCallRequest>> callRequests(int childId) async => callRequestsValue;

  @override
  Future<FamilyCallRequest> askForCall(
    int childId, {
    required bool toOffice,
    required String reason,
    String? preferredTime,
  }) async {
    if (failCallWith != null) throw failCallWith!;
    callsAsked.add((toOffice: toOffice, reason: reason, time: preferredTime));
    return FamilyCallRequest(id: 40, toOffice: toOffice, reason: reason, called: false, sentAt: DateTime(2026, 11, 9));
  }

  @override
  Future<NoticeReply> replyToNotice(int noticeId, {required int studentId, required bool answer, String? note}) async {
    if (failReplyWith != null) throw failReplyWith!;
    replies.add((noticeId: noticeId, studentId: studentId, answer: answer, note: note));
    return tripQuestion(answer: answer);
  }

  List<FamilyAbsenceNote> notesValue = [
    FamilyAbsenceNote(
      id: 7,
      startDate: DateTime(2026, 11, 3),
      endDate: DateTime(2026, 11, 4),
      reason: 'Fever - the doctor advised two days of rest.',
      hasPhoto: true,
      seen: true,
    ),
    FamilyAbsenceNote(
      id: 8,
      startDate: DateTime(2026, 11, 20),
      endDate: DateTime(2026, 11, 20),
      reason: 'A family wedding out of town.',
      hasPhoto: false,
      seen: false,
    ),
  ];
  Failure? failNotesWith;
  Failure? failSendWith;
  final List<({DateTime start, DateTime end, String reason, String? photoName})> notesSent = [];

  @override
  Future<List<FamilyAbsenceNote>> absenceNotes(int childId) async {
    if (failNotesWith != null) throw failNotesWith!;
    return notesValue;
  }

  @override
  Future<FamilyAbsenceNote> sendAbsenceNote(
    int childId, {
    required DateTime start,
    required DateTime end,
    required String reason,
    List<int>? photo,
    String? photoName,
  }) async {
    if (failSendWith != null) throw failSendWith!;
    notesSent.add((start: start, end: end, reason: reason, photoName: photoName));
    return FamilyAbsenceNote(
      id: 99,
      startDate: start,
      endDate: end,
      reason: reason,
      hasPhoto: photo != null,
      seen: false,
    );
  }

  FamilyBus? busValue = familyBus();
  Failure? failBusWith;

  /// What each ask for the live bus answers, in turn; the last repeats.
  List<FamilyBusLive?> liveAnswers = [familyBusLive()];
  int liveAsks = 0;

  @override
  Future<FamilyBus?> bus(int childId) async {
    if (failBusWith != null) throw failBusWith!;
    return busValue;
  }

  @override
  Future<FamilyBusLive?> busLive(int childId) async {
    final answer = liveAnswers[liveAsks < liveAnswers.length ? liveAsks : liveAnswers.length - 1];
    liveAsks++;
    return answer;
  }

  FamilyFees feesValue = familyFees();
  Failure? failFeesWith;
  Failure? failPdfWith;
  final List<String> pdfsAskedFor = [];

  @override
  Future<FamilyFees> fees(int childId) async {
    if (failFeesWith != null) throw failFeesWith!;
    return feesValue;
  }

  @override
  Future<List<int>> feeStatement(int childId) async {
    pdfsAskedFor.add('statement:$childId');
    if (failPdfWith != null) throw failPdfWith!;
    return const [37, 80, 68, 70];
  }

  @override
  Future<List<int>> receiptPdf(int childId, int receiptId) async {
    pdfsAskedFor.add('receipt:$childId:$receiptId');
    if (failPdfWith != null) throw failPdfWith!;
    return const [37, 80, 68, 70];
  }

  /// What admitCards() answers (docs/examinations.md).
  List<FamilyAdmitCard> admitCardList = const [];
  Failure? failAdmitCardsWith;

  @override
  Future<List<FamilyAdmitCard>> admitCards(int childId) async {
    if (failAdmitCardsWith != null) throw failAdmitCardsWith!;
    return admitCardList;
  }

  @override
  Future<List<int>> admitCardPdf(int childId, int examinationId) async {
    pdfsAskedFor.add('admit-card:$childId:$examinationId');
    if (failPdfWith != null) throw failPdfWith!;
    return const [37, 80, 68, 70];
  }

  @override
  Future<({FamilyToday today, DateTime at})?> savedToday(int childId) async => savedTodayValue;

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

  @override
  Future<FamilyResults> results(int childId, {int? termId}) async {
    resultsAskedFor.add(termId);
    return resultsFor(termId);
  }

  @override
  Future<List<int>> progressReport(int childId, {int? termId}) async {
    reportsAskedFor.add(termId);
    if (failReportWith != null) throw failReportWith!;
    return const [37, 80, 68, 70];
  }

  @override
  Future<FamilyWeek> timetable(int childId) async => familyWeek;

  @override
  Future<List<SubjectSyllabus>> syllabus(int childId) async => familySyllabus;
}

/// The family sign-in, in memory.
class FakeFamilyAuthRepository implements FamilyAuthRepository {
  FakeFamilyAuthRepository({this.account, this.device, this.failWith, this.saved});

  /// Who `restore` finds signed in; null for nobody.
  FamilyAccount? account;
  FamilyDevice? device;
  Failure? failWith;

  /// What the phone last saw - the app opens on it without asking.
  FamilyAccount? saved;
  int restores = 0;

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
  Future<FamilyAccount?> savedAccount() async => saved;

  @override
  Future<FamilyAccount?> restore() async {
    restores++;
    return account;
  }

  @override
  Future<void> logout() async {
    logouts++;
    account = null;
  }

  @override
  Future<void> forgetSession() async => account = null;
}
