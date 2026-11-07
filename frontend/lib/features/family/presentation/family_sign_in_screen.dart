import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/network/session_ended_notifier.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/family_brand.dart';
import '../../../core/widgets/family_mark.dart';
import '../../../core/widgets/phone_number_field.dart';
import '../../../core/widgets/secure_screen.dart';
import '../../auth/data/passcode_rules.dart';
import '../application/family_session_notifier.dart';
import '../data/family_auth_repository.dart';

/// Which of the two forms the screen shows.
enum FamilySignInMode { loading, passcode, register }

/// A parent's sign-in (docs/parent-student-app.md, F0/F1).
///
/// A phone registered as theirs asks for mobile + 6-digit passcode. A phone
/// that is not asks them to register it: their mobile, the 8-digit setup code
/// on the school's letter, and a passcode of their own.
class FamilySignInScreen extends ConsumerStatefulWidget {
  const FamilySignInScreen({super.key});

  @override
  ConsumerState<FamilySignInScreen> createState() => _FamilySignInScreenState();
}

class _FamilySignInScreenState extends ConsumerState<FamilySignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _mobile = TextEditingController();
  final _passcode = TextEditingController();
  final _setupCode = TextEditingController();
  final _newPasscode = TextEditingController();
  final _confirmPasscode = TextEditingController();

  FamilySignInMode _mode = FamilySignInMode.loading;
  bool _submitting = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    if (ref.read(sessionEndedProvider)) _problem = sessionEndedMessage;
    _loadDevice();
  }

  Future<void> _loadDevice() async {
    final repository = ref.read(familyAuthRepositoryProvider);
    final device = await repository.registeredDevice();
    final mobile = device?.mobile ?? await repository.lastMobile();
    if (!mounted) return;

    setState(() {
      _mobile.text = mobile ?? '';
      _mode = device == null ? FamilySignInMode.register : FamilySignInMode.passcode;
    });
  }

  @override
  void dispose() {
    for (final controller in [_mobile, _passcode, _setupCode, _newPasscode, _confirmPasscode]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
      _problem = null;
    });

    final repository = ref.read(familyAuthRepositoryProvider);
    final mobile = _mobile.text.trim();

    try {
      final account = _mode == FamilySignInMode.passcode
          ? await repository.login(mobile: mobile, passcode: _passcode.text)
          : await repository.setup(mobile: mobile, setupCode: _setupCode.text.trim(), passcode: _newPasscode.text);

      // The router takes a signed-in parent home.
      ref.read(familySessionProvider.notifier).signedIn(account);
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _problem = failure.message;
        _passcode.clear();
        // The school removed this phone: the only way on is a new code.
        if (failure.code == FamilyAuthRepository.deviceNotRegisteredCode) _mode = FamilySignInMode.register;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// A forgotten passcode is reset the way it was first set: a new letter
  /// from the school office, whose code lets the parent choose a new one.
  /// (A code sent to the mobile comes once sending is approved.)
  Future<void> _forgotPasscode() async {
    final hasCode = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('family-forgot-dialog'),
        title: const Text('Forgot your passcode?'),
        content: const Text(
          "Ask your child's school office for a new Family app letter. It has a new setup code: enter it here "
          'with your mobile number, and choose a new passcode. Your phone stays the same.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Close')),
          FilledButton(
            key: const Key('family-have-new-code'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('I have a new code'),
          ),
        ],
      ),
    );
    if (hasCode == true && mounted) _switchTo(FamilySignInMode.register);
  }

  void _switchTo(FamilySignInMode mode) => setState(() {
    _mode = mode;
    _problem = null;
  });

  @override
  Widget build(BuildContext context) {
    // A passcode or a setup code is typed here: kept out of screenshots.
    return SecureScreen(
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: _mode == FamilySignInMode.loading
                    ? const Center(child: FamilyMark(size: 64, tile: true))
                    : _form(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final registering = _mode == FamilySignInMode.register;
    final muted = context.appColors.muted;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(alignment: Alignment.centerLeft, child: FamilyMark(size: 56, tile: true)),
          const SizedBox(height: 18),
          Text(
            registering ? 'Set up the Family app' : 'Welcome back',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            registering
                ? 'Use the letter from your child\'s school: your mobile number, the 8-digit setup code, '
                      'and a 6-digit passcode you choose.'
                : 'Sign in with your mobile number and your 6-digit passcode.',
            style: TextStyle(fontSize: 14, color: muted, height: 1.4),
          ),
          const SizedBox(height: 22),
          PhoneNumberField(
            key: ValueKey('family-mobile-$_mode'),
            controller: _mobile,
            label: 'Mobile number',
            required: true,
          ),
          const SizedBox(height: 14),
          if (registering) ...[
            _DigitsField(
              key: const Key('family-setup-code'),
              controller: _setupCode,
              label: 'Setup code from the letter',
              length: 8,
              obscure: false,
              validator: (value) => RegExp(r'^\d{8}$').hasMatch(value ?? '')
                  ? null
                  : 'Enter the 8-digit setup code from the school\'s letter.',
            ),
            const SizedBox(height: 14),
            _DigitsField(
              key: const Key('family-new-passcode'),
              controller: _newPasscode,
              label: 'Choose a passcode',
              length: 6,
              validator: (value) => passcodeProblem(value ?? '', length: 6),
            ),
            const SizedBox(height: 14),
            _DigitsField(
              key: const Key('family-confirm-passcode'),
              controller: _confirmPasscode,
              label: 'Type it again',
              length: 6,
              validator: (value) => value == _newPasscode.text ? null : 'The two passcodes are not the same.',
              onSubmitted: _submit,
            ),
          ] else
            _DigitsField(
              key: const Key('family-passcode'),
              controller: _passcode,
              label: 'Passcode',
              length: 6,
              validator: (value) => RegExp(r'^\d{6}$').hasMatch(value ?? '') ? null : 'Enter your 6-digit passcode.',
              onSubmitted: _submit,
            ),
          if (_problem != null) ...[const SizedBox(height: 14), _ProblemBanner(message: _problem!)],
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: FilledButton(
              key: const Key('family-sign-in'),
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Text(registering ? 'Set up and sign in' : 'Sign in', style: const TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(height: 10),
          if (!registering)
            TextButton(
              key: const Key('family-forgot-passcode'),
              onPressed: _submitting ? null : _forgotPasscode,
              child: const Text('Forgot your passcode?'),
            ),
          if (!registering)
            TextButton(
              key: const Key('family-use-new-code'),
              onPressed: _submitting ? null : () => _switchTo(FamilySignInMode.register),
              child: const Text('New phone, or a new letter? Use the setup code'),
            )
          else
            TextButton(
              key: const Key('family-have-passcode'),
              onPressed: _submitting ? null : () => _switchTo(FamilySignInMode.passcode),
              child: const Text('Already set up on this phone? Sign in'),
            ),
          const SizedBox(height: 8),
          Text(
            'No letter? Ask your child\'s school office for the Family app setup code.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ],
      ),
    );
  }
}

/// Big, spaced digits on a number keyboard, hidden for a passcode.
class _DigitsField extends StatelessWidget {
  const _DigitsField({
    super.key,
    required this.controller,
    required this.label,
    required this.length,
    required this.validator,
    this.obscure = true,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final int length;
  final FormFieldValidator<String> validator;
  final bool obscure;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(length)],
      validator: validator,
      onFieldSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: 8),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(letterSpacing: 0, fontSize: 15),
        floatingLabelStyle: const TextStyle(letterSpacing: 0),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      ),
    );
  }
}

class _ProblemBanner extends StatelessWidget {
  const _ProblemBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final danger = context.appColors.danger;

    return Container(
      key: const Key('family-sign-in-problem'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: danger.withValues(alpha: 0.08),
        border: Border.all(color: danger.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: danger, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: danger, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// The blue the app opens on, while the session is restored.
class FamilySplashScreen extends StatelessWidget {
  const FamilySplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: FamilyBrand.gradient),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FamilyMark(size: 84),
              SizedBox(height: 14),
              Text(
                'School365ai Family',
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
