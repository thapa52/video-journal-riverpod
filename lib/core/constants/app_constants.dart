import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  AppConstants._();

  // Environment
  static String get appEnv => dotenv.env['APP_ENV'] ?? 'staging';

  // Base URL - automatically picks the right one
  static String get baseUrl {
    if (appEnv == 'production') {
      return dotenv.env['PRODUCTION_URL'] ?? '';
    }
    return dotenv.env['STAGING_URL'] ?? '';
  }

  // Storage Keys
  static const String tokenKey = 'auth_token';
  static const String userKey = 'user_data';

  // Timeouts
  static const int connectTimeout = 30000;
  static const int receiveTimeout = 30000;
}
