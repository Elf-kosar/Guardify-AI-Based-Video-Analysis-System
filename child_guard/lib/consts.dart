import 'package:flutter/material.dart';
import 'dart:io' show Platform;

//--- Uygulama sabit değerleri ---

// API URL tanımları
const String _apiUrlFromEnv = String.fromEnvironment('API_URL', defaultValue: '');

String get apiUrl {
  if (_apiUrlFromEnv.isNotEmpty) {
    return _apiUrlFromEnv;
  }

  if (Platform.isAndroid) {
    return 'http://10.0.2.2:5000/analyze';
  } else {
    return 'http://localhost:5000/analyze';
  }
}
// Google Takeout URL
const String takeoutUrl = 'https://takeout.google.com/settings/takeout/custom/youtube';

// Renk tanımları
const Color primaryColor = Colors.red; // Ana tema rengi
const Color secondaryColor = Colors.blue; // İkincil tema rengi
const Color successColor = Colors.green; // Başarılı işlem rengi
const Color warningColor = Colors.orange; // Uyarı rengi
const Color errorColor = Colors.red; // Hata rengi

// Boyut tanımları
const double defaultPadding = 16.0; // Varsayılan padding değeri
const double cardElevation = 2.0; // Kart gölge yüksekliği
const double borderRadius = 12.0; // Köşe yuvarlaklığı
const double buttonHeight = 16.0; // Buton yüksekliği
const double iconSize = 16.0; // Icon boyutu

// Dosya boyut limiti (50MB)
const int maxFileSizeBytes = 50 * 1024 * 1024;

// Timeout süreleri
const Duration requestTimeout = Duration(minutes: 30); // API istek timeout süresi

// Text Style tanımları
const TextStyle titleTextStyle = TextStyle(
  fontSize: 18,
  fontWeight: FontWeight.bold,
  color: Colors.red,
);

const TextStyle subtitleTextStyle = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.bold,
);

const TextStyle bodyTextStyle = TextStyle(
  fontSize: 14,
  height: 1.4,
);

const TextStyle captionTextStyle = TextStyle(
  fontSize: 12,
  color: Colors.grey,
);

// Risk seviyesi renkleri
const Color safeColor = Colors.green; // Güvenli içerik rengi
const Color lowRiskColor = Colors.orange; // Az riskli içerik rengi
const Color highRiskColor = Colors.red; // Riskli içerik rengi
const Color veryHighRiskColor = Color(0xFF8B0000); // Çok riskli içerik rengi