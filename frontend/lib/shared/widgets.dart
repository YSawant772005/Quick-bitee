import 'package:flutter/material.dart';

import '../core/config.dart';

String formatMinor(int minor, {String currency = 'INR'}) {
  final value = minor / 100.0;
  final text = value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
  final symbol = currency == 'INR' ? '₹' : '$currency ';
  return '$symbol$text';
}

class AppImage extends StatelessWidget {
  const AppImage({super.key, required this.url, this.height = 120, this.width = double.infinity});

  final String url;
  final double height;
  final double width;

  @override
  Widget build(BuildContext context) {
    final resolved = AppConfig.resolveAssetUrl(url);
    return Image.network(
      resolved,
      height: height,
      width: width,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          height: height,
          width: width,
          color: const Color(0xFFFFE8DB),
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
      errorBuilder: (context, error, stack) => Container(
        height: height,
        width: width,
        color: const Color(0xFFFFE8DB),
        child: const Icon(Icons.fastfood_outlined, color: Color(0xFFC2410C), size: 40),
      ),
    );
  }
}

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.height = 16, this.width = double.infinity});

  final double height;
  final double width;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: const Color(0xFFF1E4DA),
          borderRadius: BorderRadius.circular(8),
        ),
      );
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 48, color: Color(0xFFB91C1C)),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF7C2D12))),
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
            ],
          ),
        ),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: const Color(0xFFC2410C)),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(subtitle!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF7C2D12))),
              ],
            ],
          ),
        ),
      );
}

Color statusColor(String status) => switch (status) {
      'PENDING' => const Color(0xFFA16207),
      'PAID' => const Color(0xFF1D4ED8),
      'CONFIRMED' => const Color(0xFF15803D),
      'DRIVER_ASSIGNED' => const Color(0xFF0F766E),
      'PAYMENT_FAILED' || 'FAILED' => const Color(0xFFB91C1C),
      _ => Colors.black87,
    };

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status, this.size = 12});

  final String status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.replaceAll('_', ' '),
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: size),
      ),
    );
  }
}

class QtyStepper extends StatelessWidget {
  const QtyStepper({super.key, required this.quantity, required this.onChanged, this.compact = false});

  final int quantity;
  final ValueChanged<int> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 28.0 : 36.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          onPressed: quantity > 1 ? () => onChanged(quantity - 1) : null,
          icon: const Icon(Icons.remove),
          constraints: BoxConstraints(minWidth: size, minHeight: size),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text('$quantity', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ),
        IconButton.filledTonal(
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          onPressed: () => onChanged(quantity + 1),
          icon: const Icon(Icons.add),
          constraints: BoxConstraints(minWidth: size, minHeight: size),
        ),
      ],
    );
  }
}
