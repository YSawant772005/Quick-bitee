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
    _dio.options.headers['Authorization'] = _token == null ? null : 'Bearer $_token';
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
      return ApiException(401, 'UNAUTHENTICATED', 'Your session has expired. Sign in again.');
    }
    if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout) {
      return ApiException(0, 'TIMEOUT', 'The request timed out. You can safely retry.');
    }
    if (e.error is ApiException) return e.error as ApiException;
    return ApiException(status, 'NETWORK', 'Network error. Check your connection.');
  }

  Future<AuthSession> login({required String email, required String password}) async {
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

  Future<Paginated<Restaurant>> restaurants({int page = 1, int pageSize = 20, String? search}) async {
    final resp = await _guard(() => _dio.get<Map<String, dynamic>>(
          '/restaurants',
          queryParameters: {'page': page, 'page_size': pageSize, if (search != null && search.isNotEmpty) 'search': search},
        ));
    final data = resp.data!;
    return Paginated(
      items: [for (final j in data['items']) Restaurant.fromJson(j)],
      page: data['page'],
      pageSize: data['page_size'],
      total: data['total'],
    );
  }

  Future<Paginated<MenuItem>> menu(String restaurantId, {int page = 1, int pageSize = 50}) async {
    final resp = await _guard(() => _dio.get<Map<String, dynamic>>(
          '/restaurants/$restaurantId/menu',
          queryParameters: {'page': page, 'page_size': pageSize},
        ));
    final data = resp.data!;
    return Paginated(
      items: [for (final j in data['items']) MenuItem.fromJson(j)],
      page: data['page'],
      pageSize: data['page_size'],
      total: data['total'],
    );
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

  Future<Paginated<OrderListItem>> orders({int page = 1, int pageSize = 10}) async {
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
    final resp = await _guard(() => _dio.get<Map<String, dynamic>>('/orders/$id'));
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

  Future<Paginated<AppNotification>> notifications({int page = 1, int pageSize = 20}) async {
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

  Future<Paginated<OrderListItem>> adminOrders({int page = 1, int pageSize = 20, String? status}) async {
    final resp = await _guard(() => _dio.get<Map<String, dynamic>>(
          '/admin/orders',
          queryParameters: {'page': page, 'page_size': pageSize, if (status != null && status.isNotEmpty) 'status': status},
        ));
    final data = resp.data!;
    return Paginated(
      items: [for (final j in data['items']) OrderListItem.fromJson(j)],
      page: data['page'],
      pageSize: data['page_size'],
      total: data['total'],
    );
  }

  Future<AdminSummary> adminSummary() async {
    final resp = await _guard(() => _dio.get<Map<String, dynamic>>('/admin/summary'));
    return AdminSummary.fromJson(resp.data!);
  }
}
