import 'package:flutter/material.dart';

/// Semantic colors (success/danger/warning/info) that aren't part of
/// Material's base ColorScheme, exposed as a proper [ThemeExtension] so
/// they switch correctly between light and dark mode like everything else
/// - not hardcoded constants that go dark-mode-blind. Access via
/// `context.appColors`.
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.success,
    required this.onSuccessContainer,
    required this.successContainer,
    required this.danger,
    required this.onDangerContainer,
    required this.dangerContainer,
    required this.warning,
    required this.onWarningContainer,
    required this.warningContainer,
    required this.info,
    required this.onInfoContainer,
    required this.infoContainer,
    required this.muted,
  });

  final Color success;
  final Color onSuccessContainer;
  final Color successContainer;

  final Color danger;
  final Color onDangerContainer;
  final Color dangerContainer;

  final Color warning;
  final Color onWarningContainer;
  final Color warningContainer;

  final Color info;
  final Color onInfoContainer;
  final Color infoContainer;

  /// Secondary/placeholder text - lighter than the body text color.
  final Color muted;

  /// The phone apps' set (Driver, Teacher, Family).
  static const light = AppColors(
    success: Color(0xFF16A34A),
    onSuccessContainer: Color(0xFF166534),
    successContainer: Color(0xFFDCFCE7),
    danger: Color(0xFFDC2626),
    onDangerContainer: Color(0xFF991B1B),
    dangerContainer: Color(0xFFFEE2E2),
    warning: Color(0xFFD97706),
    onWarningContainer: Color(0xFF92400E),
    warningContainer: Color(0xFFFEF3C7),
    info: Color(0xFF1E40AF),
    onInfoContainer: Color(0xFF1E40AF),
    infoContainer: Color(0xFFDBE4FF),
    muted: Color(0xFF64748B),
  );

  /// The web app's set (School365AI palette, 2026-11-21): green, amber,
  /// red and navy chosen to sit beside teal on off-white. Each
  /// "on...Container" text colour reads at 4.5:1 or better on its container.
  static const brandLight = AppColors(
    success: Color(0xFF1F7A4D),
    onSuccessContainer: Color(0xFF175E3B),
    successContainer: Color(0xFFE4F5EC),
    danger: Color(0xFFB42318),
    onDangerContainer: Color(0xFF912018),
    dangerContainer: Color(0xFFFDECEA),
    warning: Color(0xFFB45309),
    onWarningContainer: Color(0xFF8A3E06),
    warningContainer: Color(0xFFFFF4E5),
    info: Color(0xFF1D4E89),
    onInfoContainer: Color(0xFF173F70),
    infoContainer: Color(0xFFE8F0FA),
    muted: Color(0xFF5B6C84),
  );

  static const brandDark = AppColors(
    success: Color(0xFF6FD3A0),
    onSuccessContainer: Color(0xFF9FE3C0),
    successContainer: Color(0xFF113A2A),
    danger: Color(0xFFF59A92),
    onDangerContainer: Color(0xFFF8BAB4),
    dangerContainer: Color(0xFF4A1A18),
    warning: Color(0xFFF2B86A),
    onWarningContainer: Color(0xFFF6CF98),
    warningContainer: Color(0xFF43300F),
    info: Color(0xFF9CC2F2),
    onInfoContainer: Color(0xFFC1D8F6),
    infoContainer: Color(0xFF15304F),
    muted: Color(0xFFA9B8CB),
  );

  static const dark = AppColors(
    success: Color(0xFF4ADE80),
    onSuccessContainer: Color(0xFF86EFAC),
    successContainer: Color(0xFF0F3A25),
    danger: Color(0xFFF87171),
    onDangerContainer: Color(0xFFFCA5A5),
    dangerContainer: Color(0xFF4A1717),
    warning: Color(0xFFFBBF24),
    onWarningContainer: Color(0xFFFCD34D),
    warningContainer: Color(0xFF4A3208),
    info: Color(0xFF93C5FD),
    onInfoContainer: Color(0xFF93C5FD),
    infoContainer: Color(0xFF1B2F5A),
    muted: Color(0xFF93A0B8),
  );

  @override
  AppColors copyWith({
    Color? success,
    Color? onSuccessContainer,
    Color? successContainer,
    Color? danger,
    Color? onDangerContainer,
    Color? dangerContainer,
    Color? warning,
    Color? onWarningContainer,
    Color? warningContainer,
    Color? info,
    Color? onInfoContainer,
    Color? infoContainer,
    Color? muted,
  }) {
    return AppColors(
      success: success ?? this.success,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      successContainer: successContainer ?? this.successContainer,
      danger: danger ?? this.danger,
      onDangerContainer: onDangerContainer ?? this.onDangerContainer,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      warning: warning ?? this.warning,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      warningContainer: warningContainer ?? this.warningContainer,
      info: info ?? this.info,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
      infoContainer: infoContainer ?? this.infoContainer,
      muted: muted ?? this.muted,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;

    return AppColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccessContainer: Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      onDangerContainer: Color.lerp(onDangerContainer, other.onDangerContainer, t)!,
      dangerContainer: Color.lerp(dangerContainer, other.dangerContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarningContainer: Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      info: Color.lerp(info, other.info, t)!,
      onInfoContainer: Color.lerp(onInfoContainer, other.onInfoContainer, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}
