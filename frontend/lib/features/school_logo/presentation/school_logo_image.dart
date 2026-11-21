import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/user_avatar.dart';

/// A school's logo on a white tile, or its initials when it has none.
///
/// The logo is behind sign-in, so its bytes come through the app's own
/// client ([userPhotoProvider] fetches any image that way). The initials also
/// stand in while it loads and if it cannot be fetched - a missing logo is
/// never an error on the page.
class SchoolLogoImage extends ConsumerWidget {
  const SchoolLogoImage({
    super.key,
    required this.logoUrl,
    required this.schoolName,
    this.size = 44,
    this.onDark = false,
  });

  /// The logo's path relative to the API base, or null when there is none.
  final String? logoUrl;
  final String schoolName;
  final double size;

  /// On the navy sidebar the initials are light on a faint tile.
  final bool onDark;

  /// "Riverside Public School" is "RP": the first letters of the first two words.
  static String initialsOf(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    return words.take(2).map((w) => w[0]).join().toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = logoUrl;
    final radius = BorderRadius.circular(size * 0.22);
    if (url == null) return _initials(context, radius);

    final logo = ref.watch(userPhotoProvider(url));

    return logo.when(
      data: (bytes) => Container(
        key: const Key('school-logo-image'),
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.08),
        decoration: BoxDecoration(color: Colors.white, borderRadius: radius),
        child: Image.memory(
          bytes,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          semanticLabel: '$schoolName logo',
          errorBuilder: (_, _, _) => _initialsText(context),
        ),
      ),
      loading: () => _initials(context, radius),
      error: (_, _) => _initials(context, radius),
    );
  }

  Widget _initials(BuildContext context, BorderRadius radius) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      key: const Key('school-logo-initials'),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: onDark ? const Color(0x1FFFFFFF) : colors.primaryContainer,
        borderRadius: radius,
      ),
      child: _initialsText(context),
    );
  }

  Widget _initialsText(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Text(
      initialsOf(schoolName),
      style: TextStyle(
        fontSize: size * 0.36,
        fontWeight: FontWeight.w700,
        color: onDark ? Colors.white : colors.onPrimaryContainer,
      ),
    );
  }
}
