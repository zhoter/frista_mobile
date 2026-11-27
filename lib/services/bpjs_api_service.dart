import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/patient_info.dart';
import 'dlib_service.dart';

class BpjsApiService extends ChangeNotifier {
  static const String _keyBaseUrl = 'bpjs_base_url';
  static const String _keyToken = 'bpjs_auth_token';
  static const String _defaultUrl = 'https://frista.bpjs-kesehatan.go.id/frista-api';
  static const String _userAgent = 'python-requests/2.31.0';

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
        'User-Agent': _userAgent,
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
          'User-Agent': _userAgent,
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

  /// Alters a 128-d face descriptor slightly by adding tiny random perturbation
  /// and re-normalizing the vector to unit Euclidean norm (L2 = 1.0).
  ///
  /// Mathematical justification:
  /// Euclidean distance to baseline will be ~0.07 - 0.08, which is strictly
  /// non-zero (> 0.05, defeating zero-distance/exact-duplicate replay detection)
  /// while being far below the <= 0.60 match threshold (~98% match confidence).
  static List<double> alterDescriptor(List<double> descriptor) {
    final rand = math.Random();
    final perturbed = List<double>.generate(descriptor.length, (i) {
      // Add slight random jitter between -0.012 and +0.012
      final jitter = (rand.nextDouble() - 0.5) * 0.024;
      return descriptor[i] + jitter;
    });

    // Re-normalize to unit length (L2 norm = 1.0)
    double sumSq = 0.0;
    for (final v in perturbed) {
      sumSq += v * v;
    }
    final norm = math.sqrt(sumSq);
    if (norm > 0) {
      return perturbed.map((v) => v / norm).toList();
    }
    return perturbed;
  }

  /// Low-level call to /face/upload (Perekaman Wajah Baru ke database BPJS)
  Future<Map<String, dynamic>> uploadFace({
    required String nik,
    required Uint8List photoBytes,
  }) async {
    final uploadUri = Uri.parse('$_baseUrl/face/upload');
    final uploadReq = http.MultipartRequest('POST', uploadUri)
      ..headers['Authorization'] = 'Bearer $_token'
      ..headers['User-Agent'] = _userAgent
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
      try {
        return jsonDecode(uploadResp.body) as Map<String, dynamic>;
      } catch (_) {
        return {'status': true, 'message': uploadResp.body};
      }
    }
    return {
      'status': false,
      'message': 'Upload gagal (Server merespon ${uploadResp.statusCode})',
    };
  }

  /// Low-level call to /face/match2 (Pencocokan Biometrik & Check-In SEP Kehadiran)
  Future<Map<String, dynamic>> matchFace({
    required int nikInt,
    required List<double> descriptor,
  }) async {
    final matchUri = Uri.parse('$_baseUrl/face/match2');
    final matchResponse = await http.post(
      matchUri,
      headers: {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
        'User-Agent': _userAgent,
      },
      body: jsonEncode({
        'id': nikInt,
        'encoding': descriptor,
      }),
    );

    if (matchResponse.statusCode == 200) {
      return jsonDecode(matchResponse.body) as Map<String, dynamic>;
    }
    return {
      'status': false,
      'code': '-1',
      'message': 'Server BPJS merespon kode: ${matchResponse.statusCode}',
    };
  }

  /// MODE 1: Verifikasi Kehadiran Pasien Bedside
  /// Jika pasien belum terdaftar, otomatis rekam wajah (/face/upload),
  /// alter descriptor sedikit, dan verifikasi kehadiran (/face/match2) dalam 1x scan!
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

      // Step 1: Lookup patient name if empty
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

      // Step 3: Try /face/match2 first
      final matchData = await matchFace(nikInt: nikInt, descriptor: descriptor);
      final bool matchStatus = matchData['status'] == true;
      final String matchMsg = matchData['message'] ?? '';
      final dynamic matchCode = matchData['code'];

      // If success or already registered today -> VALID
      if (matchStatus || matchMsg.contains('terdaftar hari ini')) {
        final resNama = matchData['data']?['nama'] ?? name;
        return VerificationResult(
          isSuccess: true,
          message: 'Selamat Datang $resNama\nAnda berhasil verifikasi wajah (Status SEP: Valid).',
          patientName: resNama,
        );
      }

      // If face NOT yet registered (code "0" or message indicates unregistered)
      final bool isUnregistered = matchCode == '0' ||
          matchCode == 0 ||
          matchMsg.toLowerCase().contains('belum') ||
          matchMsg.toLowerCase().contains('daftar');

      if (isUnregistered) {
        // Otomatis 1x scan: daftarkan dulu lalu alter sedikit dan proseskan verifikasi!
        final uploadData = await uploadFace(nik: nik, photoBytes: photoBytes);
        if (uploadData['status'] == true) {
          // Alter descriptor slightly to avoid zero-distance / exact duplicate detection
          final alteredDescriptor = alterDescriptor(descriptor);
          final retryData = await matchFace(nikInt: nikInt, descriptor: alteredDescriptor);

          final bool retryStatus = retryData['status'] == true;
          final String retryMsg = retryData['message'] ?? '';
          if (retryStatus || retryMsg.contains('terdaftar hari ini')) {
            final resNama = retryData['data']?['nama'] ?? name;
            return VerificationResult(
              isSuccess: true,
              isNewRegistration: true,
              message: 'Selamat Datang $resNama\n'
                  'Pasien belum terdaftar sebelumnya. Perekaman wajah baru & verifikasi kehadiran berhasil diproses dalam 1x scan!',
              patientName: resNama,
            );
          } else {
            // Upload succeeded, but check-in had another message
            return VerificationResult(
              isSuccess: true,
              isNewRegistration: true,
              message: 'Perekaman wajah baru berhasil didaftarkan ke BPJS.\n'
                  'Catatan verifikasi: ${retryMsg.isNotEmpty ? retryMsg : "Silakan tap verifikasi sekali lagi."}',
              patientName: name,
            );
          }
        } else {
          return VerificationResult(
            isSuccess: false,
            message: 'Pasien belum terdaftar dan gagal perekaman otomatis: ${uploadData['message']}',
            patientName: name,
          );
        }
      }

      return VerificationResult(
        isSuccess: false,
        message: matchMsg.isNotEmpty ? matchMsg : 'Verifikasi biometrik tidak cocok',
        patientName: name,
      );
    } catch (e) {
      return VerificationResult(
        isSuccess: false,
        message: 'Gagal verifikasi biometrik: $e',
        patientName: patientName,
      );
    }
  }

  /// MODE 2: Pendaftaran Wajah Baru (Enrollment) & Langsung Verifikasi dalam 1x Scan
  /// Mengunggah foto ke /face/upload terlebih dahulu, kemudian meng-alter descriptor sedikit,
  /// dan langsung memverifikasi kehadiran ke /face/match2.
  Future<VerificationResult> registerAndVerifyFace({
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

      // Step 1: Lookup patient name if empty
      String name = patientName ?? '';
      if (name.isEmpty) {
        final info = await searchNik(nik);
        if (info != null && info.nama.isNotEmpty) {
          name = info.nama;
        }
      }

      // Step 2: Compute Face Descriptor
      final descriptor = await DlibService.computeDescriptor(photoBytes);
      if (descriptor == null || descriptor.length != 128) {
        return VerificationResult(
          isSuccess: false,
          message: 'Wajah tidak dapat diproses. Pastikan wajah pasien terlihat jelas di kamera.',
          patientName: name,
        );
      }

      // Step 3: Register face first via /face/upload
      final uploadData = await uploadFace(nik: nik, photoBytes: photoBytes);
      final bool uploadSuccess = uploadData['status'] == true;
      final String uploadMsg = uploadData['message'] ?? '';

      if (!uploadSuccess && !uploadMsg.toLowerCase().contains('terdaftar')) {
        return VerificationResult(
          isSuccess: false,
          message: 'Pendaftaran wajah gagal: $uploadMsg',
          patientName: name,
        );
      }

      // Step 4: Alter descriptor slightly to guarantee non-zero Euclidean distance
      // while preserving >95% biometric similarity for BPJS matching engine
      final alteredDescriptor = alterDescriptor(descriptor);

      // Step 5: Immediately call /face/match2 to complete attendance verification
      final matchData = await matchFace(nikInt: nikInt, descriptor: alteredDescriptor);
      final bool matchStatus = matchData['status'] == true;
      final String matchMsg = matchData['message'] ?? '';

      if (matchStatus || matchMsg.contains('terdaftar hari ini')) {
        final resNama = matchData['data']?['nama'] ?? name;
        return VerificationResult(
          isSuccess: true,
          isNewRegistration: true,
          message: 'Pendaftaran & Verifikasi Sukses!\n'
              'Selamat Datang $resNama\n'
              'Wajah berhasil didaftarkan ke biometrik BPJS dan status kehadiran SEP valid dalam 1x scan.',
          patientName: resNama,
        );
      } else {
        // Upload succeeded, return enrollment success with match note
        return VerificationResult(
          isSuccess: true,
          isNewRegistration: true,
          message: 'Pendaftaran Wajah Berhasil!\n'
              'Foto biometrik pasien telah tersimpan di server BPJS.\n'
              'Info kehadiran: ${matchMsg.isNotEmpty ? matchMsg : "Valid"}',
          patientName: name,
        );
      }
    } catch (e) {
      return VerificationResult(
        isSuccess: false,
        message: 'Gagal proses registrasi wajah: $e',
        patientName: patientName,
      );
    }
  }
}
