import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/voice_search.dart';

/// Finds a child on the trip sheet: type a name, or say it.
///
/// Fifty children on a bus is fifty cards to scroll, and the one who has
/// just climbed on is somewhere in the middle. The field sits above the
/// list and never scrolls away. The microphone is for crew who would rather
/// not type - it fills the same box with what it hears, so nothing else
/// about the screen changes (docs/driver-app.md, D8).
class RiderSearchField extends ConsumerStatefulWidget {
  const RiderSearchField({super.key, required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  ConsumerState<RiderSearchField> createState() => _RiderSearchFieldState();
}

class _RiderSearchFieldState extends ConsumerState<RiderSearchField> {
  final _controller = TextEditingController();
  late final Future<bool> _canListen = ref.read(voiceSearchProvider).isAvailable();
  StreamSubscription<String>? _hearing;

  bool get _listening => _hearing != null;

  @override
  void dispose() {
    _hearing?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _set(String text) {
    _controller.text = text;
    widget.onChanged(text);
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _hearing?.cancel();
      if (mounted) setState(() => _hearing = null);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _hearing = ref
          .read(voiceSearchProvider)
          .listen()
          .listen(
            (words) => setState(() => _set(words)),
            onDone: () {
              if (mounted) setState(() => _hearing = null);
            },
            onError: (Object _) {
              if (!mounted) return;
              setState(() => _hearing = null);
              // Said once, here, because the button is still there: the
              // phone may listen next time if the permission is granted.
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(
                    content: Text("The microphone could not be used. Check the app's permission, or type the name."),
                  ),
                );
            },
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _controller.text.isNotEmpty;

    return FutureBuilder<bool>(
      future: _canListen,
      builder: (context, snapshot) {
        final canListen = snapshot.data ?? false;

        return TextField(
          key: const Key('rider-search'),
          controller: _controller,
          onChanged: _set,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: _listening ? 'Listening… say the child\'s name' : 'Find a child by name, class or number',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasText)
                  IconButton(
                    key: const Key('rider-search-clear'),
                    tooltip: 'Clear',
                    onPressed: () => setState(() => _set('')),
                    icon: const Icon(Icons.close),
                  ),
                if (canListen)
                  IconButton(
                    key: const Key('rider-search-voice'),
                    tooltip: _listening ? 'Stop listening' : 'Say the name',
                    onPressed: _toggleListening,
                    isSelected: _listening,
                    icon: Icon(_listening ? Icons.mic : Icons.mic_none),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
