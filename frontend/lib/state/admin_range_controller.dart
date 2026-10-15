import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Presets offered by the admin date-range control.
enum AdminRangePreset { today, last7, last30, custom }

/// The reporting period selected in the admin header.
///
/// Held in one place so Overview, Orders and Analytics always agree on the
/// window they describe, and so the previous-period comparison computed by the
/// server lines up with the range shown on screen.
class AdminRange {
  const AdminRange({this.preset = AdminRangePreset.last7, this.customFrom, this.customTo});

  final AdminRangePreset preset;
  final DateTime? customFrom;
  final DateTime? customTo;

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Inclusive `[dateFrom, dateTo]` pair in ISO `YYYY-MM-DD` form.
  ({String from, String to}) resolve([DateTime? now]) {
    final today = _day(now ?? DateTime.now());
    switch (preset) {
      case AdminRangePreset.today:
        return (from: _iso(today), to: _iso(today));
      case AdminRangePreset.last7:
        return (from: _iso(today.subtract(const Duration(days: 6))), to: _iso(today));
      case AdminRangePreset.last30:
        return (from: _iso(today.subtract(const Duration(days: 29))), to: _iso(today));
      case AdminRangePreset.custom:
        final from = customFrom == null ? null : _day(customFrom!);
        final to = customTo == null ? null : _day(customTo!);
        if (from == null || to == null) {
          return (from: _iso(today.subtract(const Duration(days: 6))), to: _iso(today));
        }
        // Never hand the API an inverted range.
        final start = from.isAfter(to) ? to : from;
        final end = from.isAfter(to) ? from : to;
        return (from: _iso(start), to: _iso(end));
    }
  }

  String get label {
    switch (preset) {
      case AdminRangePreset.today:
        return 'Today';
      case AdminRangePreset.last7:
        return 'Last 7 days';
      case AdminRangePreset.last30:
        return 'Last 30 days';
      case AdminRangePreset.custom:
        final r = resolve();
        return '${r.from} → ${r.to}';
    }
  }
}

class AdminRangeController extends Notifier<AdminRange> {
  @override
  AdminRange build() => const AdminRange();

  void select(AdminRangePreset preset) {
    if (preset == state.preset && preset != AdminRangePreset.custom) return;
    if (preset == AdminRangePreset.custom) {
      final fallback = const AdminRange().resolve();
      state = AdminRange(
        preset: AdminRangePreset.custom,
        customFrom: DateTime.parse(fallback.from),
        customTo: DateTime.parse(fallback.to),
      );
      return;
    }
    state = AdminRange(preset: preset);
  }

  void setCustom(DateTime from, DateTime to) {
    state = AdminRange(preset: AdminRangePreset.custom, customFrom: from, customTo: to);
  }
}

final adminRangeProvider =
    NotifierProvider<AdminRangeController, AdminRange>(AdminRangeController.new);
