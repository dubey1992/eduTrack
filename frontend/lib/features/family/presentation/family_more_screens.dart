import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../application/family_notifiers.dart';
import '../application/family_session_notifier.dart';
import '../data/models/family_account.dart';
import '../data/models/family_records.dart';
import 'widgets/family_widgets.dart';
import 'family_talk_screens.dart';

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
    // Only what the school uses: no Results row at a school without tests.
    final learning = [
      _MoreRow(
        key: const Key('family-more-absence-notes'),
        icon: Icons.edit_note_rounded,
        title: 'Absence notes',
        subtitle: 'Tell the school your child will be away',
        onTap: () => context.push('/absence-notes'),
      ),
      _MoreRow(
        key: const Key('family-more-call'),
        icon: Icons.phone_callback_rounded,
        title: 'Ask the school to call you',
        subtitle: 'The class teacher or the office rings you back',
        onTap: () => context.push('/call-requests'),
      ),
      if (features.results)
        _MoreRow(
          key: const Key('family-more-results'),
          icon: Icons.grade_rounded,
          title: 'Results',
          subtitle: 'Test marks and the progress report',
          onTap: () => context.push('/results'),
        ),
      if (features.timetable)
        _MoreRow(
          key: const Key('family-more-timetable'),
          icon: Icons.schedule_rounded,
          title: 'Timetable',
          subtitle: "The class's week",
          onTap: () => context.push('/timetable'),
        ),
      if (features.syllabus)
        _MoreRow(
          key: const Key('family-more-syllabus'),
          icon: Icons.menu_book_rounded,
          title: 'Syllabus',
          subtitle: 'How far each subject has got',
          onTap: () => context.push('/syllabus'),
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
                title: 'Notices',
                subtitle: unread > 0 ? '$unread new' : 'Messages from the school',
                onTap: () => context.push('/notices'),
              ),
              _MoreRow(
                key: const Key('family-more-calendar'),
                icon: Icons.calendar_month_rounded,
                title: 'School calendar',
                subtitle: 'Holidays and closed days',
                onTap: () => context.push('/calendar'),
              ),
              _MoreRow(
                key: const Key('family-more-notifications'),
                icon: Icons.notifications_active_outlined,
                title: 'Notifications',
                subtitle: 'Choose what comes to this app',
                onTap: () => context.push('/notifications'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (account != null) _ContactCard(account: account),
        const SizedBox(height: 12),
        FamilyCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: _MoreRow(
            key: const Key('family-sign-out'),
            icon: Icons.logout_rounded,
            title: 'Sign out',
            subtitle: 'This phone stays set up; sign in again with your passcode',
            onTap: () async {
              final sure = await confirmDialog(
                context,
                title: 'Sign out?',
                message: 'You will need your passcode to sign in again.',
                confirmLabel: 'Sign out',
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
      messenger.showSnackBar(const SnackBar(content: Text('This phone could not open that. Please try another way.')));
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
          const CardHeading(icon: Icons.support_agent_rounded, title: 'Contact the school'),
          const SizedBox(height: 6),
          Text(account.schoolName, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (account.schoolAddress != null)
            Text(account.schoolAddress!, style: TextStyle(color: context.appColors.muted, fontSize: 13)),
          const SizedBox(height: 12),
          if (phone == null && email == null)
            Text('The school has not added its contact details yet.', style: TextStyle(color: context.appColors.muted))
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
                    label: const Text('Call'),
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
                    label: const Text('Email'),
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
        title: const Text('Notices'),
        actions: [
          if (unread > 0)
            TextButton(
              key: const Key('family-read-all'),
              onPressed: () => _readAll(context, ref),
              child: const Text('Mark all read'),
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
                  children: const [
                    SizedBox(height: 80),
                    FamilyEmptyView(
                      icon: Icons.mark_email_read_outlined,
                      title: 'No notices yet',
                      message: 'Messages from the school will appear here.',
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
                    itemCount: state.notices.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => _NoticeTile(notice: state.notices[index]),
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
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
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
                  notice.title ?? notice.kindLabel,
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
              Text(notice.title ?? notice.kindLabel, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                '${formatDate(notice.createdAt)} ${DateFormat('h:mm a').format(notice.createdAt)}',
                style: TextStyle(color: context.appColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 14),
              SelectableText(notice.body, style: const TextStyle(fontSize: 15, height: 1.45)),
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

  @override
  Widget build(BuildContext context) {
    final key = monthKey(_month);
    final calendar = ref.watch(schoolCalendarProvider(key));

    return Scaffold(
      appBar: AppBar(title: const Text('School calendar')),
      body: Column(
        children: [
          Row(
            children: [
              IconButton(
                key: const Key('family-calendar-back'),
                tooltip: 'Previous month',
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
                tooltip: 'Next month',
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
                    title: 'This month',
                    holidays: data.holidays,
                    empty: 'No holidays this month.',
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
                              'The school is closed every '
                              '${data.closedWeekdays.map((d) => '${d[0].toUpperCase()}${d.substring(1)}').join(' and ')}.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _HolidayList(title: 'Coming up', holidays: data.upcoming, empty: 'No holidays planned yet.'),
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

  static const _kinds = [
    ('attendance', 'Attendance', 'Absent, or on leave', Icons.event_available_rounded),
    ('transport', 'School bus', 'Boarded, dropped, did not take the bus', Icons.directions_bus_rounded),
    ('fee', 'Fees', 'Reminders and receipts', Icons.receipt_long_rounded),
    ('result', 'Results', 'When a test result is published', Icons.grade_rounded),
    ('notices', 'Notices', 'Announcements and messages from the school', Icons.campaign_rounded),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(familyNotificationSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
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
                  for (final (key, title, subtitle, icon) in _kinds)
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
                  const Expanded(child: Text('Emergency messages from the school always come through.')),
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
    try {
      await ref.read(familyNotificationSettingsProvider.notifier).set(key, value);
      messenger
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Saved.'), duration: Duration(seconds: 1)));
    } on Failure catch (failure) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }
}
