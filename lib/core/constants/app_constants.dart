import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  AppConstants._();

  // Environment
  static String get appEnv => dotenv.env['APP_ENV'] ?? 'staging';

  // Base URL
  static String get baseUrl {
    if (appEnv == 'production') {
      return dotenv.env['PRODUCTION_URL'] ?? '';
    }
    return dotenv.env['STAGING_URL'] ?? '';
  }

  // Storage Keys
  static const String tokenKey = 'auth_token';
  static const String authResponseKey = 'auth_response';
  static const String userKey = 'user';
  static const String authStatusKey = 'auth';
  static const String selectedOrgIdKey = 'selected_organization_id';

  // Timeouts
  static const int connectTimeout = 30;
  static const int receiveTimeout = 30;
}
