import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/patient_info.dart';
import 'dlib_service.dart';

class BpjsApiService extends ChangeNotifier {
  static const String _keyBaseUrl = 'bpjs_base_url';
  static const String _keyToken = 'bpjs_auth_token';
  static const String _defaultUrl = 'https://frista.bpjs-kesehatan.go.id/frista-api';

  String? _token;
  String _baseUrl = _defaultUrl;

  String get baseUrl => _baseUrl;
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString(_keyBaseUrl);
    if (savedUrl == null || savedUrl.contains('192.168.1.100')) {
      _baseUrl = _defaultUrl;
      await prefs.setString(_keyBaseUrl, _defaultUrl);
    } else {
      _baseUrl = savedUrl.trim();
      while (_baseUrl.endsWith('/')) {
        _baseUrl = _baseUrl.substring(0, _baseUrl.length - 1);
      }
    }
    _token = null;
  }

  Future<void> setBaseUrl(String url) async {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBaseUrl, _baseUrl);
    notifyListeners();
  }

  Future<bool> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/user/login/rs'),
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'Mozilla/5.0',
      },
      body: jsonEncode({
        'username': username,
        'password': password,
        'version': '3.0.2',
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['status'] == true || data['token'] != null) {
        _token = data['token']?.toString();
        if (_token != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_keyToken, _token!);
        }
        notifyListeners();
        return true;
      } else {
        throw Exception(data['message'] ?? 'Username atau password salah');
      }
    } else {
      try {
        final data = jsonDecode(response.body);
        throw Exception(data['message'] ?? 'Server error (${response.statusCode})');
      } catch (e) {
        if (e is! FormatException) rethrow;
        throw Exception('Server merespon kode ${response.statusCode}');
      }
    }
  }

  void logout() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyToken);
    notifyListeners();
  }

  Future<PatientInfo?> searchNik(String nik) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/face/nik2'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: jsonEncode({'nik': nik}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == true) {
          return PatientInfo.fromJson(data);
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<VerificationResult> verifyFace({
    required String nik,
    required Uint8List photoBytes,
    String? patientName,
  }) async {
    try {
      final nikInt = int.tryParse(nik);
      if (nikInt == null) {
        return VerificationResult(
          isSuccess: false,
          message: 'NIK harus berupa angka',
          patientName: patientName,
        );
      }

      // Step 1: If patient name not yet provided, lookup NIK
      String name = patientName ?? '';
      if (name.isEmpty) {
        final info = await searchNik(nik);
        if (info != null && info.nama.isNotEmpty) {
          name = info.nama;
        }
      }

      // Step 2: Compute Face Descriptor (128-float dlib ResNet)
      final descriptor = await DlibService.computeDescriptor(photoBytes);
      if (descriptor == null || descriptor.length != 128) {
        return VerificationResult(
          isSuccess: false,
          message: 'Wajah tidak dapat diproses. Pastikan wajah pasien terlihat jelas di kamera.',
          patientName: name,
        );
      }

      // Step 3: Call /face/match2 (Check-In BPJS V-Claim Attendance)
      final matchUri = Uri.parse('$_baseUrl/face/match2');
      final matchResponse = await http.post(
        matchUri,
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
          'User-Agent': 'Mozilla/5.0',
        },
        body: jsonEncode({
          'id': nikInt,
          'encoding': descriptor,
        }),
      );

      if (matchResponse.statusCode == 200) {
        final matchData = jsonDecode(matchResponse.body);
        final bool matchStatus = matchData['status'] == true;
        final String matchMsg = matchData['message'] ?? '';

        // If success or already registered today -> VALID
        if (matchStatus || matchMsg.contains('terdaftar hari ini')) {
          final resNama = matchData['data']?['nama'] ?? name;
          return VerificationResult(
            isSuccess: true,
            message: 'Selamat Datang $resNama\nAnda berhasil verifikasi wajah (Status SEP: Valid).',
            patientName: resNama,
          );
        }

        // If face not yet enrolled in BPJS database (status: false, code: "0")
        if (matchData['code'] == '0') {
          // Fallback to /face/upload (Perekaman Wajah Baru)
          final uploadUri = Uri.parse('$_baseUrl/face/upload');
          final uploadReq = http.MultipartRequest('POST', uploadUri)
            ..headers['Authorization'] = 'Bearer $_token'
            ..headers['User-Agent'] = 'Mozilla/5.0'
            ..fields['id'] = nik
            ..files.add(
              http.MultipartFile.fromBytes(
                'file',
                photoBytes,
                filename: 'photo.jpg',
              ),
            );
          final streamedUpload = await uploadReq.send();
          final uploadResp = await http.Response.fromStream(streamedUpload);

          if (uploadResp.statusCode == 200) {
            final uploadData = jsonDecode(uploadResp.body);
            if (uploadData['status'] == true) {
              // Immediately call /face/match2 to complete check-in
              final retryMatch = await http.post(
                matchUri,
                headers: {
                  'Authorization': 'Bearer $_token',
                  'Content-Type': 'application/json',
                  'User-Agent': 'Mozilla/5.0',
                },
                body: jsonEncode({
                  'id': nikInt,
                  'encoding': descriptor,
                }),
              );
              if (retryMatch.statusCode == 200) {
                final retryData = jsonDecode(retryMatch.body);
                if (retryData['status'] == true || (retryData['message'] ?? '').contains('terdaftar hari ini')) {
                  final retryNama = retryData['data']?['nama'] ?? name;
                  return VerificationResult(
                    isSuccess: true,
                    message: 'Selamat Datang $retryNama\nPerekaman & Verifikasi Kehadiran Berhasil.',
                    patientName: retryNama,
                  );
                }
              }
            }
          }
        }

        return VerificationResult(
          isSuccess: false,
          message: matchMsg.isNotEmpty ? matchMsg : 'Verifikasi biometrik tidak cocok',
          patientName: name,
        );
      } else {
        return VerificationResult(
          isSuccess: false,
          message: 'Server BPJS merespon kode: ${matchResponse.statusCode}',
          patientName: name,
        );
      }
    } catch (e) {
      return VerificationResult(
        isSuccess: false,
        message: 'Gagal verifikasi biometrik: $e',
        patientName: patientName,
      );
    }
  }
}
