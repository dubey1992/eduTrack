import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_language.dart';
import 'l10n.dart';

/// "Language" in a phone app's profile (docs/mobile-apps-review.md, M11):
/// the phone's language, English or Hindi. Each option is written in its
/// own language, so a person who cannot read the current one still finds
/// theirs.
class LanguageTile extends ConsumerWidget {
  const LanguageTile({super.key});

  String _label(BuildContext context, AppLanguage language) => switch (language) {
    AppLanguage.phone => context.l10n.languagePhone,
    AppLanguage.english => context.l10n.languageEnglish,
    AppLanguage.hindi => context.l10n.languageHindi,
  };

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final current = ref.read(appLanguageProvider);
    final chosen = await showDialog<AppLanguage>(
      context: context,
      builder: (context) => SimpleDialog(
        key: const Key('language-dialog'),
        title: Text(context.l10n.languageTitle),
        children: [
          for (final language in AppLanguage.values)
            SimpleDialogOption(
              key: Key('language-${language.name}'),
              onPressed: () => Navigator.of(context).pop(language),
              child: Row(
                children: [
                  Expanded(child: Text(_label(context, language), style: const TextStyle(fontSize: 16))),
                  if (language == current) Icon(Icons.check, color: Theme.of(context).colorScheme.primary),
                ],
              ),
            ),
        ],
      ),
    );
    if (chosen == null || chosen == current || !context.mounted) return;

    await ref.read(appLanguageProvider.notifier).choose(chosen);
    if (!context.mounted) return;
    // After the switch, so the confirmation is in the language just chosen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.languageChanged)));
      }
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The web office shares the profile screen and stays English for now.
    if (!ref.watch(languagePickerEnabledProvider)) return const SizedBox.shrink();
    final language = ref.watch(appLanguageProvider);

    return ListTile(
      key: const Key('language-tile'),
      leading: const Icon(Icons.translate),
      title: Text(context.l10n.languageTitle),
      subtitle: Text(_label(context, language)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _pick(context, ref),
    );
  }
}
