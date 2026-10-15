import 'package:flutter/material.dart';

/// QuickBitee design tokens.
///
/// Palette: **Forest Green + Lime Green + Warm Cream** with realistic food
/// photography. These are the single source of truth for colour; screens must
/// reference these constants instead of hard-coding hex values.
class AppColors {
  // Brand
  static const forest = Color(0xFF123B35);
  static const forestDeep = Color(0xFF0B2925);
  static const forestSoft = Color(0xFF1C5149);
  static const lime = Color(0xFFB8E986);
  static const limeDark = Color(0xFF97C95F);
  static const limeSoft = Color(0xFFEBF7DA);

  // Surfaces
  static const cream = Color(0xFFF7F4EB);
  static const creamDeep = Color(0xFFEFEADC);
  static const white = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFEFEEE5);

  // Text
  static const textPrimary = Color(0xFF17231F);
  static const textSecondary = Color(0xFF6D7771);
  static const textMuted = Color(0xFF9AA39D);
  static const onForest = Color(0xFFF3F7F2);
  static const onForestMuted = Color(0xFFA9BDB6);

  // Lines
  static const border = Color(0xFFE6E8E0);
  static const borderSubtle = Color(0xFFF0F1EA);

  // Semantics
  static const success = Color(0xFF218653);
  static const warning = Color(0xFFE6A23C);
  static const error = Color(0xFFD94B4B);
  static const info = Color(0xFF2F6FB3);

  // Tints used for badges/backgrounds
  static const successSoft = Color(0xFFE3F2E9);
  static const warningSoft = Color(0xFFFBF0DC);
  static const errorSoft = Color(0xFFFBE5E5);
  static const infoSoft = Color(0xFFE7EFF8);
  static const forestSoft2 = Color(0xFFE4ECE9);
}

/// Spacing scale (multiples of 4).
class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;
  static const huge = 64.0;
}

/// Corner radii.
class AppRadius {
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 20.0;
  static const xl = 28.0;
  static const pill = 999.0;
}

/// Layout breakpoints (logical pixels).
class AppBreakpoints {
  static const mobile = 0.0;
  static const tablet = 720.0;
  static const desktop = 1080.0;

  static bool isDesktop(double w) => w >= desktop;
  static bool isTablet(double w) => w >= tablet && w < desktop;
  static bool isMobile(double w) => w < tablet;
}

/// Soft, tasteful shadows. Avoid heavy elevation.
class AppShadows {
  static const card = [
    BoxShadow(color: Color(0x0F17231F), blurRadius: 18, offset: Offset(0, 6)),
  ];
  static const raised = [
    BoxShadow(color: Color(0x1A17231F), blurRadius: 28, offset: Offset(0, 12)),
  ];
  static const subtle = [
    BoxShadow(color: Color(0x0A17231F), blurRadius: 10, offset: Offset(0, 3)),
  ];
}

class AppTheme {
  // --- Backwards-compatible aliases (older screens referenced these) ---
  static const primary = AppColors.forest;
  static const primaryDark = AppColors.forestDeep;
  static const primaryLight = AppColors.limeSoft;
  static const onPrimarySurface = Colors.white;
  static const bg = AppColors.cream;
  static const surface = AppColors.white;
  static const surfaceMuted = AppColors.surfaceMuted;
  static const border = AppColors.border;
  static const borderSubtle = AppColors.borderSubtle;
  static const textPrimary = AppColors.textPrimary;
  static const textSecondary = AppColors.textSecondary;
  static const textMuted = AppColors.textMuted;
  static const accent = AppColors.limeDark;
  static const accentLight = AppColors.limeSoft;
  static const success = AppColors.success;
  static const danger = AppColors.error;
  static const warning = AppColors.warning;

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.forest,
      primary: AppColors.forest,
      onPrimary: Colors.white,
      primaryContainer: AppColors.limeSoft,
      onPrimaryContainer: AppColors.forestDeep,
      secondary: AppColors.lime,
      onSecondary: AppColors.forestDeep,
      secondaryContainer: AppColors.limeSoft,
      onSecondaryContainer: AppColors.forestDeep,
      tertiary: AppColors.limeDark,
      surface: AppColors.white,
      onSurface: AppColors.textPrimary,
      surfaceContainerHighest: AppColors.surfaceMuted,
      error: AppColors.error,
      outline: AppColors.border,
      outlineVariant: AppColors.borderSubtle,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.cream,
      splashFactory: InkSparkle.splashFactory,
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontSize: 56, fontWeight: FontWeight.w800, height: 1.04, letterSpacing: -1.4, color: AppColors.textPrimary),
        displayMedium: TextStyle(fontSize: 44, fontWeight: FontWeight.w800, height: 1.06, letterSpacing: -1.1, color: AppColors.textPrimary),
        displaySmall: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, height: 1.1, letterSpacing: -0.7, color: AppColors.textPrimary),
        headlineMedium: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.15, letterSpacing: -0.4, color: AppColors.textPrimary),
        headlineSmall: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.2, letterSpacing: -0.2, color: AppColors.textPrimary),
        titleLarge: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.25, color: AppColors.textPrimary),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.3, color: AppColors.textPrimary),
        titleSmall: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.3, color: AppColors.textPrimary),
        bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, height: 1.5, color: AppColors.textPrimary),
        bodyMedium: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w400, height: 1.5, color: AppColors.textSecondary),
        bodySmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, height: 1.45, color: AppColors.textSecondary),
        labelLarge: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, letterSpacing: 0.1, color: AppColors.textPrimary),
        labelMedium: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0.2, color: AppColors.textSecondary),
        labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: AppColors.textSecondary),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: AppColors.cream,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.2),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.forestDeep,
        contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        actionTextColor: AppColors.lime,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.forest, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.error, width: 1.4),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.error, width: 1.8),
        ),
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14.5),
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.forest,
          foregroundColor: Colors.white,
          minimumSize: const Size(44, 50),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          elevation: 0,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.forest,
          minimumSize: const Size(44, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: const BorderSide(color: AppColors.border, width: 1.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.forest,
          textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.white,
        selectedColor: AppColors.forest,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        secondaryLabelStyle: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1, space: 24),
      iconTheme: const IconThemeData(color: AppColors.textPrimary),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.forest),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.forestDeep,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Admin console palette.
///
/// The admin shell is deliberately a different environment from the customer
/// app: an ink-dark sidebar (#102B27) against a cool canvas (#F5F6F2), white
/// cards, hairline borders and compact type. No gradients, no promo imagery —
/// this is an operations surface, not a storefront.
class AdminColors {
  /// Sidebar background.
  static const sidebar = Color(0xFF102B27);

  /// Hover/fill on the sidebar.
  static const sidebarHover = Color(0xFF17403A);

  /// Muted green used for the active navigation row.
  static const sidebarActive = Color(0xFF1E5247);

  /// Hairline divider inside the sidebar.
  static const sidebarLine = Color(0xFF1C3F39);

  /// Secondary sidebar text.
  static const sidebarText = Color(0xFF9DB3AC);

  /// Page canvas — cooler and flatter than the customer cream.
  static const canvas = Color(0xFFF5F6F2);

  /// Card/table surface.
  static const card = AppColors.white;

  /// Strongest text.
  static const ink = AppColors.textPrimary; // #17231F

  /// Secondary text.
  static const inkSoft = AppColors.textSecondary; // #6D7771

  /// Muted text (labels, timestamps).
  static const inkMuted = AppColors.textMuted;

  /// Hairline border for cards, tables and inputs.
  static const line = AppColors.border; // #E6E8E0

  /// Even fainter line (table row separators).
  static const lineSoft = AppColors.borderSubtle;

  /// Brand accent for the logo, active rail and key emphasis.
  static const brand = AppColors.forest; // #123B35

  /// Lime accent — used sparingly (active nav icon, small highlights).
  static const accent = AppColors.lime; // #B8E986

  /// Selected/zebra row fill.
  static const rowFill = Color(0xFFF0F2EC);

  /// Metric card tint.
  static const metricFill = Color(0xFFFAFBF8);
}

/// Compact typography for the admin console.
///
/// One step smaller and tighter than the customer text theme so dense tables
/// and metric grids stay readable without scrolling.
class AdminType {
  static const pageTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w800,
    height: 1.2,
    letterSpacing: -0.3,
    color: AdminColors.ink,
  );

  static const sectionTitle = TextStyle(
    fontSize: 14.5,
    fontWeight: FontWeight.w700,
    height: 1.3,
    color: AdminColors.ink,
  );

  static const body = TextStyle(fontSize: 13.5, height: 1.45, color: AdminColors.ink);

  static const bodySoft = TextStyle(fontSize: 13.5, height: 1.45, color: AdminColors.inkSoft);

  static const label = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.3,
    color: AdminColors.inkMuted,
  );

  static const caption = TextStyle(fontSize: 11.5, height: 1.35, color: AdminColors.inkMuted);

  static const metricValue = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w800,
    height: 1.05,
    letterSpacing: -0.7,
    color: AdminColors.ink,
  );

  static const tableHeader = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.5,
    color: AdminColors.inkMuted,
  );

  static const cell = TextStyle(fontSize: 13, height: 1.35, color: AdminColors.ink);

  static const mono = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.2,
    color: AdminColors.ink,
    fontFamily: 'monospace',
  );
}

/// Sidebar geometry for the admin shell.
class AdminLayout {
  static const sidebarWidth = 244.0;
  static const headerHeight = 64.0;
  static const contentMaxWidth = 1440.0;
  /// Radius for admin cards — tighter than the customer storefront cards.
  static const radius = 10.0;
}
