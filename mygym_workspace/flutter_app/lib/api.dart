import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class ApiError implements Exception {
  final String message;
  ApiError(this.message);
  @override
  String toString() => message;
}

class GymApi {
  static const String url = 'https://mygym.rconsoft.com/api/v1';
  static const _store = FlutterSecureStorage();
  String? token;
  Map<String, dynamic>? identity;
  Map<String, dynamic>? gym;

  Future<bool> restore() async {
    token = await _store.read(key: 'mygym_token');
    if (token == null || token!.isEmpty) return false;
    try {
      final who = await get('/me');
      identity = asMap(who['user']);
      gym = who['gym'] == null ? null : asMap(who['gym']);
      return true;
    } catch (_) {
      await clear();
      return false;
    }
  }

  Future<void> login({required String type, required String code,
    required String username, required String password}) async {
    final r = await post('/login', {
      'account_type': type, 'gym_code': code.trim().toUpperCase(),
      'username': username.trim(), 'password': password, 'device_name': 'MyGym Workspace Android'
    }, authenticated: false);
    token = r['token']?.toString();
    if (token == null || token!.isEmpty) throw ApiError('No session token returned.');
    await _store.write(key: 'mygym_token', value: token);
    identity = asMap(r['user']);
    gym = r['gym'] == null ? null : asMap(r['gym']);
  }

  Future<void> logout() async {
    try { if (token != null) await post('/logout', {}); } catch (_) {}
    await clear();
  }

  Future<void> clear() async {
    token = null; identity = null; gym = null;
    await _store.delete(key: 'mygym_token');
  }

  Map<String, String> get headers => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token'
  };

  Future<Map<String, dynamic>> get(String path, [Map<String, String>? query]) async {
    final u = Uri.parse('$url$path').replace(queryParameters: query);
    return _read(await http.get(u, headers: headers).timeout(const Duration(seconds: 25)));
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> data, {bool authenticated = true}) async {
    final h = {...headers};
    if (!authenticated) h.remove('Authorization');
    return _read(await http.post(Uri.parse('$url$path'), headers: h, body: jsonEncode(data))
      .timeout(const Duration(seconds: 25)));
  }

  Future<Map<String, dynamic>> uploadUpi(String vpa, String payee, XFile? image) async {
    final r = http.MultipartRequest('POST', Uri.parse('$url/settings/upi'));
    r.headers['Accept'] = 'application/json';
    if (token != null) r.headers['Authorization'] = 'Bearer $token';
    r.fields['upi_vpa'] = vpa; r.fields['upi_payee'] = payee;
    if (image != null) {
      r.files.add(await http.MultipartFile.fromPath('qr_image', image.path));
    }
    final response = await http.Response.fromStream(await r.send().timeout(const Duration(seconds: 40)));
    return _read(response);
  }

  Future<Uint8List> qrBytes() async {
    final r = await http.get(Uri.parse('$url/settings/upi/qr'), headers: headers)
      .timeout(const Duration(seconds: 25));
    if (r.statusCode < 200 || r.statusCode >= 300) throw ApiError('QR image not available.');
    return r.bodyBytes;
  }

  Map<String, dynamic> _read(http.Response response) {
    Map<String, dynamic> body = {};
    try { body = asMap(jsonDecode(response.body)); } catch (_) {}
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var msg = body['message']?.toString() ?? 'Request failed (${response.statusCode}).';
      final e = body['errors'];
      if (e is Map && e.isNotEmpty && e.values.first is List && (e.values.first as List).isNotEmpty) {
        msg = (e.values.first as List).first.toString();
      }
      throw ApiError(msg);
    }
    return body;
  }

  bool get owner => identity?['role'] == 'superadmin';
  bool get admin => identity?['role'] == 'admin';
  bool get manager => identity?['role'] == 'manager';
}

Map<String, dynamic> asMap(dynamic input) {
  if (input is Map<String, dynamic>) return input;
  if (input is Map) return input.map((key, value) => MapEntry(key.toString(), value));
  return {};
}

List<Map<String, dynamic>> maps(dynamic input) {
  if (input is List) return input.map(asMap).toList();
  return [];
}