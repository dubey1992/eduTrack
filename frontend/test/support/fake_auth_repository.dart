import 'dart:async';

import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';

/// Test double for [AuthRepository] - no real Dio/network involved, per
/// backend CLAUDE.md rule 29 (Flutter unit/widget tests mock API deps).
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    this.sessionOnRestore,
    this.failLoginWith,
    this.loginGate,
    this.restoreGate,
    this.loginAs,
    this.failForgotWith,
  });

  /// Who login() signs in as. A Super Admin when not given, which is what
  /// every test written before the Teacher app expects.
  AuthenticatedUser? loginAs;

  /// If set, forgotPassword() throws this instead of succeeding.
  Failure? failForgotWith;

  /// The address the last reset link was asked for.
  String? forgotEmail;

  /// What the last login() was given.
  String? loginEmail;

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

  /// How many times the session was read - at start-up and on each refresh.
  int restoreCalls = 0;

  @override
  Future<AuthenticatedUser?> restoreSession() async {
    restoreCalls++;
    if (restoreGate != null) await restoreGate!.future;
    return sessionOnRestore;
  }

  @override
  Future<AuthenticatedUser> login({required String email, required String password}) async {
    if (loginGate != null) await loginGate!.future;
    loginEmail = email;
    if (failLoginWith != null) throw failLoginWith!;
    return loginAs ??
        const AuthenticatedUser(id: 1, name: 'Test User', email: 'test@example.com', role: UserRole.superAdmin);
  }

  @override
  Future<void> logout() async {
    loggedOutCalled = true;
  }

  /// What the session looks like after a successful password change - by
  /// default the same user with the flag cleared.
  AuthenticatedUser? sessionAfterChange;

  /// If set, changePassword() throws this instead of succeeding.
  Failure? failChangeWith;

  String? changedFrom;
  String? changedTo;

  @override
  Future<AuthenticatedUser> changePassword({required String currentPassword, required String password}) async {
    if (failChangeWith != null) throw failChangeWith!;

    changedFrom = currentPassword;
    changedTo = password;

    return sessionAfterChange ??
        const AuthenticatedUser(id: 1, name: 'Test User', email: 'test@example.com', role: UserRole.teacher);
  }

  @override
  Future<void> forgotPassword(String email) async {
    forgotEmail = email;
    if (failForgotWith != null) throw failForgotWith!;
  }

  @override
  Future<void> resetPassword({required String email, required String token, required String password}) async {}
}
