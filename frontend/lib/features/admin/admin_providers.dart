import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../state/admin_range_controller.dart';
import '../../state/auth_controller.dart';

/// Bumped by any admin "Refresh" action. Every admin provider watches it, so a
/// single increment re-fetches the whole console without needing to know which
/// family instances are alive.
final adminRefreshTokenProvider = StateProvider<int>((ref) => 0);

/// Revenue bucketing for the chart: `day`, `week` or `month`.
final adminGranularityProvider = StateProvider<String>((ref) => 'day');

/// Convenience refresh for a page: bumps the shared token and re-runs the
/// period-scoped aggregations.
void refreshAdminData(WidgetRef ref) {
  ref.read(adminRefreshTokenProvider.notifier).state++;
  ref.invalidate(adminSummaryProvider);
  ref.invalidate(adminAnalyticsProvider);
}

// ---------------------------------------------------------------------------
// Query objects (value equality so family keys behave predictably)
// ---------------------------------------------------------------------------

class AdminOrdersQuery {
  const AdminOrdersQuery({
    this.status,
    this.search,
    this.sort = 'created_desc',
    this.page = 1,
    this.pageSize = 20,
  });

  final String? status;
  final String? search;
  final String sort;
  final int page;
  final int pageSize;

  AdminOrdersQuery copyWith({
    String? status,
    String? search,
    String? sort,
    int? page,
    int? pageSize,
    bool clearStatus = false,
    bool clearSearch = false,
  }) {
    return AdminOrdersQuery(
      status: clearStatus ? null : status ?? this.status,
      search: clearSearch ? null : search ?? this.search,
      sort: sort ?? this.sort,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }

  /// Returns a query reset to page 1 — used whenever a filter changes.
  AdminOrdersQuery filtered({String? status, String? search, bool clearStatus = false, bool clearSearch = false}) {
    return copyWith(
      status: status,
      search: search,
      clearStatus: clearStatus,
      clearSearch: clearSearch,
      page: 1,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AdminOrdersQuery &&
      other.status == status &&
      other.search == search &&
      other.sort == sort &&
      other.page == page &&
      other.pageSize == pageSize;

  @override
  int get hashCode => Object.hash(status, search, sort, page, pageSize);
}

class AdminCatalogQuery {
  const AdminCatalogQuery({this.search, this.available, this.restaurantId, this.page = 1, this.pageSize = 20});

  final String? search;
  final bool? available;
  final String? restaurantId;
  final int page;
  final int pageSize;

  AdminCatalogQuery copyWith({
    String? search,
    bool? available,
    String? restaurantId,
    int? page,
    int? pageSize,
    bool clearSearch = false,
    bool clearAvailable = false,
    bool clearRestaurant = false,
  }) {
    return AdminCatalogQuery(
      search: clearSearch ? null : search ?? this.search,
      available: clearAvailable ? null : available ?? this.available,
      restaurantId: clearRestaurant ? null : restaurantId ?? this.restaurantId,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }

  AdminCatalogQuery filtered({String? search, bool? available, String? restaurantId, bool clearSearch = false, bool clearAvailable = false, bool clearRestaurant = false}) {
    return copyWith(
      search: search,
      available: available,
      restaurantId: restaurantId,
      clearSearch: clearSearch,
      clearAvailable: clearAvailable,
      clearRestaurant: clearRestaurant,
      page: 1,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AdminCatalogQuery &&
      other.search == search &&
      other.available == available &&
      other.restaurantId == restaurantId &&
      other.page == page &&
      other.pageSize == pageSize;

  @override
  int get hashCode => Object.hash(search, available, restaurantId, page, pageSize);
}

class AdminSearchQuery {
  const AdminSearchQuery({this.search, this.page = 1, this.pageSize = 20});

  final String? search;
  final int page;
  final int pageSize;

  AdminSearchQuery filtered({String? search, bool clearSearch = false, int? page, int? pageSize}) => AdminSearchQuery(
        search: clearSearch ? null : search ?? this.search,
        page: page ?? 1,
        pageSize: pageSize ?? this.pageSize,
      );

  @override
  bool operator ==(Object other) =>
      other is AdminSearchQuery && other.search == search && other.page == page && other.pageSize == pageSize;

  @override
  int get hashCode => Object.hash(search, page, pageSize);
}

// ---------------------------------------------------------------------------
// Overview / analytics
// ---------------------------------------------------------------------------

/// Summary for the selected reporting period, including the previous-period
/// comparison computed server-side.
final adminSummaryProvider = FutureProvider.autoDispose<AdminSummary>((ref) {
  ref.watch(adminRefreshTokenProvider);
  final period = ref.watch(adminRangeProvider).resolve();
  final granularity = ref.watch(adminGranularityProvider);
  return ref.watch(apiClientProvider).adminSummary(
        dateFrom: period.from,
        dateTo: period.to,
        granularity: granularity,
      );
});

final adminAnalyticsProvider = FutureProvider.autoDispose<AdminAnalytics>((ref) {
  ref.watch(adminRefreshTokenProvider);
  final period = ref.watch(adminRangeProvider).resolve();
  final granularity = ref.watch(adminGranularityProvider);
  return ref.watch(apiClientProvider).adminAnalytics(
        dateFrom: period.from,
        dateTo: period.to,
        granularity: granularity,
      );
});

// ---------------------------------------------------------------------------
// Orders
// ---------------------------------------------------------------------------

final adminOrdersProvider =
    FutureProvider.autoDispose.family<Paginated<AdminOrderListItem>, AdminOrdersQuery>((ref, query) {
  ref.watch(adminRefreshTokenProvider);
  final period = ref.watch(adminRangeProvider).resolve();
  return ref.watch(apiClientProvider).adminOrders(
        page: query.page,
        pageSize: query.pageSize,
        status: query.status,
        search: query.search,
        sort: query.sort,
        dateFrom: period.from,
        dateTo: period.to,
      );
});

final adminOrderDetailProvider = FutureProvider.autoDispose.family<AdminOrderDetail, String>((ref, id) {
  return ref.watch(apiClientProvider).adminOrder(id);
});

// ---------------------------------------------------------------------------
// Catalogue
// ---------------------------------------------------------------------------

final adminRestaurantsProvider =
    FutureProvider.autoDispose.family<Paginated<AdminRestaurant>, AdminCatalogQuery>((ref, query) {
  ref.watch(adminRefreshTokenProvider);
  return ref.watch(apiClientProvider).adminRestaurants(
        page: query.page,
        pageSize: query.pageSize,
        search: query.search,
        available: query.available,
      );
});

final adminMenuItemsProvider =
    FutureProvider.autoDispose.family<Paginated<AdminMenuItem>, AdminCatalogQuery>((ref, query) {
  ref.watch(adminRefreshTokenProvider);
  return ref.watch(apiClientProvider).adminMenuItems(
        page: query.page,
        pageSize: query.pageSize,
        search: query.search,
        restaurantId: query.restaurantId,
        available: query.available,
      );
});

// ---------------------------------------------------------------------------
// Customers & deliveries
// ---------------------------------------------------------------------------

final adminCustomersProvider =
    FutureProvider.autoDispose.family<Paginated<AdminCustomer>, AdminSearchQuery>((ref, query) {
  ref.watch(adminRefreshTokenProvider);
  return ref.watch(apiClientProvider)
      .adminCustomers(page: query.page, pageSize: query.pageSize, search: query.search);
});

final adminDeliveriesProvider =
    FutureProvider.autoDispose.family<Paginated<AdminDelivery>, AdminSearchQuery>((ref, query) {
  ref.watch(adminRefreshTokenProvider);
  return ref.watch(apiClientProvider)
      .adminDeliveries(page: query.page, pageSize: query.pageSize, search: query.search);
});
