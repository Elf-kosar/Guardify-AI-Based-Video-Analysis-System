import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'consts.dart';


// Risk seviyesine göre renk döndüren fonksiyon
Color fncGetRiskColor(String? riskLevel) {
  if (riskLevel == null || riskLevel.isEmpty) return Colors.grey;

  switch (riskLevel.toLowerCase()) {
    case 'çocuklara uygun':
      return safeColor;
    case 'az riskli':
      return lowRiskColor;
    case 'riskli':
      return highRiskColor;
    case 'çok riskli':
      return veryHighRiskColor;
    case 'değerlendirildi':
      return secondaryColor;
    default:
      return Colors.grey;
  }
}

// Risk seviyesine göre icon döndüren fonksiyon
IconData fncGetRiskIcon(String riskLevel) {
  switch (riskLevel.toLowerCase()) {
    case 'çocuklara uygun':
      return Icons.verified_user;
    case 'az riskli':
      return Icons.warning_amber;
    case 'riskli':
      return Icons.error;
    case 'çok riskli':
      return Icons.dangerous;
    default:
      return Icons.help;
  }
}

// Timestamp formatı düzenleme fonksiyonu
String fncFormatTimestamp(String? timestamp) {
  if (timestamp == null) return 'Bilinmiyor';
  try {
    final dateTime = DateTime.parse(timestamp);
    return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  } catch (e) {
    return timestamp;
  }
}

// API için tarih formatı düzenleme fonksiyonu
String fncGetFormattedDateForAPI(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

// URL açma fonksiyonu
Future<void> fncOpenUrl(String url, Function(String) onError) async {
  try {
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } else {
      onError('URL açılamadı. Lütfen manuel olarak Google Takeout\'a gidin.');
    }
  } catch (e) {
    onError('URL açılırken hata oluştu: $e');
  }
}

//--- Widget oluşturma fonksiyonları ---

// Info row widget oluşturan fonksiyon
Widget fncBuildInfoRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Text(
          '$label: ',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        Text(value),
      ],
    ),
  );
}

// Detail row widget oluşturan fonksiyon
Widget fncBuildDetailRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(
          value,
          style: const TextStyle(fontSize: 14),
        ),
        const Divider(height: 1),
      ],
    ),
  );
}

// Hata widget'ı oluşturan fonksiyon
Widget fncBuildErrorWidget(String? error) {
  return Container(
    padding: const EdgeInsets.all(12),
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: Colors.red.shade50,
      border: Border.all(color: Colors.red.shade200),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline, color: Colors.red),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            error ?? 'Bilinmeyen bir hata oluştu',
            style: TextStyle(color: Colors.red.shade800),
          ),
        ),
      ],
    ),
  );
}

// Loading indicator widget oluşturan fonksiyon
Widget fncBuildLoadingIndicator(double uploadProgress, String fileName, DateTime? selectedDate) {
  return Column(
    children: [
      const SizedBox(height: 20),
      Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              value: uploadProgress > 0 ? uploadProgress : null,
              color: primaryColor,
              strokeWidth: 4,
            ),
          ),
          if (uploadProgress > 0)
            Text(
              '${(uploadProgress * 100).toInt()}%',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
      const SizedBox(height: 16),
      Text(
        'Dosya: $fileName',
        style: const TextStyle(fontSize: 14, color: Colors.grey),
      ),
      const SizedBox(height: 8),
      Text(
        'Sadece ${selectedDate != null ? fncGetFormattedDateForAPI(selectedDate) : "bugünkü"} videolar analiz ediliyor...',
        style: const TextStyle(fontSize: 14, color: Colors.grey),
        textAlign: TextAlign.center,
      ),
    ],
  );
}