import 'widgets/saved_copy_line.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../application/family_session_notifier.dart';
import '../data/family_repository.dart';
import '../data/models/family_account.dart';
import '../data/models/family_admit_card.dart';
import '../../../core/utils/calendar_file.dart';
import '../../../core/utils/pdf_hand_off.dart';
import 'widgets/family_widgets.dart';

/// The child's admit cards (docs/examinations.md): every published exam
/// their class sits, newest first. A card that is ready downloads; one that
/// is not says the school's sentence - never why it is withheld.
final familyAdmitCardsProvider = FutureProvider.autoDispose.family<List<FamilyAdmitCard>, int>((ref, childId) {
  return ref.watch(familyRepositoryProvider).admitCards(childId);
}, retry: (retryCount, error) => null);

class FamilyAdmitCardsScreen extends ConsumerStatefulWidget {
  const FamilyAdmitCardsScreen({super.key});

  @override
  ConsumerState<FamilyAdmitCardsScreen> createState() => _FamilyAdmitCardsScreenState();
}

class _FamilyAdmitCardsScreenState extends ConsumerState<FamilyAdmitCardsScreen> {
  int? _downloading;

  Future<void> _download(FamilyChild child, FamilyAdmitCard card) async {
    if (_downloading != null) return;
    setState(() => _downloading = card.examinationId);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final bytes = await ref.read(familyRepositoryProvider).admitCardPdf(child.id, card.examinationId);
      final name = 'admit-card-${child.firstName.toLowerCase()}-${card.name.toLowerCase().replaceAll(' ', '-')}.pdf';
      await ref.read(pdfHandOffProvider)(bytes, name);
    } on Failure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    } finally {
      if (mounted) setState(() => _downloading = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = ref.watch(selectedChildProvider);
    final colors = context.appColors;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Admit cards'),
            if (child != null) Text(child.fullName, style: TextStyle(fontSize: 12, color: colors.muted)),
          ],
        ),
      ),
      body: child == null
          ? const FamilyEmptyView(icon: Icons.family_restroom_rounded, title: 'No children to show')
          : ref
                .watch(familyAdmitCardsProvider(child.id))
                .when(
                  loading: () => const PlaceholderCards(),
                  error: (error, _) =>
                      FamilyErrorView(error: error, onRetry: () => ref.invalidate(familyAdmitCardsProvider(child.id))),
                  data: (cards) => cards.isEmpty
                      ? const FamilyEmptyView(
                          key: Key('family-admit-cards-empty'),
                          icon: Icons.badge_outlined,
                          title: 'No admit cards yet',
                          message: 'When the school publishes an exam your child sits, its admit card appears here.',
                        )
                      : RefreshIndicator(
                          onRefresh: () async => ref.invalidate(familyAdmitCardsProvider(child.id)),
                          child: ListView(
                            key: const Key('family-admit-cards'),
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            children: [
                              SavedCopyLine(name: 'admit-cards:${child.id}'),
                              for (final card in cards) _card(child, card),
                            ],
                          ),
                        ),
                ),
    );
  }

  Future<void> _addToCalendar(FamilyChild child, FamilyAdmitCard card) async {
    final file = calendarFile([
      for (final paper in card.papers)
        CalendarItem.timed(
          uid: 'exam-${card.examinationId}-${child.id}-${paper.date.toIso8601String().substring(0, 10)}-${paper.start}',
          title: '${paper.subject} - ${card.name} (${child.firstName})',
          day: paper.date,
          start: paper.start,
          end: paper.end,
          location: card.centre,
          note: card.reportingTime == null ? null : 'Reporting time ${card.reportingTime}.',
        ),
    ], name: card.name);

    try {
      await ref.read(calendarHandOffProvider)(file, '${_fileStem(card.name)}.ics');
    } catch (error) {
      debugPrint('Sharing the exam calendar failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('The calendar file could not be shared.')));
      }
    }
  }

  static String _fileStem(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');

  Widget _card(FamilyChild child, FamilyAdmitCard card) {
    final colors = context.appColors;
    final busy = _downloading == card.examinationId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FamilyCard(
        key: Key('family-admit-card-${card.examinationId}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(card.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            Text([card.yearName, ?card.termName].join(' · '), style: TextStyle(color: colors.muted, fontSize: 13)),
            const SizedBox(height: 8),
            Text(card.message, style: TextStyle(color: card.available ? colors.success : colors.warning, fontSize: 14)),
            if (card.available && card.issuedOn != null)
              Text(
                'Version ${card.version}, issued ${card.issuedOn}',
                style: TextStyle(color: colors.muted, fontSize: 12),
              ),
            if (card.available) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                key: Key('family-admit-card-download-${card.examinationId}'),
                onPressed: busy ? null : () => _download(child, card),
                icon: busy
                    ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download_rounded, size: 18),
                label: const Text('Download admit card'),
              ),
            ],
            // The date sheet into the phone's calendar (M8, 6.3) - offered
            // even when the card itself is held back: the dates are the class's.
            if (card.papers.isNotEmpty) ...[
              const SizedBox(height: 6),
              TextButton.icon(
                key: Key('family-exam-calendar-${card.examinationId}'),
                onPressed: () => _addToCalendar(child, card),
                icon: const Icon(Icons.event_available_rounded, size: 18),
                label: Text('Add ${card.papers.length} ${card.papers.length == 1 ? 'paper' : 'papers'} to calendar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
