import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../application/route_students_notifier.dart';
import '../data/models/transport_route.dart';

/// "Students on Bus" for one route, in stop order.
class RouteStudentsDialog extends ConsumerWidget {
  const RouteStudentsDialog({super.key, required this.route});

  final TransportRoute route;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentsState = ref.watch(routeStudentsProvider(route.id));
    final muted = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);

    return AlertDialog(
      title: Text('Students · ${route.label}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 520, maxWidth: 520, maxHeight: 480),
        child: AsyncValueView<PagedList<RouteStudent>>(
          value: studentsState,
          onRetry: () => ref.read(routeStudentsProvider(route.id).notifier).refresh(),
          isEmpty: (page) => page.items.isEmpty,
          emptyBuilder: (context) =>
              const Padding(padding: EdgeInsets.all(16), child: Text('No students are assigned to this route yet.')),
          data: (context, page) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final rider in page.items)
                    ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 14,
                        child: Text('${rider.stopSequenceNumber}', style: const TextStyle(fontSize: 12)),
                      ),
                      title: Text('${rider.admissionNumber} · ${rider.name}'),
                      subtitle: Text(
                        '${rider.stopName} · ${rider.classSectionName ?? '-'} · ${rider.guardianName}'
                        '${rider.guardianMobile == null ? '' : ' (${rider.guardianMobile})'}',
                        style: muted,
                      ),
                    ),
                  PaginationControls(
                    currentPage: page.currentPage,
                    lastPage: page.lastPage,
                    total: page.total,
                    perPage: page.perPage,
                    onPageChanged: (p) => ref.read(routeStudentsProvider(route.id).notifier).goToPage(p),
                    onPerPageChanged: (p) => ref.read(routeStudentsProvider(route.id).notifier).setPerPage(p),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done'))],
    );
  }
}
