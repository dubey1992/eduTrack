import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/status_badge.dart';
import '../../../core/errors/failure.dart';
import '../../../core/models/module_access.dart';
import '../../../core/models/user_role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../auth/application/auth_notifier.dart';
import '../../classes/application/class_section_picker_provider.dart';
import '../../subjects/data/models/subject.dart';
import '../../timetable/application/subject_picker_provider.dart';
import '../application/syllabus_checklist_notifier.dart';
import '../data/models/syllabus_checklist.dart';
import '../data/syllabus_topic_repository.dart';
import 'widgets/add_topic_dialog.dart';
import 'widgets/edit_topic_dialog.dart';
import '../../../core/widgets/school_picker.dart';
import '../../../core/widgets/searchable_dropdown.dart';

/// Phase 12 - a subject's curriculum outline (ordered topics) plus one
/// class section's completion checklist against it. Outline management
/// (add/edit/delete topics) is separate from marking progress - see
/// SyllabusTopicPolicy on the backend for exactly who can do which.
const _outlineManagerRoles = {UserRole.superAdmin, UserRole.groupAdmin, UserRole.schoolAdmin, UserRole.hod};

class SyllabusScreen extends ConsumerStatefulWidget {
  const SyllabusScreen({super.key});

  @override
  ConsumerState<SyllabusScreen> createState() => _SyllabusScreenState();
}

class _SyllabusScreenState extends ConsumerState<SyllabusScreen> {
  int? _schoolId;
  int? _subjectId;
  int? _classSectionId;

  @override
  Widget build(BuildContext context) {
    final actor = ref.watch(authNotifierProvider).value;
    if (actor == null) return const SizedBox.shrink();

    final picksSchool = actor.picksSchool;
    final canManageOutline = _outlineManagerRoles.contains(actor.role) && actor.canManage(AppModules.syllabus);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Syllabus Tracking', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Curriculum outline and per-class coverage.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (picksSchool)
                    SizedBox(
                      width: 240,
                      child: SchoolPicker(
                        required: false,
                        selected: _schoolId,
                        onChanged: (value) => setState(() {
                          _schoolId = value;
                          _subjectId = null;
                          _classSectionId = null;
                        }),
                      ),
                    ),
                  SizedBox(
                    width: 220,
                    child: _SubjectPicker(
                      schoolId: _schoolId,
                      selected: _subjectId,
                      onChanged: (value) => setState(() => _subjectId = value),
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: _ClassSectionPicker(
                      schoolId: _schoolId,
                      selected: _classSectionId,
                      onChanged: (value) => setState(() => _classSectionId = value),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (_subjectId != null && _classSectionId != null)
            _Checklist(
              key: ValueKey('$_subjectId-$_classSectionId'),
              schoolId: _schoolId,
              subjectId: _subjectId!,
              classSectionId: _classSectionId!,
              canManageOutline: canManageOutline,
            )
          else
            const Card(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('Pick a subject and a class section to view its syllabus.')),
              ),
            ),
        ],
      ),
    );
  }
}

class _SubjectPicker extends ConsumerWidget {
  const _SubjectPicker({required this.schoolId, required this.selected, required this.onChanged});

  final int? schoolId;
  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjectsState = ref.watch(subjectPickerProvider(schoolId));

    return AsyncValueView<List<Subject>>(
      value: subjectsState,
      data: (context, subjects) {
        return SearchableDropdown<int>(
          initialValue: subjects.any((s) => s.id == selected) ? selected : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Subject'),
          items: [
            for (final subject in subjects)
              DropdownMenuItem(
                value: subject.id,
                child: Text(subject.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged,
        );
      },
    );
  }
}

class _ClassSectionPicker extends ConsumerWidget {
  const _ClassSectionPicker({required this.schoolId, required this.selected, required this.onChanged});

  final int? schoolId;
  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final optionsState = ref.watch(classSectionPickerProvider(schoolId));

    return AsyncValueView<List<ClassSectionOption>>(
      value: optionsState,
      data: (context, options) {
        return SearchableDropdown<int>(
          initialValue: options.any((o) => o.id == selected) ? selected : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Class'),
          items: [for (final option in options) DropdownMenuItem(value: option.id, child: Text(option.label))],
          onChanged: onChanged,
        );
      },
    );
  }
}

class _Checklist extends ConsumerWidget {
  const _Checklist({
    super.key,
    required this.schoolId,
    required this.subjectId,
    required this.classSectionId,
    required this.canManageOutline,
  });

  final int? schoolId;
  final int subjectId;
  final int classSectionId;
  final bool canManageOutline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = SyllabusChecklistParams(classSectionId: classSectionId, subjectId: subjectId);
    final checklistState = ref.watch(syllabusChecklistProvider(params));

    return AsyncValueView<SyllabusChecklist>(
      value: checklistState,
      onRetry: () => ref.invalidate(syllabusChecklistProvider(params)),
      data: (context, checklist) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (checklist.classLevelName != null) ...[
                            Text(
                              '${checklist.classLevelName} syllabus - shared by every section of the class',
                              key: const Key('syllabus-whose'),
                              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 4),
                          ],
                          Text(
                            '${checklist.completedTopics} of ${checklist.totalTopics} topics covered',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: checklist.totalTopics == 0 ? 0 : checklist.completedTopics / checklist.totalTopics,
                              minHeight: 8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text('${checklist.progressPercent}%', style: Theme.of(context).textTheme.headlineSmall),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (canManageOutline)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => AddTopicDialog(
                      schoolId: schoolId,
                      subjectId: subjectId,
                      params: params,
                      classLevel: checklist.classLevel,
                      classLevelName: checklist.classLevelName,
                      nextSequenceNumber: _nextNumber(checklist),
                    ),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Topic'),
                ),
              ),
            const SizedBox(height: 8),
            if (checklist.topics.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('No syllabus topics defined yet.')),
                ),
              )
            else
              Card(
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: checklist.topics.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final topic = checklist.topics[index];
                    return ListTile(
                      leading: Checkbox(
                        value: topic.completed,
                        onChanged: (value) => _toggle(context, ref, params, topic.id, value ?? false),
                      ),
                      title: Text.rich(
                        TextSpan(
                          text: '${topic.sequenceNumber}. ${topic.title}',
                          children: [
                            // Written before topics had classes: every class
                            // follows it until it is given one (Edit).
                            if (topic.isForEveryClass && checklist.classLevel != null)
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: StatusBadge(
                                    key: Key('topic-all-classes-${topic.id}'),
                                    label: 'All classes',
                                    tone: BadgeTone.neutral,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      subtitle: topic.completed && topic.completedByName != null
                          ? Text('Completed by ${topic.completedByName}')
                          : null,
                      trailing: canManageOutline
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, size: 20),
                                  tooltip: 'Edit',
                                  onPressed: () => showDialog(
                                    context: context,
                                    builder: (_) => EditTopicDialog(
                                      topic: topic,
                                      params: params,
                                      classLevel: checklist.classLevel,
                                      classLevelName: checklist.classLevelName,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete_outline, size: 20, color: context.appColors.danger),
                                  tooltip: 'Delete',
                                  onPressed: () => _delete(context, ref, params, topic.id),
                                ),
                              ],
                            )
                          : null,
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  /// Next after the last of this class's own topics: each class numbers
  /// its topics from 1, and the ones for every class keep their own order.
  static int _nextNumber(SyllabusChecklist checklist) {
    final own = [
      for (final topic in checklist.topics)
        if (topic.classLevel == checklist.classLevel) topic.sequenceNumber,
    ];

    return own.isEmpty ? 1 : own.reduce((a, b) => a > b ? a : b) + 1;
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    SyllabusChecklistParams params,
    int topicId,
    bool completed,
  ) async {
    try {
      await ref.read(syllabusChecklistProvider(params).notifier).toggle(topicId, completed);
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, SyllabusChecklistParams params, int topicId) async {
    try {
      await ref.read(syllabusTopicRepositoryProvider).delete(topicId);
      await ref.read(syllabusChecklistProvider(params).notifier).refresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Topic deleted.')));
      }
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }
}
