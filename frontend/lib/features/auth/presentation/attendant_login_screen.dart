import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../core/widgets/phone_number_field.dart';
import '../../marketing/presentation/marketing_colors.dart';
import '../application/auth_notifier.dart';
import '../data/attendant_auth_repository.dart';
import '../data/passcode_rules.dart';
import 'widgets/auth_card.dart';
import 'widgets/primary_button.dart';

/// Which of the two forms the screen shows.
enum _Mode { loading, passcode, register }

/// A bus attendant's sign-in (docs/maps.md, "The Bus Attendant").
///
/// A phone registered as theirs asks for mobile + 4-digit passcode. A phone
/// that is not asks them to register it: mobile, the 8-digit setup code the
/// school office gave them, and a passcode of their choosing.
class AttendantLoginScreen extends ConsumerStatefulWidget {
  const AttendantLoginScreen({super.key});

  @override
  ConsumerState<AttendantLoginScreen> createState() => _AttendantLoginScreenState();
}

class _AttendantLoginScreenState extends ConsumerState<AttendantLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _mobileController = TextEditingController();
  final _passcodeController = TextEditingController();
  final _setupCodeController = TextEditingController();
  final _newPasscodeController = TextEditingController();
  final _confirmPasscodeController = TextEditingController();

  _Mode _mode = _Mode.loading;
  bool _isSubmitting = false;

  /// The server's last answer, shown above the button.
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDevice();
  }

  Future<void> _loadDevice() async {
    final repository = ref.read(attendantAuthRepositoryProvider);
    final device = await repository.registeredDevice();
    final mobile = device?.mobile ?? await repository.lastMobile();
    if (!mounted) return;

    setState(() {
      _mobileController.text = mobile ?? '';
      _mode = device == null ? _Mode.register : _Mode.passcode;
    });
  }

  @override
  void dispose() {
    _mobileController.dispose();
    _passcodeController.dispose();
    _setupCodeController.dispose();
    _newPasscodeController.dispose();
    _confirmPasscodeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final repository = ref.read(attendantAuthRepositoryProvider);
    final mobile = _mobileController.text.trim();

    try {
      final user = _mode == _Mode.passcode
          ? await repository.login(mobile: mobile, passcode: _passcodeController.text)
          : await repository.setup(
              mobile: mobile,
              setupCode: _setupCodeController.text.trim(),
              passcode: _newPasscodeController.text,
            );

      // The router takes a signed-in attendant on to My Trip.
      ref.read(authNotifierProvider.notifier).signedIn(user);
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _errorMessage = failure.message;
        _passcodeController.clear();
        // The server no longer knows this phone (and its secret has been
        // forgotten): the only way on is a new setup code.
        if (failure.code == AttendantAuthRepository.deviceNotRegisteredCode) _mode = _Mode.register;
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _switchTo(_Mode mode) {
    setState(() {
      _mode = mode;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MarketingColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: AuthCard(
              child: _mode == _Mode.loading
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _buildForm(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    final registering = _mode == _Mode.register;

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.directions_bus_filled, size: 36, color: MarketingColors.primary),
          const SizedBox(height: 12),
          Text(
            registering ? 'Register this phone' : 'Bus attendant sign in',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: MarketingColors.text),
          ),
          const SizedBox(height: 4),
          Text(
            registering
                ? 'Enter your mobile number, the 8-digit setup code from your school office, and choose a 4-digit passcode.'
                : 'Enter your mobile number and your 4-digit passcode.',
            style: const TextStyle(fontSize: 14, color: MarketingColors.muted),
          ),
          const SizedBox(height: 20),
          PhoneNumberField(
            // A new field per form, so it picks up the number already typed.
            key: ValueKey('mobile-$_mode'),
            controller: _mobileController,
            label: 'Mobile',
            required: true,
          ),
          const SizedBox(height: 14),
          if (registering) ...[
            _DigitsField(
              key: const Key('attendant-setup-code'),
              controller: _setupCodeController,
              label: 'Setup code',
              length: 8,
              obscure: false,
              validator: (value) =>
                  RegExp(r'^\d{8}$').hasMatch(value ?? '') ? null : 'Enter the 8-digit setup code from your office',
            ),
            const SizedBox(height: 14),
            _DigitsField(
              key: const Key('attendant-new-passcode'),
              controller: _newPasscodeController,
              label: 'New passcode',
              length: 4,
              validator: (value) => passcodeProblem(value ?? ''),
            ),
            const SizedBox(height: 14),
            _DigitsField(
              key: const Key('attendant-confirm-passcode'),
              controller: _confirmPasscodeController,
              label: 'Confirm passcode',
              length: 4,
              validator: (value) => value == _newPasscodeController.text ? null : 'The passcodes do not match',
              onSubmitted: _submit,
            ),
          ] else
            _DigitsField(
              key: const Key('attendant-passcode'),
              controller: _passcodeController,
              label: 'Passcode',
              length: 4,
              validator: (value) => RegExp(r'^\d{4}$').hasMatch(value ?? '') ? null : 'Enter your 4-digit passcode',
              onSubmitted: _submit,
            ),
          if (_errorMessage != null) ...[const SizedBox(height: 14), _ErrorBanner(message: _errorMessage!)],
          const SizedBox(height: 20),
          PrimaryButton(
            label: registering ? 'Register and sign in' : 'Sign In',
            isLoading: _isSubmitting,
            onPressed: _submit,
          ),
          const SizedBox(height: 12),
          if (!registering)
            TextButton(
              onPressed: _isSubmitting ? null : () => _switchTo(_Mode.register),
              style: TextButton.styleFrom(foregroundColor: MarketingColors.primary),
              child: const Text('Have a new setup code? Register this phone again'),
            ),
          TextButton(
            onPressed: _isSubmitting ? null : () => context.go('/login'),
            style: TextButton.styleFrom(foregroundColor: MarketingColors.primary),
            child: const Text('Sign in with email instead'),
          ),
        ],
      ),
    );
  }
}

/// A digits-only field: big, spaced figures on a number keyboard, hidden for
/// a passcode.
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
      style: const TextStyle(color: MarketingColors.text, fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: 10),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: MarketingColors.subtle, letterSpacing: 0, fontSize: 15),
        floatingLabelStyle: const TextStyle(color: MarketingColors.primary, letterSpacing: 0),
        errorStyle: const TextStyle(color: MarketingColors.danger, fontSize: 12, fontWeight: FontWeight.w600),
        filled: true,
        fillColor: MarketingColors.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MarketingColors.danger.withValues(alpha: 0.08),
        border: Border.all(color: MarketingColors.danger.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: MarketingColors.danger, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: MarketingColors.danger, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
