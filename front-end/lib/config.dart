// lib/config.dart
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import 'auth_store.dart';

/// When the backend returns a non-2xx status, we throw this.
/// You can switch on `status` (e.g., 401) to show friendly messages.
class ApiException implements Exception {
  final int status;
  final String message;
  final dynamic body; // parsed JSON or raw string
  ApiException(this.status, this.message, this.body);
  @override
  String toString() => 'ApiException($status, $message)';
}

/* =========================
   Backend host configuration
   ========================= */
const String API_HOST_OVERRIDE = '10.0.2.2'; // change to your PC's LAN IP on a real device
const int    API_PORT          = 5000;
const String API_SCHEME        = 'http';

String _autoHost() {
  if (kIsWeb) return 'localhost';
  try {
    if (Platform.isAndroid) return '10.0.2.2'; // Android emulator -> host machine
  } catch (_) {}
  return 'localhost';
}

String get _host =>
    (API_HOST_OVERRIDE.trim().isNotEmpty) ? API_HOST_OVERRIDE : _autoHost();

String get apiBase => '$API_SCHEME://$_host:$API_PORT';

/* =========================
   Current user (query param)
   ========================= */
int get effectiveUserId => AuthStore.currentUserId.value ?? 1;
int get defaultUserId => effectiveUserId;

/* =========================
   URL + headers + decoding
   ========================= */
Uri apiUri(String path, [Map<String, String>? query]) {
  final q = {'userId': '$effectiveUserId', ...?query};
  return Uri.parse('$apiBase$path').replace(queryParameters: q);
}

const Duration _timeout = Duration(seconds: 8);

Map<String, String> _headersJson() {
  final headers = <String, String>{'Content-Type': 'application/json'};
  final t = AuthStore.token;
  if (t != null && t.isNotEmpty) {
    headers['Authorization'] = 'Bearer $t';
  }
  return headers;
}

dynamic _decode(http.Response r, String label) {
  // Success
  if (r.statusCode >= 200 && r.statusCode < 300) {
    return r.body.isEmpty ? {} : jsonDecode(r.body);
  }

  // Error: try to parse JSON to extract "error" field
  dynamic parsed;
  String msg = 'request failed';
  try {
    parsed = r.body.isEmpty ? null : jsonDecode(r.body);
    if (parsed is Map && parsed['error'] is String) {
      msg = parsed['error'] as String;
    } else {
      msg = r.body.toString();
    }
  } catch (_) {
    parsed = r.body;
    msg = r.body.toString();
  }

  throw ApiException(r.statusCode, msg, parsed);
}

/* =========================
   HTTP helpers
   ========================= */
Future<dynamic> apiGet(String path, [Map<String, String>? q]) async {
  final r = await http.get(apiUri(path, q), headers: _headersJson()).timeout(_timeout);
  return _decode(r, 'GET $path');
}

Future<dynamic> apiPost(String path, Map body, [Map<String, String>? q]) async {
  final r = await http
      .post(apiUri(path, q), headers: _headersJson(), body: jsonEncode(body))
      .timeout(_timeout);
  return _decode(r, 'POST $path');
}

Future<dynamic> apiPut(String path, Map body, [Map<String, String>? q]) async {
  final r = await http
      .put(apiUri(path, q), headers: _headersJson(), body: jsonEncode(body))
      .timeout(_timeout);
  return _decode(r, 'PUT $path');
}

Future<dynamic> apiDelete(String path, [Map<String, String>? q]) async {
  final r = await http.delete(apiUri(path, q), headers: _headersJson()).timeout(_timeout);
  return _decode(r, 'DELETE $path');
}

/* =========================
   Quick connectivity checks
   ========================= */
Future<String> apiPing() async {
  try {
    final res = await apiGet('/__ping');
    return 'ok: ${res['ok']}';
  } on ApiException catch (e) {
    return 'ping failed: ${e.status} ${e.message}';
  } catch (e) {
    return 'ping failed: $e';
  }
}
