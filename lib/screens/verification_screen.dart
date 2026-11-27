import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:provider/provider.dart';
import '../models/patient_info.dart';
import '../services/bpjs_api_service.dart';
import '../services/face_detector_service.dart';
import 'barcode_scanner_screen.dart';

enum VerificationMode {
  verification, // Verifikasi Kehadiran Bedside
  registration, // Pendaftaran Wajah Baru (Enrollment) & Langsung Verifikasi
}

class VerificationScreen extends StatefulWidget {
  final PatientInfo? initialPatient;
  final VerificationMode mode;

  const VerificationScreen({
    super.key,
    this.initialPatient,
    this.mode = VerificationMode.verification,
  });

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final _nikController = TextEditingController();
  final _faceService = FaceDetectorService();

  late VerificationMode _currentMode;
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  bool _isTorchOn = false;
  bool _isProcessingFrame = false;
  bool _isSearchingNik = false;
  bool _isVerifying = false;

  PatientInfo? _patient;
  LivenessState _livenessState = LivenessState.noFace;
  String _livenessStatusText = 'Mencari Wajah...';

  @override
  void initState() {
    super.initState();
    _currentMode = widget.mode;
    if (widget.initialPatient != null) {
      _patient = widget.initialPatient;
      _nikController.text = _patient!.nik;
    }
    _initCameras();
  }

  Future<void> _initCameras() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) {
        // Default to back camera for bedside patient scanning
        _selectedCameraIndex = _cameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
        );
        if (_selectedCameraIndex == -1) _selectedCameraIndex = 0;
        await _startCamera(_cameras[_selectedCameraIndex]);
      }
    } catch (e) {
      debugPrint('Error init camera: $e');
    }
  }

  Future<void> _startCamera(CameraDescription description) async {
    await _cameraController?.dispose();
    _cameraController = CameraController(
      description,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await _cameraController!.initialize();
      _isTorchOn = false;
      if (mounted) setState(() {});
      _cameraController!.startImageStream(_processCameraFrame);
    } catch (e) {
      debugPrint('Error starting camera: $e');
    }
  }

  void _switchCamera() {
    if (_cameras.length < 2) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    _startCamera(_cameras[_selectedCameraIndex]);
  }

  Future<void> _toggleTorch() async {
    if (_cameraController == null) return;
    _isTorchOn = !_isTorchOn;
    await _cameraController!.setFlashMode(
      _isTorchOn ? FlashMode.torch : FlashMode.off,
    );
    if (mounted) setState(() {});
  }

  void _processCameraFrame(CameraImage image) async {
    if (_isProcessingFrame || _isVerifying) return;
    _isProcessingFrame = true;

    try {
      // Build ML Kit InputImage from CameraImage
      final camera = _cameras[_selectedCameraIndex];
      final sensorOrientation = camera.sensorOrientation;
      final rotation = InputImageRotationValue.fromRawValue(sensorOrientation) ??
          InputImageRotation.rotation0deg;
      final format = InputImageFormatValue.fromRawValue(image.format.raw) ??
          InputImageFormat.nv21;

      final bytes = image.planes.first.bytes;
      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );

      final faces = await _faceService.detectFaces(inputImage);
      if (!mounted) return;

      final state = _faceService.evaluateFace(faces);
      setState(() {
        _livenessState = state;
        switch (state) {
          case LivenessState.noFace:
            _livenessStatusText = 'Posisikan Wajah Pasien di Dalam Oval';
            break;
          case LivenessState.faceDetected:
            _livenessStatusText = 'Kedipkan Mata untuk Liveness Check';
            break;
          case LivenessState.ready:
            _livenessStatusText = _currentMode == VerificationMode.registration
                ? 'Wajah Pasien Siap! Tekan Daftarkan Wajah'
                : 'Wajah Siap Diverifikasi (Live OK)';
            break;
          default:
            _livenessStatusText = '';
        }
      });
    } catch (_) {
      // Ignore frame drop
    } finally {
      _isProcessingFrame = false;
    }
  }

  Future<void> _searchNik() async {
    FocusScope.of(context).unfocus();
    final nik = _nikController.text.trim();
    if (nik.length < 13) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('NIK/No Kartu minimal 13-16 digit')),
      );
      return;
    }

    setState(() => _isSearchingNik = true);
    final api = context.read<BpjsApiService>();
    try {
      final patient = await api.searchNik(nik);
      setState(() => _patient = patient);
      if (patient != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Data Ditemukan: ${patient.nama}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pencarian NIK gagal: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSearchingNik = false);
    }
  }

  Future<void> _scanBarcode() async {
    FocusScope.of(context).unfocus();
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );

    if (result != null && result.isNotEmpty) {
      _nikController.text = result;
      _searchNik();
    }
  }

  Future<void> _captureAndProcess() async {
    FocusScope.of(context).unfocus();
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    if (_patient == null && _nikController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Silakan cari NIK pasien terlebih dahulu')),
      );
      return;
    }

    setState(() => _isVerifying = true);
    try {
      final picture = await _cameraController!.takePicture();
      final photoBytes = await picture.readAsBytes();

      if (!mounted) return;
      final api = context.read<BpjsApiService>();
      final nik = _patient?.nik ?? _nikController.text.trim();
      final name = _patient?.nama;

      final VerificationResult result;
      if (_currentMode == VerificationMode.registration) {
        // Mode Registrasi Wajah Baru: Upload foto ke BPJS -> Alter descriptor sedikit -> Langsung Verifikasi Match2
        result = await api.registerAndVerifyFace(
          nik: nik,
          photoBytes: photoBytes,
          patientName: name,
        );
      } else {
        // Mode Verifikasi Reguler: Match2 -> jika belum terdaftar, otomatis Upload + Alter + Match2 dalam 1x scan
        result = await api.verifyFace(
          nik: nik,
          photoBytes: photoBytes,
          patientName: name,
        );
      }

      if (!mounted) return;
      _showResultDialog(result, photoBytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memproses wajah: $e')),
      );
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  void _showResultDialog(VerificationResult result, Uint8List? photo) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              result.isSuccess ? Icons.check_circle : Icons.error,
              color: result.isSuccess ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                result.isSuccess
                    ? (_currentMode == VerificationMode.registration
                        ? 'Pendaftaran & Verifikasi Sukses'
                        : (result.isNewRegistration
                            ? 'Perekaman & Verifikasi Berhasil'
                            : 'Verifikasi Sukses'))
                    : 'Proses Gagal',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (photo != null)
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(photo, width: 120, height: 120, fit: BoxFit.cover),
                ),
              ),
            const SizedBox(height: 12),
            if (result.isNewRegistration)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '★ Wajah Baru Berhasil Didaftarkan ke Database BPJS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueAccent,
                  ),
                ),
              ),
            Text('Nama: ${result.patientName ?? _patient?.nama ?? "-"}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('NIK: ${_patient?.nik ?? _nikController.text}'),
            const SizedBox(height: 8),
            Text(result.message, style: const TextStyle(fontSize: 13, color: Colors.black87)),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (result.isSuccess) {
                Navigator.pop(context); // Back to Home
              }
            },
            child: const Text('Selesai'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceService.dispose();
    _nikController.dispose();
    super.dispose();
  }

  Color get _guideColor {
    switch (_livenessState) {
      case LivenessState.ready:
        return Colors.greenAccent;
      case LivenessState.faceDetected:
        return Colors.yellowAccent;
      default:
        return Colors.white54;
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF088A76);
    final isRegistration = _currentMode == VerificationMode.registration;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(isRegistration ? 'Pendaftaran Wajah Baru' : 'Verifikasi Wajah Bedside'),
        backgroundColor: isRegistration ? const Color(0xFF2E4057) : primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_isTorchOn ? Icons.flash_on : Icons.flash_off),
            tooltip: 'Lampu Senter Pasien',
            onPressed: _toggleTorch,
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_android),
            tooltip: 'Ganti Kamera Depan/Belakang',
            onPressed: _switchCamera,
          ),
        ],
      ),
      body: Column(
        children: [
          // Mode Toggle Pills (Allows switching directly on camera screen)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: Colors.grey.shade100,
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _currentMode = VerificationMode.verification),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: !isRegistration ? primaryColor : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Verifikasi Kehadiran',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: !isRegistration ? Colors.white : Colors.black54,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _currentMode = VerificationMode.registration),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isRegistration ? const Color(0xFF2E4057) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Daftar Wajah Baru',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isRegistration ? Colors.white : Colors.black54,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // NIK Input & Search Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nikController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _searchNik(),
                    onChanged: (val) {
                      final clean = val.trim();
                      if (clean.length == 16 || clean.length == 13) {
                        _searchNik();
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'No. BPJS / NIK Pasien',
                      hintText: '16 digit NIK atau 13 digit No Kartu',
                      isDense: true,
                      border: const OutlineInputBorder(),
                      prefixIcon: isRegistration
                          ? const Icon(Icons.person_add_alt, size: 20, color: Color(0xFF2E4057))
                          : const Icon(Icons.badge, size: 20, color: primaryColor),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.qr_code_scanner, color: isRegistration ? const Color(0xFF2E4057) : primaryColor),
                  tooltip: 'Scan Barcode KTP/Kartu BPJS',
                  onPressed: _scanBarcode,
                ),
                IconButton(
                  icon: _isSearchingNik
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.search, color: isRegistration ? const Color(0xFF2E4057) : primaryColor),
                  tooltip: 'Cari Pasien',
                  onPressed: _searchNik,
                ),
              ],
            ),
          ),

          // Patient Info Banner
          if (_patient != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: isRegistration ? Colors.blueGrey.shade50 : Colors.teal.shade50,
              child: Row(
                children: [
                  Icon(
                    isRegistration ? Icons.person_add_alt_1 : Icons.person,
                    color: isRegistration ? const Color(0xFF2E4057) : primaryColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_patient!.nama} (${_patient!.noKartu})',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isRegistration ? const Color(0xFF2E4057) : primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Camera Viewport with Oval Guide
          Expanded(
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              behavior: HitTestBehavior.opaque,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_cameraController != null && _cameraController!.value.isInitialized)
                    ClipRect(
                      child: SizedBox.expand(
                        child: FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: _cameraController!.value.previewSize?.height ?? 720,
                            height: _cameraController!.value.previewSize?.width ?? 1280,
                            child: CameraPreview(_cameraController!),
                          ),
                        ),
                      ),
                    )
                  else
                    const Center(child: CircularProgressIndicator()),

                  // Oval Guidance Overlay
                  Center(
                    child: Container(
                      width: 240,
                      height: 310,
                      decoration: BoxDecoration(
                        border: Border.all(color: _guideColor, width: 3.5),
                        borderRadius: BorderRadius.circular(150),
                      ),
                    ),
                  ),

                  // Mode & Liveness Banner
                  Positioned(
                    top: 16,
                    left: 20,
                    right: 20,
                    child: Column(
                      children: [
                        if (isRegistration)
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2E4057).withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.flash_auto, color: Colors.amberAccent, size: 14),
                                SizedBox(width: 6),
                                Text(
                                  '1x Scan: Perekaman + Verifikasi Kehadiran',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _livenessStatusText,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _guideColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Action Capture Button
                  Positioned(
                    bottom: 16,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 72,
                            height: 72,
                            child: FloatingActionButton(
                              backgroundColor: _livenessState == LivenessState.ready
                                  ? Colors.green
                                  : (isRegistration ? const Color(0xFF2E4057) : primaryColor),
                              onPressed: _isVerifying ? null : _captureAndProcess,
                              child: _isVerifying
                                  ? const CircularProgressIndicator(color: Colors.white)
                                  : Icon(
                                      isRegistration ? Icons.how_to_reg : Icons.camera_alt,
                                      size: 34,
                                      color: Colors.white,
                                    ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              isRegistration ? 'Daftarkan & Verifikasi' : 'Verifikasi Wajah',
                              style: const TextStyle(color: Colors.white, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
