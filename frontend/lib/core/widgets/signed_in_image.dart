import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/dio_client.dart';
import '../theme/app_colors.dart';

/// A picture the server gives only to someone signed in - an event's photo
/// (docs/mobile-apps-review.md, M12, 8.6) - read through the app's own
/// session, since an Image.network would carry no token. [url] is the API
/// path, e.g. `/gallery-photos/12?size=thumb`.
final signedInImageProvider = FutureProvider.autoDispose.family<Uint8List, String>((ref, url) async {
  try {
    final response = await ref
        .read(dioClientProvider)
        .get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
    return Uint8List.fromList(response.data ?? const <int>[]);
  } on DioException catch (e) {
    throw failureFromDioException(e);
  }
}, retry: (retryCount, error) => null);

class SignedInImage extends ConsumerWidget {
  const SignedInImage({super.key, required this.url, this.fit = BoxFit.cover, this.semanticLabel});

  final String url;
  final BoxFit fit;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colours = context.appColors;

    return ref
        .watch(signedInImageProvider(url))
        .when(
          loading: () => ColoredBox(color: colours.muted.withValues(alpha: 0.12)),
          error: (_, _) => ColoredBox(
            color: colours.muted.withValues(alpha: 0.12),
            child: IconButton(
              tooltip: semanticLabel,
              onPressed: () => ref.invalidate(signedInImageProvider(url)),
              icon: Icon(Icons.refresh_rounded, color: colours.muted),
            ),
          ),
          data: (bytes) => Image.memory(
            bytes,
            fit: fit,
            semanticLabel: semanticLabel,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => Icon(Icons.broken_image_outlined, color: colours.muted),
          ),
        );
  }
}

/// The photos of one event full screen: swipe between them, pinch to zoom.
class PhotoViewer extends StatefulWidget {
  const PhotoViewer({super.key, required this.urls, this.initialIndex = 0, this.title});

  final List<String> urls;
  final int initialIndex;
  final String? title;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${widget.title == null ? '' : '${widget.title}  '}${_index + 1}/${widget.urls.length}'),
      ),
      body: PageView.builder(
        key: const Key('photo-viewer'),
        controller: _pages,
        itemCount: widget.urls.length,
        onPageChanged: (index) => setState(() => _index = index),
        itemBuilder: (context, index) => InteractiveViewer(
          maxScale: 4,
          child: Center(
            child: SignedInImage(url: widget.urls[index], fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}
