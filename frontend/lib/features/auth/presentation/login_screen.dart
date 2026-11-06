import '../../../core/network/session_ended_notifier.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/widgets/responsive.dart';
import '../application/auth_notifier.dart';
import 'widgets/auth_palette.dart';
import 'widgets/brand_panel.dart';
import 'widgets/login_card.dart';
import 'widgets/website_links.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.offersAttendantSignIn = true});

  /// Whether to show the bus crew's way in. The web portal offers it; the
  /// teacher app has no passcode sign-in behind the link, so it does not
  /// (docs/teacher-app.md, T0).
  final bool offersAttendantSignIn;

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
    // Here because the server ended the last session - say so.
    if (ref.read(sessionEndedProvider)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            // Longer than a passing note: somebody who did not sign themselves
            // out needs time to read why they are here.
            const SnackBar(
              key: Key('session-ended'),
              duration: Duration(seconds: 10),
              content: Text(sessionEndedMessage),
            ),
          );
      });
    }
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

    // Signed in: the browser may now offer to save the password.
    if (ref.read(authNotifierProvider).value != null) TextInput.finishAutofillContext();

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

    final attendantSignIn = widget.offersAttendantSignIn ? () => context.go('/attendant-login') : null;

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
      onAttendantSignIn: attendantSignIn,
    );

    return Scaffold(
      backgroundColor: AuthPalette.of(context).background,
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
                    mobile: (context) => ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Align(alignment: Alignment.centerLeft, child: BrandMark()),
                          const SizedBox(height: 16),
                          loginCard,
                          const SizedBox(height: 16),
                          const _ParentNote(),
                          const SizedBox(height: 8),
                          const _HelpLinks(),
                        ],
                      ),
                    ),
                    // Flexible hero + a fixed-width card, matching the
                    // prototype's `grid-template-columns: 1fr 430px`.
                    desktop: (context) => ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1400),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(child: BrandPanel(onAttendantSignIn: attendantSignIn)),
                          const SizedBox(width: 60),
                          SizedBox(
                            width: 430,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [loginCard, const SizedBox(height: 16), const _HelpLinks()],
                            ),
                          ),
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

/// For a phone, where most parents arrive: the desktop explains who signs in
/// beside the form, a phone has room for this one line.
class _ParentNote extends StatelessWidget {
  const _ParentNote();

  @override
  Widget build(BuildContext context) {
    final palette = AuthPalette.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.family_restroom_outlined, size: 18, color: palette.subtle),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            "Parent? You don't need to sign in. Your school sends updates to your phone.",
            style: TextStyle(fontSize: 13, height: 1.4, color: palette.muted),
          ),
        ),
      ],
    );
  }
}

/// Under the form: a school that is not on School365ai yet, and anybody
/// who cannot get in.
class _HelpLinks extends StatelessWidget {
  const _HelpLinks();

  @override
  Widget build(BuildContext context) {
    final palette = AuthPalette.of(context);
    final style = TextButton.styleFrom(
      foregroundColor: palette.primary,
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      children: [
        TextButton(
          key: const Key('login-book-demo'),
          style: style,
          onPressed: () => WebsiteLinks.open(WebsiteLinks.bookDemo),
          child: const Text('New school? Book a free demo'),
        ),
        TextButton.icon(
          key: const Key('login-whatsapp-help'),
          style: style,
          onPressed: () => WebsiteLinks.open(WebsiteLinks.whatsApp),
          icon: const Icon(Icons.chat_outlined, size: 16),
          label: const Text('Need help? WhatsApp ${WebsiteLinks.supportPhone}'),
        ),
      ],
    );
  }
}
