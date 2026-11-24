import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../features/auth/presentation/widgets/auth_palette.dart';
import 'app_colors.dart';
import 'brand_tokens.dart';
import 'driver_brand.dart';
import 'family_brand.dart';
import 'teacher_brand.dart';

/// The apps' themes.
///
/// **The web app** ([light], [dark]) wears the public website's School365AI
/// design (Homepage V3, 2026-11-21): teal actions and navy text on
/// off-white, a deep navy sidebar, DM Sans for text and Manrope for
/// headings. Every screen takes
/// its look from here and from the [ThemeExtension]s below, so one change
/// here reaches all of them.
///
/// **The phone apps** wear the same design since 2026-11-24 (slice B1,
/// docs/mobile-apps-review.md): the web app's grounds, navy text, DM Sans and
/// Manrope - each with one accent so they are told apart in a hand. Staff
/// is the brand teal ([teacherLight]), the Driver app navy with the brand
/// orange ([crewLight]), the Family app the logo's violet ([familyLight]).
/// The status colours (present, absent, late) are the same in every app.
///
/// Both follow the device's light/dark setting (ThemeMode.system).
class AppTheme {
  const AppTheme._();

  /// The phone apps' radii before B1. Kept for the few widgets that name
  /// them; every theme now uses [BrandRadii].
  static const radiusCard = 8.0;
  static const radiusControl = 6.0;

  // ---- The web app ----

  static ThemeData light() => _build(
    _Palette.brand(
      brightness: Brightness.light,
      primary: BrandColors.teal,
      onPrimary: Colors.white,
      primarySoft: BrandColors.mint,
      primaryInk: BrandColors.tealInk,
    ),
    editorial: true,
  );

  static ThemeData dark() => _build(
    _Palette.brand(
      brightness: Brightness.dark,
      primary: BrandColors.nightTeal,
      onPrimary: BrandColors.deep,
      primarySoft: BrandColors.nightMint,
      primaryInk: BrandColors.nightText,
    ),
    editorial: true,
  );

  // ---- The Driver app ----
  //
  // Navy buttons with white text - the strongest contrast there is, for a
  // phone read in sunlight on a bus - and the brand orange as the warm note
  // on what is chosen. At night the orange leads, dark text on it.
  static ThemeData crewLight() => _build(
    _Palette.brand(
      brightness: Brightness.light,
      primary: DriverBrand.navy,
      onPrimary: Colors.white,
      primarySoft: DriverBrand.orangeSoft,
      primaryInk: DriverBrand.orangeInk,
    ),
    editorial: true,
  );

  static ThemeData crewDark() => _build(
    _Palette.brand(
      brightness: Brightness.dark,
      primary: DriverBrand.orange,
      onPrimary: BrandColors.deep,
      primarySoft: DriverBrand.orangeNight,
      primaryInk: BrandColors.nightText,
    ),
    editorial: true,
  );

  // ---- The Staff app (docs/teacher-app.md) ----
  //
  // The brand teal: the same look as the web app, so a teacher who uses both
  // meets one product. Status colours unchanged: a "Report owed" means the
  // same thing everywhere.
  static ThemeData teacherLight() => _build(
    _Palette.brand(
      brightness: Brightness.light,
      primary: TeacherBrand.teal,
      onPrimary: Colors.white,
      primarySoft: TeacherBrand.mint,
      primaryInk: BrandColors.tealInk,
    ),
    editorial: true,
  );

  static ThemeData teacherDark() => _build(
    _Palette.brand(
      brightness: Brightness.dark,
      primary: TeacherBrand.tealBright,
      onPrimary: BrandColors.deep,
      primarySoft: TeacherBrand.tealNight,
      primaryInk: BrandColors.nightText,
    ),
    editorial: true,
  );

  // ---- The Family app (docs/parent-student-app.md) ----
  //
  // The violet of the logo's "AI", on the brand's grounds. Status colours
  // unchanged: "Absent" is the same red a teacher sees.
  static ThemeData familyLight() => _build(
    _Palette.brand(
      brightness: Brightness.light,
      primary: FamilyBrand.violet,
      onPrimary: Colors.white,
      primarySoft: FamilyBrand.mist,
      primaryInk: FamilyBrand.violetDeep,
    ),
    editorial: true,
  );

  static ThemeData familyDark() => _build(
    _Palette.brand(
      brightness: Brightness.dark,
      primary: FamilyBrand.violetBright,
      onPrimary: BrandColors.deep,
      primarySoft: FamilyBrand.violetNight,
      primaryInk: BrandColors.nightText,
    ),
    editorial: true,
  );

  static ThemeData _build(_Palette p, {bool editorial = false}) {
    final dark = p.brightness == Brightness.dark;
    final cardRadius = editorial ? BrandRadii.card : radiusCard;
    final controlRadius = editorial ? BrandRadii.control : radiusControl;

    final seeded = ColorScheme.fromSeed(
      seedColor: p.primary,
      brightness: p.brightness,
      primary: p.primary,
      onPrimary: p.onPrimary,
      surface: p.surface,
      primaryContainer: p.primarySoft,
    );
    final colorScheme = editorial
        ? seeded.copyWith(
            onPrimaryContainer: p.primaryInk,
            secondary: p.accent,
            onSecondary: dark ? BrandColors.deep : Colors.white,
            secondaryContainer: p.primarySoft,
            onSecondaryContainer: p.primaryInk,
            tertiary: BrandColors.orange,
            onSurface: p.text,
            onSurfaceVariant: p.muted,
            outline: dark ? BrandColors.nightOutline : BrandColors.outline,
            outlineVariant: p.border,
            surfaceContainerLowest: p.surfaceTints[0],
            surfaceContainerLow: p.surfaceTints[1],
            surfaceContainer: p.surfaceTints[2],
            surfaceContainerHigh: p.surfaceTints[3],
            surfaceContainerHighest: p.surfaceTints[4],
            error: p.appColors.danger,
          )
        : seeded;

    // Text: DM Sans with Manrope headings for the web app, Poppins for the
    // phone apps. Every sub-theme that carries its own TextStyle (buttons,
    // chips, the DataTable, the SnackBar) names the font again, since those
    // are not guaranteed to inherit it from [textTheme].
    TextStyle body({Color? color, double? fontSize, FontWeight? fontWeight}) => editorial
        ? GoogleFonts.dmSans(color: color, fontSize: fontSize, fontWeight: fontWeight)
        : GoogleFonts.poppins(color: color, fontSize: fontSize, fontWeight: fontWeight);
    TextStyle heading({Color? color, double? fontSize, FontWeight? fontWeight}) => editorial
        ? GoogleFonts.manrope(
            color: color,
            fontSize: fontSize,
            fontWeight: fontWeight == FontWeight.w600 ? FontWeight.w800 : fontWeight,
            letterSpacing: -0.4,
          )
        : body(color: color, fontSize: fontSize, fontWeight: fontWeight);

    final base = Typography.material2021(platform: TargetPlatform.android).black
        .apply(bodyColor: p.text, displayColor: p.text);
    final bodyTheme = editorial ? GoogleFonts.dmSansTextTheme(base) : GoogleFonts.poppinsTextTheme(base);
    final textTheme = editorial
        ? bodyTheme.copyWith(
            displayLarge: heading(color: p.text, fontSize: 52, fontWeight: FontWeight.w600),
            displayMedium: heading(color: p.text, fontSize: 42, fontWeight: FontWeight.w600),
            displaySmall: heading(color: p.text, fontSize: 34, fontWeight: FontWeight.w600),
            headlineLarge: heading(color: p.text, fontSize: 30, fontWeight: FontWeight.w600),
            headlineMedium: heading(color: p.text, fontSize: 26, fontWeight: FontWeight.w600),
            headlineSmall: heading(color: p.text, fontSize: 23, fontWeight: FontWeight.w600),
            // A page's and a section's title: the heading face, as on the website.
            titleLarge: heading(color: p.text, fontSize: 22, fontWeight: FontWeight.w600),
            // A card's title: the text face, bold, so a dense screen stays easy to scan.
            titleMedium: body(color: p.text, fontSize: 16, fontWeight: FontWeight.w700),
            titleSmall: body(color: p.text, fontSize: 14, fontWeight: FontWeight.w700),
          )
        : bodyTheme.copyWith(
            // A slightly heavier weight than default reads better for an
            // admin dashboard's headings.
            titleLarge: body(color: p.text, fontWeight: FontWeight.w800),
            titleMedium: body(color: p.text, fontWeight: FontWeight.w700),
          );

    final controlShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(controlRadius));
    const buttonPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 13);

    return ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: p.background,
      // The web app's default face for any TextStyle that names none - a
      // button's own textStyle, a hand-built label - so nothing falls back
      // to Roboto beside the DM Sans around it.
      fontFamily: editorial ? GoogleFonts.dmSans().fontFamily : null,
      canvasColor: editorial ? p.surface : null,
      extensions: [p.appColors, p.authPalette],
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: p.surface,
        foregroundColor: p.text,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: editorial
            ? heading(color: p.text, fontSize: 21, fontWeight: FontWeight.w600)
            : body(color: p.text, fontSize: 20, fontWeight: FontWeight.w800),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(color: p.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: editorial ? heading(color: p.text, fontSize: 24, fontWeight: FontWeight.w600) : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(editorial ? BrandRadii.dialog : 18)),
      ),
      bottomSheetTheme: editorial
          ? BottomSheetThemeData(
              backgroundColor: p.surface,
              surfaceTintColor: Colors.transparent,
              showDragHandle: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(BrandRadii.dialog)),
              ),
            )
          : null,
      popupMenuTheme: editorial
          ? PopupMenuThemeData(
              color: p.surface,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(controlRadius),
                side: BorderSide(color: p.border),
              ),
            )
          : null,
      menuTheme: editorial
          ? MenuThemeData(
              style: MenuStyle(
                backgroundColor: WidgetStatePropertyAll(p.surface),
                surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(controlRadius),
                    side: BorderSide(color: p.border),
                  ),
                ),
              ),
            )
          : null,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        // One line is Material's default, and it cuts a sentence off at
        // the field's width: on a phone "Choose a passcode that is not a
        // straight run of digits" became "...that is not a straight...",
        // which tells somebody they are wrong without telling them how.
        errorMaxLines: 3,
        labelStyle: editorial ? body(color: p.muted) : null,
        floatingLabelStyle: editorial ? body(color: p.accent, fontWeight: FontWeight.w600) : null,
        hintStyle: editorial ? body(color: p.muted) : null,
        prefixIconColor: editorial ? p.muted : null,
        suffixIconColor: editorial ? p.muted : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: editorial ? colorScheme.outline : p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: editorial ? p.accent : p.primary, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: editorial ? 0 : null,
          padding: buttonPadding,
          textStyle: body(fontWeight: FontWeight.w700),
          shape: controlShape,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.primary,
          // The text colour that goes with that background, said for tonal
          // buttons too: FilledButton.tonal takes this theme's background
          // but, left alone, Material's tonal *foreground* - which in the
          // dark theme is a light grey on this light primary. On the trip
          // sheet the one button a crew member could press, Dropped, had
          // its label all but invisible (docs/driver-app.md, D9).
          foregroundColor: colorScheme.onPrimary,
          // Disabled said explicitly for both themes as well, so a greyed-
          // out button never outshines the live ones beside it.
          disabledBackgroundColor: colorScheme.onSurface.withValues(alpha: 0.12),
          disabledForegroundColor: colorScheme.onSurface.withValues(alpha: 0.38),
          padding: buttonPadding,
          textStyle: body(fontWeight: FontWeight.w700),
          shape: controlShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.primary,
          backgroundColor: editorial ? p.surface : null,
          side: BorderSide(color: editorial ? colorScheme.outline : p.border),
          padding: buttonPadding,
          textStyle: body(fontWeight: FontWeight.w700),
          shape: controlShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: editorial ? p.accent : p.primary,
          textStyle: body(fontWeight: editorial ? FontWeight.w700 : FontWeight.w600),
          shape: editorial ? controlShape : null,
        ),
      ),
      iconButtonTheme: editorial ? IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: p.text)) : null,
      floatingActionButtonTheme: editorial
          ? FloatingActionButtonThemeData(
              backgroundColor: p.primary,
              foregroundColor: colorScheme.onPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            )
          : null,
      snackBarTheme: SnackBarThemeData(
        backgroundColor: editorial ? (dark ? BrandColors.nightText : BrandColors.deep) : p.text,
        contentTextStyle: body(
          color: editorial ? (dark ? BrandColors.deep : Colors.white) : p.background,
          fontSize: 13,
        ),
        actionTextColor: editorial ? (dark ? BrandColors.teal : BrandColors.orange) : null,
        behavior: SnackBarBehavior.floating,
        // Floating alone still stretches to the full window width on
        // desktop/web - capping `width` is what actually makes it read as a
        // small toast instead of a full-width bar.
        width: 360,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(editorial ? 14 : 10)),
      ),
      tooltipTheme: editorial
          ? TooltipThemeData(
              decoration: BoxDecoration(
                color: dark ? BrandColors.nightText : BrandColors.deep,
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: body(color: dark ? BrandColors.deep : Colors.white, fontSize: 12),
            )
          : null,
      dividerTheme: DividerThemeData(color: p.border, space: 1),
      chipTheme: ChipThemeData(
        backgroundColor: p.primarySoft,
        labelStyle: body(
          color: editorial ? colorScheme.onPrimaryContainer : p.primary,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
        side: BorderSide.none,
        shape: editorial ? const StadiumBorder() : null,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),
      tabBarTheme: editorial
          ? TabBarThemeData(
              labelColor: p.accent,
              unselectedLabelColor: p.muted,
              indicatorColor: p.accent,
              indicatorSize: TabBarIndicatorSize.label,
              dividerColor: p.border,
              labelStyle: body(fontWeight: FontWeight.w700, fontSize: 14),
              unselectedLabelStyle: body(fontWeight: FontWeight.w600, fontSize: 14),
            )
          : null,
      segmentedButtonTheme: editorial
          ? SegmentedButtonThemeData(
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: p.primarySoft,
                selectedForegroundColor: colorScheme.onPrimaryContainer,
                side: BorderSide(color: colorScheme.outline),
                textStyle: body(fontWeight: FontWeight.w600),
              ),
            )
          : null,
      listTileTheme: editorial
          ? ListTileThemeData(
              selectedColor: p.accent,
              selectedTileColor: p.primarySoft,
              iconColor: p.muted,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(controlRadius)),
            )
          : null,
      dataTableTheme: DataTableThemeData(
        // The website's table head: a faint blush band, small muted capitals.
        headingRowColor: WidgetStatePropertyAll(editorial ? p.surfaceTints[2] : p.background),
        dataRowColor: editorial
            ? WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.hovered) ? p.surfaceTints[1] : p.surface,
              )
            : WidgetStatePropertyAll(p.surface),
        headingTextStyle: body(color: p.appColors.muted, fontWeight: FontWeight.w700, fontSize: editorial ? 12.5 : 13),
        dividerThickness: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: editorial ? p.accent : p.primary,
        linearTrackColor: editorial ? p.primarySoft : null,
        circularTrackColor: editorial ? Colors.transparent : null,
      ),
    );
  }
}

/// The handful of colours a theme is built from.
class _Palette {
  const _Palette({
    required this.brightness,
    required this.primary,
    required this.onPrimary,
    required this.primarySoft,
    required this.accent,
    required this.background,
    required this.surface,
    required this.surfaceTints,
    required this.text,
    required this.muted,
    required this.border,
    required this.appColors,
    required this.authPalette,
    required this.primaryInk,
  });

  /// An app's palette on the School365AI grounds - the web app's, and since
  /// B1 every phone app's - with its own [primary].
  factory _Palette.brand({
    required Brightness brightness,
    required Color primary,
    required Color onPrimary,
    required Color primarySoft,
    required Color primaryInk,
  }) {
    final dark = brightness == Brightness.dark;

    return _Palette(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      primarySoft: primarySoft,
      accent: primary,
      background: dark ? BrandColors.night : BrandColors.workspace,
      surface: dark ? BrandColors.nightSurface : Colors.white,
      surfaceTints: dark
          ? const [Color(0xFF0F1D33), Color(0xFF13233B), Color(0xFF172A44), Color(0xFF1B304D), Color(0xFF203656)]
          : const [Colors.white, Color(0xFFFBFCFD), Color(0xFFF5F8FB), Color(0xFFEFF4F8), Color(0xFFE9EFF5)],
      text: dark ? BrandColors.nightText : BrandColors.ink,
      muted: dark ? BrandColors.nightMuted : BrandColors.muted,
      border: dark ? BrandColors.nightLine : BrandColors.line,
      appColors: dark ? AppColors.brandDark : AppColors.brandLight,
      authPalette: dark ? AuthPalette.brandDark : AuthPalette.brandLight,
      primaryInk: primaryInk,
    );
  }

  final Brightness brightness;
  final Color primary;
  final Color? onPrimary;
  final Color primarySoft;

  /// Text and icons on [primarySoft]: a chosen chip, a selected row.
  final Color primaryInk;

  /// The colour that marks what is active or chosen: teal in the web app.
  final Color accent;
  final Color background;
  final Color surface;

  /// The five surface containers, lowest to highest.
  final List<Color> surfaceTints;
  final Color text;
  final Color muted;
  final Color border;
  final AppColors appColors;
  final AuthPalette authPalette;
}
