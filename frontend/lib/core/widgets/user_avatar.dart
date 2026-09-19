import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/dio_client.dart';

/// A profile photo's bytes, fetched once per [photoUrl].
///
/// Photos are behind sign-in, so they come through the app's own Dio client,
/// which sends the bearer token - Image.network would not. The url changes
/// whenever the photo does, which makes it a safe cache key.
///
/// Not retried: a photo that is gone or not ours to see answers 404, and
/// asking again will not change that - the initials stay instead.
final userPhotoProvider = FutureProvider.autoDispose.family<Uint8List, String>((ref, photoUrl) async {
  final response = await ref
      .read(dioClientProvider)
      .get<List<int>>(photoUrl, options: Options(responseType: ResponseType.bytes));

  return Uint8List.fromList(response.data ?? const []);
}, retry: (retryCount, error) => null);

/// Someone's photo in a circle, or their initials when there is none.
///
/// The initials also stand in while the photo loads and if it cannot be
/// fetched or decoded - a missing picture is never an error on the page.
class UserAvatar extends ConsumerWidget {
  const UserAvatar({super.key, required this.photoUrl, required this.name, this.radius = 20});

  /// The photo's path relative to the API base, or null when there is none.
  final String? photoUrl;
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = photoUrl;
    if (url == null) return _Initials(name: name, radius: radius);

    final photo = ref.watch(userPhotoProvider(url));
    final size = radius * 2;

    return photo.when(
      data: (bytes) => ClipOval(
        child: Image.memory(
          bytes,
          key: const Key('user-avatar-photo'),
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _Initials(name: name, radius: radius),
        ),
      ),
      loading: () => _Initials(name: name, radius: radius),
      error: (_, _) => _Initials(name: name, radius: radius),
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.name, required this.radius});

  final String name;
  final double radius;

  /// First letter of the first and last words: "Asha Rao" is "AR".
  static String initialsOf(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    final first = words.first[0];
    final last = words.length > 1 ? words.last[0] : '';
    return (first + last).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return CircleAvatar(
      key: const Key('user-avatar-initials'),
      radius: radius,
      backgroundColor: colorScheme.primaryContainer,
      foregroundColor: colorScheme.onPrimaryContainer,
      child: Text(
        initialsOf(name),
        style: TextStyle(fontSize: radius * 0.8, fontWeight: FontWeight.w600),
      ),
    );
  }
}
