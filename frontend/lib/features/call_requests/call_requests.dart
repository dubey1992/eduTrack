import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors/failure.dart';
import '../../core/network/dio_client.dart';
import '../../core/network/paginated_response.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/async_value_view.dart';
import '../../core/widgets/section_header.dart';
import '../../core/widgets/status_badge.dart';

/// Parents asking to be called, from the Family app (docs/parent-student-app.md,
/// F5): to the class teacher or the school office. A teacher sees their own;
/// the school's admins see them all. Calling back and marking it called is
/// what the parent sees; the note of how it went stays with the school.
class CallRequest {
  const CallRequest({
    required this.id,
    required this.studentName,
    required this.parentName,
    required this.parentMobile,
    required this.toOffice,
    required this.reason,
    required this.called,
    this.preferredTime,
    this.teacherName,
    this.calledBy,
    this.outcomeNote,
  });

  factory CallRequest.fromJson(Map<String, dynamic> json) {
    final parent = json['parent'] as Map<String, dynamic>;
    return CallRequest(
      id: json['id'] as int,
      studentName: (json['student'] as Map<String, dynamic>)['name'] as String,
      parentName: parent['name'] as String,
      parentMobile: parent['mobile'] as String?,
      toOffice: json['recipient'] == 'office',
      reason: json['reason'] as String,
      preferredTime: json['preferred_time'] as String?,
      called: json['status'] == 'called',
      teacherName: json['teacher_name'] as String?,
      calledBy: json['called_by'] as String?,
      outcomeNote: json['outcome_note'] as String?,
    );
  }

  final int id;
  final String studentName;
  final String parentName;
  final String? parentMobile;
  final bool toOffice;
  final String reason;
  final String? preferredTime;
  final bool called;
  final String? teacherName;
  final String? calledBy;
  final String? outcomeNote;
}

final callRequestsRepositoryProvider = Provider<CallRequestsRepository>(
  (ref) => CallRequestsRepository(ref.watch(dioClientProvider)),
);

class CallRequestsRepository {
  CallRequestsRepository(this._dio);

  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<PaginatedResponse<CallRequest>> list({required bool open, int page = 1}) => _call(() async {
    final response = await _dio.get(
      '/call-requests',
      queryParameters: {'status': open ? 'open' : 'called', 'page': page},
    );
    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, CallRequest.fromJson);
  });

  Future<CallRequest> markCalled(int id, {String? note}) => _call(() async {
    final response = await _dio.post('/call-requests/$id/called', data: {'outcome_note': ?note});
    return CallRequest.fromJson(response.data as Map<String, dynamic>);
  });
}

/// Whether the page shows the requests still waiting for a call (the default).
final callRequestsOpenProvider = NotifierProvider<CallRequestsOpen, bool>(CallRequestsOpen.new);

class CallRequestsOpen extends Notifier<bool> {
  @override
  bool build() => true;

  void show({required bool open}) => state = open;
}

/// How many parents are waiting for this person's call - the card on the
/// Staff app's Today (docs/mobile-apps-review.md, 7.3). The server counts
/// only the caller's own (a teacher's) or their school's (the office).
final callRequestsWaitingProvider = FutureProvider.autoDispose<int>(
  (ref) async => (await ref.watch(callRequestsRepositoryProvider).list(open: true)).total,
  retry: (retryCount, error) => null,
);

final callRequestsProvider = FutureProvider.autoDispose<PaginatedResponse<CallRequest>>(
  (ref) => ref.watch(callRequestsRepositoryProvider).list(open: ref.watch(callRequestsOpenProvider)),
);

/// Opens the phone's dialler, or the computer's calling app. Swappable in tests.
typedef Dialler = Future<bool> Function(Uri uri);

final diallerProvider = Provider<Dialler>(
  (ref) =>
      (uri) => launchUrl(uri),
);

class CallRequestsScreen extends ConsumerWidget {
  const CallRequestsScreen({super.key, this.compact = false});

  /// The Staff app's own screen (7.3): its app bar has the title, so the
  /// page's heading goes and the filter sits on its own row.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(callRequestsOpenProvider);
    final requests = ref.watch(callRequestsProvider);

    final filter = SegmentedButton<bool>(
      key: const Key('call-requests-filter'),
      segments: const [
        ButtonSegment(value: true, label: Text('To call')),
        ButtonSegment(value: false, label: Text('Called')),
      ],
      selected: {open},
      onSelectionChanged: (choice) => ref.read(callRequestsOpenProvider.notifier).show(open: choice.first),
    );

    return ListView(
      padding: EdgeInsets.only(top: compact ? 12 : 0, bottom: 24),
      children: [
        if (compact)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Align(alignment: Alignment.centerLeft, child: filter),
          )
        else
          SectionHeader(title: 'Call Requests', actions: [filter]),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Parents ask to be called from the Family app. Ring them on the number shown, then mark it called.',
            style: TextStyle(color: context.appColors.muted),
          ),
        ),
        const SizedBox(height: 12),
        AsyncValueView(
          value: requests,
          onRetry: () => ref.invalidate(callRequestsProvider),
          isEmpty: (page) => page.items.isEmpty,
          emptyBuilder: (context) => Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(
                open ? 'Nobody is waiting for a call.' : 'No calls marked yet.',
                style: TextStyle(color: context.appColors.muted),
              ),
            ),
          ),
          data: (context, page) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                for (final request in page.items) ...[_RequestCard(request: request), const SizedBox(height: 10)],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RequestCard extends ConsumerWidget {
  const _RequestCard({required this.request});

  final CallRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colours = context.appColors;
    final mobile = request.parentMobile;

    return Card(
      key: Key('call-request-${request.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(request.parentName, style: Theme.of(context).textTheme.titleMedium),
                Text('about ${request.studentName}', style: TextStyle(color: colours.muted)),
                StatusBadge(
                  label: request.toOffice ? 'To the office' : 'To ${request.teacherName ?? 'the class teacher'}',
                  tone: BadgeTone.info,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(request.reason),
            if (request.preferredTime != null)
              Text('Good time: ${request.preferredTime}', style: TextStyle(color: colours.muted, fontSize: 13)),
            if (request.called)
              Text(
                'Called by ${request.calledBy ?? 'the school'}${request.outcomeNote == null ? '' : ' · ${request.outcomeNote}'}',
                style: TextStyle(color: colours.muted, fontSize: 13),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (mobile != null)
                  OutlinedButton.icon(
                    key: Key('call-request-dial-${request.id}'),
                    onPressed: () => ref.read(diallerProvider)(Uri(scheme: 'tel', path: mobile.replaceAll(' ', ''))),
                    icon: const Icon(Icons.call_rounded, size: 18),
                    label: Text(mobile),
                  ),
                if (!request.called)
                  FilledButton(
                    key: Key('call-request-called-${request.id}'),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => _CalledDialog(request: request),
                    ),
                    child: const Text('Mark as called'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CalledDialog extends ConsumerStatefulWidget {
  const _CalledDialog({required this.request});

  final CallRequest request;

  @override
  ConsumerState<_CalledDialog> createState() => _CalledDialogState();
}

class _CalledDialogState extends ConsumerState<_CalledDialog> {
  final _note = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final note = _note.text.trim();
      await ref.read(callRequestsRepositoryProvider).markCalled(widget.request.id, note: note.isEmpty ? null : note);
      ref.invalidate(callRequestsProvider);
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Marked as called. The parent can see that.')));
    } on Failure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Called ${widget.request.parentName}?'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('call-request-note'),
              controller: _note,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'How did it go? (optional)',
                helperText: 'Only the school sees this note.',
              ),
            ),
            if (_error != null) Text(_error!, style: TextStyle(color: context.appColors.danger, fontSize: 13)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          key: const Key('call-request-save'),
          onPressed: _saving ? null : _save,
          child: const Text('Mark as called'),
        ),
      ],
    );
  }
}
