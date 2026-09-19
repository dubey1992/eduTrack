import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/widgets/responsive.dart';
import '../../marketing/presentation/marketing_colors.dart';
import '../application/auth_notifier.dart';
import 'widgets/brand_panel.dart';
import 'widgets/login_card.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // Deliberately local, not derived from authNotifierProvider.isLoading:
  // that flag is also true while the initial session-restore check runs on
  // app start, which is a different concept from "this form is submitting".
  bool _isSubmitting = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _loadRememberedEmail();
  }

  Future<void> _loadRememberedEmail() async {
    final email = await ref.read(authTokenStorageProvider).readRememberedEmail();
    if (email == null || !mounted) return;
    setState(() {
      _emailController.text = email;
      _rememberMe = true;
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    final email = _emailController.text.trim();
    await ref.read(authNotifierProvider.notifier).login(email: email, password: _passwordController.text);

    final tokenStorage = ref.read(authTokenStorageProvider);
    if (_rememberMe) {
      await tokenStorage.saveRememberedEmail(email);
    } else {
      await tokenStorage.clearRememberedEmail();
    }

    if (mounted) setState(() => _isSubmitting = false);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authNotifierProvider, (previous, next) {
      final error = next.error;
      if (error != null && next is! AsyncLoading) {
        final failure = error is Failure ? error : Failure.unknown(error.toString());
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(failure.message)));
      }
    });

    final loginCard = LoginCard(
      formKey: _formKey,
      emailController: _emailController,
      passwordController: _passwordController,
      obscurePassword: _obscurePassword,
      onToggleObscurePassword: () => setState(() => _obscurePassword = !_obscurePassword),
      rememberMe: _rememberMe,
      onRememberMeChanged: (value) => setState(() => _rememberMe = value),
      isSubmitting: _isSubmitting,
      onSubmit: _submit,
      onForgotPassword: () => context.push('/forgot-password'),
      onAttendantSignIn: () => context.go('/attendant-login'),
    );

    return Scaffold(
      backgroundColor: MarketingColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              // Matches the prototype's `min-height:100vh; align-items:center`
              // - short content (mobile card, or a desktop window taller than
              // the login content) centers vertically in the viewport;
              // content taller than the viewport just scrolls normally.
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: viewport.maxHeight - 48),
                child: Center(
                  child: ResponsiveBuilder(
                    // A phone screen keeps the login card as the only thing
                    // on screen - the hero copy and illustration are
                    // decorative and would otherwise bury the actual form
                    // below the fold.
                    mobile: (context) =>
                        ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: loginCard),
                    // Flexible hero + a fixed-width card, matching the
                    // prototype's `grid-template-columns: 1fr 430px`.
                    desktop: (context) => ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1400),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Expanded(child: BrandPanel()),
                          const SizedBox(width: 60),
                          SizedBox(width: 430, child: loginCard),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
