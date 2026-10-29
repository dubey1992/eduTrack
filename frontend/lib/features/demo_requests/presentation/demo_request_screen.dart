import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/horizontal_scroll_table.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_badge.dart';
import '../application/demo_request_notifier.dart';
import '../data/models/demo_request.dart';
import 'demo_request_detail_dialog.dart';

/// Schools that have asked to be shown the product.
///
/// A queue, like Early Access: newest first. What matters most on each row is
/// when they want the demo, so that leads.
class DemoRequestScreen extends ConsumerStatefulWidget {
  const DemoRequestScreen({super.key});

  @override
  ConsumerState<DemoRequestScreen> createState() => _DemoRequestScreenState();
}

class _DemoRequestScreenState extends ConsumerState<DemoRequestScreen> {
  final _searchController = TextEditingController();
  DemoRequestStatus? _status;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final requestsState = ref.watch(demoRequestNotifierProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Demo Requests',
          actions: [
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<DemoRequestStatus?>(
                initialValue: _status,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Status', isDense: true),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All requests')),
                  for (final status in DemoRequestStatus.values)
                    DropdownMenuItem(value: status, child: Text(status.label)),
                ],
                onChanged: (value) {
                  setState(() => _status = value);
                  ref.read(demoRequestNotifierProvider.notifier).setStatus(value);
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
              onSubmitted: (value) => ref.read(demoRequestNotifierProvider.notifier).search(value.trim()),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: AsyncValueView<PagedList<DemoRequest>>(
            value: requestsState,
            onRetry: () => ref.read(demoRequestNotifierProvider.notifier).refresh(),
            isEmpty: (page) => page.items.isEmpty,
            emptyBuilder: (context) => const Center(child: Text('No schools have asked for a demo yet.')),
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
                    onPageChanged: (p) => ref.read(demoRequestNotifierProvider.notifier).goToPage(p),
                    onPerPageChanged: (p) => ref.read(demoRequestNotifierProvider.notifier).setPerPage(p),
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

class DemoRequestStatusBadge extends StatelessWidget {
  const DemoRequestStatusBadge({super.key, required this.status});

  final DemoRequestStatus status;

  @override
  Widget build(BuildContext context) {
    return StatusBadge(
      label: status.label,
      tone: switch (status) {
        DemoRequestStatus.newRequest => BadgeTone.info,
        DemoRequestStatus.scheduled => BadgeTone.warning,
        DemoRequestStatus.done => BadgeTone.success,
        DemoRequestStatus.declined => BadgeTone.neutral,
      },
    );
  }
}

class _RequestTable extends StatelessWidget {
  const _RequestTable({required this.requests});

  final List<DemoRequest> requests;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: HorizontalScrollTable(
        child: DataTable(
          columnSpacing: 22,
          horizontalMargin: 20,
          columns: const [
            DataColumn(label: Text('Preferred slot')),
            DataColumn(label: Text('School')),
            DataColumn(label: Text('Contact')),
            DataColumn(label: Text('Students'), numeric: true),
            DataColumn(label: Text('Received')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Action')),
          ],
          rows: [
            for (final request in requests)
              DataRow(
                cells: [
                  // The date leads, in bold; the part of day and timezone sit
                  // under it so the column stays narrow.
                  DataCell(
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: request.preferredDateLabel,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (request.preferredTimeOfDay.isNotEmpty) TextSpan(text: '\n${request.preferredTimeOfDay}'),
                        ],
                      ),
                    ),
                  ),
                  // Where the school is sits under its name: the slot column is
                  // wide, and a column of its own pushed View off a laptop.
                  DataCell(Text('${request.schoolName}\n${request.location}')),
                  DataCell(Text('${request.contactName}\n${request.email}')),
                  // A dash, not a zero: not knowing is different from none.
                  DataCell(Text(request.expectedStudents?.toString() ?? '-')),
                  DataCell(Text(request.submittedAt)),
                  DataCell(DemoRequestStatusBadge(status: request.status)),
                  DataCell(
                    TextButton(onPressed: () => showDemoRequestDetail(context, request), child: const Text('View')),
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

  final List<DemoRequest> requests;

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
            subtitle: Text('${request.preferredSlot}\n${request.contactName} - ${request.location}'),
            isThreeLine: true,
            trailing: DemoRequestStatusBadge(status: request.status),
            onTap: () => showDemoRequestDetail(context, request),
          ),
        );
      },
    );
  }
}
