class PatientInfo {
  final String nik;
  final String noKartu;
  final String nama;
  final String? fktl;

  PatientInfo({
    required this.nik,
    required this.noKartu,
    required this.nama,
    this.fktl,
  });

  factory PatientInfo.fromJson(Map<String, dynamic> json) {
    return PatientInfo(
      nik: json['nik']?.toString() ?? '',
      noKartu: json['nokartu']?.toString() ?? '',
      nama: json['nama']?.toString() ?? '',
      fktl: json['fktl']?.toString(),
    );
  }
}

class VerificationResult {
  final bool isSuccess;
  final String message;
  final String? patientName;
  final double? similarityScore;

  VerificationResult({
    required this.isSuccess,
    required this.message,
    this.patientName,
    this.similarityScore,
  });
}
