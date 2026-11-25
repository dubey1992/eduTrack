import 'widgets/saved_copy_line.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/errors/failure.dart';
import '../../../core/l10n/failure_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/calendar_file.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../application/family_notifiers.dart';
import '../application/family_session_notifier.dart';
import '../data/models/family_account.dart';
import '../data/models/family_records.dart';
import 'family_words.dart';
import 'widgets/family_widgets.dart';
import 'family_talk_screens.dart';
import '../../../core/widgets/notice_attachment_chips.dart';
import '../../../core/l10n/language_tile.dart';

/// Opens the phone's dialler, WhatsApp or mail app. Swappable in tests.
typedef ExternalOpener = Future<bool> Function(Uri uri);

final externalOpenerProvider = Provider<ExternalOpener>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// More: the parent's own things - notices, the school's calendar, which
/// messages come to the app, how to reach the school, and signing out.
class FamilyMoreScreen extends ConsumerWidget {
  const FamilyMoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(familySessionProvider).value;
    final unread = ref.watch(familyNoticesProvider).value?.unreadCount ?? 0;
    final muted = context.appColors.muted;
    final features = account?.features ?? FamilyFeatures.all;
    final l10n = context.l10n;
    // Only what the school uses: no Results row at a school without tests.
    final learning = [
      _MoreRow(
        key: const Key('family-more-absence-notes'),
        icon: Icons.edit_note_rounded,
        title: l10n.familyAbsenceNotes,
        subtitle: l10n.familyAbsenceNotesSub,
        onTap: () => context.push('/absence-notes'),
      ),
      _MoreRow(
        key: const Key('family-more-guardian'),
        icon: Icons.person_add_alt_1_rounded,
        title: l10n.familyAddGuardian,
        subtitle: l10n.familyAddGuardianSub,
        onTap: () => context.push('/guardians/new'),
      ),
      _MoreRow(
        key: const Key('family-more-call'),
        icon: Icons.phone_callback_rounded,
        title: l10n.familyAskToCall,
        subtitle: l10n.familyAskToCallSub,
        onTap: () => context.push('/call-requests'),
      ),
      _MoreRow(
        key: const Key('family-more-meetings'),
        icon: Icons.groups_2_rounded,
        title: l10n.familyMeetings,
        subtitle: l10n.familyMeetingsSub,
        onTap: () => context.push('/meetings'),
      ),
      if (features.results)
        _MoreRow(
          key: const Key('family-more-results'),
          icon: Icons.grade_rounded,
          title: l10n.familyResults,
          subtitle: l10n.familyResultsCardLine,
          onTap: () => context.push('/results'),
        ),
      // Exams sit under Class Tests: no row at a school without them.
      if (features.results)
        _MoreRow(
          key: const Key('family-more-admit-cards'),
          icon: Icons.badge_rounded,
          title: l10n.familyAdmitCards,
          subtitle: l10n.familyAdmitCardsSub,
          onTap: () => context.push('/admit-cards'),
        ),
      if (features.timetable)
        _MoreRow(
          key: const Key('family-more-timetable'),
          icon: Icons.schedule_rounded,
          title: l10n.familyTimetable,
          subtitle: l10n.familyTimetableSub,
          onTap: () => context.push('/timetable'),
        ),
      if (features.syllabus)
        _MoreRow(
          key: const Key('family-more-syllabus'),
          icon: Icons.menu_book_rounded,
          title: l10n.familySyllabus,
          subtitle: l10n.familySyllabusSub,
          onTap: () => context.push('/syllabus'),
        ),
      if (features.homework)
        _MoreRow(
          key: const Key('family-more-homework'),
          icon: Icons.edit_note_rounded,
          title: l10n.familyHomework,
          subtitle: l10n.familyHomeworkSub,
          onTap: () => context.push('/homework'),
        ),
    ];

    return ListView(
      key: const Key('family-more'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (account != null)
          FamilyCard(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Text(account.firstName.isEmpty ? '?' : account.firstName[0].toUpperCase()),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(account.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      Text(
                        [if (account.mobile != null) account.mobile!, account.schoolName].join(' · '),
                        style: TextStyle(color: muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (learning.isNotEmpty) ...[
          const SizedBox(height: 12),
          FamilyCard(
            key: const Key('family-more-learning'),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(children: learning),
          ),
        ],
        const SizedBox(height: 12),
        FamilyCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              _MoreRow(
                key: const Key('family-more-notices'),
                icon: Icons.campaign_rounded,
                title: l10n.familyNotices,
                subtitle: unread > 0 ? l10n.familyNewCount(unread) : l10n.familyNoticesSub,
                onTap: () => context.push('/notices'),
              ),
              _MoreRow(
                key: const Key('family-more-calendar'),
                icon: Icons.calendar_month_rounded,
                title: l10n.familySchoolCalendar,
                subtitle: l10n.familySchoolCalendarSub,
                onTap: () => context.push('/calendar'),
              ),
              _MoreRow(
                key: const Key('family-more-notifications'),
                icon: Icons.notifications_active_outlined,
                title: l10n.familyNotifications,
                subtitle: l10n.familyNotificationsSub,
                onTap: () => context.push('/notifications'),
              ),
              _MoreRow(
                key: const Key('family-more-privacy'),
                icon: Icons.shield_outlined,
                title: l10n.familyYourPrivacy,
                subtitle: l10n.familyYourPrivacySub,
                onTap: () => context.push('/privacy'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // English or Hindi (M11).
        const FamilyCard(padding: EdgeInsets.symmetric(vertical: 6), child: LanguageTile()),
        const SizedBox(height: 12),
        if (account != null) _ContactCard(account: account),
        const SizedBox(height: 12),
        FamilyCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: _MoreRow(
            key: const Key('family-sign-out'),
            icon: Icons.logout_rounded,
            title: l10n.familySignOut,
            subtitle: l10n.familySignOutSub,
            onTap: () async {
              final sure = await confirmDialog(
                context,
                title: l10n.familySignOutQuestion,
                message: l10n.familySignOutMessage,
                confirmLabel: l10n.familySignOut,
              );
              if (sure) await ref.read(familySessionProvider.notifier).logout();
            },
          ),
        ),
      ],
    );
  }
}

class _MoreRow extends StatelessWidget {
  const _MoreRow({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minTileHeight: 60,
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

/// Contact the school: the office's own number, WhatsApp and email.
class _ContactCard extends ConsumerWidget {
  const _ContactCard({required this.account});

  final FamilyAccount account;

  Future<void> _open(BuildContext context, WidgetRef ref, Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await ref.read(externalOpenerProvider)(uri);
    } on Exception catch (e) {
      debugPrint('Could not open ${uri.scheme}: $e');
    }
    if (!opened) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(context.l10n.familyCouldNotOpen)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phone = account.schoolPhone;
    final email = account.schoolEmail;
    final digits = phone?.replaceAll(RegExp(r'[^0-9]'), '');

    return FamilyCard(
      key: const Key('family-contact'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeading(icon: Icons.support_agent_rounded, title: context.l10n.familyContactSchool),
          const SizedBox(height: 6),
          Text(account.schoolName, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (account.schoolAddress != null)
            Text(account.schoolAddress!, style: TextStyle(color: context.appColors.muted, fontSize: 13)),
          const SizedBox(height: 12),
          if (phone == null && email == null)
            Text(context.l10n.familyNoContactDetails, style: TextStyle(color: context.appColors.muted))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (phone != null)
                  FilledButton.icon(
                    key: const Key('family-call-school'),
                    onPressed: () => _open(context, ref, Uri(scheme: 'tel', path: phone)),
                    icon: const Icon(Icons.call_rounded, size: 18),
                    label: Text(context.l10n.familyCall),
                  ),
                if (digits != null && digits.length >= 8)
                  OutlinedButton.icon(
                    key: const Key('family-whatsapp-school'),
                    onPressed: () => _open(context, ref, Uri.parse('https://wa.me/$digits')),
                    icon: const Icon(Icons.chat_rounded, size: 18),
                    label: const Text('WhatsApp'),
                  ),
                if (email != null)
                  OutlinedButton.icon(
                    key: const Key('family-email-school'),
                    onPressed: () => _open(context, ref, Uri(scheme: 'mailto', path: email)),
                    icon: const Icon(Icons.mail_outline_rounded, size: 18),
                    label: Text(context.l10n.familyEmail),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

// -- Notices ------------------------------------------------------------------

/// The school's messages, newest first, unread in bold with a dot.
class FamilyNoticesScreen extends ConsumerWidget {
  const FamilyNoticesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notices = ref.watch(familyNoticesProvider);
    final unread = notices.value?.unreadCount ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.familyNotices),
        actions: [
          if (unread > 0)
            // An icon with its words as the tooltip, which a screen reader
            // speaks: the words did not fit the bar in Hindi at large text
            // (M11, 3.4).
            IconButton(
              key: const Key('family-read-all'),
              tooltip: context.l10n.familyMarkAllRead,
              onPressed: () => _readAll(context, ref),
              icon: const Icon(Icons.done_all_rounded),
            ),
        ],
      ),
      body: notices.when(
        skipLoadingOnRefresh: true,
        loading: () => const PlaceholderCards(),
        error: (error, _) =>
            FamilyErrorView(error: error, onRetry: () => ref.read(familyNoticesProvider.notifier).refresh()),
        data: (state) => RefreshIndicator(
          onRefresh: () => ref.read(familyNoticesProvider.notifier).refresh(),
          child: state.notices.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 80),
                    FamilyEmptyView(
                      icon: Icons.mark_email_read_outlined,
                      title: context.l10n.familyNoNoticesYet,
                      message: context.l10n.familyNoNoticesYetMessage,
                    ),
                  ],
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: (scroll) {
                    if (scroll.metrics.extentAfter < 300) ref.read(familyNoticesProvider.notifier).loadMore();
                    return false;
                  },
                  child: ListView.separated(
                    key: const Key('family-notices'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    // The first row says when a saved copy is showing (2.2).
                    itemCount: state.notices.length + 1,
                    separatorBuilder: (_, index) => SizedBox(height: index == 0 ? 0 : 10),
                    itemBuilder: (context, index) => index == 0
                        ? const SavedCopyLine(name: 'notices')
                        : _NoticeTile(notice: state.notices[index - 1]),
                  ),
                ),
        ),
      ),
    );
  }

  Future<void> _readAll(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(familyNoticesProvider.notifier).markAllRead();
    } on Failure catch (failure) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(failure.localizedMessage(context))));
    }
  }
}

class _NoticeTile extends ConsumerWidget {
  const _NoticeTile({required this.notice});

  final FamilyNotice notice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = context.appColors.muted;
    final emergency = notice.category == 'emergency';

    return FamilyCard(
      key: Key('family-notice-${notice.id}'),
      onTap: () => _open(context, ref),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 10),
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: notice.read ? Colors.transparent : Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notice.title ?? notice.kindWords(context.l10n),
                  style: TextStyle(
                    fontWeight: notice.read ? FontWeight.w500 : FontWeight.w700,
                    color: emergency ? context.appColors.danger : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  notice.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: muted),
                ),
                if (notice.attachments.isNotEmpty)
                  Row(
                    children: [
                      Icon(Icons.attach_file, size: 14, color: muted),
                      Text(
                        context.l10n.familyFilesCount(notice.attachments.length),
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                if (notice.reply?.awaitsAnswer ?? false) const AnswerNeededBadge(),
                const SizedBox(height: 4),
                Text(
                  [
                    if (notice.studentName != null) notice.studentName!,
                    '${formatDate(notice.createdAt)} ${DateFormat('h:mm a').format(notice.createdAt)}',
                  ].join(' · '),
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    // Read the moment it is opened; a failure to tell the server is not worth
    // interrupting the parent over, so it is logged, not shown.
    ref
        .read(familyNoticesProvider.notifier)
        .markRead(notice)
        .catchError((Object error) => debugPrint('Could not mark notice ${notice.id} read: $error'));

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            key: const Key('family-notice-open'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                notice.title ?? notice.kindWords(context.l10n),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '${formatDate(notice.createdAt)} ${DateFormat('h:mm a').format(notice.createdAt)}',
                style: TextStyle(color: context.appColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 14),
              SelectableText(notice.body, style: const TextStyle(fontSize: 15, height: 1.45)),
              if (notice.attachments.isNotEmpty) ...[
                const SizedBox(height: 14),
                NoticeAttachmentChips(attachments: notice.attachments),
              ],
              // A notice that asks: Yes or No for each child it is about (F5).
              if (notice.reply != null) NoticeReplyPanel(notice: notice),
            ],
          ),
        ),
      ),
    );
  }
}

// -- School calendar ------------------------------------------------------------

class FamilyCalendarScreen extends ConsumerStatefulWidget {
  const FamilyCalendarScreen({super.key});

  @override
  ConsumerState<FamilyCalendarScreen> createState() => _FamilyCalendarScreenState();
}

class _FamilyCalendarScreenState extends ConsumerState<FamilyCalendarScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  /// The coming holidays into the phone's calendar, each over its own days
  /// (M8, 6.3).
  Future<void> _addHolidays(List<SchoolHoliday> holidays) async {
    final file = calendarFile([
      for (final holiday in holidays)
        CalendarItem.allDay(
          uid: 'holiday-${holiday.start.toIso8601String().substring(0, 10)}-${holiday.name.hashCode}',
          title: holiday.name,
          day: holiday.start,
          lastDay: holiday.end,
        ),
    ], name: context.l10n.familyHolidaysCalendarName);

    try {
      await ref.read(calendarHandOffProvider)(file, 'school-holidays.ics');
    } catch (error) {
      debugPrint('Sharing the holidays calendar failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.familyCalendarShareFailed)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = monthKey(_month);
    final calendar = ref.watch(schoolCalendarProvider(key));

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.familySchoolCalendar)),
      body: Column(
        children: [
          Row(
            children: [
              IconButton(
                key: const Key('family-calendar-back'),
                tooltip: context.l10n.familyPreviousMonth,
                onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  DateFormat('MMMM yyyy').format(_month),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                key: const Key('family-calendar-next'),
                tooltip: context.l10n.familyNextMonth,
                onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          Expanded(
            child: calendar.when(
              loading: () => const PlaceholderCards(count: 2),
              error: (error, _) => FamilyErrorView(
                error: error,
                onRetry: () => ref.read(schoolCalendarProvider(key).notifier).refresh(),
              ),
              data: (data) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  _HolidayList(
                    key: const Key('family-calendar-month'),
                    title: context.l10n.familyThisMonth,
                    holidays: data.holidays,
                    empty: context.l10n.familyNoHolidaysThisMonth,
                  ),
                  if (data.closedWeekdays.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    FamilyCard(
                      child: Row(
                        children: [
                          Icon(Icons.weekend_outlined, color: context.appColors.info),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              context.l10n.familyClosedEvery(
                                data.closedWeekdays
                                    .map((d) => context.l10n.familyWeekday(d))
                                    .join(context.l10n.familyAndJoin),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _HolidayList(
                    title: context.l10n.familyHolidaysComingUp,
                    holidays: data.upcoming,
                    empty: context.l10n.familyNoHolidaysPlanned,
                  ),
                  // The school's coming holidays into the phone's calendar (M8, 6.3).
                  if (data.upcoming.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const Key('family-holidays-calendar'),
                        onPressed: () => _addHolidays(data.upcoming),
                        icon: const Icon(Icons.event_available_rounded, size: 18),
                        label: Text(context.l10n.familyAddHolidaysToCalendar),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HolidayList extends StatelessWidget {
  const _HolidayList({super.key, required this.title, required this.holidays, required this.empty});

  final String title;
  final List<SchoolHoliday> holidays;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final muted = context.appColors.muted;

    return FamilyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeading(icon: Icons.celebration_outlined, title: title, colour: context.appColors.warning),
          const SizedBox(height: 8),
          if (holidays.isEmpty)
            Text(empty, style: TextStyle(color: muted))
          else
            for (final holiday in holidays)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(holiday.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    Text(
                      holiday.isOneDay
                          ? formatDate(holiday.start)
                          : '${formatDate(holiday.start)} - ${formatDate(holiday.end)}',
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

// -- Notifications ------------------------------------------------------------------

/// Which kinds of message come to this app. The school's own SMS and
/// WhatsApp are not these switches' business, and an emergency always comes.
class FamilyNotificationsScreen extends ConsumerWidget {
  const FamilyNotificationsScreen({super.key});

  static List<(String, String, String, IconData)> _kinds(AppLocalizations l10n) => [
    ('attendance', l10n.familyKindAttendance, l10n.familySwitchAttendanceSub, Icons.event_available_rounded),
    ('transport', l10n.familySchoolBus, l10n.familySwitchBusSub, Icons.directions_bus_rounded),
    ('fee', l10n.familyKindFees, l10n.familySwitchFeesSub, Icons.receipt_long_rounded),
    ('result', l10n.familyResults, l10n.familySwitchResultsSub, Icons.grade_rounded),
    ('notices', l10n.familyNotices, l10n.familySwitchNoticesSub, Icons.campaign_rounded),
    ('homework', l10n.familyHomework, l10n.familySwitchHomeworkSub, Icons.edit_note_rounded),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(familyNotificationSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.familyNotifications)),
      body: settings.when(
        loading: () => const PlaceholderCards(count: 2),
        error: (error, _) => FamilyErrorView(
          error: error,
          onRetry: () => ref.read(familyNotificationSettingsProvider.notifier).refresh(),
        ),
        data: (values) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FamilyCard(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  for (final (key, title, subtitle, icon) in _kinds(context.l10n))
                    SwitchListTile(
                      key: Key('family-switch-$key'),
                      secondary: Icon(icon),
                      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(subtitle),
                      value: values.valueOf(key),
                      onChanged: (value) => _set(context, ref, key, value),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FamilyCard(
              child: Row(
                children: [
                  Icon(Icons.priority_high_rounded, color: context.appColors.danger),
                  const SizedBox(width: 12),
                  Expanded(child: Text(context.l10n.familyEmergencyAlwaysComes)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _set(BuildContext context, WidgetRef ref, String key, bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await ref.read(familyNotificationSettingsProvider.notifier).set(key, value);
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l10n.familySaved), duration: const Duration(seconds: 1)));
    } on Failure catch (failure) {
      if (!context.mounted) return;
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(failure.localizedMessage(context))));
    }
  }
}
