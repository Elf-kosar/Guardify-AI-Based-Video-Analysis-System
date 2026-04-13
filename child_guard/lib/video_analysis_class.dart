import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'consts.dart';

// YouTube Video Analiz API'si için model class
class VideoAnalysisJsClass {
  bool? success; // API yanıtının başarılı olup olmadığı
  String? targetDate; // Analiz edilen hedef tarih
  int? totalVideosFound; // Bulunan toplam video sayısı
  int? analyzedVideos; // Analiz edilen video sayısı
  List<VideoItemClass>? videos; // Video listesi
  dynamic analysis; // Genel analiz sonucu
  String? timestamp; // İşlem zaman damgası
  int? durationSeconds; // İşlem süresi
  String? error; // Hata mesajı
  dynamic statistics; // İstatistik bilgileri

  // Constructor
  VideoAnalysisJsClass({
    this.success,
    this.targetDate,
    this.totalVideosFound,
    this.analyzedVideos,
    this.videos,
    this.analysis,
    this.timestamp,
    this.durationSeconds,
    this.error,
    this.statistics,
  });

  // Güvenli int dönüştürme fonksiyonu
  static int? safeToInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
      final doubleValue = double.tryParse(value);
      return doubleValue?.toInt();
    }
    return null;
  }

  // JSON'dan obje oluşturma
  factory VideoAnalysisJsClass.fromJson(Map<String, dynamic> json) {
    // Backend'den gelen yeni yapı: statistics altında veriler
    final stats = json['statistics'] as Map<String, dynamic>?;
    
    return VideoAnalysisJsClass(
      success: json['success'] ?? false,
      targetDate: json['target_date'] ?? 'Bilinmiyor',
      totalVideosFound: safeToInt(stats?['total_videos_in_takeout'] ?? 0),
      analyzedVideos: safeToInt(stats?['analyzed'] ?? json['videos']?.length ?? 0),
      videos: parseVideosList(json['videos']),
      analysis: json['analysis'],
      timestamp: json['timestamp'] ?? 'Tarih bilinmiyor',
      durationSeconds: safeToInt(stats?['processing_time_seconds'] ?? 0),
      error: json['error'],
      statistics: stats,
    );
  }

  // Video listesini parse etme metodu
  static List<VideoItemClass>? parseVideosList(dynamic videos) {
    if (videos == null) return null;

    if (videos is List) {
      return videos.map<VideoItemClass>((video) {
        if (video is Map<String, dynamic>) {
          return VideoItemClass.fromJson(video);
        }
        return VideoItemClass();
      }).toList();
    }

    return null;
  }
}

// Video item için model class
class VideoItemClass {
  int? index; // Video sıra numarası
  String? url; // Video URL'si
  String? videoId; // Video ID'si
  String? title; // Video başlığı
  String? channel; // Kanal adı
  String? thumbnail; // Thumbnail URL'si
  String? watchDate; // İzlenme tarihi
  String? date; // Tarih
  dynamic analysis; // Video analizi

  // Constructor
  VideoItemClass({
    this.index,
    this.url,
    this.videoId,
    this.title,
    this.channel,
    this.thumbnail,
    this.watchDate,
    this.date,
    this.analysis,
  });

  // Güvenli int dönüştürme fonksiyonu
  static int? safeToInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
      final doubleValue = double.tryParse(value);
      return doubleValue?.toInt();
    }
    return null;
  }

  // JSON'dan obje oluşturma
  factory VideoItemClass.fromJson(Map<String, dynamic> json) {
    return VideoItemClass(
      index: safeToInt(json['index'] ?? 0),
      url: json['url'] ?? '',
      videoId: json['video_id'] ?? 'N/A',
      title: json['title'] ?? 'Bilinmiyor',
      channel: json['channel'] ?? 'Bilinmiyor',
      thumbnail: json['thumbnail'] ?? '',
      watchDate: json['watch_date'] ?? '',
      date: json['date'] ?? '',
      analysis: json['analysis'],
    );
  }

  // Risk seviyesini analiz verisinden çıkarma metodu
  String getRiskLevel() {
    if (analysis == null || analysis is! Map<String, dynamic>) {
      return 'Değerlendirilmedi';
    }
    
    final analysisMap = analysis as Map<String, dynamic>;
    
    // Backend'in yeni yapısı: multimodal_evaluation içinde safety_score
    final multimodal = analysisMap['multimodal_evaluation'] as Map<String, dynamic>?;
    
    if (multimodal != null) {
      final safetyScore = safeToInt(multimodal['safety_score']) ?? 50;
      
      // Safety score'a göre risk seviyesi belirle
      if (safetyScore >= 80) {
        return 'Çocuklara Uygun';
      } else if (safetyScore >= 60) {
        return 'Az Riskli';
      } else if (safetyScore >= 40) {
        return 'Riskli';
      } else {
        return 'Çok Riskli';
      }
    }
    
    // Eski yapı ile uyumluluk
    String overallSafety = analysisMap['overall_safety'] ?? '';
    if (overallSafety.contains('UYGUN DEĞİLDİR') || overallSafety.contains('uygun değil')) {
      return 'Riskli';
    } else if (overallSafety.contains('UYGUNDUR') || overallSafety.contains('uygun')) {
      return 'Çocuklara Uygun';
    }
    
    return 'Değerlendirildi';
  }
  
  // Gemini analiz metnini al
  String getGeminiAnalysis() {
    if (analysis == null || analysis is! Map<String, dynamic>) {
      return 'Analiz bulunamadı';
    }
    
    final analysisMap = analysis as Map<String, dynamic>;
    final multimodal = analysisMap['multimodal_evaluation'] as Map<String, dynamic>?;
    
    if (multimodal != null) {
      return multimodal['gemini_analysis'] as String? ?? 'Analiz metni bulunamadı';
    }
    
    return 'Analiz bulunamadı';
  }
  
  // Güvenlik skorunu al
  int getSafetyScore() {
    if (analysis == null || analysis is! Map<String, dynamic>) {
      return 0;
    }
    
    final analysisMap = analysis as Map<String, dynamic>;
    final multimodal = analysisMap['multimodal_evaluation'] as Map<String, dynamic>?;
    
    if (multimodal != null) {
      return safeToInt(multimodal['safety_score']) ?? 0;
    }
    
    return 0;
  }

  // Analiz durumu kontrol metodu
  bool hasAnalysis() {
    return analysis != null &&
        analysis is Map<String, dynamic> &&
        (analysis as Map<String, dynamic>).isNotEmpty;
  }
}

//--- API Controller fonksiyonları ---

// Dosya yükleme ve analiz işlemi
Future<VideoAnalysisJsClass> fncVideoAnalysisDbProcess({
  required File file,
  DateTime? selectedDate,
  required Function(double) onProgressUpdate,
  required Duration timeout,
}) async {
  try {
    onProgressUpdate(0.1);

    var request = http.MultipartRequest('POST', Uri.parse(apiUrl));
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: MediaType('application', 'zip'),
      ),
    );

    // Seçilen tarihi ekle
    if (selectedDate != null) {
      String formattedDate = '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';
      request.fields['target_date'] = formattedDate;
    }

    onProgressUpdate(0.3);

    // İsteği gönder
    final streamedResponse = await request.send().timeout(
      timeout,
      onTimeout: () {
        throw TimeoutException('İstek zaman aşımına uğradı. Lütfen daha sonra tekrar deneyin.');
      },
    );

    onProgressUpdate(0.7);

    // Yanıtı işle
    final response = await http.Response.fromStream(streamedResponse);
    onProgressUpdate(0.9);

    if (response.statusCode == 200) {
      final jsonResponse = json.decode(response.body);
      onProgressUpdate(1.0);
      return VideoAnalysisJsClass.fromJson(jsonResponse);
    } else if (response.statusCode == 404) {
      final errorResponse = json.decode(response.body);
      throw Exception(errorResponse['error'] ?? 'Seçilen tarihte video bulunamadı');
    } else {
      throw Exception('Sunucu hatası: ${response.statusCode}\n${response.body}');
    }
  } on TimeoutException {
    throw Exception('İstek zaman aşımına uğradı. Lütfen internet bağlantınızı kontrol edip tekrar deneyin.');
  } on SocketException {
    throw Exception('Sunucuya bağlanılamadı. Lütfen internet bağlantınızı kontrol edin ve sunucunun çalıştığından emin olun.');
  } on http.ClientException catch (e) {
    throw Exception('Bağlantı hatası: ${e.message}');
  } catch (e) {
    throw Exception('Beklenmeyen hata: $e');
  }
}

// Dosya boyutu kontrol fonksiyonu
bool fncCheckFileSize(File file) {
  final fileSize = file.lengthSync();
  return fileSize <= maxFileSizeBytes;
}