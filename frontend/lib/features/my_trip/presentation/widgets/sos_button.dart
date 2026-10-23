import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Asks the school for help, and takes a two-second press to do it.
///
/// Held rather than tapped because of where it lives: a phone in a cradle
/// on a moving bus, under a driver's hand, on the same screen as the
/// buttons they press forty times a morning. One stray touch must not put
/// the office on the phone (docs/driver-app.md, D5.2).
///
/// The hold is shown as it fills, so a driver who means it can see it
/// working and one who did not can let go.
class SosButton extends StatefulWidget {
  const SosButton({super.key, required this.onSos});

  static const hold = Duration(seconds: 2);

  /// Called once the hold has been held all the way.
  final Future<void> Function() onSos;

  @override
  State<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<SosButton> with SingleTickerProviderStateMixin {
  late final AnimationController _held = AnimationController(vsync: this, duration: SosButton.hold)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) unawaited(_send());
    });

  /// Stops a second send while the first is still going out, and stops the
  /// controller's own completion firing twice.
  bool _sending = false;

  /// Where the finger went down, to tell a hold from a scroll.
  Offset _from = Offset.zero;
  static const _slop = 24.0;

  @override
  void dispose() {
    _held.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() => _sending = true);

    await widget.onSos();

    if (!mounted) return;
    _held.reset();
    setState(() => _sending = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('SOS sent. Your school has been told where you are.')));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    // Raw pointer events rather than a GestureDetector, and deliberately.
    // A gesture recogniser has to win an arena, and this one cannot: the
    // SelectionArea the app wraps every screen in claims the long press
    // first and turns the hold into "select this label" - a highlight and a
    // Copy bar where help was meant to go. Pointer events are delivered
    // before any of that and cannot be taken away.
    return Listener(
      key: const Key('sos'),
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        _from = event.position;
        _held.forward();
      },
      // A finger travelling is somebody scrolling the trip sheet with their
      // thumb resting here, not somebody calling for help.
      onPointerMove: (event) {
        if ((event.position - _from).distance > _slop) _held.reverse();
      },
      onPointerUp: (_) => _held.reverse(),
      onPointerCancel: (_) => _held.reverse(),
      // The app wraps every screen in a SelectionArea, so the office can
      // copy a name off one. On a button that is *held*, that is a trap:
      // the long press is taken as "select this text", the label
      // highlights, a Copy bar slides in, and the press that was meant to
      // call for help never arrives. Found on a phone rather than in a
      // test, because a widget test does not wrap the screen the way the
      // app does - so sos_selection_test.dart now does.
      child: SelectionContainer.disabled(
        child: Semantics(
          button: true,
          label: 'SOS. Hold for two seconds to ask your school for help.',
          child: SizedBox(
            height: 56,
            child: AnimatedBuilder(
              animation: _held,
              builder: (context, _) => Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.dangerContainer,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.danger),
                    ),
                  ),
                  // The fill is the whole feedback: it says the press is
                  // being counted, and how much of it is left.
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: _held.value,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: colors.danger, borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.sos_outlined, color: colors.onDangerContainer),
                        const SizedBox(width: 8),
                        Text(
                          _held.isAnimating || _sending ? 'Keep holding...' : 'Hold for SOS',
                          style: TextStyle(fontWeight: FontWeight.w800, color: colors.onDangerContainer),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
