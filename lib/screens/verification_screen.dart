import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:provider/provider.dart';
import '../models/patient_info.dart';
import '../services/bpjs_api_service.dart';
import '../services/face_detector_service.dart';
import 'barcode_scanner_screen.dart';

class VerificationScreen extends StatefulWidget {
  final PatientInfo? initialPatient;
  const VerificationScreen({super.key, this.initialPatient});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final _nikController = TextEditingController();
  final _faceService = FaceDetectorService();
  
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
      imageFormatGroup: ImageFormatGroup.nv21,
    );

    await _cameraController!.initialize();
    if (!mounted) return;

    _cameraController!.startImageStream(_processCameraFrame);
    setState(() {});
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
    setState(() {});
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
            _livenessStatusText = 'Wajah Siap Diverifikasi (Live OK)';
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
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );

    if (result != null && result.isNotEmpty) {
      _nikController.text = result;
      _searchNik();
    }
  }

  Future<void> _captureAndVerify() async {
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
      final result = await api.verifyFace(
        nik: _patient?.nik ?? _nikController.text.trim(),
        photoBytes: photoBytes,
        patientName: _patient?.nama,
      );

      if (!mounted) return;
      _showResultDialog(result, photoBytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal verifikasi wajah: $e')),
      );
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  void _manualMedicalBypass() {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Verifikasi Pengecualian Medis (IGD / ICU)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Gunakan fitur ini jika pasien tidak memungkinkan verifikasi biometrik (masker O2, selang NGT, luka wajah parah, koma):',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Alasan Medis',
                hintText: 'Misal: Pasien ventilator / luka bakar wajah',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () {
              Navigator.pop(ctx);
              _showResultDialog(
                VerificationResult(
                  isSuccess: true,
                  message: 'Verifikasi Manual Tercatat: ${reasonController.text}',
                  patientName: _patient?.nama ?? 'Pasien IGD',
                ),
                null,
              );
            },
            child: const Text('Verifikasi Manual', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
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
            Text(result.isSuccess ? 'Verifikasi Sukses' : 'Verifikasi Gagal'),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verifikasi Wajah Bedside'),
        backgroundColor: primaryColor,
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
                    onChanged: (val) {
                      final clean = val.trim();
                      if (clean.length == 16 || clean.length == 13) {
                        _searchNik();
                      }
                    },
                    decoration: const InputDecoration(
                      labelText: 'No. BPJS / NIK Pasien',
                      hintText: '16 digit NIK atau 13 digit No Kartu',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.qr_code_scanner, color: primaryColor),
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
                      : const Icon(Icons.search, color: primaryColor),
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
              color: Colors.teal.shade50,
              child: Row(
                children: [
                  const Icon(Icons.person, color: primaryColor, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_patient!.nama} (${_patient!.noKartu})',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: primaryColor),
                    ),
                  ),
                ],
              ),
            ),

          // Camera Viewport with Oval Guide
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_cameraController != null && _cameraController!.value.isInitialized)
                  CameraPreview(_cameraController!)
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

                // Liveness Banner
                Positioned(
                  top: 16,
                  left: 20,
                  right: 20,
                  child: Container(
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
                ),

                // Medical Bypass Button
                Positioned(
                  bottom: 90,
                  left: 20,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.black54,
                      foregroundColor: Colors.orangeAccent,
                    ),
                    icon: const Icon(Icons.medical_services_outlined, size: 18),
                    label: const Text('Pasien Masker/IGD', style: TextStyle(fontSize: 12)),
                    onPressed: _manualMedicalBypass,
                  ),
                ),

                // Action Capture Button
                Positioned(
                  bottom: 16,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: FloatingActionButton(
                        backgroundColor: _livenessState == LivenessState.ready
                            ? Colors.green
                            : primaryColor,
                        onPressed: _isVerifying ? null : _captureAndVerify,
                        child: _isVerifying
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Icon(Icons.camera_alt, size: 36, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
