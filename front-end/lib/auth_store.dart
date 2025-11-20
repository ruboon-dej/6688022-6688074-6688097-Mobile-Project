// lib/auth_store.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthStore {
  static const _kUserId = 'auth_user_id';
  static const _kToken  = 'auth_token';

  static final ValueNotifier<int?> currentUserId = ValueNotifier<int?>(null);
  static String? token;
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    currentUserId.value = _prefs!.getInt(_kUserId);
    token = _prefs!.getString(_kToken);
  }

  static Future<void> setUser({required int userId, String? bearerToken}) async {
    currentUserId.value = userId;
    await _prefs?.setInt(_kUserId, userId);
    if (bearerToken != null) {
      token = bearerToken;
      await _prefs?.setString(_kToken, bearerToken);
    }
  }

  static Future<void> logout() async {
    currentUserId.value = null;
    token = null;
    await _prefs?.remove(_kUserId);
    await _prefs?.remove(_kToken);
  }
}
