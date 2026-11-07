import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/guardians/data/guardian_repository.dart';
import 'package:edutrack_app/features/guardians/data/models/guardian_link.dart';

GuardianLink guardianLink({
  int id = 1,
  String name = 'Meera Sharma',
  String? mobile = '+919876543210',
  String? email,
  GuardianRelationship relationship = GuardianRelationship.mother,
  bool isPrimary = true,
  bool hasFamilyAccount = false,
  int children = 1,
  DateTime? consentAt,
}) {
  return GuardianLink(
    id: id,
    guardianId: id + 100,
    name: name,
    mobile: mobile,
    email: email,
    relationship: relationship,
    isPrimary: isPrimary,
    consentAt: consentAt,
    hasFamilyAccount: hasFamilyAccount,
    children: children,
  );
}

FamilyAccess familyAccess({
  String? loginMobile = '+919876543210',
  DateTime? consentAt,
  bool hasPasscode = false,
  bool setupCodePending = false,
  List<FamilyPhone> devices = const [],
}) {
  return FamilyAccess(
    loginMobile: loginMobile,
    consentAt: consentAt,
    hasAccount: hasPasscode || setupCodePending,
    hasPasscode: hasPasscode,
    isLocked: false,
    setupCodePending: setupCodePending,
    setupCodeExpiresAt: setupCodePending ? DateTime(2026, 11, 14) : null,
    devices: devices,
  );
}

/// The guardians API, in memory. Records what was sent so a test can say the
/// screen sent the right thing.
class FakeGuardianRepository implements GuardianRepository {
  FakeGuardianRepository({List<GuardianLink>? links, FamilyAccess? access, this.failListWith, this.failSaveWith})
    : links = links ?? [guardianLink()],
      currentAccess = access ?? familyAccess();

  List<GuardianLink> links;
  FamilyAccess currentAccess;
  Failure? failListWith;
  Failure? failSaveWith;

  final List<Map<String, Object?>> saved = [];
  final List<int> unlinked = [];
  final List<bool> codesIssuedWithConsent = [];
  final List<int> phonesRemoved = [];

  @override
  Future<List<GuardianLink>> list(int studentId) async {
    if (failListWith != null) throw failListWith!;
    return links;
  }

  @override
  Future<GuardianLink> add(
    int studentId, {
    required String name,
    String? mobile,
    String? email,
    required GuardianRelationship relationship,
    required bool isPrimary,
  }) async {
    if (failSaveWith != null) throw failSaveWith!;
    saved.add({'name': name, 'mobile': mobile, 'email': email, 'relationship': relationship, 'primary': isPrimary});
    final link = guardianLink(id: links.length + 1, name: name, mobile: mobile, isPrimary: isPrimary);
    links = [...links, link];
    return link;
  }

  @override
  Future<GuardianLink> update(
    int studentId,
    int linkId, {
    required String name,
    String? mobile,
    String? email,
    required GuardianRelationship relationship,
    required bool isPrimary,
  }) async {
    if (failSaveWith != null) throw failSaveWith!;
    saved.add({'id': linkId, 'name': name, 'mobile': mobile, 'email': email});
    return links.firstWhere((link) => link.id == linkId);
  }

  @override
  Future<void> unlink(int studentId, int linkId) async {
    unlinked.add(linkId);
    links = links.where((link) => link.id != linkId).toList();
  }

  @override
  Future<FamilyAccess> access(int studentId, int linkId) async => currentAccess;

  @override
  Future<IssuedSetupCode> issueSetupCode(int studentId, int linkId, {required bool consent}) async {
    codesIssuedWithConsent.add(consent);
    currentAccess = familyAccess(consentAt: DateTime(2026, 11, 7), setupCodePending: true);
    return IssuedSetupCode(code: '48271593', expiresAt: DateTime(2026, 11, 14), loginMobile: '+919876543210');
  }

  @override
  Future<List<int>> letter(int studentId, int linkId, {required bool consent}) async {
    codesIssuedWithConsent.add(consent);
    return const [37, 80, 68, 70];
  }

  @override
  Future<FamilyAccess> removePhone(int studentId, int linkId, int deviceId) async {
    phonesRemoved.add(deviceId);
    currentAccess = familyAccess(hasPasscode: true, consentAt: DateTime(2026, 11, 7));
    return currentAccess;
  }
}
