# FRISTA Mobile (Bedside & IGD Edition)

Aplikasi Flutter Mobile untuk Verifikasi Biometrik Wajah Pasien BPJS Kesehatan langsung di sisi tempat tidur (*bedside*) atau ruang IGD/ICU rumah sakit.

## 🚀 Fitur Unggulan Mobile
1. **Dukungan Kamera Depan & Belakang**: Petugas dapat mengarahkan kamera belakang smartphone/tablet langsung ke wajah pasien yang sedang berbaring tanpa memindahkan posisi pasien.
2. **Lampu Senter Terintegrasi (Torch)**: Memastikan pencahayaan wajah tetap optimal di ruangan IGD atau bangsal rawat inap yang redup.
3. **Deteksi Wajah & Liveness Real-time (Google ML Kit)**: Berjalan 100% offline di perangkat mobile untuk deteksi wajah, bounding box, dan deteksi kedipan mata (*anti-spoofing blink check*).
4. **Pemindai Barcode / QR Kartu BPJS & KTP**: Pindai barcode kartu peserta BPJS atau e-KTP langsung lewat kamera untuk pengisian NIK instan tanpa ketik manual.
5. **Verifikasi Pengecualian Medis (Medical Bypass)**: Tombol darurat untuk pasien dengan ventilator, masker oksigen, atau perban luka bakar yang tidak memungkinkan verifikasi biometrik.
6. **Kompatibilitas Penuh API BPJS**: Menghubungkan langsung ke endpoint REST API yang sama dengan aplikasi desktop FRISTA:
   - `POST /user/login/`
   - `POST /face/nik2`
   - `POST /face/match2`
   - `POST /face/upload`

## 📁 Struktur Direktori
```
D:\frista_mobile\
├── android\
│   └── app\
│       ├── build.gradle.kts (minSdk 21)
│       └── src\main\AndroidManifest.xml (Camera & Internet permissions)
├── lib\
│   ├── models\
│   │   └── patient_info.dart (Model Pasien & Status Verifikasi)
│   ├── services\
│   │   ├── bpjs_api_service.dart (Klien HTTP multipart REST API BPJS)
│   │   └── face_detector_service.dart (Google ML Kit Face Detection & Cropper)
│   ├── screens\
│   │   ├── login_screen.dart (Autentikasi Petugas & Konfigurasi Server)
│   │   ├── home_screen.dart (Dasbor Layanan Faskes / IGD)
│   │   ├── verification_screen.dart (Kamera, Torch, Oval Guide & Liveness)
│   │   └── barcode_scanner_screen.dart (Scanner Barcode Kartu BPJS)
│   └── main.dart (Entry point & Provider theme)
└── pubspec.yaml
```

## 🛠️ Cara Menjalankan & Build APK

### 1. Menjalankan di Device / Emulator Android
Hubungkan HP Android via kabel USB dengan mode USB Debugging aktif:
```powershell
cd D:\frista_mobile
flutter run
```

### 2. Membangun File APK (Release)
Untuk menghasilkan file installer APK yang siap di-install di HP perawat/petugas:
```powershell
cd D:\frista_mobile
flutter build apk --split-per-abi
```
File APK akan berada di folder:
`D:\frista_mobile\build\app\outputs\flutter-apk\`
