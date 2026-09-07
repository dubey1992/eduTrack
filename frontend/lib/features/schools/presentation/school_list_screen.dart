import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/status_badge.dart';
import '../application/school_list_notifier.dart';
import '../data/models/school.dart';
import 'add_school_dialog.dart';

class SchoolListScreen extends ConsumerWidget {
  const SchoolListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schoolsState = ref.watch(schoolListNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Schools'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add school',
            onPressed: () => showDialog(context: context, builder: (_) => const AddSchoolDialog()),
          ),
        ],
      ),
      body: AsyncValueView<List<School>>(
        value: schoolsState,
        onRetry: () => ref.read(schoolListNotifierProvider.notifier).refresh(),
        isEmpty: (schools) => schools.isEmpty,
        emptyBuilder: (context) => const Center(child: Text('No schools yet.')),
        data: (context, schools) {
          return ResponsiveBuilder(
            mobile: (context) => _SchoolListMobile(schools: schools),
            desktop: (context) => _SchoolListDesktop(schools: schools),
          );
        },
      ),
    );
  }
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
              trailing: _SchoolStatusToggle(school: school),
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
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Card(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Name')),
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
                    DataCell(Text(school.email)),
                    DataCell(Text(school.city)),
                    DataCell(Text(school.country)),
                    DataCell(Text(school.currencyCode)),
                    DataCell(_SchoolStatusBadge(status: school.status)),
                    DataCell(_SchoolStatusToggle(school: school)),
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

    return StatusBadge(
      label: isActive ? 'Active' : 'Inactive',
      tone: isActive ? BadgeTone.success : BadgeTone.danger,
    );
  }
}

class _SchoolStatusToggle extends ConsumerWidget {
  const _SchoolStatusToggle({required this.school});

  final School school;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = school.status == SchoolStatus.active;

    return TextButton(
      onPressed: () => ref.read(schoolListNotifierProvider.notifier).setActive(school, !isActive),
      child: Text(isActive ? 'Deactivate' : 'Activate'),
    );
  }
}
