import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/failure_text.dart';
import '../l10n/l10n.dart';
import '../models/notice_attachment.dart';
import '../network/dio_client.dart';
import '../utils/file_saver.dart';

/// Hands a file to the person: a download in a browser, the share sheet on
/// a phone (save to Files, open in a PDF reader, send on). Swappable in tests.
typedef FileHandOff = Future<void> Function(List<int> bytes, String fileName, String mimeType);

final fileHandOffProvider = Provider<FileHandOff>(
  (ref) => (bytes, fileName, mimeType) async {
    if (kIsWeb) {
      saveBytes(fileName: fileName, bytes: bytes, mimeType: mimeType);
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(Uint8List.fromList(bytes), mimeType: mimeType, name: fileName)],
        fileNameOverrides: [fileName],
      ),
    );
  },
);

/// A notice's files, one chip each (M9, 8.3). A picture opens in the app,
/// where it can be zoomed and saved; a PDF goes straight to download or the
/// share sheet. Each file is fetched only when tapped.
class NoticeAttachmentChips extends ConsumerStatefulWidget {
  const NoticeAttachmentChips({super.key, required this.attachments});

  final List<NoticeAttachment> attachments;

  @override
  ConsumerState<NoticeAttachmentChips> createState() => _NoticeAttachmentChipsState();
}

class _NoticeAttachmentChipsState extends ConsumerState<NoticeAttachmentChips> {
  int? _opening;

  Future<void> _open(NoticeAttachment attachment) async {
    if (_opening != null) return;
    setState(() => _opening = attachment.id);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final response = await ref
          .read(dioClientProvider)
          .get<List<int>>(attachment.url, options: Options(responseType: ResponseType.bytes));
      final bytes = response.data ?? const <int>[];
      if (!mounted) return;
      // Fetched: the spinner stops before the picture or the share sheet opens.
      setState(() => _opening = null);

      if (attachment.isImage) {
        await showDialog<void>(
          context: context,
          builder: (context) => _PictureDialog(attachment: attachment, bytes: bytes),
        );
      } else {
        await ref.read(fileHandOffProvider)(bytes, attachment.name, attachment.contentType);
      }
    } on DioException catch (error) {
      final failure = failureFromDioException(error);
      debugPrint('Opening attachment ${attachment.id} failed: ${failure.code}');
      messenger.showSnackBar(SnackBar(content: Text(mounted ? failure.localizedMessage(context) : failure.message)));
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.attachments.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final attachment in widget.attachments)
          ActionChip(
            key: Key('notice-attachment-${attachment.id}'),
            avatar: _opening == attachment.id
                ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(attachment.isImage ? Icons.image_outlined : Icons.picture_as_pdf_outlined, size: 18),
            label: Text('${attachment.name} · ${attachment.sizeLabel}', overflow: TextOverflow.ellipsis),
            onPressed: () => _open(attachment),
          ),
      ],
    );
  }
}

class _PictureDialog extends ConsumerWidget {
  const _PictureDialog({required this.attachment, required this.bytes});

  final NoticeAttachment attachment;
  final List<int> bytes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dialog(
      key: const Key('notice-attachment-picture'),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: InteractiveViewer(
              maxScale: 5,
              child: Image.memory(
                Uint8List.fromList(bytes),
                fit: BoxFit.contain,
                errorBuilder: (context, _, _) => Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(context.l10n.staffPictureNotShown, textAlign: TextAlign.center),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Expanded(child: Text(attachment.name, overflow: TextOverflow.ellipsis)),
                TextButton.icon(
                  key: const Key('notice-attachment-save'),
                  onPressed: () => ref.read(fileHandOffProvider)(bytes, attachment.name, attachment.contentType),
                  icon: Icon(kIsWeb ? Icons.download_outlined : Icons.share_outlined),
                  label: Text(kIsWeb ? context.l10n.staffDownload : context.l10n.staffSaveOrShare),
                ),
                TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.l10n.staffClose)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
