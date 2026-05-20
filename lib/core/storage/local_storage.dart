import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../constants/app_constants.dart';
import '../utils/logger.dart';

// Provider
final localStorageProvider = Provider<LocalStorage>((ref) {
  return LocalStorage();
});

class LocalStorage {
  static const String _boxName = 'app_storage';

  // Singleton
  static final LocalStorage _instance = LocalStorage._internal();
  factory LocalStorage() => _instance;
  LocalStorage._internal();

  // ─────────────────────────────────────────────
  // INITIALIZE HIVE
  // ─────────────────────────────────────────────

  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox<dynamic>(_boxName);
    appLogger.i('Hive initialized successfully');
  }

  // ─────────────────────────────────────────────
  // GET THE BOX
  // ─────────────────────────────────────────────

  Box<dynamic> get _box => Hive.box<dynamic>(_boxName);

  // ─────────────────────────────────────────────
  // AUTH STATUS
  // ─────────────────────────────────────────────

  Future<void> saveAuth(bool value) async {
    await _box.put(AppConstants.authStatusKey, value);
  }

  bool getAuth() {
    return _box.get(AppConstants.authStatusKey, defaultValue: false) as bool;
  }

  // ─────────────────────────────────────────────
  // AUTH RESPONSE
  // ─────────────────────────────────────────────

  Future<void> saveAuthResponse(Map<String, dynamic> authResponse) async {
    await _box.put(AppConstants.authResponseKey, jsonEncode(authResponse));
  }

  Map<String, dynamic>? getAuthResponse() {
    final String? data = _box.get(AppConstants.authResponseKey) as String?;
    if (data != null) {
      return jsonDecode(data) as Map<String, dynamic>;
    }
    return null;
  }

  // ─────────────────────────────────────────────
  // TOKEN
  // ─────────────────────────────────────────────

  String? getToken() {
    final auth = getAuthResponse();
    return auth?['token'] as String?;
  }

  Future<void> saveToken(String token) async {
    final auth = getAuthResponse() ?? {};
    auth['token'] = token;
    await saveAuthResponse(auth);
  }

  // ─────────────────────────────────────────────
  // USER
  // ─────────────────────────────────────────────

  Future<void> saveUser(Map<String, dynamic> user) async {
    await _box.put(AppConstants.userKey, jsonEncode(user));
  }

  Map<String, dynamic>? getUser() {
    final String? data = _box.get(AppConstants.userKey) as String?;
    if (data != null) {
      return jsonDecode(data) as Map<String, dynamic>;
    }
    return null;
  }

  // ─────────────────────────────────────────────
  // CLEAR ALL (Logout)
  // ─────────────────────────────────────────────

  Future<void> clearAll() async {
    await _box.clear();
    appLogger.i('All local storage cleared');
  }
}
