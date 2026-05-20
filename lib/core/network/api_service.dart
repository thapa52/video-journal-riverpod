import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import '../error/failures.dart';
import '../storage/local_storage.dart';
import '../utils/logger.dart';

// Provider
final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService();
});

class ApiService {
  late final Dio _dio;
  late final Dio _refreshDio;
  final LocalStorage _storage = LocalStorage();

  ApiService() {
    _dio = _buildDio();
    _refreshDio = _buildDio();
  }

  // ─────────────────────────────────────────────
  // DIO SETUP
  // ─────────────────────────────────────────────

  Dio _buildDio() {
    final String baseUrl = AppConstants.baseUrl;
    final String normalizedBase = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';

    return Dio(
      BaseOptions(
        baseUrl: normalizedBase,
        connectTimeout: Duration(seconds: AppConstants.connectTimeout),
        receiveTimeout: Duration(seconds: AppConstants.receiveTimeout),
        validateStatus: (_) => true,
      ),
    );
  }

  // ─────────────────────────────────────────────
  // TOKEN MANAGEMENT
  // ─────────────────────────────────────────────

  String? getToken() => _storage.getToken();

  void setToken(String token) => _storage.saveToken(token);

  // ─────────────────────────────────────────────
  // HEADERS
  // ─────────────────────────────────────────────

  Map<String, String> _buildHeaders({bool isJson = false}) {
    final String platform = Platform.isIOS ? 'ios' : 'android';

    return <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer ${getToken() ?? ''}',
      'X-Platform': platform,
      if (isJson) 'Content-Type': 'application/json',
    };
  }

  // ─────────────────────────────────────────────
  // PATH NORMALISATION
  // ─────────────────────────────────────────────

  String _normalisePath(String path) =>
      path.startsWith('/') ? path.substring(1) : path;

  // ─────────────────────────────────────────────
  // RETRY CONFIGURATION
  // ─────────────────────────────────────────────

  static const int _maxRetries = 2;
  static const Duration _retryDelay = Duration(seconds: 1);

  Future<Response<dynamic>> _withRetry(
    Future<Response<dynamic>> Function() request,
    String method,
    String path,
  ) async {
    int attempt = 0;

    while (true) {
      try {
        return await request();
      } on DioException catch (e) {
        final bool isTransient =
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError;

        if (!isTransient) rethrow;

        attempt++;
        if (attempt > _maxRetries) rethrow;

        appLogger.w(
          'RETRY [$method] $path '
          '(attempt $attempt/$_maxRetries) — ${e.message}',
        );

        await Future<void>.delayed(_retryDelay * attempt);
      }
    }
  }

  // ─────────────────────────────────────────────
  // TOKEN REFRESH
  // ─────────────────────────────────────────────

  static Completer<bool>? _refreshCompleter;

  Future<bool> attemptTokenRefresh() async {
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    _refreshCompleter = Completer<bool>();

    try {
      final bool success = await _doRefresh();
      _refreshCompleter!.complete(success);
      return success;
    } catch (e) {
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      _refreshCompleter = null;
    }
  }

  Future<bool> _doRefresh() async {
    try {
      final currentToken = getToken();
      if (currentToken == null || currentToken.isEmpty) {
        return false;
      }

      final Response<dynamic> response = await _refreshDio.post<dynamic>(
        'auth/refresh',
        options: Options(
          headers: <String, String>{
            'Accept': 'application/json',
            'Authorization': 'Bearer $currentToken',
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200) {
        final dynamic data = response.data;
        final String? newToken =
            data is Map<String, dynamic>
                ? (data['access_token'] as String? ?? data['token'] as String?)
                : null;

        if (newToken != null && newToken.isNotEmpty) {
          setToken(newToken);
          appLogger.i('TOKEN REFRESH: Success');
          return true;
        }
      }

      return false;
    } catch (e) {
      appLogger.e('TOKEN REFRESH: Error — $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────
  // ERROR HANDLING
  // ─────────────────────────────────────────────

  Never _throwFailure(Response<dynamic> response, String method, String path) {
    final int? statusCode = response.statusCode;

    appLogger.e('$method $path → Error $statusCode');

    if (statusCode == 401) {
      throw const UnauthorizedFailure(
        message: 'Session expired. Please login again.',
      );
    }

    if (statusCode == 422) {
      final json =
          response.data is Map<String, dynamic>
              ? response.data as Map<String, dynamic>
              : null;
      throw ServerFailure(
        message: json?['message'] as String? ?? 'Validation error',
      );
    }

    if (statusCode != null && statusCode >= 500) {
      throw ServerFailure(
        message: 'Server error ($statusCode). Please try again.',
      );
    }

    final json =
        response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : null;
    throw ServerFailure(
      message:
          json?['message'] as String? ??
          json?['error'] as String? ??
          'Request failed ($statusCode)',
    );
  }

  // ─────────────────────────────────────────────
  // 401 HANDLER
  // ─────────────────────────────────────────────

  Future<Response<dynamic>> _handle401(
    String method,
    String path,
    Future<Response<dynamic>> Function() retryRequest,
  ) async {
    final bool refreshed = await attemptTokenRefresh();

    if (!refreshed) {
      throw const UnauthorizedFailure(
        message: 'Session expired. Please login again.',
      );
    }

    final Response<dynamic> retryResponse = await retryRequest();

    if (retryResponse.statusCode == 200 || retryResponse.statusCode == 201) {
      return retryResponse;
    }

    if (retryResponse.statusCode == 401) {
      throw const UnauthorizedFailure(
        message: 'Session expired. Please login again.',
      );
    }

    _throwFailure(retryResponse, method, path);
  }

  // ─────────────────────────────────────────────
  // PUBLIC API METHODS
  // ─────────────────────────────────────────────

  // ── GET ───────────────────────────────────────

  Future<dynamic> get(String path) async {
    final String normPath = _normalisePath(path);

    try {
      final Response<dynamic> response = await _withRetry(
        () => _dio.get<dynamic>(
          normPath,
          options: Options(headers: _buildHeaders()),
        ),
        'GET',
        normPath,
      );

      appLogger.d('GET $normPath → ${response.statusCode}');

      if (response.statusCode == 200) return response.data;

      if (response.statusCode == 401) {
        final retry = await _handle401(
          'GET',
          normPath,
          () => _dio.get<dynamic>(
            normPath,
            options: Options(headers: _buildHeaders()),
          ),
        );
        return retry.data;
      }

      _throwFailure(response, 'GET', normPath);
    } on DioException catch (e) {
      throw NetworkFailure(message: e.message ?? 'Network error occurred');
    }
  }

  // ── POST ──────────────────────────────────────

  Future<dynamic> post(
    String path, {
    Map<String, dynamic> body = const <String, dynamic>{},
  }) async {
    final String normPath = _normalisePath(path);

    try {
      final Response<dynamic> response = await _withRetry(
        () => _dio.post<dynamic>(
          normPath,
          data: body,
          options: Options(headers: _buildHeaders(isJson: true)),
        ),
        'POST',
        normPath,
      );

      appLogger.d('POST $normPath → ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        return response.data;
      }

      if (response.statusCode == 401) {
        final retry = await _handle401(
          'POST',
          normPath,
          () => _dio.post<dynamic>(
            normPath,
            data: body,
            options: Options(headers: _buildHeaders(isJson: true)),
          ),
        );
        return retry.data;
      }

      _throwFailure(response, 'POST', normPath);
    } on DioException catch (e) {
      throw NetworkFailure(message: e.message ?? 'Network error occurred');
    }
  }

  // ── PUT ───────────────────────────────────────

  Future<dynamic> put(
    String path, {
    Map<String, dynamic> body = const <String, dynamic>{},
  }) async {
    final String normPath = _normalisePath(path);

    try {
      final Response<dynamic> response = await _withRetry(
        () => _dio.put<dynamic>(
          normPath,
          data: body,
          options: Options(headers: _buildHeaders(isJson: true)),
        ),
        'PUT',
        normPath,
      );

      appLogger.d('PUT $normPath → ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        return response.data;
      }

      if (response.statusCode == 401) {
        final retry = await _handle401(
          'PUT',
          normPath,
          () => _dio.put<dynamic>(
            normPath,
            data: body,
            options: Options(headers: _buildHeaders(isJson: true)),
          ),
        );
        return retry.data;
      }

      _throwFailure(response, 'PUT', normPath);
    } on DioException catch (e) {
      throw NetworkFailure(message: e.message ?? 'Network error occurred');
    }
  }

  // ── PATCH ─────────────────────────────────────

  Future<dynamic> patch(
    String path, {
    Map<String, dynamic> body = const <String, dynamic>{},
  }) async {
    final String normPath = _normalisePath(path);

    try {
      final Response<dynamic> response = await _withRetry(
        () => _dio.patch<dynamic>(
          normPath,
          data: body,
          options: Options(headers: _buildHeaders(isJson: true)),
        ),
        'PATCH',
        normPath,
      );

      appLogger.d('PATCH $normPath → ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        return response.data;
      }

      if (response.statusCode == 401) {
        final retry = await _handle401(
          'PATCH',
          normPath,
          () => _dio.patch<dynamic>(
            normPath,
            data: body,
            options: Options(headers: _buildHeaders(isJson: true)),
          ),
        );
        return retry.data;
      }

      _throwFailure(response, 'PATCH', normPath);
    } on DioException catch (e) {
      throw NetworkFailure(message: e.message ?? 'Network error occurred');
    }
  }

  // ── DELETE ────────────────────────────────────

  Future<dynamic> delete(String path) async {
    final String normPath = _normalisePath(path);

    try {
      final Response<dynamic> response = await _withRetry(
        () => _dio.delete<dynamic>(
          normPath,
          options: Options(headers: _buildHeaders()),
        ),
        'DELETE',
        normPath,
      );

      appLogger.d('DELETE $normPath → ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        return response.data;
      }

      if (response.statusCode == 401) {
        final retry = await _handle401(
          'DELETE',
          normPath,
          () => _dio.delete<dynamic>(
            normPath,
            options: Options(headers: _buildHeaders()),
          ),
        );
        return retry.data;
      }

      _throwFailure(response, 'DELETE', normPath);
    } on DioException catch (e) {
      throw NetworkFailure(message: e.message ?? 'Network error occurred');
    }
  }

  // ── MULTIPART (File Upload) ───────────────────

  Future<dynamic> postMultipart(
    String path, {
    Map<String, String> fields = const <String, String>{},
    String? fileField,
    String? filePath,
  }) async {
    final String normPath = _normalisePath(path);

    Future<FormData> buildForm() async {
      final Map<String, dynamic> formMap = <String, dynamic>{...fields};
      if (fileField != null && filePath != null) {
        formMap[fileField] = await MultipartFile.fromFile(filePath);
      }
      return FormData.fromMap(formMap);
    }

    try {
      final Map<String, String> headers = Map<String, String>.from(
        _buildHeaders(),
      )..remove('Content-Type');

      final Response<dynamic> response = await _withRetry(
        () async => _dio.post<dynamic>(
          normPath,
          data: await buildForm(),
          options: Options(headers: headers),
        ),
        'MULTIPART',
        normPath,
      );

      appLogger.d('MULTIPART $normPath → ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        return response.data;
      }

      if (response.statusCode == 401) {
        final retry = await _handle401('MULTIPART', normPath, () async {
          final Map<String, String> retryHeaders = Map<String, String>.from(
            _buildHeaders(),
          )..remove('Content-Type');

          return _dio.post<dynamic>(
            normPath,
            data: await buildForm(),
            options: Options(headers: retryHeaders),
          );
        });
        return retry.data;
      }

      _throwFailure(response, 'MULTIPART', normPath);
    } on DioException catch (e) {
      throw NetworkFailure(message: e.message ?? 'Network error occurred');
    }
  }
}
