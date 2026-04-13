/*
Bu sayfa YouTube Video Analizi için ana ekranı oluşturmak amacıyla yazılmıştır.
Kullanıcının Google Takeout ZIP dosyası yüklemesi ve belirli bir tarihteki videoları
analiz etmesi için gerekli arayüzü sağlar.
*/

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'functions.dart';
import 'consts.dart';
import 'detailed_analysis_screen_class.dart';
import 'video_analysis_class.dart';

class VideoAnalyzerScreenClass extends StatefulWidget {
  const VideoAnalyzerScreenClass({super.key});

  @override
  VideoAnalyzerScreenState createState() => VideoAnalyzerScreenState();
}

class VideoAnalyzerScreenState extends State<VideoAnalyzerScreenClass> {
  bool isLoading = false; // Yükleme durumu kontrolü için
  String fileName = ''; // Seçilen dosya adı için
  VideoAnalysisJsClass? analysisResult; // Analiz sonucu için
  String? error; // Hata mesajı için
  double uploadProgress = 0.0; // Yükleme ilerlemesi için
  DateTime? selectedDate; // Seçilen analiz tarihi için

  @override
  void initState() {
    super.initState();
    selectedDate = DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('YouTube Video Analiz'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      body: fncBuildBody(),
    );
  }

  // --- Ana sayfa içeriği ---
  Widget fncBuildBody() {
    return Padding(
      padding: const EdgeInsets.all(defaultPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          fncBuildDateSelector(),
          const SizedBox(height: 20),
          fncBuildTakeoutGuideCard(),
          const SizedBox(height: 20),
          fncBuildUploadButton(),
          const SizedBox(height: 20),
          if (isLoading) fncBuildLoadingIndicator(uploadProgress, fileName, selectedDate),
          if (error != null) fncBuildErrorWidget(error),
          if (analysisResult != null)
            Expanded(child: fncBuildAnalysisResults()),
        ],
      ),
    );
  }

  // --- Tarih seçici widget ---
  Widget fncBuildDateSelector() {
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
                Icon(Icons.calendar_today, color: secondaryColor),
                const SizedBox(width: 8),
                Text(
                  'Analiz Edilecek Tarih',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: secondaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    selectedDate != null
                        ? '${selectedDate!.day.toString().padLeft(2, '0')}/${selectedDate!.month.toString().padLeft(2, '0')}/${selectedDate!.year}'
                        : 'Tarih seçilmedi',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                // --- Tarih değiştirme butonu ---
                ElevatedButton.icon(
                  onPressed: fncSelectDate,
                  icon: Icon(Icons.edit_calendar),
                  label: Text('Değiştir'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: secondaryColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'SADECE bu tarihteki videolar analiz edilecektir.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.red[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            if (selectedDate != null)
              Text(
                'Seçilen: ${fncGetFormattedDateForAPI(selectedDate!)}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // --- Google Takeout rehber kartı ---
  Widget fncBuildTakeoutGuideCard() {
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
                Icon(Icons.download, color: successColor),
                const SizedBox(width: 8),
                Text(
                  'Google Takeout\'tan Veri İndirme',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: successColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'YouTube geçmişinizi indirmek için:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              '1. Google Takeout\'a gidin\n'
                  '2. Seçili alanı ZIP formatında indirin',
              style: bodyTextStyle,
            ),
            const SizedBox(height: 12),
            // --- Google Takeout açma butonu ---
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: fncOpenTakeoutUrl,
                icon: Icon(Icons.open_in_new),
                label: Text('Google Takeout\'u Aç'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: successColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Dosya yükleme butonu ---
  Widget fncBuildUploadButton() {
    return ElevatedButton.icon(
      onPressed: isLoading ? null : fncPickAndAnalyzeFile,
      icon: Icon(Icons.upload_file),
      label: Text(isLoading
          ? 'İşleniyor...'
          : 'ZIP Dosyası Seç ve ${selectedDate != null ? fncGetFormattedDateForAPI(selectedDate!) : "Bugünkü"} Videoları Analiz Et'),
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: buttonHeight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  // --- Analiz sonuçları widget ---
  Widget fncBuildAnalysisResults() {
    if (analysisResult == null) return const SizedBox.shrink();

    final result = analysisResult!;
    final videos = result.videos ?? [];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Özet bilgiler kartı ---
          Card(
            elevation: cardElevation,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(borderRadius),
            ),
            child: Padding(
              padding: const EdgeInsets.all(defaultPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Analiz Özeti',
                    style: titleTextStyle,
                  ),
                  const SizedBox(height: 12),
                  fncBuildInfoRow('Hedef Tarih', result.targetDate ?? 'Belirtilmedi'),
                  fncBuildInfoRow('Bulunan Video', '${result.totalVideosFound ?? 0}'),
                  fncBuildInfoRow('Analiz Edilen', '${result.analyzedVideos ?? 0}'),
                  fncBuildInfoRow('İşlem Süresi', '${result.durationSeconds ?? 0} saniye'),
                  fncBuildInfoRow('İşlem Tarihi', fncFormatTimestamp(result.timestamp)),
                  const SizedBox(height: 8),
                  // --- Başarı durumu göstergesi ---
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: (result.success == true)
                          ? Colors.green.shade50
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: (result.success == true)
                            ? Colors.green.shade200
                            : Colors.red.shade200,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          (result.success == true)
                              ? Icons.check_circle
                              : Icons.error,
                          color: (result.success == true)
                              ? successColor
                              : errorColor,
                          size: iconSize,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          (result.success == true)
                              ? 'Başarılı'
                              : 'Hata Oluştu',
                          style: TextStyle(
                            color: (result.success == true)
                                ? successColor
                                : errorColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // --- Video listesi ---
          if (videos.isNotEmpty) ...[
            Text(
              'Seçilen Tarihteki Videolar (${result.targetDate}):',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            ...videos.map((video) => fncBuildVideoCard(video)),
          ] else ...[
            // --- Video bulunamadı kartı ---
            Card(
              child: Padding(
                padding: const EdgeInsets.all(defaultPadding),
                child: Column(
                  children: [
                    Icon(Icons.info_outline, color: warningColor, size: 48),
                    const SizedBox(height: 8),
                    Text(
                      'Seçilen tarihte video bulunamadı',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Lütfen başka bir tarih seçerek tekrar deneyin.',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- Video kartı widget ---
  Widget fncBuildVideoCard(VideoItemClass video) {
    String riskLevel = video.getRiskLevel();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: Colors.red.shade100,
          child: Text(
            '${video.index ?? '?'}',
            style: const TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Video ID: ${video.videoId ?? 'Bilinmiyor'}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  if (video.watchDate != null)
                    Text(
                      'İzlenme: ${video.watchDate}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                ],
              ),
            ),
            // --- Risk seviyesi etiketi ---
            if (riskLevel.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: fncGetRiskColor(riskLevel).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: fncGetRiskColor(riskLevel)),
                ),
                child: Text(
                  riskLevel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: fncGetRiskColor(riskLevel),
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          video.url ?? '',
          style: const TextStyle(fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: () => fncShowVideoDetails(video),
      ),
    );
  }

  // --- Tarih seçme fonksiyonu ---
  Future<void> fncSelectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate ?? DateTime.now(),
      firstDate: DateTime(2005), // YouTube'un kuruluş yılı
      lastDate: DateTime.now(),
      helpText: 'Analiz edilecek tarihi seçin',
      cancelText: 'İptal',
      confirmText: 'Seç',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: primaryColor,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
        error = null;
        analysisResult = null;
      });
    }
  }

  // --- Google Takeout URL açma fonksiyonu ---
  Future<void> fncOpenTakeoutUrl() async {
    await fncOpenUrl(takeoutUrl, fncShowSnackbar);
  }

  // --- Snackbar gösterme fonksiyonu ---
  void fncShowSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: errorColor,
      ),
    );
  }

  // --- Dosya seçme ve analiz başlatma fonksiyonu ---
  Future<void> fncPickAndAnalyzeFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          isLoading = true;
          fileName = result.files.single.name;
          error = null;
          analysisResult = null;
          uploadProgress = 0.0;
        });

        File file = File(result.files.single.path!);

        // --- Dosya boyutu kontrolü ---
        if (!fncCheckFileSize(file)) {
          setState(() {
            isLoading = false;
            error = 'Dosya boyutu çok büyük. Maksimum 50MB boyutunda dosya yükleyebilirsiniz.';
          });
          return;
        }

        await fncUploadFile(file);
      }
    } catch (e) {
      fncHandleError('Dosya seçimi hatası: $e');
    }
  }

  // --- Dosya yükleme ve analiz fonksiyonu ---
  Future<void> fncUploadFile(File file) async {
    try {
      final result = await fncVideoAnalysisDbProcess(
        file: file,
        selectedDate: selectedDate,
        onProgressUpdate: (progress) {
          if (mounted) {
            setState(() => uploadProgress = progress);
          }
        },
        timeout: requestTimeout,
      );

      if (mounted) {
        setState(() {
          analysisResult = result;
          isLoading = false;
          uploadProgress = 1.0;
        });
      }
    } catch (e) {
      fncHandleError(e.toString());
    }
  }

  // --- Hata işleme fonksiyonu ---
  void fncHandleError(String message) {
    if (mounted) {
      setState(() {
        error = message.replaceAll('Exception: ', '');
        isLoading = false;
        uploadProgress = 0.0;
      });
    }
  }

  // --- Video detayları gösterme fonksiyonu ---
  void fncShowVideoDetails(VideoItemClass video) {
    bool hasAnalysis = video.hasAnalysis();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Video Detayları',
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              fncBuildDetailRow('Sıra', '${video.index ?? '?'}'),
              const SizedBox(height: 8),
              fncBuildDetailRow('Video ID', video.videoId ?? 'Bilinmiyor'),
              const SizedBox(height: 8),
              fncBuildDetailRow('URL', video.url ?? ''),
              const SizedBox(height: 8),
              if (video.watchDate != null)
                fncBuildDetailRow('İzlenme Tarihi/Saati', video.watchDate!),
              const SizedBox(height: 16),

              // --- Analiz durumu göstergesi ---
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: hasAnalysis ? Colors.green.shade50 : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: hasAnalysis ? Colors.green.shade200 : Colors.orange.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      hasAnalysis ? Icons.check_circle : Icons.warning,
                      color: hasAnalysis ? successColor : warningColor,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hasAnalysis
                            ? 'Video analizi tamamlandı'
                            : 'Video analizi tamamlanamadı',
                        style: TextStyle(
                          color: hasAnalysis ? Colors.green.shade800 : Colors.orange.shade800,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // --- Detaylı Analiz butonu ---
              if (hasAnalysis)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      fncShowDetailedAnalysis(video);
                    },
                    icon: const Icon(Icons.analytics),
                    label: const Text('Detaylı Analiz Sonucu'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: secondaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                )
              else
              // --- Analiz tamamlanamadı butonu ---
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.info_outline),
                    label: const Text('Analiz Tamamlanamadı'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.shade300,
                      foregroundColor: Colors.grey.shade600,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  // --- Detaylı analiz ekranını gösterme fonksiyonu ---
  void fncShowDetailedAnalysis(VideoItemClass video) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetailedAnalysisScreenClass(
          analysisData: video.analysis,
          videoInfo: {
            'index': video.index,
            'video_id': video.videoId,
            'title': video.title,
            'url': video.url,
            'watch_date': video.watchDate,
          },
        ),
      ),
    );
  }
}