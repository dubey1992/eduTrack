import 'dart:async';

import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';

/// Test double for [AuthRepository] - no real Dio/network involved, per
/// backend CLAUDE.md rule 29 (Flutter unit/widget tests mock API deps).
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.sessionOnRestore, this.failLoginWith, this.loginGate, this.restoreGate});

  /// What restoreSession() should return - null means "not logged in".
  AuthenticatedUser? sessionOnRestore;

  /// If set, login() throws this failure instead of succeeding.
  Failure? failLoginWith;

  /// If set, login() waits for this to complete before resolving - lets
  /// tests observe the in-flight loading state.
  Completer<void>? loginGate;

  /// If set, restoreSession() waits for this to complete before resolving -
  /// lets tests observe app-boot behavior while the session is still loading.
  Completer<void>? restoreGate;

  bool loggedOutCalled = false;

  @override
  Future<AuthenticatedUser?> restoreSession() async {
    if (restoreGate != null) await restoreGate!.future;
    return sessionOnRestore;
  }

  @override
  Future<AuthenticatedUser> login({required String email, required String password}) async {
    if (loginGate != null) await loginGate!.future;
    if (failLoginWith != null) throw failLoginWith!;
    return const AuthenticatedUser(id: 1, name: 'Test User', email: 'test@example.com', role: UserRole.superAdmin);
  }

  @override
  Future<void> logout() async {
    loggedOutCalled = true;
  }

  @override
  Future<void> forgotPassword(String email) async {}

  @override
  Future<void> resetPassword({required String email, required String token, required String password}) async {}
}
