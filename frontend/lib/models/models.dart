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

class OrderLine {
  OrderLine({required this.menuItemId, required this.name, required this.unitPriceMinor, required this.quantity});

  final String menuItemId;
  final String name;
  final int unitPriceMinor;
  final int quantity;

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
  });

  final String id;
  final String status;
  final int totalMinor;
  final String currency;
  final DateTime createdAt;
  final String restaurantName;
  final String itemSummary;

  factory OrderListItem.fromJson(Map<String, dynamic> j) => OrderListItem(
        id: j['id'],
        status: j['status'],
        totalMinor: j['total_minor'],
        currency: j['currency'],
        createdAt: DateTime.parse(j['created_at']),
        restaurantName: j['restaurant_name'] ?? '',
        itemSummary: j['item_summary'] ?? '',
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

class AdminSummary {
  AdminSummary({
    required this.totalOrders,
    required this.byStatus,
    required this.pendingOutbox,
    required this.retryBacklog,
    required this.quarantineCount,
  });

  final int totalOrders;
  final Map<String, int> byStatus;
  final int pendingOutbox;
  final int retryBacklog;
  final int quarantineCount;

  factory AdminSummary.fromJson(Map<String, dynamic> j) => AdminSummary(
        totalOrders: j['total_orders'],
        byStatus: {for (final e in (j['by_status']).entries) e.key: e.value as int},
        pendingOutbox: j['pending_outbox'],
        retryBacklog: j['retry_backlog'],
        quarantineCount: j['quarantine_count'],
      );
}
