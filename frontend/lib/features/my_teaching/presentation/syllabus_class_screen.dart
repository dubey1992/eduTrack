import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../syllabus/application/syllabus_checklist_notifier.dart';
import '../../syllabus/data/models/syllabus_checklist.dart';
import '../application/my_teaching_providers.dart';

/// One class's syllabus for one subject, on the phone (docs/teacher-app.md,
/// T3): the topics in teaching order, each ticked off or not, with who did
/// it. Ticking goes straight to the server under the web's rule: the
/// teacher timetabled for that subject in that class.
class SyllabusClassScreen extends ConsumerStatefulWidget {
  const SyllabusClassScreen({super.key, required this.params, required this.label});

  final SyllabusChecklistParams params;

  /// "Mathematics · Grade 3 A".
  final String label;

  @override
  ConsumerState<SyllabusClassScreen> createState() => _SyllabusClassScreenState();
}

class _SyllabusClassScreenState extends ConsumerState<SyllabusClassScreen> {
  /// The topic being saved. One at a time, so two quick taps never race.
  int? _saving;

  Future<void> _toggle(SyllabusChecklistItem topic) async {
    if (_saving != null) return;
    setState(() => _saving = topic.id);
    try {
      await ref.read(syllabusChecklistProvider(widget.params).notifier).toggle(topic.id, !topic.completed);
      ref.invalidate(mySyllabusProvider);
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) {
        final message = failure.code == 'NETWORK_ERROR'
            ? 'No connection. "${topic.title}" was not changed.'
            : failure.message;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final checklist = ref.watch(syllabusChecklistProvider(widget.params));

    return Scaffold(
      appBar: AppBar(title: Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: AsyncValueView<SyllabusChecklist>(
              value: checklist,
              onRetry: () => ref.read(syllabusChecklistProvider(widget.params).notifier).refresh(),
              data: (context, list) => _Checklist(list: list, saving: _saving, onToggle: _toggle),
            ),
          ),
        ),
      ),
    );
  }
}

class _Checklist extends StatelessWidget {
  const _Checklist({required this.list, required this.saving, required this.onToggle});

  final SyllabusChecklist list;
  final int? saving;
  final ValueChanged<SyllabusChecklistItem> onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    if (list.topics.isEmpty) {
      return Center(
        key: const Key('syllabus-class-empty'),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_outlined, size: 48, color: colors.muted),
              const SizedBox(height: 12),
              const Text('No topics in this syllabus yet.', textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(
                'Your HOD or school office sets out the topics on the website.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.muted),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      key: const Key('syllabus-class-list'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text(
          '${list.completedTopics} of ${list.totalTopics} topics done · ${list.progressPercent}%',
          key: const Key('syllabus-class-progress'),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: list.totalTopics == 0 ? 0 : list.completedTopics / list.totalTopics,
            minHeight: 8,
            backgroundColor: colors.muted.withValues(alpha: 0.15),
          ),
        ),
        const SizedBox(height: 16),
        for (final topic in list.topics)
          Card(
            key: Key('syllabus-topic-${topic.id}'),
            child: CheckboxListTile(
              value: topic.completed,
              onChanged: saving == null ? (_) => onToggle(topic) : null,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text('${topic.sequenceNumber}. ${topic.title}'),
              subtitle: topic.completed && topic.completedByName != null
                  ? Text('Done · ${topic.completedByName}', style: TextStyle(color: colors.muted))
                  : null,
              secondary: saving == topic.id
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : null,
            ),
          ),
      ],
    );
  }
}
