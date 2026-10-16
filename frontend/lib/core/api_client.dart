import 'package:dio/dio.dart';

import '../models/models.dart';

class ApiClient {
  ApiClient({Dio? dio, String? baseUrl})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl ?? 'http://127.0.0.1:8000/api/v1',
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 15),
            ));

  final Dio _dio;
  String? _token;
  void Function()? onUnauthorized;

  set token(String? value) => _token = value;

  void attachAuthHeader() {
    _dio.options.headers['Authorization'] =
        _token == null ? null : 'Bearer $_token';
  }

  Future<Response<T>> _guard<T>(Future<Response<T>> Function() call) async {
    try {
      attachAuthHeader();
      return await call();
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  ApiException _mapError(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      return ApiException(
        e.response?.statusCode ?? 0,
        data['code']?.toString() ?? 'UNKNOWN',
        data['message']?.toString() ?? 'Request failed.',
        details: (data['details'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
    }
    final status = e.response?.statusCode ?? 0;
    if (status == 401) {
      onUnauthorized?.call();
      return ApiException(
          401, 'UNAUTHENTICATED', 'Your session has expired. Sign in again.');
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return ApiException(
          0, 'TIMEOUT', 'The request timed out. You can safely retry.');
    }
    if (e.error is ApiException) return e.error as ApiException;
    return ApiException(
        status, 'NETWORK', 'Network error. Check your connection.');
  }

  Future<AuthSession> login(
      {required String email, required String password}) async {
    final resp = await _guard(() => _dio.post<Map<String, dynamic>>(
          '/auth/login',
          data: {'email': email, 'password': password},
        ));
    final data = resp.data!;
    return AuthSession(
      accessToken: data['access_token'],
      expiresIn: data['expires_in'],
      user: User.fromJson(data['user']),
    );
  }

  Future<User> me() async {
    final resp = await _guard(() => _dio.get<Map<String, dynamic>>('/auth/me'));
    return User.fromJson(resp.data!);
  }

  Future<Paginated<Restaurant>> restaurants({
    int page = 1,
    int pageSize = 20,
    String? search,
    String? category,
    String? foodType,
    String? sort,
  }) async {
    final resp = await _guard(() => _dio.get<Map<String, dynamic>>(
          '/restaurants',
          queryParameters: {
            'page': page,
            'page_size': pageSize,
            if (search != null && search.isNotEmpty) 'search': search,
            if (category != null && category.isNotEmpty) 'category': category,
            if (foodType != null && foodType.isNotEmpty) 'food_type': foodType,
            if (sort != null && sort.isNotEmpty) 'sort': sort,
          },
        ));
    final data = resp.data!;
    return Paginated(
      items: [for (final j in data['items']) Restaurant.fromJson(j)],
      page: data['page'],
      pageSize: data['page_size'],
      total: data['total'],
    );
  }

  /// Loads the complete matching restaurant set for catalogue screens.
  ///
  /// The API remains paginated (and this method still honours its filters),
  /// but callers that render a catalogue must not silently lose entries after
  /// the first 100 rows.
  Future<Paginated<Restaurant>> allRestaurants({
    String? search,
    String? category,
    String? foodType,
    String? sort,
  }) async {
    const pageSize = 100;
    final first = await restaurants(
      pageSize: pageSize,
      search: search,
      category: category,
      foodType: foodType,
      sort: sort,
    );
    if (first.totalPages <= 1) return first;
    final items = <Restaurant>[...first.items];
    for (var page = 2; page <= first.totalPages; page++) {
      final next = await restaurants(
        page: page,
        pageSize: pageSize,
        search: search,
        category: category,
        foodType: foodType,
        sort: sort,
      );
      items.addAll(next.items);
    }
    return Paginated(
        items: items, page: 1, pageSize: items.length, total: first.total);
  }

  /// Full detail payload for one restaurant (address, hours, ETA, rating…).
  ///
  /// Throws an [ApiException] when the server returns an unexpected payload
  /// (e.g. the generic list envelope), so callers can fall back gracefully
  /// instead of rendering a half-built restaurant.
  Future<Restaurant> restaurantDetail(String restaurantId) async {
    final resp = await _guard(() =>
        _dio.get<Map<String, dynamic>>('/restaurants/$restaurantId'));
    final data = resp.data;
    final id = data?['id'];
    if (data == null || id is! String || id.isEmpty) {
      throw ApiException(
          200, 'INVALID_RESPONSE', 'Restaurant details unavailable.');
    }
    return Restaurant.fromJson(data);
  }

  Future<Paginated<MenuItem>> menu(
    String restaurantId, {
    int page = 1,
    int pageSize = 50,
    String? search,
    String? foodType,
    String? category,
    String? sort,
  }) async {
    final resp = await _guard(() => _dio.get<Map<String, dynamic>>(
          '/restaurants/$restaurantId/menu',
          queryParameters: {
            'page': page,
            'page_size': pageSize,
            if (search != null && search.isNotEmpty) 'search': search,
            if (foodType != null && foodType.isNotEmpty) 'food_type': foodType,
            if (category != null && category.isNotEmpty) 'category': category,
            if (sort != null && sort.isNotEmpty) 'sort': sort,
          },
        ));
    final data = resp.data!;
    return Paginated(
      items: [for (final j in data['items']) MenuItem.fromJson(j)],
      page: data['page'],
      pageSize: data['page_size'],
      total: data['total'],
    );
  }

  Future<Paginated<MenuItem>> allMenu(
    String restaurantId, {
    String? search,
    String? foodType,
    String? category,
    String? sort,
  }) async {
    const pageSize = 100;
    final first = await menu(restaurantId,
        pageSize: pageSize,
        search: search,
        foodType: foodType,
        category: category,
        sort: sort);
    if (first.totalPages <= 1) return first;
    final items = <MenuItem>[...first.items];
    for (var page = 2; page <= first.totalPages; page++) {
      final next = await menu(restaurantId,
          page: page,
          pageSize: pageSize,
          search: search,
          foodType: foodType,
          category: category,
          sort: sort);
      items.addAll(next.items);
    }
    return Paginated(
        items: items, page: 1, pageSize: items.length, total: first.total);
  }

  Future<Paginated<Dish>> dishes({
    int page = 1,
    int pageSize = 12,
    String? search,
    String sort = 'popular',
    String? category,
    String? foodType,
  }) async {
    final resp = await _guard(() => _dio.get<Map<String, dynamic>>(
          '/dishes',
          queryParameters: {
            'page': page,
            'page_size': pageSize,
            'sort': sort,
            if (search != null && search.isNotEmpty) 'search': search,
            if (category != null && category.isNotEmpty) 'category': category,
            if (foodType != null && foodType.isNotEmpty) 'food_type': foodType,
          },
        ));
    final data = resp.data!;
    return Paginated(
      items: [for (final j in data['items']) Dish.fromJson(j)],
      page: data['page'],
      pageSize: data['page_size'],
      total: data['total'],
    );
  }

  /// Dish-first browsing across every restaurant, paged through completely so a
  /// catalogue screen never silently drops rows after the first API page.
  Future<Paginated<Dish>> allDishes({
    String? search,
    String? category,
    String? foodType,
    String sort = 'popular',
  }) async {
    const pageSize = 100;
    final first = await dishes(
        pageSize: pageSize,
        search: search,
        category: category,
        foodType: foodType,
        sort: sort);
    if (first.totalPages <= 1) return first;
    final items = <Dish>[...first.items];
    for (var page = 2; page <= first.totalPages; page++) {
      final next = await dishes(
          page: page,
          pageSize: pageSize,
          search: search,
          category: category,
          foodType: foodType,
          sort: sort);
      items.addAll(next.items);
    }
    return Paginated(
        items: items, page: 1, pageSize: items.length, total: first.total);
  }

  /// Homepage banners + offers. Missing/empty payloads degrade to an empty set,
  /// so a stripped-down or older backend never breaks the home screen.
  Future<Promotions> promotions() async {
    final resp =
        await _guard(() => _dio.get<Map<String, dynamic>>('/promotions'));
    return Promotions.fromJson(resp.data ?? const {});
  }

  Future<OrderAccepted> placeOrder({
    required String restaurantId,
    required String deliveryAddress,
    required List<OrderLine> items,
    required String idempotencyKey,
  }) async {
    final resp = await _guard(() => _dio.post<Map<String, dynamic>>(
          '/orders',
          data: {
            'restaurant_id': restaurantId,
            'delivery_address': deliveryAddress,
            'items': [for (final i in items) i.toJson()],
          },
          options: Options(headers: {'Idempotency-Key': idempotencyKey}),
        ));
    return OrderAccepted.fromJson(resp.data!);
  }

  Future<Paginated<OrderListItem>> orders(
      {int page = 1, int pageSize = 10}) async {
    final resp = await _guard(() => _dio.get<Map<String, dynamic>>(
          '/orders',
          queryParameters: {'page': page, 'page_size': pageSize},
        ));
    final data = resp.data!;
    return Paginated(
      items: [for (final j in data['items']) OrderListItem.fromJson(j)],
      page: data['page'],
      pageSize: data['page_size'],
      total: data['total'],
    );
  }

  Future<OrderDetail> order(String id) async {
    final resp =
        await _guard(() => _dio.get<Map<String, dynamic>>('/orders/$id'));
    return OrderDetail.fromJson(resp.data!);
  }

  Future<Paginated<HistoryEntry>> orderHistory(String id) async {
    final resp = await _guard(() => _dio.get<Map<String, dynamic>>(
          '/orders/$id/history',
          queryParameters: {'page': 1, 'page_size': 100},
        ));
    final data = resp.data!;
    return Paginated(
      items: [for (final j in data['items']) HistoryEntry.fromJson(j)],
      page: data['page'],
      pageSize: data['page_size'],
      total: data['total'],
    );
  }

  Future<Paginated<AppNotification>> notifications(
      {int page = 1, int pageSize = 20}) async {
    final resp = await _guard(() => _dio.get<Map<String, dynamic>>(
          '/notifications',
          queryParameters: {'page': page, 'page_size': pageSize},
        ));
    final data = resp.data!;
    return Paginated(
      items: [for (final j in data['items']) AppNotification.fromJson(j)],
      page: data['page'],
      pageSize: data['page_size'],
      total: data['total'],
    );
  }

  // -------------------------------------------------------------------------
  // Admin console
  // -------------------------------------------------------------------------

  /// Generic paginated GET used by every admin list screen.
  Future<Paginated<T>> _adminPage<T>(
    String path,
    Map<String, dynamic> params,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final resp = await _guard(
        () => _dio.get<Map<String, dynamic>>(path, queryParameters: params));
    final data = resp.data!;
    return Paginated(
      items: [
        for (final j in data['items']) fromJson(j as Map<String, dynamic>)
      ],
      page: data['page'],
      pageSize: data['page_size'],
      total: data['total'],
    );
  }

  Map<String, dynamic> _rangeParams(String? dateFrom, String? dateTo,
          {String? granularity}) =>
      {
        if (dateFrom != null && dateFrom.isNotEmpty) 'date_from': dateFrom,
        if (dateTo != null && dateTo.isNotEmpty) 'date_to': dateTo,
        if (granularity != null && granularity.isNotEmpty)
          'granularity': granularity,
      };

  Future<Paginated<AdminOrderListItem>> adminOrders({
    int page = 1,
    int pageSize = 20,
    String? status,
    String? search,
    String? dateFrom,
    String? dateTo,
    String sort = 'created_desc',
  }) {
    return _adminPage(
      '/admin/orders',
      {
        'page': page,
        'page_size': pageSize,
        'sort': sort,
        if (status != null && status.isNotEmpty) 'status': status,
        if (search != null && search.isNotEmpty) 'search': search,
        ..._rangeParams(dateFrom, dateTo),
      },
      AdminOrderListItem.fromJson,
    );
  }

  Future<AdminOrderDetail> adminOrder(String id) async {
    final resp =
        await _guard(() => _dio.get<Map<String, dynamic>>('/admin/orders/$id'));
    return AdminOrderDetail.fromJson(resp.data!);
  }

  Future<AdminSummary> adminSummary(
      {String? dateFrom, String? dateTo, String? granularity}) async {
    final resp = await _guard(() => _dio.get<Map<String, dynamic>>(
          '/admin/summary',
          queryParameters:
              _rangeParams(dateFrom, dateTo, granularity: granularity),
        ));
    return AdminSummary.fromJson(resp.data!);
  }

  Future<AdminAnalytics> adminAnalytics(
      {String? dateFrom, String? dateTo, String? granularity}) async {
    final resp = await _guard(() => _dio.get<Map<String, dynamic>>(
          '/admin/analytics',
          queryParameters:
              _rangeParams(dateFrom, dateTo, granularity: granularity),
        ));
    return AdminAnalytics.fromJson(resp.data!);
  }

  Future<Paginated<AdminRestaurant>> adminRestaurants({
    int page = 1,
    int pageSize = 20,
    String? search,
    bool? available,
  }) {
    return _adminPage(
      '/admin/restaurants',
      {
        'page': page,
        'page_size': pageSize,
        if (search != null && search.isNotEmpty) 'search': search,
        if (available != null) 'available': available,
      },
      AdminRestaurant.fromJson,
    );
  }

  Future<AdminRestaurant> adminUpdateRestaurant(
    String id, {
    bool? available,
    String? name,
    String? description,
    String? cuisine,
    String? imageUrl,
  }) async {
    final resp = await _guard(() => _dio.patch<Map<String, dynamic>>(
          '/admin/restaurants/$id',
          data: {
            if (available != null) 'available': available,
            if (name != null) 'name': name,
            if (description != null) 'description': description,
            if (cuisine != null) 'cuisine': cuisine,
            if (imageUrl != null) 'image_url': imageUrl,
          },
        ));
    return AdminRestaurant.fromJson(resp.data!);
  }

  Future<Paginated<AdminMenuItem>> adminMenuItems({
    int page = 1,
    int pageSize = 20,
    String? search,
    String? restaurantId,
    bool? available,
  }) {
    return _adminPage(
      '/admin/menu-items',
      {
        'page': page,
        'page_size': pageSize,
        if (search != null && search.isNotEmpty) 'search': search,
        if (restaurantId != null && restaurantId.isNotEmpty)
          'restaurant_id': restaurantId,
        if (available != null) 'available': available,
      },
      AdminMenuItem.fromJson,
    );
  }

  Future<AdminMenuItem> adminUpdateMenuItem(
    String id, {
    bool? available,
    int? priceMinor,
    String? name,
    String? description,
    String? imageUrl,
  }) async {
    final resp = await _guard(() => _dio.patch<Map<String, dynamic>>(
          '/admin/menu-items/$id',
          data: {
            if (available != null) 'available': available,
            if (priceMinor != null) 'price_minor': priceMinor,
            if (name != null) 'name': name,
            if (description != null) 'description': description,
            if (imageUrl != null) 'image_url': imageUrl,
          },
        ));
    return AdminMenuItem.fromJson(resp.data!);
  }

  Future<Paginated<AdminCustomer>> adminCustomers({
    int page = 1,
    int pageSize = 20,
    String? search,
  }) {
    return _adminPage(
      '/admin/customers',
      {
        'page': page,
        'page_size': pageSize,
        if (search != null && search.isNotEmpty) 'search': search,
      },
      AdminCustomer.fromJson,
    );
  }

  Future<Paginated<AdminDelivery>> adminDeliveries({
    int page = 1,
    int pageSize = 20,
    String? search,
  }) {
    return _adminPage(
      '/admin/deliveries',
      {
        'page': page,
        'page_size': pageSize,
        if (search != null && search.isNotEmpty) 'search': search,
      },
      AdminDelivery.fromJson,
    );
  }
}
