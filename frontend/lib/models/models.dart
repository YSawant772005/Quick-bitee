class ApiException implements Exception {
  ApiException(this.statusCode, this.code, this.message, {this.details = const {}});

  final int statusCode;
  final String code;
  final String message;
  final Map<String, dynamic> details;

  bool get isExpiredToken => statusCode == 401;
}

class User {
  User({required this.id, required this.email, required this.role});

  final String id;
  final String email;
  final String role;

  factory User.fromJson(Map<String, dynamic> j) =>
      User(id: j['id'], email: j['email'], role: j['role']);
}

class AuthSession {
  AuthSession({required this.accessToken, required this.expiresIn, required this.user});

  final String accessToken;
  final int expiresIn;
  final User user;
}

class Restaurant {
  Restaurant({
    required this.id,
    required this.name,
    required this.description,
    required this.cuisine,
    required this.imageUrl,
    required this.available,
  });

  final String id;
  final String name;
  final String description;
  final String cuisine;
  final String imageUrl;
  final bool available;

  factory Restaurant.fromJson(Map<String, dynamic> j) => Restaurant(
        id: j['id'],
        name: j['name'],
        description: j['description'],
        cuisine: j['cuisine'],
        imageUrl: j['image_url'],
        available: j['available'],
      );
}

class MenuItem {
  MenuItem({
    required this.id,
    required this.restaurantId,
    required this.name,
    required this.description,
    required this.priceMinor,
    required this.currency,
    required this.imageUrl,
    required this.available,
  });

  final String id;
  final String restaurantId;
  final String name;
  final String description;
  final int priceMinor;
  final String currency;
  final String imageUrl;
  final bool available;

  factory MenuItem.fromJson(Map<String, dynamic> j) => MenuItem(
        id: j['id'],
        restaurantId: j['restaurant_id'],
        name: j['name'],
        description: j['description'],
        priceMinor: j['price_minor'],
        currency: j['currency'],
        imageUrl: j['image_url'],
        available: j['available'],
      );
}

class Paginated<T> {
  Paginated({required this.items, required this.page, required this.pageSize, required this.total});

  final List<T> items;
  final int page;
  final int pageSize;
  final int total;

  int get totalPages => total == 0 ? 1 : (total + pageSize - 1) ~/ pageSize;
}

/// A menu item enriched with its restaurant, used for dish-first browsing.
class Dish {
  Dish({
    required this.id,
    required this.restaurantId,
    required this.restaurantName,
    required this.name,
    required this.description,
    required this.priceMinor,
    required this.currency,
    required this.imageUrl,
    required this.available,
    required this.orderCount,
  });

  final String id;
  final String restaurantId;
  final String restaurantName;
  final String name;
  final String description;
  final int priceMinor;
  final String currency;
  final String imageUrl;
  final bool available;
  final int orderCount;

  factory Dish.fromJson(Map<String, dynamic> j) => Dish(
        id: j['id'],
        restaurantId: j['restaurant_id'],
        restaurantName: j['restaurant_name'] ?? '',
        name: j['name'],
        description: j['description'],
        priceMinor: j['price_minor'],
        currency: j['currency'],
        imageUrl: j['image_url'] ?? '',
        available: j['available'] ?? true,
        orderCount: j['order_count'] ?? 0,
      );

  /// Converts to a cart menu item so a dish card can add straight to the cart.
  MenuItem asMenuItem() => MenuItem(
        id: id,
        restaurantId: restaurantId,
        name: name,
        description: description,
        priceMinor: priceMinor,
        currency: currency,
        imageUrl: imageUrl,
        available: available,
      );
}

class OrderLine {
  OrderLine({
    required this.menuItemId,
    required this.name,
    required this.unitPriceMinor,
    required this.quantity,
    this.imageUrl = '',
  });

  final String menuItemId;
  final String name;
  final int unitPriceMinor;
  final int quantity;
  final String imageUrl;

  int get lineTotalMinor => unitPriceMinor * quantity;

  Map<String, dynamic> toJson() => {'menu_item_id': menuItemId, 'quantity': quantity};
}

class OrderAccepted {
  OrderAccepted({required this.orderId, required this.status, required this.totalMinor, required this.currency});

  final String orderId;
  final String status;
  final int totalMinor;
  final String currency;

  factory OrderAccepted.fromJson(Map<String, dynamic> j) => OrderAccepted(
        orderId: j['order_id'],
        status: j['status'],
        totalMinor: j['total_minor'],
        currency: j['currency'],
      );
}

class Driver {
  Driver({required this.driverName, required this.vehicle, required this.etaMinutes});

  final String driverName;
  final String vehicle;
  final int etaMinutes;

  factory Driver.fromJson(Map<String, dynamic> j) =>
      Driver(driverName: j['driver_name'], vehicle: j['vehicle'], etaMinutes: j['eta_minutes']);
}

class OrderDetail {
  OrderDetail({
    required this.id,
    required this.restaurantId,
    required this.restaurantName,
    required this.status,
    required this.totalMinor,
    required this.currency,
    required this.deliveryAddress,
    required this.version,
    this.failureReason,
    this.driver,
    required this.items,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String restaurantId;
  final String restaurantName;
  final String status;
  final int totalMinor;
  final String currency;
  final String deliveryAddress;
  final int version;
  final String? failureReason;
  final Driver? driver;
  final List<OrderLine> items;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isTerminal => const {'PAYMENT_FAILED', 'FAILED', 'DRIVER_ASSIGNED'}.contains(status);

  factory OrderDetail.fromJson(Map<String, dynamic> j) => OrderDetail(
        id: j['id'],
        restaurantId: j['restaurant_id'],
        restaurantName: j['restaurant_name'] ?? '',
        status: j['status'],
        totalMinor: j['total_minor'],
        currency: j['currency'],
        deliveryAddress: j['delivery_address'],
        version: j['version'],
        failureReason: j['failure_reason'],
        driver: j['driver'] == null ? null : Driver.fromJson(j['driver']),
        items: [
          for (final i in j['items'])
            OrderLine(
              menuItemId: i['menu_item_id'],
              name: i['name'],
              unitPriceMinor: i['unit_price_minor'],
              quantity: i['quantity'],
              imageUrl: i['image_url'] ?? '',
            ),
        ],
        createdAt: DateTime.parse(j['created_at']),
        updatedAt: DateTime.parse(j['updated_at']),
      );
}

class OrderListItem {
  OrderListItem({
    required this.id,
    required this.status,
    required this.totalMinor,
    required this.currency,
    required this.createdAt,
    required this.restaurantName,
    required this.itemSummary,
    this.thumbnailUrl = '',
  });

  final String id;
  final String status;
  final int totalMinor;
  final String currency;
  final DateTime createdAt;
  final String restaurantName;
  final String itemSummary;
  final String thumbnailUrl;

  factory OrderListItem.fromJson(Map<String, dynamic> j) => OrderListItem(
        id: j['id'],
        status: j['status'],
        totalMinor: j['total_minor'],
        currency: j['currency'],
        createdAt: DateTime.parse(j['created_at']),
        restaurantName: j['restaurant_name'] ?? '',
        itemSummary: j['item_summary'] ?? '',
        thumbnailUrl: j['thumbnail_url'] ?? '',
      );
}

class HistoryEntry {
  HistoryEntry({required this.status, required this.version, required this.note, required this.createdAt});

  final String status;
  final int version;
  final String note;
  final DateTime createdAt;

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        status: j['status'],
        version: j['version'],
        note: j['note'],
        createdAt: DateTime.parse(j['created_at']),
      );
}

class AppNotification {
  AppNotification({
    required this.id,
    required this.orderId,
    required this.eventType,
    required this.title,
    required this.message,
    required this.createdAt,
  });

  final String id;
  final String orderId;
  final String eventType;
  final String title;
  final String message;
  final DateTime createdAt;

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'],
        orderId: j['order_id'],
        eventType: j['event_type'],
        title: j['title'],
        message: j['message'],
        createdAt: DateTime.parse(j['created_at']),
      );
}

class DailyRevenue {
  DailyRevenue({required this.date, required this.orders, required this.revenueMinor});

  final String date;
  final int orders;
  final int revenueMinor;

  factory DailyRevenue.fromJson(Map<String, dynamic> j) => DailyRevenue(
        date: j['date'],
        orders: j['orders'],
        revenueMinor: j['revenue_minor'],
      );
}

class TopDish {
  TopDish({
    required this.name,
    required this.quantity,
    required this.revenueMinor,
    this.menuItemId = '',
    this.imageUrl = '',
    this.restaurantName = '',
  });

  final String name;
  final int quantity;
  final int revenueMinor;
  final String menuItemId;
  final String imageUrl;
  final String restaurantName;

  factory TopDish.fromJson(Map<String, dynamic> j) => TopDish(
        name: j['name'],
        quantity: j['quantity'],
        revenueMinor: j['revenue_minor'],
        menuItemId: j['menu_item_id'] ?? '',
        imageUrl: j['image_url'] ?? '',
        restaurantName: j['restaurant_name'] ?? '',
      );
}

class TopRestaurant {
  TopRestaurant({
    required this.restaurantId,
    required this.name,
    this.imageUrl = '',
    this.orders = 0,
    this.revenueMinor = 0,
  });

  final String restaurantId;
  final String name;
  final String imageUrl;
  final int orders;
  final int revenueMinor;

  factory TopRestaurant.fromJson(Map<String, dynamic> j) => TopRestaurant(
        restaurantId: j['restaurant_id'],
        name: j['name'],
        imageUrl: j['image_url'] ?? '',
        orders: j['orders'] ?? 0,
        revenueMinor: j['revenue_minor'] ?? 0,
      );
}

/// A metric for the selected period plus the previous equivalent period.
///
/// [changePct] is null when the previous period had no data, so the UI never
/// renders a fabricated percentage.
class MetricDelta {
  MetricDelta({required this.current, required this.previous, this.changePct});

  final int current;
  final int previous;
  final double? changePct;

  factory MetricDelta.fromJson(Map<String, dynamic> j) => MetricDelta(
        current: j['current'] ?? 0,
        previous: j['previous'] ?? 0,
        changePct: (j['change_pct'] as num?)?.toDouble(),
      );
}

class PeriodComparison {
  PeriodComparison({this.dateFrom, this.dateTo, required this.orders, required this.revenue, required this.customers, required this.aov});

  final String? dateFrom;
  final String? dateTo;
  final MetricDelta orders;
  final MetricDelta revenue;
  final MetricDelta customers;
  final MetricDelta aov;

  factory PeriodComparison.fromJson(Map<String, dynamic> j) => PeriodComparison(
        dateFrom: j['date_from'],
        dateTo: j['date_to'],
        orders: MetricDelta.fromJson(j['orders'] ?? const {}),
        revenue: MetricDelta.fromJson(j['revenue_minor'] ?? const {}),
        customers: MetricDelta.fromJson(j['active_customers'] ?? const {}),
        aov: MetricDelta.fromJson(j['avg_order_value_minor'] ?? const {}),
      );
}

class AttentionItem {
  AttentionItem({required this.key, required this.label, required this.count});

  final String key;
  final String label;
  final int count;

  factory AttentionItem.fromJson(Map<String, dynamic> j) => AttentionItem(
        key: j['key'],
        label: j['label'],
        count: j['count'] ?? 0,
      );
}

class AdminSummary {
  AdminSummary({
    required this.totalOrders,
    required this.byStatus,
    required this.pendingOutbox,
    required this.retryBacklog,
    required this.quarantineCount,
    this.currency = 'INR',
    this.totalRevenueMinor = 0,
    this.successfulOrders = 0,
    this.failedOrders = 0,
    this.activeCustomers = 0,
    this.avgOrderValueMinor = 0,
    this.revenueByDay = const [],
    this.topDishes = const [],
    this.dateFrom,
    this.dateTo,
    this.granularity = 'day',
    this.comparison,
    this.attention = const [],
    this.topRestaurants = const [],
    this.unavailableMenuItems = 0,
    this.unavailableRestaurants = 0,
    this.totalCustomers = 0,
    this.activeDeliveries = 0,
    this.paymentFailedOrders = 0,
  });

  final int totalOrders;
  final Map<String, int> byStatus;
  final int pendingOutbox;
  final int retryBacklog;
  final int quarantineCount;
  final String currency;
  final int totalRevenueMinor;
  final int successfulOrders;
  final int failedOrders;
  final int activeCustomers;
  final int avgOrderValueMinor;
  final List<DailyRevenue> revenueByDay;
  final List<TopDish> topDishes;

  /// Period actually applied by the server; both null means "all time".
  final String? dateFrom;
  final String? dateTo;
  final String granularity;
  final PeriodComparison? comparison;
  final List<AttentionItem> attention;
  final List<TopRestaurant> topRestaurants;
  final int unavailableMenuItems;
  final int unavailableRestaurants;
  final int totalCustomers;
  final int activeDeliveries;
  final int paymentFailedOrders;

  int countOf(String status) => byStatus[status] ?? 0;

  factory AdminSummary.fromJson(Map<String, dynamic> j) => AdminSummary(
        totalOrders: j['total_orders'],
        byStatus: {for (final e in (j['by_status'] as Map).entries) e.key as String: e.value as int},
        pendingOutbox: j['pending_outbox'],
        retryBacklog: j['retry_backlog'],
        quarantineCount: j['quarantine_count'],
        currency: j['currency'] ?? 'INR',
        totalRevenueMinor: j['total_revenue_minor'] ?? 0,
        successfulOrders: j['successful_orders'] ?? 0,
        failedOrders: j['failed_orders'] ?? 0,
        activeCustomers: j['active_customers'] ?? 0,
        avgOrderValueMinor: j['avg_order_value_minor'] ?? 0,
        revenueByDay: [
          for (final d in (j['revenue_by_day'] ?? [])) DailyRevenue.fromJson(d),
        ],
        topDishes: [
          for (final d in (j['top_dishes'] ?? [])) TopDish.fromJson(d),
        ],
        dateFrom: j['date_from'],
        dateTo: j['date_to'],
        granularity: j['granularity'] ?? 'day',
        comparison: j['comparison'] == null ? null : PeriodComparison.fromJson(j['comparison']),
        attention: [
          for (final a in (j['attention'] ?? [])) AttentionItem.fromJson(a),
        ],
        topRestaurants: [
          for (final r in (j['top_restaurants'] ?? [])) TopRestaurant.fromJson(r),
        ],
        unavailableMenuItems: j['unavailable_menu_items'] ?? 0,
        unavailableRestaurants: j['unavailable_restaurants'] ?? 0,
        totalCustomers: j['total_customers'] ?? 0,
        activeDeliveries: j['active_deliveries'] ?? 0,
        paymentFailedOrders: j['payment_failed_orders'] ?? 0,
      );
}

// ---------------------------------------------------------------------------
// Admin console entities
// ---------------------------------------------------------------------------

/// Admin view of an order row: adds customer, payment state and item count on
/// top of the customer-facing list item.
class AdminOrderListItem {
  AdminOrderListItem({
    required this.id,
    required this.status,
    required this.totalMinor,
    required this.currency,
    required this.createdAt,
    required this.restaurantName,
    required this.itemSummary,
    this.customerId = '',
    this.customerEmail = '',
    this.paymentStatus,
    this.paymentAttempts = 0,
    this.itemCount = 0,
    this.updatedAt,
  });

  final String id;
  final String status;
  final int totalMinor;
  final String currency;
  final DateTime createdAt;
  final String restaurantName;
  final String itemSummary;
  final String customerId;
  final String customerEmail;
  final String? paymentStatus;
  final int paymentAttempts;
  final int itemCount;
  final DateTime? updatedAt;

  factory AdminOrderListItem.fromJson(Map<String, dynamic> j) => AdminOrderListItem(
        id: j['id'],
        status: j['status'],
        totalMinor: j['total_minor'],
        currency: j['currency'],
        createdAt: DateTime.parse(j['created_at']),
        restaurantName: j['restaurant_name'] ?? '',
        itemSummary: j['item_summary'] ?? '',
        customerId: j['customer_id'] ?? '',
        customerEmail: j['customer_email'] ?? '',
        paymentStatus: j['payment_status'],
        paymentAttempts: j['payment_attempts'] ?? 0,
        itemCount: j['item_count'] ?? 0,
        updatedAt: j['updated_at'] == null ? null : DateTime.tryParse(j['updated_at']),
      );
}

/// Admin order detail: customer identity, payment outcome and fulfilment
/// timeline in one payload, so the detail view needs no extra round trips.
class AdminOrderDetail {
  AdminOrderDetail({
    required this.id,
    required this.restaurantId,
    required this.restaurantName,
    required this.status,
    required this.totalMinor,
    required this.currency,
    required this.deliveryAddress,
    required this.version,
    required this.items,
    required this.createdAt,
    required this.updatedAt,
    required this.timeline,
    this.failureReason,
    this.driver,
    this.customerId = '',
    this.customerEmail = '',
    this.paymentStatus,
    this.paymentAttempts = 0,
    this.paymentFailureReason,
  });

  final String id;
  final String restaurantId;
  final String restaurantName;
  final String status;
  final int totalMinor;
  final String currency;
  final String deliveryAddress;
  final int version;
  final String? failureReason;
  final Driver? driver;
  final List<OrderLine> items;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String customerId;
  final String customerEmail;
  final String? paymentStatus;
  final int paymentAttempts;
  final String? paymentFailureReason;
  final List<HistoryEntry> timeline;

  /// Items subtotal, before any adjustments (the API has no tax/fee fields).
  int get itemsSubtotalMinor => items.fold<int>(0, (sum, l) => sum + l.lineTotalMinor);

  factory AdminOrderDetail.fromJson(Map<String, dynamic> j) => AdminOrderDetail(
        id: j['id'],
        restaurantId: j['restaurant_id'],
        restaurantName: j['restaurant_name'] ?? '',
        status: j['status'],
        totalMinor: j['total_minor'],
        currency: j['currency'],
        deliveryAddress: j['delivery_address'] ?? '',
        version: j['version'],
        failureReason: j['failure_reason'],
        driver: j['driver'] == null ? null : Driver.fromJson(j['driver']),
        items: [
          for (final i in j['items'])
            OrderLine(
              menuItemId: i['menu_item_id'],
              name: i['name'],
              unitPriceMinor: i['unit_price_minor'],
              quantity: i['quantity'],
              imageUrl: i['image_url'] ?? '',
            ),
        ],
        createdAt: DateTime.parse(j['created_at']),
        updatedAt: DateTime.parse(j['updated_at']),
        customerId: j['customer_id'] ?? '',
        customerEmail: j['customer_email'] ?? '',
        paymentStatus: j['payment_status'],
        paymentAttempts: j['payment_attempts'] ?? 0,
        paymentFailureReason: j['payment_failure_reason'],
        timeline: [
          for (final t in (j['timeline'] ?? [])) HistoryEntry.fromJson(t),
        ],
      );
}

class AdminRestaurant {
  AdminRestaurant({
    required this.id,
    required this.name,
    required this.description,
    required this.cuisine,
    required this.imageUrl,
    required this.available,
    this.menuItemCount = 0,
    this.availableItemCount = 0,
    this.orderCount = 0,
    this.revenueMinor = 0,
  });

  final String id;
  final String name;
  final String description;
  final String cuisine;
  final String imageUrl;
  final bool available;
  final int menuItemCount;
  final int availableItemCount;
  final int orderCount;
  final int revenueMinor;

  factory AdminRestaurant.fromJson(Map<String, dynamic> j) => AdminRestaurant(
        id: j['id'],
        name: j['name'],
        description: j['description'] ?? '',
        cuisine: j['cuisine'] ?? '',
        imageUrl: j['image_url'] ?? '',
        available: j['available'] ?? true,
        menuItemCount: j['menu_item_count'] ?? 0,
        availableItemCount: j['available_item_count'] ?? 0,
        orderCount: j['order_count'] ?? 0,
        revenueMinor: j['revenue_minor'] ?? 0,
      );
}

class AdminMenuItem {
  AdminMenuItem({
    required this.id,
    required this.restaurantId,
    required this.restaurantName,
    required this.name,
    required this.description,
    required this.priceMinor,
    required this.currency,
    required this.imageUrl,
    required this.available,
    this.unitsSold = 0,
    this.revenueMinor = 0,
  });

  final String id;
  final String restaurantId;
  final String restaurantName;
  final String name;
  final String description;
  final int priceMinor;
  final String currency;
  final String imageUrl;
  final bool available;
  final int unitsSold;
  final int revenueMinor;

  factory AdminMenuItem.fromJson(Map<String, dynamic> j) => AdminMenuItem(
        id: j['id'],
        restaurantId: j['restaurant_id'],
        restaurantName: j['restaurant_name'] ?? '',
        name: j['name'],
        description: j['description'] ?? '',
        priceMinor: j['price_minor'],
        currency: j['currency'] ?? 'INR',
        imageUrl: j['image_url'] ?? '',
        available: j['available'] ?? true,
        unitsSold: j['units_sold'] ?? 0,
        revenueMinor: j['revenue_minor'] ?? 0,
      );
}

class AdminCustomer {
  AdminCustomer({
    required this.id,
    required this.email,
    required this.role,
    required this.registeredAt,
    this.totalOrders = 0,
    this.successfulOrders = 0,
    this.activeOrders = 0,
    this.lastOrderAt,
    this.totalSpentMinor = 0,
    this.currency = 'INR',
  });

  final String id;
  final String email;
  final String role;
  final DateTime registeredAt;
  final int totalOrders;
  final int successfulOrders;
  final int activeOrders;
  final DateTime? lastOrderAt;
  final int totalSpentMinor;
  final String currency;

  factory AdminCustomer.fromJson(Map<String, dynamic> j) => AdminCustomer(
        id: j['id'],
        email: j['email'],
        role: j['role'],
        registeredAt: DateTime.parse(j['registered_at']),
        totalOrders: j['total_orders'] ?? 0,
        successfulOrders: j['successful_orders'] ?? 0,
        activeOrders: j['active_orders'] ?? 0,
        lastOrderAt: j['last_order_at'] == null ? null : DateTime.tryParse(j['last_order_at']),
        totalSpentMinor: j['total_spent_minor'] ?? 0,
        currency: j['currency'] ?? 'INR',
      );
}

class AdminDelivery {
  AdminDelivery({
    required this.orderId,
    required this.driverName,
    required this.vehicle,
    required this.etaMinutes,
    required this.orderStatus,
    required this.totalMinor,
    required this.currency,
    required this.createdAt,
    required this.deliveryAddress,
    this.restaurantName = '',
    this.customerEmail = '',
  });

  final String orderId;
  final String driverName;
  final String vehicle;
  final int etaMinutes;
  final String orderStatus;
  final String restaurantName;
  final String customerEmail;
  final int totalMinor;
  final String currency;
  final DateTime createdAt;
  final String deliveryAddress;

  factory AdminDelivery.fromJson(Map<String, dynamic> j) => AdminDelivery(
        orderId: j['order_id'],
        driverName: j['driver_name'] ?? '',
        vehicle: j['vehicle'] ?? '',
        etaMinutes: j['eta_minutes'] ?? 0,
        orderStatus: j['order_status'],
        restaurantName: j['restaurant_name'] ?? '',
        customerEmail: j['customer_email'] ?? '',
        totalMinor: j['total_minor'],
        currency: j['currency'] ?? 'INR',
        createdAt: DateTime.parse(j['created_at']),
        deliveryAddress: j['delivery_address'] ?? '',
      );
}

class AnalyticsBucket {
  AnalyticsBucket({required this.label, required this.count, required this.revenueMinor});

  final String label;
  final int count;
  final int revenueMinor;

  factory AnalyticsBucket.fromJson(Map<String, dynamic> j) => AnalyticsBucket(
        label: j['label'],
        count: j['count'] ?? 0,
        revenueMinor: j['revenue_minor'] ?? 0,
      );
}

class AdminAnalytics {
  AdminAnalytics({
    required this.currency,
    required this.dateFrom,
    required this.dateTo,
    required this.granularity,
    required this.totalOrders,
    required this.totalRevenueMinor,
    required this.successfulOrders,
    required this.failedOrders,
    required this.avgOrderValueMinor,
    required this.activeCustomers,
    required this.avgItemsPerOrder,
    required this.revenueByDay,
    required this.revenueByRestaurant,
    required this.ordersByWeekday,
    required this.ordersByHour,
    required this.ordersByStatus,
  });

  final String currency;
  final String? dateFrom;
  final String? dateTo;
  final String granularity;
  final int totalOrders;
  final int totalRevenueMinor;
  final int successfulOrders;
  final int failedOrders;
  final int avgOrderValueMinor;
  final int activeCustomers;
  final double avgItemsPerOrder;
  final List<DailyRevenue> revenueByDay;
  final List<TopRestaurant> revenueByRestaurant;
  final List<AnalyticsBucket> ordersByWeekday;
  final List<AnalyticsBucket> ordersByHour;
  final Map<String, int> ordersByStatus;

  factory AdminAnalytics.fromJson(Map<String, dynamic> j) => AdminAnalytics(
        currency: j['currency'] ?? 'INR',
        dateFrom: j['date_from'],
        dateTo: j['date_to'],
        granularity: j['granularity'] ?? 'day',
        totalOrders: j['total_orders'] ?? 0,
        totalRevenueMinor: j['total_revenue_minor'] ?? 0,
        successfulOrders: j['successful_orders'] ?? 0,
        failedOrders: j['failed_orders'] ?? 0,
        avgOrderValueMinor: j['avg_order_value_minor'] ?? 0,
        activeCustomers: j['active_customers'] ?? 0,
        avgItemsPerOrder: (j['avg_items_per_order'] ?? 0).toDouble(),
        revenueByDay: [
          for (final d in (j['revenue_by_day'] ?? [])) DailyRevenue.fromJson(d),
        ],
        revenueByRestaurant: [
          for (final d in (j['revenue_by_restaurant'] ?? [])) TopRestaurant.fromJson(d),
        ],
        ordersByWeekday: [
          for (final d in (j['orders_by_weekday'] ?? [])) AnalyticsBucket.fromJson(d),
        ],
        ordersByHour: [
          for (final d in (j['orders_by_hour'] ?? [])) AnalyticsBucket.fromJson(d),
        ],
        ordersByStatus: {
          for (final e in ((j['orders_by_status'] ?? {}) as Map).entries)
            e.key as String: e.value as int,
        },
      );
}
