import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/chart_palette.dart';
import '../../../../core/utils/date_format.dart';
import '../../../auth/data/models/authenticated_user.dart';
import '../../../reports/application/report_link.dart';
import '../../../reports/data/models/report.dart';
import '../../data/models/dashboard.dart';
import '../dashboard_links.dart';

/// The dashboard's added panels (docs/dashboard.md): one-click jobs, today's
/// money per person who took it, and this month's messages.

/// A titled block with an optional action on the right.
class DashboardPanel extends StatelessWidget {
  const DashboardPanel({super.key, required this.title, required this.child, this.subtitle, this.action});

  final String title;
  final String? subtitle;
  final Widget? action;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    if (subtitle != null)
                      Text(subtitle!, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
                ?action,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// The jobs an office does every day, each one click away. Only those the
/// person may open are shown; nothing at all when none is left.
class QuickActionsPanel extends StatelessWidget {
  const QuickActionsPanel({super.key, required this.user, required this.today, this.schoolId});

  final AuthenticatedUser? user;
  final DateTime today;

  /// The school picked in the dashboard's filter, carried into the reports.
  final int? schoolId;

  @override
  Widget build(BuildContext context) {
    final actions = quickActionsFor(user, today, schoolId: schoolId);
    if (actions.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return DashboardPanel(
      key: const Key('dashboard-quick-actions'),
      title: 'Quick actions',
      child: LayoutBuilder(
        builder: (context, constraints) {
          // A row of tiles where there is room; one full-width tile per line
          // on a phone, rather than a narrow column with a gap beside it.
          final tileWidth = constraints.maxWidth < 480 ? constraints.maxWidth : 220.0;

          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final action in actions)
                SizedBox(
                  width: tileWidth,
                  child: Material(
                    color: ChartPalette.hueFor('quick-${action.key}').soft(context),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      key: Key('quick-action-${action.key}'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => context.go(action.link.location),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(action.icon, color: ChartPalette.hueFor('quick-${action.key}').strong(context)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(action.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  Text(action.hint, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Today's fee receipts per person who took them: the fee collection
/// report's own grouping over today, so the two agree to the paisa. Each
/// line opens the report narrowed to that person.
class CollectionsTodayPanel extends StatelessWidget {
  const CollectionsTodayPanel({super.key, required this.collections, this.schoolId});

  final CollectionsToday collections;

  /// The school picked in the dashboard's filter, carried into the report.
  final int? schoolId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final day = DateTime.parse(collections.date);
    final anyCredit = collections.byStaff.any((line) => line.hasCredit);
    final report = ReportLink(kind: ReportKind.feeCollection, schoolId: schoolId, from: day, to: day);

    return DashboardPanel(
      key: const Key('dashboard-collections-today'),
      title: 'Collected today, by person',
      subtitle:
          '${formatDate(day)} - ${collections.collected.join(' + ')} in '
          '${collections.receipts} receipt${collections.receipts == 1 ? '' : 's'}'
          '${collections.cancelledReceipts > 0 ? ', ${collections.cancelledReceipts} cancelled not counted' : ''}',
      action: TextButton.icon(
        key: const Key('collections-open-report'),
        onPressed: () => context.go(report.location),
        icon: const Icon(Icons.open_in_new, size: 16),
        label: const Text('Open report'),
      ),
      child: collections.byStaff.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('No fees have been collected yet today.', style: TextStyle(color: scheme.onSurfaceVariant)),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final line in collections.byStaff) _StaffLine(line: line, day: day, schoolId: schoolId),
                if (anyCredit) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Held as credit is part of the amount: money a family paid ahead of what they owe, '
                    'kept against their next fees.',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
    );
  }
}

class _StaffLine extends StatelessWidget {
  const _StaffLine({required this.line, required this.day, this.schoolId});

  final StaffCollection line;
  final DateTime day;
  final int? schoolId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final id = line.receivedById;
    final details = [
      '${line.receipts} receipt${line.receipts == 1 ? '' : 's'}',
      'cash ${line.cash}',
      if (line.hasCredit) 'held as credit ${line.credit}',
    ].join(' - ');

    return ListTile(
      key: Key('collections-person-${id ?? 'unknown'}'),
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: ChartPalette.hueFor(line.receivedBy).soft(context),
        child: Text(
          line.receivedBy.isEmpty ? '?' : line.receivedBy.characters.first.toUpperCase(),
          style: TextStyle(color: ChartPalette.hueFor(line.receivedBy).strong(context), fontWeight: FontWeight.w700),
        ),
      ),
      title: Text(line.receivedBy, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(details, style: TextStyle(color: scheme.onSurfaceVariant)),
      trailing: Text(line.amount, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      // Receipts from before the app kept who took them cannot be narrowed to.
      onTap: id == null
          ? null
          : () => context.go(
              ReportLink(
                kind: ReportKind.feeCollection,
                schoolId: schoolId,
                from: day,
                to: day,
                receivedBy: id,
                receivedByName: line.receivedBy,
              ).location,
            ),
    );
  }
}

/// This month's SMS and WhatsApp, by the statuses the message log keeps.
/// No "delivered" figure: no provider reports delivery back yet, and saying
/// "delivered" of a message a provider merely accepted would be untrue.
class MessagesPanel extends StatelessWidget {
  const MessagesPanel({super.key, required this.messages, required this.user});

  final MessagesThisMonth messages;
  final AuthenticatedUser? user;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colours = context.appColors;
    final total = messages.total;
    const log = DashboardLink('/communication');

    return DashboardPanel(
      key: const Key('dashboard-messages'),
      title: 'SMS & WhatsApp - ${messages.month}',
      subtitle: '${total.all} message${total.all == 1 ? '' : 's'}, ${messages.feeRelated} about fees',
      action: log.allowedFor(user)
          ? TextButton.icon(
              key: const Key('messages-open-log'),
              onPressed: () => context.go(log.location),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Message log'),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Count(label: 'Sent to provider', value: total.sent, colour: colours.info),
              if (messages.deliveryReported) ...[
                _Count(label: 'Delivered', value: total.delivered, colour: colours.success),
                _Count(label: 'Not delivered', value: total.undelivered, colour: colours.danger),
              ],
              _Count(label: 'Waiting to send', value: total.queued, colour: colours.warning),
              _Count(label: 'Failed', value: total.failed, colour: colours.danger),
              _Count(label: 'Not sent', value: total.skipped, colour: scheme.onSurfaceVariant),
            ],
          ),
          const SizedBox(height: 10),
          for (final channel in messages.channels)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                messages.deliveryReported
                    ? '${channel.label}: ${channel.sent} sent (${channel.delivered} delivered, '
                          '${channel.undelivered} not delivered), ${channel.queued} waiting, '
                          '${channel.failed} failed, ${channel.skipped} not sent'
                    : '${channel.label}: ${channel.sent} sent, ${channel.queued} waiting, '
                          '${channel.failed} failed, ${channel.skipped} not sent',
                key: Key('messages-channel-${channel.channel}'),
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            switch ((messages.deliveryReported, messages.providerDelivers)) {
              (true, _) =>
                'Delivered and not delivered are what the phone network reported back. A sent message with no '
                    'report yet is in neither. "Not sent" is usually a missing phone number.',
              (false, true) =>
                '"Sent" means the provider accepted the message. Delivery to the phone is not reported back. '
                    '"Not sent" is usually a missing phone number.',
              (false, false) => 'No SMS provider that delivers is set up yet, so SMS counted here do not reach phones.',
            },
            key: const Key('messages-delivery-note'),
            style: TextStyle(fontSize: 12, color: messages.providerDelivers ? scheme.onSurfaceVariant : colours.danger),
          ),
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value, required this.colour});

  final String label;
  final int value;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: 130,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          Text(
            '$value',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: value == 0 ? scheme.onSurface : colour),
          ),
        ],
      ),
    );
  }
}
