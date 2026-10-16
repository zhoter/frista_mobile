import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/bpjs_api_service.dart';
import 'barcode_scanner_screen.dart';
import 'login_screen.dart';
import 'verification_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF088A76);
    final api = context.watch<BpjsApiService>();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        title: const Text('FRISTA Mobile'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () {
              api.logout();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF088A76), Color(0xFF0EAA92)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.local_hospital, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Faskes / Rumah Sakit Aktif',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Unit IGD & Rawat Inap (Bedside)',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Server: ${api.baseUrl}',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            const Text(
              'Pilih Layanan Pasien',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 14),

            // Card 1: Verifikasi Pasien Bedside / IGD
            _buildMenuCard(
              context: context,
              icon: Icons.face_unlock_rounded,
              color: Colors.teal,
              title: 'Verifikasi Pasien Bedside / IGD',
              subtitle: 'Scan wajah pasien di ranjang/IGD dengan kamera depan/belakang & lampu senter.',
              badgeText: 'Paling Sering Digunakan',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const VerificationScreen()),
                );
              },
            ),
            const SizedBox(height: 14),

            // Card 2: Scan Cepat Barcode / QR Kartu BPJS
            _buildMenuCard(
              context: context,
              icon: Icons.qr_code_scanner_rounded,
              color: Colors.indigo,
              title: 'Scan Cepat Barcode Kartu BPJS',
              subtitle: 'Pindai barcode pada kartu BPJS/KTP untuk langsung memanggil data pasien.',
              onTap: () async {
                final scannedNik = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
                );
                if (scannedNik != null && context.mounted) {
                  final patient = await api.searchNik(scannedNik);
                  if (context.mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VerificationScreen(initialPatient: patient),
                      ),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: 14),

            // Card 3: Pendaftaran Wajah Baru (Enrollment)
            _buildMenuCard(
              context: context,
              icon: Icons.person_add_alt_1_rounded,
              color: Colors.blueGrey,
              title: 'Pendaftaran Wajah Baru (Enrollment)',
              subtitle: 'Ambil foto pasien baru untuk didaftarkan ke biometrik BPJS.',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const VerificationScreen()),
                );
              },
            ),
            const SizedBox(height: 30),

            // Tips Info Box for Nurses
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline, color: Colors.orange, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Tips IGD: Nyalakan icon senter di pojok kanan atas kamera jika ruangan pasien minim cahaya. Gunakan tombol "Pasien Masker/IGD" jika pasien menggunakan ventilator.',
                      style: TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuCard({
    required BuildContext context,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    String? badgeText,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (badgeText != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.black26),
            ],
          ),
        ),
      ),
    );
  }
}
