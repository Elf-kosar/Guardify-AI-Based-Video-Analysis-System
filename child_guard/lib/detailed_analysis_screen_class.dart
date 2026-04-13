/*
Bu sayfa seçilen videonun detaylı AI analiz sonucunu göstermek
amacıyla yazılmıştır. Risk değerlendirmesi, güvenlik durumu ve
analiz raporunu kullanıcıya sunar.
*/

import 'package:flutter/material.dart';
import 'functions.dart';
import 'consts.dart';

class DetailedAnalysisScreenClass extends StatelessWidget {
  final dynamic analysisData; // Analiz verisi
  final Map<String, dynamic>? videoInfo; // Video bilgileri

  const DetailedAnalysisScreenClass({
    super.key,
    required this.analysisData,
    this.videoInfo,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detaylı Analiz Sonucu'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: fncBuildAnalysisContent(context),
    );
  }

  // --- Ana analiz içeriği ---
  Widget fncBuildAnalysisContent(BuildContext context) {
    if (analysisData == null) {
      return fncBuildNoAnalysisWidget();
    }

    // --- Analiz verisini parse etme (Backend'in yeni yapısı) ---
    String analysisText = '';
    String safetyStatus = '';
    String timestamp = '';
    int safetyScore = 0;

    if (analysisData is Map<String, dynamic>) {
      // Yeni yapı: multimodal_evaluation içinde
      final multimodal = analysisData['multimodal_evaluation'] as Map<String, dynamic>?;
      
      if (multimodal != null) {
        analysisText = multimodal['gemini_analysis'] ?? 'Analiz bulunamadı';
        safetyScore = (multimodal['safety_score'] is int) 
            ? multimodal['safety_score'] 
            : int.tryParse(multimodal['safety_score']?.toString() ?? '0') ?? 0;
        
        // Safety score'dan status belirle
        if (safetyScore >= 80) {
          safetyStatus = 'Çocuklar için uygun';
        } else if (safetyScore >= 60) {
          safetyStatus = 'Ebeveyn kontrolü önerilir';
        } else if (safetyScore >= 40) {
          safetyStatus = 'Dikkatli izlenmeli';
        } else {
          safetyStatus = 'Çocuklar için uygun değil';
        }
      } else {
        // Eski yapı ile uyumluluk
        analysisText = analysisData['video_summary'] ??
            analysisData['error'] ??
            'Analiz verisi bulunamadı';
        safetyStatus = analysisData['overall_safety'] ?? '';
      }
      
      // Metadata'dan timestamp al
      final metadata = analysisData['metadata'] as Map<String, dynamic>?;
      timestamp = metadata?['analysis_timestamp'] ?? 
                  analysisData['analysis_timestamp'] ?? '';
    } else if (analysisData is String) {
      analysisText = analysisData;
    } else {
      analysisText = analysisData.toString();
    }

    // --- Risk seviyesini belirleme ---
    String riskLevel = fncDetermineRiskLevel(safetyStatus);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(defaultPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Video bilgileri kartı ---
          if (videoInfo != null) ...[
            fncBuildVideoInfoCard(),
            const SizedBox(height: 16),
          ],

          // --- Risk değerlendirmesi kartı ---
          if (riskLevel.isNotEmpty) ...[
            fncBuildRiskAssessmentCard(riskLevel),
            const SizedBox(height: 16),
          ],
          
          // --- Güvenlik Skoru kartı (yeni) ---
          if (safetyScore > 0) ...[
            fncBuildSafetyScoreCard(safetyScore),
            const SizedBox(height: 16),
          ],

          // --- Güvenlik değerlendirmesi kartı ---
          if (safetyStatus.isNotEmpty) ...[
            fncBuildSafetyAssessmentCard(safetyStatus),
            const SizedBox(height: 16),
          ],

          // --- AI Analiz raporu kartı ---
          fncBuildAnalysisReportCard(analysisText),

          // --- Zaman bilgisi ---
          if (timestamp.isNotEmpty) ...[
            const SizedBox(height: 16),
            fncBuildTimestampWidget(timestamp),
          ],

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // --- Analiz verisi olmadığında gösterilecek widget ---
  Widget fncBuildNoAnalysisWidget() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.warning,
            color: warningColor,
            size: 64,
          ),
          SizedBox(height: 16),
          Text(
            'Analiz verisi bulunamadı',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // --- Video bilgileri kartı ---
  Widget fncBuildVideoInfoCard() {
    return Card(
      elevation: cardElevation,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.video_library, color: primaryColor),
                const SizedBox(width: 8),
                const Text(
                  'Analiz Edilen Video',
                  style: titleTextStyle,
                ),
              ],
            ),
            const SizedBox(height: 12),
            fncBuildDetailRow('Video ID', videoInfo!['video_id'] ?? 'Bilinmiyor'),
            fncBuildDetailRow('Başlık', videoInfo!['title'] ?? 'Bilinmiyor'),
            if (videoInfo!['watch_date'] != null)
              fncBuildDetailRow('İzlenme Tarihi', videoInfo!['watch_date']),
            const SizedBox(height: 8),
            // --- Video URL kartı ---
            if (videoInfo!['url'] != null)
              fncBuildUrlContainer(),
          ],
        ),
      ),
    );
  }

  // --- URL container widget ---
  Widget fncBuildUrlContainer() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          const Icon(Icons.link, size: 16, color: secondaryColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              videoInfo!['url'],
              style: const TextStyle(
                color: secondaryColor,
                fontSize: 12,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // --- Risk değerlendirmesi kartı ---
  Widget fncBuildRiskAssessmentCard(String riskLevel) {
    return Card(
      elevation: cardElevation,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  fncGetRiskIcon(riskLevel),
                  color: fncGetRiskColor(riskLevel),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Risk Değerlendirmesi',
                  style: subtitleTextStyle,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // --- Risk seviyesi göstergesi ---
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: fncGetRiskColor(riskLevel).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: fncGetRiskColor(riskLevel).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    fncGetRiskIcon(riskLevel),
                    color: fncGetRiskColor(riskLevel),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    riskLevel.toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: fncGetRiskColor(riskLevel),
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

  // --- Güvenlik değerlendirmesi kartı ---
  Widget fncBuildSafetyAssessmentCard(String safetyStatus) {
    bool isSafe = safetyStatus.contains('UYGUNDUR') || safetyStatus.contains('uygun');

    return Card(
      elevation: cardElevation,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSafe ? Icons.check_circle : Icons.warning,
                  color: isSafe ? successColor : errorColor,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Güvenlik Değerlendirmesi',
                  style: subtitleTextStyle,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // --- Güvenlik durumu göstergesi ---
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSafe
                    ? Colors.green.shade50
                    : Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSafe
                      ? Colors.green.shade200
                      : Colors.red.shade200,
                ),
              ),
              child: Text(
                safetyStatus,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isSafe
                      ? Colors.green.shade800
                      : Colors.red.shade800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- AI Analiz raporu kartı ---
  Widget fncBuildAnalysisReportCard(String analysisText) {
    return Card(
      elevation: cardElevation,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics, color: secondaryColor),
                const SizedBox(width: 8),
                Text(
                  'AI Analiz Raporu',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: secondaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Markdown formatında analiz metni
            SelectableText(
              analysisText,
              style: const TextStyle(
                fontSize: 14,
                height: 1.6,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Timestamp widget ---
  Widget fncBuildTimestampWidget(String timestamp) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.access_time, size: 16, color: Colors.grey),
            const SizedBox(width: 6),
            Text(
              'Analiz Tarihi: ${fncFormatTimestamp(timestamp)}',
              style: captionTextStyle,
            ),
          ],
        ),
      ),
    );
  }
  
  // --- Güvenlik Skoru Kartı (Yeni) ---
  Widget fncBuildSafetyScoreCard(int score) {
    Color scoreColor;
    String scoreLabel;
    
    if (score >= 80) {
      scoreColor = safeColor;
      scoreLabel = 'Güvenli';
    } else if (score >= 60) {
      scoreColor = lowRiskColor;
      scoreLabel = 'Dikkat';
    } else if (score >= 40) {
      scoreColor = highRiskColor;
      scoreLabel = 'Riskli';
    } else {
      scoreColor = veryHighRiskColor;
      scoreLabel = 'Tehlikeli';
    }
    
    return Card(
      elevation: cardElevation,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.security, color: scoreColor),
                const SizedBox(width: 8),
                const Text(
                  'Güvenlik Skoru',
                  style: subtitleTextStyle,
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Skor göstergesi
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 120,
                      height: 120,
                      child: CircularProgressIndicator(
                        value: score / 100,
                        strokeWidth: 12,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                      ),
                    ),
                    Column(
                      children: [
                        Text(
                          '$score',
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.bold,
                            color: scoreColor,
                          ),
                        ),
                        Text(
                          scoreLabel,
                          style: TextStyle(
                            fontSize: 14,
                            color: scoreColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Skor açıklaması
            Text(
              score >= 80
                  ? '✓ Bu video çocuklar için güvenli görünüyor.'
                  : score >= 60
                      ? '⚠ Bu video ebeveyn kontrolü ile izlenmelidir.'
                      : score >= 40
                          ? '⚠ Bu videoda potansiyel riskler bulunuyor.'
                          : '✗ Bu video çocuklar için uygun değil.',
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // --- Risk seviyesi belirleme fonksiyonu ---
  String fncDetermineRiskLevel(String safetyStatus) {
    if (safetyStatus.contains('UYGUN DEĞİLDİR') || safetyStatus.contains('uygun değil')) {
      return 'Riskli';
    } else if (safetyStatus.contains('UYGUNDUR') || safetyStatus.contains('uygun')) {
      return 'Çocuklara Uygun';
    }
    return '';
  }
}