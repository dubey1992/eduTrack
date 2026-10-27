import 'package:flutter/material.dart';

import '../../../marketing/data/marketing_links.dart';

/// Asks for a link's words and where it goes. Returns null if cancelled.
///
/// The address is checked against the same rules as a homepage footer line
/// (and again by the server), so a link that would be drawn as plain text
/// is refused here, where somebody can still fix it.
Future<({String words, String address})?> showLinkDialog(BuildContext context, {String words = ''}) {
  return showDialog<({String words, String address})>(
    context: context,
    builder: (context) => _LinkDialog(words: words),
  );
}

class _LinkDialog extends StatefulWidget {
  const _LinkDialog({required this.words});

  final String words;

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _words = TextEditingController(text: widget.words);
  final _address = TextEditingController();

  @override
  void dispose() {
    _words.dispose();
    _address.dispose();
    super.dispose();
  }

  void _insert() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop((words: _words.text.trim(), address: _address.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a link'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _words,
                autofocus: widget.words.isEmpty,
                decoration: const InputDecoration(labelText: 'Words to show', hintText: 'e.g. Privacy Policy'),
                validator: (value) => (value ?? '').trim().isEmpty ? 'Enter the words to show.' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _address,
                autofocus: widget.words.isNotEmpty,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  hintText: 'https://…, /privacy, mailto:… or tel:…',
                  helperText:
                      'A web address, a page of this site starting with /, an email (mailto:) or a phone (tel:).',
                  helperMaxLines: 3,
                ),
                onFieldSubmitted: (_) => _insert(),
                validator: (value) {
                  final address = (value ?? '').trim();
                  if (address.isEmpty) return 'Enter where the link goes.';
                  if (linkKind(address) == null) {
                    return 'Start with https://, http://, mailto:, tel: or / for a page of this site.';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _insert, child: const Text('Add link')),
      ],
    );
  }
}
