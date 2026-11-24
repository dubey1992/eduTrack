import 'package:edutrack_app/core/theme/app_colors.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/theme/brand_tokens.dart';
import 'package:edutrack_app/core/theme/driver_brand.dart';
import 'package:edutrack_app/core/theme/family_brand.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The phone apps in the School365AI design (slice B1, 2026-11-24,
/// docs/mobile-apps-review.md): the brand's grounds and type, one accent
/// each, and the same status colours everywhere.
void main() {
  // Built inside each test: a theme names its fonts through google_fonts,
  // which a testWidgets body keeps off the network.
  final apps = {
    'Staff': (AppTheme.teacherLight, AppTheme.teacherDark, BrandColors.teal),
    'Driver': (AppTheme.crewLight, AppTheme.crewDark, DriverBrand.navy),
    'Family': (AppTheme.familyLight, AppTheme.familyDark, FamilyBrand.violet),
  };

  for (final MapEntry(key: app, value: (lightOf, darkOf, accent)) in apps.entries) {
    group('the $app app', () {
      testWidgets('wears its own accent on the brand grounds', (tester) async {
        final (light, dark) = (lightOf(), darkOf());
        expect(light.colorScheme.primary, accent);
        expect(light.scaffoldBackgroundColor, BrandColors.workspace);
        expect(dark.scaffoldBackgroundColor, BrandColors.night);
      });

      testWidgets('uses the brand type: DM Sans for text, Manrope for titles', (tester) async {
        final light = lightOf();
        expect(light.textTheme.bodyMedium?.fontFamily, contains('DMSans'));
        expect(light.textTheme.titleLarge?.fontFamily, contains('Manrope'));
      });

      testWidgets('keeps the status colours every app shares', (tester) async {
        final (light, dark) = (lightOf(), darkOf());
        expect(light.extension<AppColors>(), AppColors.brandLight);
        expect(dark.extension<AppColors>(), AppColors.brandDark);
      });

      testWidgets('puts white text on its accent in light mode', (tester) async {
        final light = lightOf();
        expect(light.colorScheme.onPrimary, Colors.white);
        // Readable: at least 4.5:1 between the accent and white text.
        final ratio = 1.05 / (accent.computeLuminance() + 0.05);
        expect(ratio, greaterThanOrEqualTo(4.5));
      });
    });
  }

  testWidgets('the Driver app is told apart by the brand orange at night', (tester) async {
    expect(AppTheme.crewDark().colorScheme.primary, DriverBrand.orange);
  });
}
