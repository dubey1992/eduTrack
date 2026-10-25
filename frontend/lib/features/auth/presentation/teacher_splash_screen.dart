import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/teacher_brand.dart';
import '../../../core/widgets/teacher_mark.dart';
import '../application/auth_notifier.dart';

/// The first thing a teacher sees, while the app finds out whether they are
/// still signed in (docs/teacher-app.md).
///
/// Full-bleed teal, matching the Android launch window it follows, so the
/// app opens in one colour rather than flashing white. The book opens, the
/// name follows, and a line says what is happening. After [_patience] it
/// offers the one useful thing - try again - rather than a spinner for ever.
class TeacherSplashScreen extends ConsumerStatefulWidget {
  const TeacherSplashScreen({super.key});

  @override
  ConsumerState<TeacherSplashScreen> createState() => _TeacherSplashScreenState();
}

class _TeacherSplashScreenState extends ConsumerState<TeacherSplashScreen> with SingleTickerProviderStateMixin {
  static const _patience = Duration(seconds: 6);

  late final AnimationController _opening = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
  );

  Timer? _timer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Somebody who has asked their phone for less motion gets the book
    // already open.
    if (MediaQuery.of(context).disableAnimations) {
      _opening.value = 1;
    } else if (!_opening.isAnimating && _opening.value == 0) {
      _opening.forward();
    }
  }

  void _arm() {
    _timer?.cancel();
    _timer = Timer(_patience, () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _opening.dispose();
    super.dispose();
  }

  void _tryAgain() {
    setState(() => _slow = false);
    _arm();
    ref.invalidate(authNotifierProvider);
  }

  @override
  Widget build(BuildContext context) {
    final book = CurvedAnimation(parent: _opening, curve: Curves.easeOutBack);
    final words = CurvedAnimation(
      parent: _opening,
      curve: const Interval(0.45, 1, curve: Curves.easeOut),
    );
    const soft = Color(0xD9FFFFFF);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(gradient: TeacherBrand.gradient),
          child: Stack(
            children: [
              // Two quiet circles behind the mark, for depth. Nothing reads
              // from them.
              const Positioned(top: -90, right: -70, child: _Halo(size: 260)),
              const Positioned(bottom: -120, left: -90, child: _Halo(size: 320)),
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedBuilder(
                          animation: book,
                          builder: (context, _) => Transform.scale(
                            scale: 0.85 + 0.15 * book.value.clamp(0, 1.1),
                            child: TeacherMark(key: const Key('splash-mark'), size: 132, openness: book.value),
                          ),
                        ),
                        const SizedBox(height: 22),
                        FadeTransition(
                          opacity: words,
                          child: SlideTransition(
                            position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(words),
                            child: Column(
                              children: [
                                Text.rich(
                                  TextSpan(
                                    children: [
                                      const TextSpan(text: 'School365ai '),
                                      TextSpan(
                                        text: 'Teacher',
                                        style: TextStyle(color: TeacherBrand.amber.withValues(alpha: 0.95)),
                                      ),
                                    ],
                                  ),
                                  style: Theme.of(context).textTheme.headlineSmall
                                      ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: -0.2),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Your school day, in your pocket.',
                                  style: TextStyle(color: soft, fontSize: 15),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 44),
                        if (_slow) ...[
                          FilledButton.icon(
                            key: const Key('splash-try-again'),
                            onPressed: _tryAgain,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: TeacherBrand.tealDeep,
                            ),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Try again'),
                          ),
                          const SizedBox(height: 12),
                        ] else
                          const SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white),
                          ),
                        const SizedBox(height: 14),
                        Text(
                          _slow
                              ? 'Still trying to reach your school. Check that this phone is online.'
                              : 'Getting your day ready…',
                          key: const Key('splash-status'),
                          style: const TextStyle(color: soft, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Halo extends StatelessWidget {
  const _Halo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.06)),
      ),
    );
  }
}
