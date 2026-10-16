import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/config.dart';
import 'theme.dart';

/// Formats minor units (paise) as a display price. Always shows the currency
/// symbol; keeps whole rupees tidy (₹220 not ₹220.00).
String formatMinor(int minor, {String currency = 'INR'}) {
  final value = minor / 100.0;
  final text = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
  final symbol = currency == 'INR' ? '₹' : '$currency ';
  return '$symbol$text';
}

/// Compact rupee formatting for chart axes / KPI values (₹1.2k, ₹3.4L).
String formatCompactCurrency(int minor, {String currency = 'INR'}) {
  final value = minor / 100.0;
  final symbol = currency == 'INR' ? '₹' : '$currency ';
  if (value >= 10000000) return '$symbol${(value / 10000000).toStringAsFixed(1)}Cr';
  if (value >= 100000) return '$symbol${(value / 100000).toStringAsFixed(1)}L';
  if (value >= 1000) return '$symbol${(value / 1000).toStringAsFixed(1)}k';
  return '$symbol${value.toStringAsFixed(0)}';
}

/// A network image with a branded, non-broken fallback and a stable loading
/// state. Use everywhere food photography is shown so every screen behaves
/// identically when an image is missing or slow.
class AppImage extends StatelessWidget {
  const AppImage({
    super.key,
    required this.url,
    this.height,
    this.width = double.infinity,
    this.fit = BoxFit.cover,
    this.radius = 0,
    this.aspectRatio,
    this.fallbackIcon = Icons.restaurant_menu,
    this.fallbackColor = AppColors.creamDeep,
  });

  final String url;
  final double? height;
  final double width;
  final BoxFit fit;
  final double radius;
  final double? aspectRatio;
  final IconData fallbackIcon;
  final Color fallbackColor;

  @override
  Widget build(BuildContext context) {
    Widget child = url.trim().isEmpty ? _fallback() : _network();
    if (aspectRatio != null) {
      child = AspectRatio(aspectRatio: aspectRatio!, child: child);
    }
    if (radius > 0) {
      child = ClipRRect(borderRadius: BorderRadius.circular(radius), child: child);
    }
    return child;
  }

  Widget _fallback() => Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [fallbackColor, AppColors.cream],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        alignment: Alignment.center,
        child: Icon(fallbackIcon, color: AppColors.forest.withValues(alpha: 0.45), size: 34),
      );

  Widget _network() => Image.network(
        AppConfig.resolveAssetUrl(url),
        height: height,
        width: width,
        fit: fit,
        gaplessPlayback: true,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            height: height,
            width: width,
            color: fallbackColor,
            alignment: Alignment.center,
            child: const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.forest),
            ),
          );
        },
        errorBuilder: (context, error, stack) => _fallback(),
      );
}

/// QuickBitee logo mark — a forest tile with a lime accent and cutlery glyph.
/// Vector-composed so it scales crisply on web, desktop and mobile.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40, this.onDark = false});

  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.forestSoft, AppColors.forestDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.29),
        boxShadow: AppShadows.subtle,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.restaurant, color: onDark ? Colors.white : AppColors.lime, size: size * 0.54),
          Positioned(
            top: size * 0.14,
            right: size * 0.14,
            child: Container(
              width: size * 0.20,
              height: size * 0.20,
              decoration: const BoxDecoration(color: AppColors.lime, shape: BoxShape.circle),
            ),
          ),
        ],
      ),
    );
  }
}

/// Logo mark + wordmark.
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.size = 40,
    this.showWordmark = true,
    this.onDark = false,
    this.onTap,
  });

  final double size;
  final bool showWordmark;
  final bool onDark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(size: size, onDark: onDark),
        if (showWordmark) ...[
          SizedBox(width: size * 0.28),
          RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: size * 0.52,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                color: onDark ? Colors.white : AppColors.textPrimary,
              ),
              children: const [
                TextSpan(text: 'Quick'),
                TextSpan(text: 'Bitee', style: TextStyle(color: AppColors.limeDark)),
              ],
            ),
          ),
        ],
      ],
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: content,
        ),
      ),
    );
  }
}

/// A white rounded surface with a hairline border and soft shadow.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.color = AppColors.white,
    this.radius = AppRadius.lg,
    this.border = true,
    this.clip = false,
    this.width,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color color;
  final double radius;
  final bool border;
  final bool clip;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: border ? Border.all(color: AppColors.border) : null,
        boxShadow: AppShadows.subtle,
      ),
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      child: onTap == null
          ? content
          : Material(
              color: Colors.transparent,
              child: InkWell(borderRadius: BorderRadius.circular(radius), onTap: onTap, child: content),
            ),
    );
  }
}

/// Heading for a content section, with an optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onSeeAll,
    this.seeAllLabel = 'See all',
    this.dark = false,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onSeeAll;
  final String seeAllLabel;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: dark ? Colors.white : AppColors.textPrimary,
                    ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: dark ? AppColors.onForestMuted : AppColors.textSecondary,
                      ),
                ),
              ],
            ],
          ),
        ),
        if (onSeeAll != null)
          TextButton(
            onPressed: onSeeAll,
            style: TextButton.styleFrom(
              foregroundColor: dark ? AppColors.lime : AppColors.forest,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(seeAllLabel),
                const SizedBox(width: 2),
                const Icon(Icons.arrow_forward_rounded, size: 16),
              ],
            ),
          ),
      ],
    );
  }
}

/// Small rounded label ("badge"/"pill").
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    this.icon,
    this.color = AppColors.forest,
    this.background,
    this.dense = false,
  });

  final String label;
  final IconData? icon;
  final Color color;
  final Color? background;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final bg = background ?? color.withValues(alpha: 0.12);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 3 : 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 12 : 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: dense ? 11 : 12,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Maps a backend order status to a friendly, honest label.
String friendlyStatus(String status) => switch (status) {
      'PENDING' => 'Order placed',
      'PAID' => 'Payment received',
      'CONFIRMED' => 'Preparing',
      'DRIVER_ASSIGNED' => 'Out for delivery',
      'PAYMENT_FAILED' => 'Payment failed',
      'FAILED' => 'Cancelled',
      _ => status.replaceAll('_', ' '),
    };

Color statusColor(String status) => switch (status) {
      'PENDING' => AppColors.warning,
      'PAID' => AppColors.info,
      'CONFIRMED' => AppColors.success,
      'DRIVER_ASSIGNED' => AppColors.forest,
      'PAYMENT_FAILED' || 'FAILED' => AppColors.error,
      _ => AppColors.textSecondary,
    };

IconData statusIcon(String status) => switch (status) {
      'PENDING' => Icons.receipt_long_outlined,
      'PAID' => Icons.payments_outlined,
      'CONFIRMED' => Icons.soup_kitchen_outlined,
      'DRIVER_ASSIGNED' => Icons.delivery_dining_outlined,
      'PAYMENT_FAILED' || 'FAILED' => Icons.error_outline,
      _ => Icons.info_outline,
    };

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status, this.dense = false});

  final String status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return Pill(
      label: friendlyStatus(status),
      color: color,
      background: color.withValues(alpha: 0.12),
      dense: dense,
    );
  }
}

/// Price with the currency symbol, in the brand's emphasis colour.
class PriceText extends StatelessWidget {
  const PriceText({super.key, required this.minor, this.currency = 'INR', this.size = 16, this.color = AppColors.textPrimary});

  final int minor;
  final String currency;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      formatMinor(minor, currency: currency),
      style: TextStyle(fontWeight: FontWeight.w800, fontSize: size, color: color, letterSpacing: -0.2),
    );
  }
}

/// Quantity stepper used in the cart and on dish cards.
class QtyStepper extends StatelessWidget {
  const QtyStepper({
    super.key,
    required this.quantity,
    required this.onChanged,
    this.compact = false,
    this.minQuantity = 1,
  });

  final int quantity;
  final ValueChanged<int> onChanged;
  final bool compact;
  final int minQuantity;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 30.0 : 38.0;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.forest,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _btn(
            icon: Icons.remove_rounded,
            enabled: quantity > minQuantity,
            onTap: () => onChanged(quantity - 1),
            size: size,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '$quantity',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: compact ? 14 : 16,
                color: Colors.white,
              ),
            ),
          ),
          _btn(icon: Icons.add_rounded, enabled: true, onTap: () => onChanged(quantity + 1), size: size),
        ],
      ),
    );
  }

  Widget _btn({required IconData icon, required bool enabled, required VoidCallback onTap, required double size}) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: compact ? 16 : 19,
            color: enabled ? AppColors.lime : AppColors.onForestMuted.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.height = 16, this.width = double.infinity, this.radius = 10});

  final double height;
  final double width;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

/// Skeleton placeholder matching a food card's shape.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.imageHeight = 150});

  final double imageHeight;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(height: imageHeight, radius: AppRadius.lg),
          const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(height: 18, width: 190),
                SizedBox(height: 10),
                SkeletonBox(height: 13, width: 260),
                SizedBox(height: 8),
                SkeletonBox(height: 13, width: 140),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(color: AppColors.limeSoft, shape: BoxShape.circle),
                child: Icon(icon, size: 44, color: AppColors.forest),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(subtitle!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
              ],
              if (action != null) ...[
                const SizedBox(height: AppSpacing.lg),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, required this.onRetry, this.title = 'Something went wrong'});

  final String message;
  final VoidCallback onRetry;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: AppColors.errorSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.cloud_off_outlined, size: 40, color: AppColors.error),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 19),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Branded, unobtrusive confirmation toast used for add-to-cart feedback.
void showAppSnack(BuildContext context, String message, {IconData icon = Icons.check_circle_outline, SnackBarAction? action}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 1900),
        content: Row(
          children: [
            Icon(icon, color: AppColors.lime, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        action: action,
      ),
    );
}

/// A horizontally scrolling strip for filter chips, category tiles and offer
/// rails.
///
/// Flutter only scrolls a horizontal list with a trackpad or a touch swipe by
/// default: a plain mouse wheel emits a *vertical* delta, so on the web the row
/// would not move and chips past the right edge were unreachable. This widget
/// adds what a bare [SingleChildScrollView] lacks:
///
///  * a [Scrollbar] so the strip is visibly scrollable,
///  * mouse-wheel support — the wheel delta is mapped onto the strip,
///  * click-and-drag with a mouse, via an expanded [ScrollBehavior].
///
/// Only the strip scrolls horizontally; the surrounding page is untouched. At
/// either end the wheel event is left alone so the page keeps scrolling.
class HorizontalChipScroller extends StatefulWidget {
  const HorizontalChipScroller({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  @override
  State<HorizontalChipScroller> createState() =>
      _HorizontalChipScrollerState();
}

class _HorizontalChipScrollerState extends State<HorizontalChipScroller> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_controller.hasClients) return;
    final position = _controller.position;
    // A genuine horizontal delta (trackpad swipe) wins; otherwise the vertical
    // wheel is treated as horizontal movement over this strip.
    final delta = event.scrollDelta.dx != 0
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    if (delta == 0) return;
    final target = (position.pixels + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    // At either end, leave the event for the page so it keeps scrolling.
    if (target == position.pixels) return;
    // Claim the signal so the page behind the strip does not scroll too.
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      if (event is PointerScrollEvent && _controller.hasClients) {
        final pos = _controller.position;
        _controller.jumpTo((pos.pixels + delta)
            .clamp(pos.minScrollExtent, pos.maxScrollExtent));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget child = ScrollConfiguration(
      behavior: const _HorizontalDragBehavior(),
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: widget.padding,
        child: widget.child,
      ),
    );
    child = Scrollbar(controller: _controller, child: child);
    child = Listener(onPointerSignal: _onPointerSignal, child: child);
    if (widget.semanticLabel != null) {
      child = Semantics(
        container: true,
        label: widget.semanticLabel,
        child: child,
      );
    }
    return child;
  }
}

/// Lets a mouse drag a horizontal strip (touch/stylus/trackpad keep working).
class _HorizontalDragBehavior extends MaterialScrollBehavior {
  const _HorizontalDragBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}
