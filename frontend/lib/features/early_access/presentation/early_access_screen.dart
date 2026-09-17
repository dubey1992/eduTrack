import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/network/paged_list.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/horizontal_scroll_table.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_badge.dart';
import '../application/early_access_notifier.dart';
import '../data/models/early_access_request.dart';
import 'early_access_detail_dialog.dart';

/// Schools that have asked to be let in.
///
/// A queue rather than a record: newest first, and the thing nobody has
/// looked at yet is the thing that matters. See docs/early-access.md.
class EarlyAccessScreen extends ConsumerStatefulWidget {
  const EarlyAccessScreen({super.key});

  @override
  ConsumerState<EarlyAccessScreen> createState() => _EarlyAccessScreenState();
}

class _EarlyAccessScreenState extends ConsumerState<EarlyAccessScreen> {
  final _searchController = TextEditingController();
  EarlyAccessStatus? _status;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final requestsState = ref.watch(earlyAccessNotifierProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Early Access Requests',
          actions: [
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<EarlyAccessStatus?>(
                initialValue: _status,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Status', isDense: true),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All requests')),
                  for (final status in EarlyAccessStatus.values)
                    DropdownMenuItem(value: status, child: Text(status.label)),
                ],
                onChanged: (value) {
                  setState(() => _status = value);
                  ref.read(earlyAccessNotifierProvider.notifier).setStatus(value);
                },
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SizedBox(
            width: 280,
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search school, contact or email',
                prefixIcon: Icon(Icons.search, size: 20),
                isDense: true,
              ),
              onSubmitted: (value) => ref.read(earlyAccessNotifierProvider.notifier).search(value.trim()),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: AsyncValueView<PagedList<EarlyAccessRequest>>(
            value: requestsState,
            onRetry: () => ref.read(earlyAccessNotifierProvider.notifier).refresh(),
            isEmpty: (page) => page.items.isEmpty,
            emptyBuilder: (context) => const Center(child: Text('No schools have asked for access yet.')),
            data: (context, page) {
              return Column(
                children: [
                  Expanded(
                    child: ResponsiveBuilder(
                      mobile: (context) => _RequestCards(requests: page.items),
                      desktop: (context) => _RequestTable(requests: page.items),
                    ),
                  ),
                  PaginationControls(
                    currentPage: page.currentPage,
                    lastPage: page.lastPage,
                    total: page.total,
                    perPage: page.perPage,
                    onPageChanged: (p) => ref.read(earlyAccessNotifierProvider.notifier).goToPage(p),
                    onPerPageChanged: (p) => ref.read(earlyAccessNotifierProvider.notifier).setPerPage(p),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class EarlyAccessStatusBadge extends StatelessWidget {
  const EarlyAccessStatusBadge({super.key, required this.status});

  final EarlyAccessStatus status;

  @override
  Widget build(BuildContext context) {
    return StatusBadge(
      label: status.label,
      tone: switch (status) {
        EarlyAccessStatus.newRequest => BadgeTone.info,
        EarlyAccessStatus.contacted => BadgeTone.warning,
        EarlyAccessStatus.converted => BadgeTone.success,
        EarlyAccessStatus.declined => BadgeTone.neutral,
      },
    );
  }
}

class _RequestTable extends StatelessWidget {
  const _RequestTable({required this.requests});

  final List<EarlyAccessRequest> requests;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: HorizontalScrollTable(
        child: DataTable(
          columnSpacing: 22,
          horizontalMargin: 20,
          columns: const [
            DataColumn(label: Text('School')),
            DataColumn(label: Text('Contact')),
            DataColumn(label: Text('Location')),
            DataColumn(label: Text('Students'), numeric: true),
            DataColumn(label: Text('Received')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Action')),
          ],
          rows: [
            for (final request in requests)
              DataRow(
                cells: [
                  DataCell(Text(request.schoolName)),
                  DataCell(Text('${request.contactName}\n${request.email}')),
                  DataCell(Text(request.location)),
                  // A dash, not a zero: not knowing is different from none.
                  DataCell(Text(request.expectedStudents?.toString() ?? '-')),
                  DataCell(Text(request.submittedAt)),
                  DataCell(EarlyAccessStatusBadge(status: request.status)),
                  DataCell(
                    TextButton(onPressed: () => showEarlyAccessDetail(context, request), child: const Text('View')),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _RequestCards extends StatelessWidget {
  const _RequestCards({required this.requests});

  final List<EarlyAccessRequest> requests;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: requests.length,
      itemBuilder: (context, index) {
        final request = requests[index];

        return Card(
          child: ListTile(
            title: Text(request.schoolName),
            subtitle: Text('${request.contactName} - ${request.location}\n${request.submittedAt}'),
            isThreeLine: true,
            trailing: EarlyAccessStatusBadge(status: request.status),
            onTap: () => showEarlyAccessDetail(context, request),
          ),
        );
      },
    );
  }
}

/// Runs [action] and reports through a messenger captured before the await,
/// since the list re-fetches and may unmount the calling row.
Future<void> runAndReport(
  BuildContext context, {
  required String successMessage,
  required Future<void> Function() action,
}) async {
  final messenger = ScaffoldMessenger.of(context);

  try {
    await action();
    messenger.showSnackBar(SnackBar(content: Text(successMessage)));
  } catch (error) {
    final failure = error is Failure ? error : Failure.unknown(error.toString());
    messenger.showSnackBar(SnackBar(content: Text(failure.message)));
  }
}
