import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/models/user_role.dart';
import '../../../core/network/paged_list.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../../core/widgets/school_filter_dropdown.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/application/auth_notifier.dart';
import '../application/announcement_page_notifier.dart';
import '../data/models/announcement.dart';
import '../../communication/presentation/widgets/demo_gateway_notice.dart';
import 'new_announcement_dialog.dart';
import '../../../core/utils/date_format.dart';

/// Phase 17 - what has been announced, and the button that publishes the next
/// one. Reading an announcement as a recipient is the inbox, not this screen.
class AnnouncementScreen extends ConsumerStatefulWidget {
  const AnnouncementScreen({super.key});

  @override
  ConsumerState<AnnouncementScreen> createState() => _AnnouncementScreenState();
}

class _AnnouncementScreenState extends ConsumerState<AnnouncementScreen> {
  int? _schoolId;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Someone else may have published or deleted while this screen was
    // closed, so re-entering it re-reads.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Only on re-entry: on the very first build the provider is already
      // loading, and refreshing then would fetch the same page twice.
      if (mounted && ref.read(announcementPageNotifierProvider) is AsyncData) {
        ref.read(announcementPageNotifierProvider.notifier).refresh();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actor = ref.watch(authNotifierProvider).value;
    if (actor == null) return const SizedBox.shrink();

    final needsSchool = actor.role == UserRole.superAdmin && _schoolId == null;
    final notifier = ref.watch(announcementPageNotifierProvider.notifier);
    final state = ref.watch(announcementPageNotifierProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text('Announcements', style: Theme.of(context).textTheme.headlineSmall),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SchoolFilterDropdown(
                    selected: _schoolId,
                    onChanged: (schoolId) {
                      setState(() => _schoolId = schoolId);
                      notifier.setSchoolFilter(schoolId);
                    },
                  ),
                  FilledButton.icon(
                    onPressed: needsSchool
                        ? null
                        : () => showDialog<void>(
                            context: context,
                            builder: (_) => NewAnnouncementDialog(schoolId: _schoolId),
                          ),
                    icon: const Icon(Icons.campaign_outlined, size: 18),
                    label: const Text('New Announcement'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Notices published to the school, and who each one reached.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          if (needsSchool)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('Pick a school to see its announcements.')),
              ),
            )
          else ...[
            // Announcements report how many people they reached "by SMS",
            // which is only true if a real gateway is carrying them.
            DemoGatewayNotice(schoolId: _schoolId),
            _FilterBar(
              audience: notifier.audienceType,
              activeOnly: notifier.activeOnly,
              searchController: _searchController,
              onChanged: (audience, activeOnly) =>
                  notifier.setFilters(audienceType: audience, search: _searchController.text, activeOnly: activeOnly),
            ),
            const SizedBox(height: 12),
            AsyncValueView<PagedList<Announcement>>(
              value: state,
              onRetry: notifier.refresh,
              data: (context, page) => _AnnouncementList(page: page),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.audience,
    required this.activeOnly,
    required this.searchController,
    required this.onChanged,
  });

  final AnnouncementAudience? audience;
  final bool activeOnly;
  final TextEditingController searchController;
  final void Function(AnnouncementAudience? audience, bool activeOnly) onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<AnnouncementAudience?>(
                initialValue: audience,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Audience'),
                items: [
                  const DropdownMenuItem<AnnouncementAudience?>(child: Text('Any audience')),
                  for (final value in AnnouncementAudience.values)
                    DropdownMenuItem<AnnouncementAudience?>(value: value, child: Text(value.label)),
                ],
                onChanged: (value) => onChanged(value, activeOnly),
              ),
            ),
            SizedBox(
              width: 260,
              child: TextField(
                controller: searchController,
                decoration: InputDecoration(
                  labelText: 'Search title or message',
                  suffixIcon: IconButton(
                    tooltip: 'Search',
                    icon: const Icon(Icons.search),
                    onPressed: () => onChanged(audience, activeOnly),
                  ),
                ),
                onSubmitted: (_) => onChanged(audience, activeOnly),
              ),
            ),
            FilterChip(
              label: const Text('Still showing'),
              selected: activeOnly,
              onSelected: (value) => onChanged(audience, value),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnnouncementList extends ConsumerWidget {
  const _AnnouncementList({required this.page});

  final PagedList<Announcement> page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (page.items.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('Nothing has been announced yet.')),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final announcement in page.items) _AnnouncementCard(announcement: announcement),
        const SizedBox(height: 12),
        PaginationControls(
          currentPage: page.currentPage,
          lastPage: page.lastPage,
          total: page.total,
          perPage: page.perPage,
          onPageChanged: (value) => ref.read(announcementPageNotifierProvider.notifier).goToPage(value),
          onPerPageChanged: (value) => ref.read(announcementPageNotifierProvider.notifier).setPerPage(value),
        ),
      ],
    );
  }
}

class _AnnouncementCard extends ConsumerStatefulWidget {
  const _AnnouncementCard({required this.announcement});

  final Announcement announcement;

  @override
  ConsumerState<_AnnouncementCard> createState() => _AnnouncementCardState();
}

class _AnnouncementCardState extends ConsumerState<_AnnouncementCard> {
  bool _busy = false;

  Future<void> _delete() async {
    final announcement = widget.announcement;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete announcement?'),
        content: const Text(
          'It disappears from everyone\'s inbox. Messages already sent stay in the '
          'communication log, because a text that reached a phone cannot be unsent.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await ref.read(announcementPageNotifierProvider.notifier).delete(announcement);
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('"${announcement.title}" deleted.')));
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(failure.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final announcement = widget.announcement;
    final muted = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(announcement.title, style: Theme.of(context).textTheme.titleMedium),
                StatusBadge(label: announcement.audienceLabel, tone: BadgeTone.info),
                StatusBadge(label: announcement.channels.label, tone: BadgeTone.neutral),
                if (announcement.hasExpired) const StatusBadge(label: 'Expired', tone: BadgeTone.neutral),
              ],
            ),
            const SizedBox(height: 6),
            Text(announcement.body),
            const SizedBox(height: 10),
            Text(
              'Sent ${_publishedAt(announcement.publishedAtLabel)}'
              '${announcement.publishedByName == null ? '' : ' by ${announcement.publishedByName}'} · '
              'reached ${announcement.recipientsCount} '
              '${announcement.recipientsCount == 1 ? 'person' : 'people'} '
              '(${announcement.smsCount} by SMS, ${announcement.inAppCount} in-app)'
              '${announcement.expiresAt == null ? '' : ' · expires ${_expiresOn(announcement.expiresAt!)}'}',
              style: muted,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(onPressed: _busy ? null : _delete, child: const Text('Delete')),
            ),
          ],
        ),
      ),
    );
  }

  String _expiresOn(String date) {
    final parsed = DateTime.tryParse(date);

    return parsed == null ? date : formatDate(parsed);
  }

  /// Rendered by the API in the school's timezone - the browser's own zone
  /// would disagree with the timestamp written inside the messages this
  /// notice sent.
  String _publishedAt(String? label) => label ?? 'recently';
}
