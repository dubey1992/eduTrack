import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/failure.dart';
import '../../../core/models/user_role.dart';
import '../../../core/network/paged_list.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/horizontal_scroll_table.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/school_filter_dropdown.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/utils/school_clock.dart';
import '../../auth/application/auth_notifier.dart';
import '../../auth/application/school_clock_provider.dart';
import '../application/message_page_notifier.dart';
import '../data/models/message.dart';
import 'communication_settings_dialog.dart';
import 'message_detail_dialog.dart';
import 'widgets/demo_gateway_notice.dart';
import 'message_templates_dialog.dart';

/// Phase 16 - the prototype's "Communication Center": today's KPI tiles, the
/// message log with its category tabs, the template manager and the school's
/// alert switches.
class CommunicationScreen extends ConsumerStatefulWidget {
  const CommunicationScreen({super.key});

  @override
  ConsumerState<CommunicationScreen> createState() => _CommunicationScreenState();
}

class _CommunicationScreenState extends ConsumerState<CommunicationScreen> {
  int? _schoolId;
  MessageStatus? _status;
  MessageChannel? _channel;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Messages arrive from attendance, transport and leave while this screen
    // is closed, so re-entering it re-reads rather than showing the last
    // visit's list.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Only on re-entry: on the very first build the provider is already
      // loading, and refreshing then would fetch the same page twice.
      if (mounted && ref.read(messagePageNotifierProvider) is AsyncData) {
        ref.read(messagePageNotifierProvider.notifier).refresh();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _applyFilters() async {
    await ref
        .read(messagePageNotifierProvider.notifier)
        .setFilters(channel: _channel, status: _status, search: _searchController.text);
  }

  @override
  Widget build(BuildContext context) {
    final actor = ref.watch(authNotifierProvider).value;
    if (actor == null) return const SizedBox.shrink();

    final needsSchool = actor.role == UserRole.superAdmin && _schoolId == null;
    final messagesState = ref.watch(messagePageNotifierProvider);
    final selectedCategory = ref.watch(messagePageNotifierProvider.notifier).category;

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
              Text('Communication Center', style: Theme.of(context).textTheme.headlineSmall),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SchoolFilterDropdown(
                    selected: _schoolId,
                    onChanged: (schoolId) {
                      setState(() => _schoolId = schoolId);
                      ref.read(messagePageNotifierProvider.notifier).setSchoolFilter(schoolId);
                    },
                  ),
                  OutlinedButton.icon(
                    onPressed: needsSchool
                        ? null
                        : () => showDialog<void>(
                            context: context,
                            builder: (_) => MessageTemplatesDialog(schoolId: _schoolId),
                          ),
                    icon: const Icon(Icons.description_outlined, size: 18),
                    label: const Text('Message Templates'),
                  ),
                  FilledButton.icon(
                    onPressed: needsSchool
                        ? null
                        : () => showDialog<void>(
                            context: context,
                            builder: (_) => CommunicationSettingsDialog(schoolId: _schoolId),
                          ),
                    icon: const Icon(Icons.settings_outlined, size: 18),
                    label: const Text('Alert Settings'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'SMS, alerts and announcements.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          if (needsSchool)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('Pick a school to see its messages.')),
              ),
            )
          else ...[
            DemoGatewayNotice(schoolId: _schoolId),
            _SummaryTiles(schoolId: _schoolId),
            const SizedBox(height: 16),
            _CategoryTabs(
              selected: selectedCategory,
              onChanged: (category) => ref.read(messagePageNotifierProvider.notifier).setCategory(category),
            ),
            const SizedBox(height: 12),
            _FilterBar(
              status: _status,
              channel: _channel,
              searchController: _searchController,
              onStatusChanged: (status) {
                setState(() => _status = status);
                _applyFilters();
              },
              onChannelChanged: (channel) {
                setState(() => _channel = channel);
                _applyFilters();
              },
              onSearch: _applyFilters,
            ),
            const SizedBox(height: 12),
            AsyncValueView<PagedList<Message>>(
              value: messagesState,
              onRetry: () => ref.read(messagePageNotifierProvider.notifier).refresh(),
              data: (context, page) => _MessageLog(
                page: page,
                filtered:
                    selectedCategory != null ||
                    _status != null ||
                    _channel != null ||
                    _searchController.text.trim().isNotEmpty,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryTiles extends ConsumerWidget {
  const _SummaryTiles({required this.schoolId});

  final int? schoolId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryState = ref.watch(messageSummaryProvider(schoolId));

    return AsyncValueView<MessageSummary>(
      value: summaryState,
      onRetry: () => ref.invalidate(messageSummaryProvider(schoolId)),
      data: (context, summary) => Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          KpiCard(label: 'SMS Sent Today', value: '${summary.smsSentToday}'),
          KpiCard(
            label: 'Delivery Rate',
            value: summary.deliveryRate == null ? '-' : '${summary.deliveryRate!.toStringAsFixed(1)}%',
          ),
          KpiCard(label: 'Failed', value: '${summary.failedToday}'),
          KpiCard(label: 'Queued', value: '${summary.queuedToday}'),
        ],
      ),
    );
  }
}

/// The prototype's All / Attendance / Transport / Announcements strip, with
/// Leave added since leave decisions now send messages too.
class _CategoryTabs extends StatelessWidget {
  const _CategoryTabs({required this.selected, required this.onChanged});

  final MessageCategory? selected;
  final ValueChanged<MessageCategory?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(label: const Text('All'), selected: selected == null, onSelected: (_) => onChanged(null)),
        for (final category in MessageCategory.values)
          ChoiceChip(
            label: Text(category.label),
            selected: selected == category,
            onSelected: (_) => onChanged(category),
          ),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.status,
    required this.channel,
    required this.searchController,
    required this.onStatusChanged,
    required this.onChannelChanged,
    required this.onSearch,
  });

  final MessageStatus? status;
  final MessageChannel? channel;
  final TextEditingController searchController;
  final ValueChanged<MessageStatus?> onStatusChanged;
  final ValueChanged<MessageChannel?> onChannelChanged;
  final VoidCallback onSearch;

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
              width: 180,
              child: DropdownButtonFormField<MessageStatus?>(
                initialValue: status,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [
                  const DropdownMenuItem<MessageStatus?>(child: Text('Any status')),
                  for (final value in MessageStatus.values)
                    DropdownMenuItem<MessageStatus?>(value: value, child: Text(value.label)),
                ],
                onChanged: onStatusChanged,
              ),
            ),
            SizedBox(
              width: 160,
              child: DropdownButtonFormField<MessageChannel?>(
                initialValue: channel,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Channel'),
                items: [
                  const DropdownMenuItem<MessageChannel?>(child: Text('Any channel')),
                  for (final value in MessageChannel.values)
                    DropdownMenuItem<MessageChannel?>(value: value, child: Text(value.label)),
                ],
                onChanged: onChannelChanged,
              ),
            ),
            SizedBox(
              width: 260,
              child: TextField(
                controller: searchController,
                decoration: InputDecoration(
                  labelText: 'Search recipient, student or text',
                  suffixIcon: IconButton(tooltip: 'Search', icon: const Icon(Icons.search), onPressed: onSearch),
                ),
                onSubmitted: (_) => onSearch(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageLog extends ConsumerWidget {
  const _MessageLog({required this.page, required this.filtered});

  final PagedList<Message> page;

  /// Whether any filter is on, so an empty log reads correctly either way.
  final bool filtered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (page.items.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(child: Text(filtered ? 'No messages match these filters.' : 'No messages have been sent yet.')),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResponsiveBuilder(
          mobile: (context) => _MessageCards(messages: page.items),
          desktop: (context) => _MessageTable(messages: page.items),
        ),
        const SizedBox(height: 12),
        PaginationControls(
          currentPage: page.currentPage,
          lastPage: page.lastPage,
          total: page.total,
          perPage: page.perPage,
          onPageChanged: (value) => ref.read(messagePageNotifierProvider.notifier).goToPage(value),
          onPerPageChanged: (value) => ref.read(messagePageNotifierProvider.notifier).setPerPage(value),
        ),
      ],
    );
  }
}

class _MessageTable extends ConsumerWidget {
  const _MessageTable({required this.messages});

  final List<Message> messages;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clock = ref.watch(schoolClockProvider);

    return Card(
      child: HorizontalScrollTable(
        child: DataTable(
          // Tight spacing keeps every column - Actions included - on screen at
          // 1400px; the full message text is a tap away in the detail dialog.
          columnSpacing: 20,
          horizontalMargin: 12,
          columns: const [
            DataColumn(label: Text('Time')),
            DataColumn(label: Text('Recipient')),
            DataColumn(label: Text('Student')),
            DataColumn(label: Text('Type')),
            DataColumn(label: Text('Message')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Actions')),
          ],
          rows: [
            for (final message in messages)
              DataRow(
                cells: [
                  DataCell(Text(messageTimeOf(message, clock))),
                  DataCell(Text(message.recipientName)),
                  DataCell(Text(message.studentName ?? '-')),
                  DataCell(Text(message.category.label)),
                  DataCell(
                    ConstrainedBox(
                      // Narrow enough that Status and Actions stay on screen at
                      // 1400px - the full text is a tap away in the detail dialog.
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Text(message.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  DataCell(MessageStatusBadge(status: message.status)),
                  DataCell(_RowActions(message: message)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _MessageCards extends StatelessWidget {
  const _MessageCards({required this.messages});

  final List<Message> messages;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final message in messages)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message.recipientName, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    '${message.category.label} · ${formatMessageTime(message.createdOnLabel, message.createdAtLabel)}'
                    '${message.studentName == null ? '' : ' · ${message.studentName}'}',
                    style: muted,
                  ),
                  const SizedBox(height: 6),
                  Text(message.body, maxLines: 3, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      MessageStatusBadge(status: message.status),
                      _RowActions(message: message),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _RowActions extends ConsumerStatefulWidget {
  const _RowActions({required this.message});

  final Message message;

  @override
  ConsumerState<_RowActions> createState() => _RowActionsState();
}

class _RowActionsState extends ConsumerState<_RowActions> {
  bool _busy = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await ref.read(messagePageNotifierProvider.notifier).retry(widget.message);
      messenger
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Message queued to send again.')));
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => MessageDetailDialog(message: widget.message),
          ),
          child: const Text('View'),
        ),
        if (widget.message.isRetryable) ...[
          const SizedBox(width: 4),
          FilledButton(onPressed: _busy ? null : _retry, child: const Text('Send again')),
        ],
      ],
    );
  }
}

class MessageStatusBadge extends StatelessWidget {
  const MessageStatusBadge({super.key, required this.status});

  final MessageStatus status;

  @override
  Widget build(BuildContext context) {
    final tone = switch (status) {
      MessageStatus.sent => BadgeTone.success,
      MessageStatus.failed => BadgeTone.danger,
      MessageStatus.queued => BadgeTone.info,
      MessageStatus.skipped => BadgeTone.neutral,
    };

    return StatusBadge(label: status.label, tone: tone);
  }
}

/// The time the server rendered, which is the one written inside the message
/// itself, so the log and the text a parent received never disagree.
///
/// [clock] decides what counts as "today": today at the school, which is not
/// necessarily today in the browser.
String messageTimeOf(Message message, SchoolClock clock) {
  if (message.createdAtLabel == null) return formatMessageTime(message.createdOnLabel, message.createdAtLabel);

  final sentToday = message.createdOnLabel == DateFormat('d MMM y').format(clock.today);

  return sentToday ? message.createdAtLabel! : '\${message.createdOnLabel}, \${message.createdAtLabel}';
}

/// Joins the server's date and time labels, for the places that show both.
///
/// Never parses the raw UTC timestamp: the browser would render it in its own
/// timezone and quietly disagree with every other time on the screen.
String formatMessageTime(String? dateLabel, String? timeLabel) {
  if (timeLabel == null) return '-';

  return dateLabel == null ? timeLabel : '\$dateLabel, \$timeLabel';
}
