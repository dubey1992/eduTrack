import 'package:go_router/go_router.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/network/paged_list.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/horizontal_scroll_table.dart';
import '../application/school_list_notifier.dart';
import '../data/models/school.dart';
import 'add_school_dialog.dart';
import 'edit_school_dialog.dart';
import 'schools_map_view.dart';

class SchoolListScreen extends ConsumerStatefulWidget {
  const SchoolListScreen({super.key});

  @override
  ConsumerState<SchoolListScreen> createState() => _SchoolListScreenState();
}

class _SchoolListScreenState extends ConsumerState<SchoolListScreen> {
  /// The list is the default. The map answers "where are they", which is a
  /// question somebody asks occasionally; the list answers "which one",
  /// which is what this screen is opened for.
  bool _onTheMap = false;

  final _searchController = TextEditingController();
  String? _status;
  Timer? _typing;

  @override
  void dispose() {
    _typing?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Debounced: a request per keystroke would be a request per keystroke,
  /// and the answer somebody wants is the one for what they finished typing.
  void _search(String term) {
    setState(() {});
    _typing?.cancel();
    _typing = Timer(const Duration(milliseconds: 350), () {
      ref.read(schoolPageNotifierProvider.notifier).setFilters(q: term);
    });
  }

  @override
  Widget build(BuildContext context) {
    final schoolsState = ref.watch(schoolPageNotifierProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Schools',
          actions: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, icon: Icon(Icons.list, size: 18), label: Text('List')),
                ButtonSegment(value: true, icon: Icon(Icons.map_outlined, size: 18), label: Text('Map')),
              ],
              selected: {_onTheMap},
              onSelectionChanged: (choice) => setState(() => _onTheMap = choice.first),
            ),
            FilledButton.icon(
              onPressed: () => showDialog(context: context, builder: (_) => const AddSchoolDialog()),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add School'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            children: [
              SizedBox(
                width: 320,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Search schools',
                    hintText: 'Name, registration number, email or city',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            tooltip: 'Clear',
                            onPressed: () {
                              _searchController.clear();
                              _search('');
                            },
                          ),
                  ),
                  onChanged: _search,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String?>(
                  initialValue: _status,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Status', isDense: true),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('All')),
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                  ],
                  onChanged: (chosen) {
                    setState(() => _status = chosen);
                    ref.read(schoolPageNotifierProvider.notifier).setFilters(status: chosen, changeStatus: true);
                  },
                ),
              ),
            ],
          ),
        ),
        if (_onTheMap)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SchoolsMapView(onOpen: _open),
            ),
          )
        else
          Expanded(
            child: AsyncValueView<PagedList<School>>(
              value: schoolsState,
              onRetry: () => ref.read(schoolPageNotifierProvider.notifier).refresh(),
              isEmpty: (page) => page.items.isEmpty,
              emptyBuilder: (context) => const Center(child: Text('No schools yet.')),
              data: (context, page) {
                return Column(
                  children: [
                    Expanded(
                      child: ResponsiveBuilder(
                        mobile: (context) => _SchoolListMobile(schools: page.items),
                        desktop: (context) => _SchoolListDesktop(schools: page.items),
                      ),
                    ),
                    PaginationControls(
                      currentPage: page.currentPage,
                      lastPage: page.lastPage,
                      total: page.total,
                      perPage: page.perPage,
                      onPageChanged: (p) => ref.read(schoolPageNotifierProvider.notifier).goToPage(p),
                      onPerPageChanged: (p) => ref.read(schoolPageNotifierProvider.notifier).setPerPage(p),
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }

  /// Opening a school from the map. The same dialog the list opens, so a
  /// school placed from here is placed the way it is placed anywhere.
  /// A pin on the map opens the school's own page rather than the edit
  /// form. Somebody clicking a map is looking, not editing - and the page
  /// has an Edit button on it for when they are.
  void _open(int schoolId) => context.go('/schools/$schoolId');
}

class _SchoolListMobile extends StatelessWidget {
  const _SchoolListMobile({required this.schools});

  final List<School> schools;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: schools.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final school = schools[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: ListTile(
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Text(school.name, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  _SchoolStatusBadge(status: school.status),
                ],
              ),
              subtitle: Text('${school.city}, ${school.country}\n${school.email} · ${school.currencyCode}'),
              isThreeLine: true,
              trailing: _SchoolActions(school: school),
            ),
          ),
        );
      },
    );
  }
}

class _SchoolListDesktop extends StatelessWidget {
  const _SchoolListDesktop({required this.schools});

  final List<School> schools;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Card(
        child: HorizontalScrollTable(
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Name')),
              DataColumn(label: Text('Group')),
              DataColumn(label: Text('Email')),
              DataColumn(label: Text('City')),
              DataColumn(label: Text('Country')),
              DataColumn(label: Text('Currency')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Action')),
            ],
            rows: [
              for (final school in schools)
                DataRow(
                  cells: [
                    DataCell(Text(school.name)),
                    DataCell(_GroupCell(school: school)),
                    DataCell(Text(school.email)),
                    DataCell(Text(school.city)),
                    DataCell(Text(school.country)),
                    DataCell(Text(school.currencyCode)),
                    DataCell(_SchoolStatusBadge(status: school.status)),
                    DataCell(_SchoolActions(school: school)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SchoolStatusBadge extends StatelessWidget {
  const _SchoolStatusBadge({required this.status});

  final SchoolStatus status;

  @override
  Widget build(BuildContext context) {
    final isActive = status == SchoolStatus.active;

    return StatusBadge(label: isActive ? 'Active' : 'Inactive', tone: isActive ? BadgeTone.success : BadgeTone.danger);
  }
}

class _SchoolActions extends ConsumerWidget {
  const _SchoolActions({required this.school});

  final School school;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = school.status == SchoolStatus.active;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.open_in_new, size: 20),
          tooltip: 'View',
          onPressed: () => context.go('/schools/${school.id}'),
        ),
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 20),
          tooltip: 'Edit',
          onPressed: () => showDialog(
            context: context,
            builder: (_) => EditSchoolDialog(school: school),
          ),
        ),
        TextButton(
          onPressed: () async {
            try {
              await ref.read(schoolPageNotifierProvider.notifier).setActive(school, !isActive);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${school.name} was ${isActive ? 'deactivated' : 'activated'}.')),
                );
              }
            } catch (error) {
              if (context.mounted) {
                final failure = error is Failure ? error : Failure.unknown(error.toString());
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message)));
              }
            }
          },
          child: Text(isActive ? 'Deactivate' : 'Activate'),
        ),
      ],
    );
  }
}

/// Where a school sits in its group: a branch names its parent, a parent
/// counts its branches, and a standalone school says so plainly.
class _GroupCell extends StatelessWidget {
  const _GroupCell({required this.school});

  final School school;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);

    if (school.isBranch) {
      return Text('Branch of ${school.parentSchoolName ?? 'a group'}', overflow: TextOverflow.ellipsis, maxLines: 1);
    }

    if (school.isGroupParent) {
      return Text('${school.branchCount} ${school.branchCount == 1 ? 'branch' : 'branches'}');
    }

    return Text('Standalone', style: muted);
  }
}
