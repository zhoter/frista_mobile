import 'dart:typed_data';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

enum LivenessState {
  noFace,
  faceDetected,
  blinkDetected,
  ready,
}

class FaceDetectorService {
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true, // For eye open/blink detection
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.fast,
      minFaceSize: 0.2,
    ),
  );

  bool _hasBlinked = false;
  int _consecutiveClosedFrames = 0;

  bool get hasBlinked => _hasBlinked;

  void resetLiveness() {
    _hasBlinked = false;
    _consecutiveClosedFrames = 0;
  }

  Future<List<Face>> detectFaces(InputImage inputImage) async {
    return await _faceDetector.processImage(inputImage);
  }

  LivenessState evaluateFace(List<Face> faces) {
    if (faces.isEmpty) {
      resetLiveness();
      return LivenessState.noFace;
    }

    final face = faces.first;
    final leftEye = face.leftEyeOpenProbability ?? 1.0;
    final rightEye = face.rightEyeOpenProbability ?? 1.0;

    // Detect eye blink for liveness
    if (leftEye < 0.25 && rightEye < 0.25) {
      _consecutiveClosedFrames++;
      if (_consecutiveClosedFrames >= 1) {
        _hasBlinked = true;
      }
    } else if (leftEye > 0.7 && rightEye > 0.7) {
      _consecutiveClosedFrames = 0;
    }

    if (_hasBlinked) {
      return LivenessState.ready;
    } else {
      return LivenessState.faceDetected;
    }
  }

  Uint8List cropFaceToJpeg(Uint8List originalBytes, Face face) {
    final image = img.decodeImage(originalBytes);
    if (image == null) return originalBytes;

    final box = face.boundingBox;
    // Add 20% margin around bounding box for context
    final marginW = (box.width * 0.2).round();
    final marginH = (box.height * 0.2).round();

    final x = (box.left - marginW).clamp(0, image.width - 1).toInt();
    final y = (box.top - marginH).clamp(0, image.height - 1).toInt();
    final w = (box.width + marginW * 2).clamp(1, image.width - x).toInt();
    final h = (box.height + marginH * 2).clamp(1, image.height - y).toInt();

    final cropped = img.copyCrop(image, x: x, y: y, width: w, height: h);
    return Uint8List.fromList(img.encodeJpg(cropped, quality: 85));
  }

  void dispose() {
    _faceDetector.close();
  }
}
