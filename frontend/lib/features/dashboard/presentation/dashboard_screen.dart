import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/user_role.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/school_filter_dropdown.dart';
import '../../auth/application/auth_notifier.dart';
import '../application/dashboard_notifier.dart';
import '../data/models/dashboard.dart';
import 'widgets/attendance_trend_chart.dart';

/// Phase 18 - the landing screen: the figures for whoever is looking, what
/// wants attention, and the way through to the reports behind them.
///
/// The server decides which cards a role gets, so this screen renders what
/// arrives rather than branching six ways.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int? _schoolId;

  @override
  void initState() {
    super.initState();
    // These figures describe today, and the day moves on while a tab is
    // left open, so re-entering the screen re-reads them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Only on re-entry: on the first build the provider is already loading.
      if (mounted && ref.read(dashboardNotifierProvider) is AsyncData) {
        ref.read(dashboardNotifierProvider.notifier).refresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authNotifierProvider).value;
    final notifier = ref.watch(dashboardNotifierProvider.notifier);
    final state = ref.watch(dashboardNotifierProvider);

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
              Text(
                user == null ? 'Dashboard' : 'Welcome, ${user.name}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SchoolFilterDropdown(
                    selected: _schoolId,
                    onChanged: (schoolId) {
                      setState(() => _schoolId = schoolId);
                      notifier.setSchoolFilter(schoolId);
                    },
                  ),
                  OutlinedButton.icon(
                    onPressed: notifier.refresh,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          AsyncValueView<Dashboard>(
            value: state,
            onRetry: notifier.refresh,
            data: (context, dashboard) => _DashboardBody(dashboard: dashboard, role: user?.role),
          ),
        ],
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.dashboard, required this.role});

  final Dashboard dashboard;
  final UserRole? role;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Only when a school is actually in scope. Looking across every
        // school there is no single set of opening hours to be closed, and
        // saying "the school is closed" of all seven at once is nonsense.
        if (!dashboard.isWorkingDay && dashboard.schoolId != null) _ClosedBanner(dashboard: dashboard),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final card in dashboard.cards) _StatCard(card: card),
          ],
        ),
        if (dashboard.attention.isNotEmpty) ...[
          const SizedBox(height: 16),
          _AttentionList(notes: dashboard.attention),
        ],
        if (dashboard.attendanceTrend.isNotEmpty) ...[
          const SizedBox(height: 16),
          AttendanceTrendChart(points: dashboard.attendanceTrend),
        ],
        const SizedBox(height: 16),
        _ReportsLink(role: role),
      ],
    );
  }
}

/// Says the school is shut today, so "nothing marked" reads as expected
/// rather than as something somebody forgot.
class _ClosedBanner extends StatelessWidget {
  const _ClosedBanner({required this.dashboard});

  final Dashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: scheme.secondaryContainer,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.event_busy_outlined, color: scheme.onSecondaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  dashboard.holiday == null
                      ? 'The school is closed today - attendance and trips are not expected.'
                      : '${dashboard.holiday} - the school is closed today, so nothing is due to be marked.',
                  style: TextStyle(color: scheme.onSecondaryContainer, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.card});

  final DashboardCard card;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 240,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(card.label, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              Text(
                card.value,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: card.isWarning ? scheme.error : scheme.onSurface,
                ),
              ),
              if (card.hint != null) ...[
                const SizedBox(height: 4),
                Text(card.hint!, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AttentionList extends StatelessWidget {
  const _AttentionList({required this.notes});

  final List<AttentionNote> notes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Needs attention', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final note in notes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, size: 18, color: scheme.error),
                    const SizedBox(width: 8),
                    Expanded(child: Text(note.message)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReportsLink extends StatelessWidget {
  const _ReportsLink({required this.role});

  final UserRole? role;

  static const _withReports = {
    UserRole.superAdmin,
    UserRole.schoolAdmin,
    UserRole.hod,
    UserRole.transportManager,
  };

  @override
  Widget build(BuildContext context) {
    if (!_withReports.contains(role)) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.icon(
        onPressed: () => context.go('/reports'),
        icon: const Icon(Icons.insights_outlined, size: 18),
        label: const Text('Open reports'),
      ),
    );
  }
}
