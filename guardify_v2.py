"""
Guardify v3 - Çocuk Video İçerik Analiz Sistemi Backend
HATA DÜZELTMELERİ + HIZ OPTİMİZASYONLARI

Yeni Özellikler:
- yt-dlp yapılandırma iyileştirmeleri (indirme hataları düzeltildi)
- Akıllı video indirme retry mekanizması
- Daha hızlı frame extraction (OpenCV optimize)
- Gemini API hata yönetimi iyileştirildi
- Paralel işleme stabilizasyonu
- Detaylı hata loglama
"""

import os
import sys
import json
import zipfile
import re
import datetime
import uuid
import shutil
import subprocess
import traceback
import tempfile
import logging
import time
from typing import List, Dict, Any, Optional, Tuple
from concurrent.futures import ThreadPoolExecutor, as_completed
from threading import Lock, Semaphore
from dateutil import parser
from functools import wraps, lru_cache

# Flask ve CORS
from flask import Flask, request, jsonify
from flask_cors import CORS
from werkzeug.middleware.proxy_fix import ProxyFix
from werkzeug.utils import secure_filename

# Web scraping ve video indirme
import requests
from bs4 import BeautifulSoup
from yt_dlp import YoutubeDL
from youtube_transcript_api import YouTubeTranscriptApi
from youtube_transcript_api.formatters import TextFormatter

# Görüntü işleme
import cv2
from PIL import Image
import numpy as np

# Ses işleme
import whisper
try:
    from moviepy.editor import VideoFileClip
except ImportError:
    from moviepy import VideoFileClip

# ML/AI modelleri
import torch
from transformers import (
    CLIPProcessor, CLIPModel,
    VisionEncoderDecoderModel, ViTImageProcessor, AutoTokenizer,
    pipeline
)

# Transformers uyarılarını kapat
import warnings
warnings.filterwarnings('ignore', category=UserWarning, module='transformers')


app = Flask(__name__)
app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1, x_prefix=1)
CORS(app)

app.config.update(
    MAX_CONTENT_LENGTH=100 * 1024 * 1024,
    UPLOAD_FOLDER=os.path.join(os.getcwd(), 'uploads'),
    TEMP_FOLDER=os.path.join(os.getcwd(), 'temp'),
    
    REQUEST_TIMEOUT=5600,
    VIDEO_DOWNLOAD_TIMEOUT=300,  # 5 dakika - daha uzun
    TRANSCRIPT_TIMEOUT=20,
    ANALYSIS_TIMEOUT=120,
    
    RATE_LIMIT=20,
    RATE_LIMIT_WINDOW=60,
    
    MAX_VIDEOS_TO_ANALYZE=50,
    FRAME_EXTRACTION_INTERVAL=5, 
    MAX_FRAMES_PER_VIDEO=15, 
    VIDEO_MAX_DURATION=600,
    
    MAX_WORKERS=3,  
    MAX_FRAME_WORKERS=2,
    BATCH_SIZE=2,  
    
    USE_GPU=torch.cuda.is_available(),
    BATCH_INFERENCE=True,
    
    GEMINI_API_KEY=os.getenv('GEMINI_API_KEY', '').strip(),
    GEMINI_MODEL='gemini-2.0-flash-exp',
    GEMINI_MAX_RETRIES=5,  
    GEMINI_RETRY_DELAY=15,  
    GEMINI_CONCURRENT_REQUESTS=2,  
    
    AUTO_DELETE_TEMP_FILES=True,
    SECURE_FILE_HANDLING=True,
    
    
    ENABLE_CACHING=True,
    CACHE_VIDEO_INFO=True,
)

os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)
os.makedirs(app.config['TEMP_FOLDER'], exist_ok=True)


logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - [%(levelname)s] - %(name)s - %(message)s',
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler('guardify.log', encoding='utf-8')
    ]
)
logger = logging.getLogger(__name__)


rate_limits = {}
rate_limit_lock = Lock()

def rate_limit(f):
    """Rate limiting decorator"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if app.config.get('TESTING'):
            return f(*args, **kwargs)
            
        ip = request.remote_addr or '127.0.0.1'
        current_time = time.time()
        
        with rate_limit_lock:
            expired = [k for k, (ts, _) in rate_limits.items() 
                      if current_time - ts > app.config['RATE_LIMIT_WINDOW']]
            for k in expired:
                rate_limits.pop(k, None)
            
            if ip in rate_limits:
                last_time, count = rate_limits[ip]
                if current_time - last_time < app.config['RATE_LIMIT_WINDOW']:
                    if count >= app.config['RATE_LIMIT']:
                        return jsonify({
                            'error': 'Çok fazla istek. Lütfen bekleyin.',
                            'retry_after': int(app.config['RATE_LIMIT_WINDOW'] - (current_time - last_time))
                        }), 429
                    rate_limits[ip] = (last_time, count + 1)
                else:
                    rate_limits[ip] = (current_time, 1)
            else:
                rate_limits[ip] = (current_time, 1)
                
        return f(*args, **kwargs)
    return decorated_function

# ==================== MODEL YÖNETİMİ ====================

class OptimizedModelManager:
    """Thread-safe model manager"""
    
    _instance = None
    _lock = Lock()
    
    def __new__(cls):
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    cls._instance = super().__new__(cls)
        return cls._instance
    
    def __init__(self):
        if not hasattr(self, 'initialized'):
            self.initialized = False
            self.models = {}
            self.device = 'cuda' if app.config['USE_GPU'] else 'cpu'
            self.model_locks = {}
            self.load_all_models()
    
    def load_all_models(self):
        """Tüm modelleri yükle"""
        try:
            logger.info(f"🚀 AI modelleri yükleniyor... (Device: {self.device})")
            
            # 1. CLIP
            logger.info("📊 CLIP modeli yükleniyor...")
            self.models['clip_processor'] = CLIPProcessor.from_pretrained("openai/clip-vit-base-patch32")
            self.models['clip_model'] = CLIPModel.from_pretrained("openai/clip-vit-base-patch32").to(self.device)
            self.models['clip_model'].eval()
            self.model_locks['clip'] = Lock()
            
            # 2. ViT-GPT2
            logger.info("🖼️ ViT-GPT2 modeli yükleniyor...")
            self.models['caption_model'] = VisionEncoderDecoderModel.from_pretrained(
                "nlpconnect/vit-gpt2-image-captioning"
            ).to(self.device)
            self.models['caption_model'].eval()
            self.models['caption_processor'] = ViTImageProcessor.from_pretrained("nlpconnect/vit-gpt2-image-captioning")
            self.models['caption_tokenizer'] = AutoTokenizer.from_pretrained("nlpconnect/vit-gpt2-image-captioning")
            self.model_locks['caption'] = Lock()
            
            # 3. Whisper
            logger.info("🎙️ Whisper modeli yükleniyor...")
            self.models['whisper'] = whisper.load_model("base")
            self.model_locks['whisper'] = Lock()
            
            # 4. NLP
            logger.info("📝 NLP modelleri yükleniyor...")
            self.models['sentiment_analyzer'] = pipeline(
                "sentiment-analysis",
                model="distilbert-base-uncased-finetuned-sst-2-english",
                device=0 if self.device == 'cuda' else -1
            )
            self.models['toxic_classifier'] = pipeline(
                "text-classification",
                model="unitary/toxic-bert",
                top_k=None,
                device=0 if self.device == 'cuda' else -1
            )
            self.model_locks['nlp'] = Lock()
            
            self.initialized = True
            logger.info(f"✅ Tüm modeller yüklendi (Device: {self.device})")
            
        except Exception as e:
            logger.error(f"❌ Model yükleme hatası: {str(e)}")
            raise
    
    def get_model(self, model_name: str):
        return self.models.get(model_name)
    
    def get_lock(self, model_name: str):
        return self.model_locks.get(model_name, Lock())

model_manager = OptimizedModelManager()


class GeminiAPIManager:
    """Gemini API rate limit yönetimi"""
    
    def __init__(self, max_concurrent: int = 2):
        self.semaphore = Semaphore(max_concurrent)
        self.request_times = []
        self.lock = Lock()
    
    def wait_if_needed(self):
        """Rate limit kontrolü"""
        with self.lock:
            now = time.time()
            self.request_times = [t for t in self.request_times if now - t < 60]
            
            if len(self.request_times) >= 55:
                wait_time = 60 - (now - self.request_times[0])
                if wait_time > 0:
                    logger.warning(f"⏳ Gemini rate limit, {wait_time:.1f}s bekleniyor...")
                    time.sleep(wait_time)
                    self.request_times = []
            
            self.request_times.append(now)

gemini_manager = GeminiAPIManager(app.config['GEMINI_CONCURRENT_REQUESTS'])


class TakeoutParser:
    """Google Takeout parser"""
    
    @staticmethod
    def extract_youtube_links_from_html(content: str) -> List[Dict]:
        soup = BeautifulSoup(content, "html.parser")
        records = []
        
        for a in soup.find_all('a', href=True):
            href = a['href']
            if "youtube.com/watch" in href or "youtu.be/" in href:
                date_obj = None
                parent = a.find_parent()
                
                for _ in range(5):
                    if not parent:
                        break
                    parent_text = parent.get_text(" ", strip=True)
                    
                    patterns = [
                        r'(\d{1,2}\s+\w+\s+\d{4})',
                        r'(\w+\s+\d{1,2},?\s+\d{4})',
                        r'(\d{1,2}/\d{1,2}/\d{4})',
                        r'(\d{4}-\d{1,2}-\d{1,2})',
                    ]
                    
                    for pattern in patterns:
                        match = re.search(pattern, parent_text)
                        if match:
                            date_obj = TakeoutParser.parse_date_flexible(match.group(1))
                            if date_obj:
                                break
                    
                    if date_obj:
                        break
                    parent = parent.find_parent()
                
                records.append({"url": href, "date": date_obj})
        
        return records
    
    @staticmethod
    def extract_youtube_links_from_json(data: Any) -> List[Dict]:
        urls = []
        
        def recursive_search(obj):
            if isinstance(obj, dict):
                for key, value in obj.items():
                    if isinstance(value, str) and ("youtube.com/watch" in value or "youtu.be/" in value):
                        urls.append({"url": value, "date": None})
                    else:
                        recursive_search(value)
            elif isinstance(obj, list):
                for item in obj:
                    recursive_search(item)
        
        recursive_search(data)
        return urls
    
    @staticmethod
    def parse_date_flexible(date_string: str) -> Optional[datetime.datetime]:
        if not date_string:
            return None
        
        try:
            turkish_months = {
                'Oca': 'Jan', 'Şub': 'Feb', 'Mar': 'Mar', 'Nis': 'Apr',
                'May': 'May', 'Haz': 'Jun', 'Tem': 'Jul', 'Ağu': 'Aug',
                'Eyl': 'Sep', 'Eki': 'Oct', 'Kas': 'Nov', 'Ara': 'Dec',
            }
            
            for tr, en in turkish_months.items():
                date_string = date_string.replace(tr, en)
            
            formats = [
                "%d %B %Y", "%B %d, %Y", "%d/%m/%Y", "%m/%d/%Y",
                "%Y-%m-%d", "%d.%m.%Y", "%d-%m-%Y",
            ]
            
            for fmt in formats:
                try:
                    return datetime.datetime.strptime(date_string.strip(), fmt)
                except ValueError:
                    continue
            
            return parser.parse(date_string, dayfirst=True)
            
        except Exception:
            return None
    
    @staticmethod
    def parse_takeout_zip(zip_path: str) -> List[Dict]:
        records = []
        
        try:
            with zipfile.ZipFile(zip_path, 'r') as zip_ref:
                extract_dir = os.path.join(os.path.dirname(zip_path), 'extracted')
                os.makedirs(extract_dir, exist_ok=True)
                
                logger.info("📦 ZIP dosyası çıkartılıyor...")
                zip_ref.extractall(extract_dir)
                
                files_to_parse = []
                for root, _, files in os.walk(extract_dir):
                    for filename in files:
                        if filename.lower().endswith(('.html', '.htm', '.json')):
                            files_to_parse.append(os.path.join(root, filename))
                
                logger.info(f"📄 {len(files_to_parse)} dosya bulundu, paralel ayrıştırılıyor...")
                
                def parse_file(file_path):
                    try:
                        if file_path.lower().endswith(('.html', '.htm')):
                            with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                                return TakeoutParser.extract_youtube_links_from_html(f.read())
                        elif file_path.lower().endswith('.json'):
                            with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                                return TakeoutParser.extract_youtube_links_from_json(json.load(f))
                    except:
                        return []
                
                with ThreadPoolExecutor(max_workers=4) as executor:
                    results = list(executor.map(parse_file, files_to_parse))
                    for result in results:
                        records.extend(result)
                
                shutil.rmtree(extract_dir, ignore_errors=True)
        
        except Exception as e:
            logger.error(f"Takeout parse hatası: {str(e)}")
        
        logger.info(f"✅ {len(records)} video kaydı bulundu")
        return records


class VideoDownloader:
    """Düzeltilmiş video indirme"""
    
    _info_cache = {}
    _cache_lock = Lock()
    
    @staticmethod
    def extract_video_id(url: str) -> Optional[str]:
        from urllib.parse import unquote
        url = unquote(url)
        match = re.search(r"(?:v=|be/)([a-zA-Z0-9_-]{11})", url)
        return match.group(1) if match else None
    
    @staticmethod
    def download_video(url: str, output_path: str, timeout: int = 300) -> str:
        """İYİLEŞTİRİLMİŞ video indirme - HATA DÜZELTMELERİ"""
        
        ydl_opts = {
            'format': 'bestvideo[height<=480][ext=mp4]+bestaudio[ext=m4a]/best[height<=480][ext=mp4]/best[ext=mp4]/best',
            'outtmpl': output_path,
            'noplaylist': True,
            
            'quiet': False,
            'no_warnings': False,
            'verbose': True,
            
            'ignoreerrors': False,
            'socket_timeout': timeout,
            'retries': 10,
            'fragment_retries': 10,
            'file_access_retries': 10,
            'extractor_retries': 10,
            
            'skip_unavailable_fragments': True,
            'keepvideo': False,
            'nocheckcertificate': True,
            'prefer_insecure': False,
            
          
            'http_chunk_size': 10485760, 
            'concurrent_fragment_downloads': 5,
            
      
            'user_agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            
           
            'cookiefile': None,
            'external_downloader_args': [],
            
            
            'merge_output_format': 'mp4',
            'postprocessor_args': [],
            
            
            'prefer_free_formats': True,
        }
        
        max_attempts = 3
        last_error = None
        
        for attempt in range(max_attempts):
            try:
                if attempt > 0:
                    wait_time = 5 * attempt
                    logger.warning(f"🔄 İndirme yeniden deneniyor ({attempt + 1}/{max_attempts}) - {wait_time}s bekleniyor...")
                    time.sleep(wait_time)
                
                logger.info(f"📥 Video indiriliyor (deneme {attempt + 1}/{max_attempts}): {url}")
                
                if os.path.exists(output_path):
                    try:
                        os.remove(output_path)
                    except:
                        pass
                
                with YoutubeDL(ydl_opts) as ydl:
                    info = ydl.extract_info(url, download=True)
                    
                    
                    possible_paths = [
                        output_path,
                        output_path.replace('.mp4', '.webm'),
                        output_path.replace('.mp4', '.mkv'),
                    ]
                    
                    actual_path = None
                    for path in possible_paths:
                        if os.path.exists(path) and os.path.getsize(path) > 0:
                            actual_path = path
                            break
                    
                    if not actual_path:
                        raise Exception("İndirilen dosya bulunamadı veya boş")
                    
                    if actual_path != output_path:
                        logger.info(f"📝 Dosya taşınıyor: {actual_path} -> {output_path}")
                        shutil.move(actual_path, output_path)
                    
                    file_size = os.path.getsize(output_path) / 1024 / 1024
                    logger.info(f"✅ Video indirildi: {file_size:.1f}MB")
                    
                return output_path
                
            except Exception as e:
                last_error = e
                logger.error(f"❌ İndirme hatası (deneme {attempt + 1}/{max_attempts}): {str(e)}")
                
                # Kısmi dosyayı temizle
                for path in [output_path, output_path + '.part', output_path + '.ytdl']:
                    if os.path.exists(path):
                        try:
                            os.remove(path)
                        except:
                            pass
                
                if attempt == max_attempts - 1:
                    raise last_error
                
                continue
        
        raise Exception(f"Video indirilemedi (3 deneme): {last_error}")
    
    @staticmethod
    @lru_cache(maxsize=100)
    def get_video_info_cached(url: str) -> Dict:
        return VideoDownloader.get_video_info(url)
    
    @staticmethod
    def get_video_info(url: str) -> Dict:
        video_id = VideoDownloader.extract_video_id(url)
        
        if not video_id:
            return {"error": "Geçersiz URL"}
        
        if app.config['CACHE_VIDEO_INFO']:
            with VideoDownloader._cache_lock:
                if video_id in VideoDownloader._info_cache:
                    return VideoDownloader._info_cache[video_id]
        
        try:
            ydl_opts = {
                'quiet': True,
                'no_warnings': True,
                'socket_timeout': 10,
                'extract_flat': False,
            }
            with YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=False)
                result = {
                    "video_id": video_id,
                    "title": info.get('title', 'Bilinmiyor'),
                    "duration": info.get('duration', 0),
                    "thumbnail": info.get('thumbnail', f"https://img.youtube.com/vi/{video_id}/hqdefault.jpg"),
                    "channel": info.get('uploader', 'Bilinmiyor'),
                    "description": info.get('description', '')[:500],
                }
                
                if app.config['CACHE_VIDEO_INFO']:
                    with VideoDownloader._cache_lock:
                        VideoDownloader._info_cache[video_id] = result
                
                return result
        except Exception as e:
            logger.debug(f"Video bilgi hatası: {str(e)}")
            return {
                "video_id": video_id,
                "title": "Bilinmiyor",
                "thumbnail": f"https://img.youtube.com/vi/{video_id}/hqdefault.jpg"
            }


class OptimizedVisualProcessor:
    """Optimize görsel işleme"""
    
    @staticmethod
    def extract_frames_fast(video_path: str, output_dir: str, interval: int = 5, max_frames: int = 15) -> List[str]:
        """HIZLI kare çıkarma"""
        os.makedirs(output_dir, exist_ok=True)
        
        try:
            cap = cv2.VideoCapture(video_path)
            fps = int(cap.get(cv2.CAP_PROP_FPS))
            total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
            
            if fps == 0 or total_frames == 0:
                cap.release()
                return []
            
            duration = total_frames / fps
            
            frame_indices = np.linspace(0, total_frames - 1, min(max_frames, int(duration / interval)), dtype=int)
            
            saved_frames = []
            for idx, frame_idx in enumerate(frame_indices):
                cap.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
                ret, frame = cap.read()
                if ret:
                    frame = cv2.resize(frame, (480, 360), interpolation=cv2.INTER_LINEAR)
                    frame_path = os.path.join(output_dir, f"frame_{idx:04d}.jpg")
                    cv2.imwrite(frame_path, frame, [cv2.IMWRITE_JPEG_QUALITY, 80])
                    saved_frames.append(frame_path)
            
            cap.release()
            logger.debug(f"✅ {len(saved_frames)} kare çıkarıldı")
            return saved_frames
            
        except Exception as e:
            logger.error(f"Kare çıkarma hatası: {str(e)}")
            return []
    
    @staticmethod
    def analyze_frames_batch(frame_paths: List[str]) -> Dict:
        """Batch frame analizi"""
        if not frame_paths:
            return {"captions": [], "classifications": [], "total_frames": 0}
        
        safety_categories = [
            "safe educational children content",
            "violent scary content",
            "inappropriate adult content",
            "neutral content"
        ]
        
        all_captions = []
        all_classifications = []
        
        try:
            with model_manager.get_lock('clip'):
                clip_processor = model_manager.get_model('clip_processor')
                clip_model = model_manager.get_model('clip_model')
                
                batch_size = 5
                for i in range(0, len(frame_paths), batch_size):
                    batch_paths = frame_paths[i:i + batch_size]
                    images = [Image.open(p).convert('RGB') for p in batch_paths]
                    
                    inputs = clip_processor(
                        text=safety_categories,
                        images=images,
                        return_tensors="pt",
                        padding=True
                    ).to(model_manager.device)
                    
                    with torch.no_grad():
                        outputs = clip_model(**inputs)
                        probs = outputs.logits_per_image.softmax(dim=1)
                    
                    for prob in probs:
                        all_classifications.append({cat: float(p) for cat, p in zip(safety_categories, prob)})
            
            sample_frames = frame_paths[::4]
            
            with model_manager.get_lock('caption'):
                caption_model = model_manager.get_model('caption_model')
                caption_processor = model_manager.get_model('caption_processor')
                caption_tokenizer = model_manager.get_model('caption_tokenizer')
                
                for frame_path in sample_frames:
                    try:
                        image = Image.open(frame_path).convert('RGB')
                        pixel_values = caption_processor(image, return_tensors="pt").pixel_values.to(model_manager.device)
                        
                        with torch.no_grad():
                            output_ids = caption_model.generate(
                                pixel_values,
                                max_length=25,
                                num_beams=3,
                                pad_token_id=caption_tokenizer.eos_token_id
                            )
                        
                        caption = caption_tokenizer.decode(output_ids[0], skip_special_tokens=True)
                        all_captions.append(caption)
                    except Exception as e:
                        logger.debug(f"Caption hatası: {str(e)}")
                        all_captions.append("Image description unavailable")
        
        except Exception as e:
            logger.error(f"Batch analiz hatası: {str(e)}")
        
        return {
            "captions": all_captions,
            "classifications": all_classifications,
            "total_frames": len(frame_paths)
        }


class OptimizedAudioProcessor:
    """Optimize ses işleme"""
    
    @staticmethod
    def extract_audio_fast(video_path: str, audio_path: str) -> str:
        try:
            cmd = [
                'ffmpeg', '-i', video_path,
                '-vn', '-acodec', 'pcm_s16le',
                '-ar', '16000', '-ac', '1',
                '-y', audio_path
            ]
            result = subprocess.run(cmd, capture_output=True, timeout=30, text=True)
            if result.returncode == 0:
                return audio_path
            raise Exception(f"FFmpeg error: {result.stderr}")
        except Exception as e:
            logger.warning(f"FFmpeg başarısız, moviepy deneniyor: {str(e)}")
            try:
                video = VideoFileClip(video_path)
                if video.audio:
                    video.audio.write_audiofile(audio_path, logger=None)
                video.close()
                return audio_path
            except Exception as e2:
                logger.error(f"Ses çıkarma hatası: {str(e2)}")
                raise
    
    @staticmethod
    def get_youtube_transcript(url: str) -> Optional[str]:
        try:
            video_id = VideoDownloader.extract_video_id(url)
            if not video_id:
                return None
            
            for lang in ['tr', 'en']:
                try:
                    transcript = YouTubeTranscriptApi.get_transcript(video_id, languages=[lang])
                    formatter = TextFormatter()
                    text = formatter.format_transcript(transcript)
                    logger.debug(f"✅ Altyazı alındı ({lang})")
                    return text
                except:
                    continue
            return None
        except:
            return None
    
    @staticmethod
    def transcribe_audio_fast(audio_path: str) -> str:
        try:
            with model_manager.get_lock('whisper'):
                whisper_model = model_manager.get_model('whisper')
                result = whisper_model.transcribe(
                    audio_path,
                    fp16=model_manager.device == 'cuda',
                    verbose=False,
                    language='tr'
                )
                return result["text"]
        except Exception as e:
            logger.error(f"Whisper hatası: {str(e)}")
            return ""


class OptimizedTextAnalyzer:
    @staticmethod
    def analyze_text_fast(text: str) -> Dict:
        if not text or len(text) < 10:
            return {
                "sentiment": {"label": "NEUTRAL", "score": 0.5},
                "toxic_content": {"is_toxic": False, "toxicity_score": 0.0},
                "keywords": [],
                "text_length": 0,
                "word_count": 0
            }
        
        try:
            text_sample = text[:512]
            
            with model_manager.get_lock('nlp'):
                sentiment_analyzer = model_manager.get_model('sentiment_analyzer')
                sentiment = sentiment_analyzer(text_sample)[0]
                
                toxic_classifier = model_manager.get_model('toxic_classifier')
                toxic_results = toxic_classifier(text_sample)[0]
                toxic_scores = {r['label']: r['score'] for r in toxic_results}
                max_toxic = max(toxic_scores.values())
            
            words = re.findall(r'\b\w+\b', text.lower())
            stopwords = {'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for', 'of', 'with', 'by'}
            words = [w for w in words if w not in stopwords and len(w) > 3]
            
            from collections import Counter
            word_counts = Counter(words)
            keywords = [word for word, _ in word_counts.most_common(10)]
            
            return {
                "sentiment": {"label": sentiment['label'], "score": float(sentiment['score'])},
                "toxic_content": {"is_toxic": max_toxic > 0.5, "toxicity_score": max_toxic, "details": toxic_scores},
                "keywords": keywords,
                "text_length": len(text),
                "word_count": len(text.split())
            }
        except Exception as e:
            logger.warning(f"NLP hatası: {str(e)}")
            return {
                "sentiment": {"label": "UNKNOWN", "score": 0.0},
                "toxic_content": {"is_toxic": False, "toxicity_score": 0.0},
                "keywords": [],
                "text_length": len(text),
                "word_count": len(text.split())
            }


class OptimizedMultimodalAnalyzer:
    @staticmethod
    def create_concise_prompt(visual_data: Dict, text_data: str, transcript_analysis: Dict) -> str:
        captions_summary = " | ".join(visual_data.get('captions', [])[:5])
        
        classifications = visual_data.get('classifications', [])
        avg_safety_scores = {}
        if classifications:
            for key in classifications[0].keys():
                avg_safety_scores[key] = sum(c.get(key, 0) for c in classifications) / len(classifications)
        
        text_sample = text_data[:1000]
        
        prompt = f"""Çocuk video güvenlik analizi:

Görsel: {captions_summary}
Sınıflandırma: {json.dumps(avg_safety_scores, indent=2)}

Metin: {text_sample}

Duygu: {transcript_analysis.get('sentiment', {}).get('label', 'Bilinmiyor')}
Toksiklik: {transcript_analysis.get('toxic_content', {}).get('toxicity_score', 0):.2f}

JSON döndür:
{{
  "safety_score": <0-100 TEK SAYI>,
  "suitability": "Uygun"|"Koşullu Uygun"|"Uygun Değil",
  "age_recommendation": "7+",
  "summary": "2 cümle özet",
  "risk_factors": ["risk1"],
  "educational_value": "Kısa",
  "parent_notes": "Kısa"
}}

Kural: safety_score TEK SAYI, 80-100:Uygun 50-79:Koşullu 0-49:Uygun Değil
"""
        return prompt
    
    @staticmethod
    def analyze_with_gemini_fast(prompt: str) -> Dict:
        gemini_api_key = app.config.get('GEMINI_API_KEY', '')
        if not gemini_api_key:
            return {
                "success": False,
                "error": "GEMINI_API_KEY ayarlanmamis",
                "analysis": "Analiz icin GEMINI_API_KEY ortam degiskenini ayarlayin"
            }

        api_url = f"https://generativelanguage.googleapis.com/v1beta/models/{app.config['GEMINI_MODEL']}:generateContent"
        
        payload = {
            "contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {
                "temperature": 0.1,
                "topP": 0.8,
                "topK": 10,
                "maxOutputTokens": 500,
            }
        }
        
        for attempt in range(app.config['GEMINI_MAX_RETRIES']):
            try:
                if attempt > 0:
                    wait_time = app.config['GEMINI_RETRY_DELAY'] * attempt
                    logger.warning(f"⏳ Gemini retry {attempt + 1}, {wait_time}s...")
                    time.sleep(wait_time)
                
                gemini_manager.wait_if_needed()
                
                with gemini_manager.semaphore:
                    response = requests.post(
                        api_url,
                        params={"key": gemini_api_key},
                        json=payload,
                        timeout=60
                    )
                
                if response.status_code in [503, 429]:
                    if attempt < app.config['GEMINI_MAX_RETRIES'] - 1:
                        continue
                    return {"success": False, "error": f"Status {response.status_code}", "analysis": "API unavailable"}
                
                response.raise_for_status()
                result = response.json()
                
                candidates = result.get("candidates", [])
                if candidates and candidates[0].get('content', {}).get('parts'):
                    parts = candidates[0]['content']['parts']
                    if parts and parts[0].get('text'):
                        analysis_text = parts[0]['text'].strip()
                        return {"success": True, "analysis": analysis_text}
                
                if attempt < app.config['GEMINI_MAX_RETRIES'] - 1:
                    continue
                
                return {"success": False, "error": "Boş yanıt", "analysis": "Gemini boş yanıt"}
                
            except Exception as e:
                safe_error = str(e)
                if gemini_api_key:
                    safe_error = safe_error.replace(gemini_api_key, '***')
                logger.error(f"Gemini hatası: {safe_error}")
                if attempt < app.config['GEMINI_MAX_RETRIES'] - 1:
                    continue
                return {"success": False, "error": safe_error, "analysis": f"Hata: {safe_error}"}
        
        return {"success": False, "error": "Tüm retry başarısız", "analysis": "Analiz tamamlanamadı"}
    
    @staticmethod
    def format_analysis_for_display(gemini_response: str) -> str:
        try:
            json_match = re.search(r'\{[^{}]*"safety_score".*?\}', gemini_response, re.DOTALL)
            if not json_match:
                json_match = re.search(r'```json\s*(\{.*?\})\s*```', gemini_response, re.DOTALL)
                if json_match:
                    json_str = json_match.group(1)
                else:
                    json_match = re.search(r'\{.*\}', gemini_response, re.DOTALL)
                    json_str = json_match.group(0) if json_match else None
            else:
                json_str = json_match.group(0)
            
            if json_str:
                try:
                    data = json.loads(json_str)
                    formatted = []
                    
                    if data.get('summary'):
                        formatted.append(f"📝 **İçerik**\n{data['summary']}\n")
                    
                    if data.get('suitability'):
                        emoji = {'Uygun': '✅', 'Koşullu Uygun': '⚠️', 'Uygun Değil': '❌'}.get(data['suitability'], '📊')
                        formatted.append(f"{emoji} **Değerlendirme:** {data['suitability']}")
                    
                    if data.get('age_recommendation'):
                        formatted.append(f"👶 **Yaş:** {data['age_recommendation']}")
                    
                    if data.get('risk_factors'):
                        formatted.append(f"⚠️ **Dikkat:** {', '.join(data['risk_factors'])}")
                    
                    if data.get('educational_value'):
                        formatted.append(f"\n📚 **Eğitsel:** {data['educational_value']}")
                    
                    if data.get('parent_notes'):
                        formatted.append(f"\n👨‍👩‍👧 **Öneri:** {data['parent_notes']}")
                    
                    result = '\n'.join(formatted)
                    return result if result else gemini_response
                except:
                    pass
            
            return gemini_response
        except:
            return gemini_response
    
    @staticmethod
    def extract_safety_score(gemini_response: str) -> int:
        try:
            json_match = re.search(r'\{[^{}]*"safety_score"[^{}]*\}', gemini_response, re.DOTALL)
            if json_match:
                try:
                    data = json.loads(json_match.group(0))
                    score = int(data.get('safety_score', 0))
                    if 0 <= score <= 100:
                        return score
                except:
                    pass
            
            patterns = [
                r'(\d+)\s*/\s*100',
                r'\((\d+)/100\)',
                r'[*\s]*(\d+)/100',
                r'["\']?safety_score["\']?[:\s]*(\d+)',
            ]
            
            for pattern in patterns:
                match = re.search(pattern, gemini_response, re.IGNORECASE)
                if match:
                    score = int(match.group(1))
                    if 0 <= score <= 100:
                        return score
            
            response_lower = gemini_response.lower()
            if any(w in response_lower for w in ['uygun', 'güvenli', 'eğitici']):
                return 65 if 'koşullu' in response_lower else 85
            elif any(w in response_lower for w in ['uygun değil', 'tehlikeli', 'risk']):
                return 30
            
            return 50
        except:
            return 50


class OptimizedVideoAnalyzer:
    def __init__(self, temp_dir: str):
        self.temp_dir = temp_dir
    
    def analyze_video_fast(self, video_url: str, video_data: Dict, index: int) -> Dict:
        start_time = time.time()
        
        try:
            logger.info(f"🎬 [{index}] Analiz başladı")
            
            video_info = VideoDownloader.get_video_info_cached(video_url)
            video_id = video_info.get('video_id', f'unknown_{index}')
            
            video_file = os.path.join(self.temp_dir, f"{video_id}.mp4")
            audio_file = os.path.join(self.temp_dir, f"{video_id}.wav")
            frames_dir = os.path.join(self.temp_dir, f"frames_{video_id}")
            
            # Video indir
            logger.debug(f"[{index}] İndiriliyor...")
            VideoDownloader.download_video(video_url, video_file, app.config['VIDEO_DOWNLOAD_TIMEOUT'])
            
            # Paralel: Görsel + Ses
            def visual_task():
                logger.debug(f"[{index}] Görsel...")
                frames = OptimizedVisualProcessor.extract_frames_fast(
                    video_file, frames_dir,
                    app.config['FRAME_EXTRACTION_INTERVAL'],
                    app.config['MAX_FRAMES_PER_VIDEO']
                )
                return OptimizedVisualProcessor.analyze_frames_batch(frames)
            
            def audio_task():
                logger.debug(f"[{index}] Ses...")
                trans = OptimizedAudioProcessor.get_youtube_transcript(video_url)
                if trans:
                    return trans
                OptimizedAudioProcessor.extract_audio_fast(video_file, audio_file)
                return OptimizedAudioProcessor.transcribe_audio_fast(audio_file)
            
            with ThreadPoolExecutor(max_workers=2) as executor:
                visual_future = executor.submit(visual_task)
                audio_future = executor.submit(audio_task)
                
                visual_result = visual_future.result(timeout=app.config['ANALYSIS_TIMEOUT'])
                transcript = audio_future.result(timeout=app.config['ANALYSIS_TIMEOUT'])
            
            logger.debug(f"[{index}] NLP...")
            text_analysis = OptimizedTextAnalyzer.analyze_text_fast(transcript)
            
            logger.debug(f"[{index}] Gemini...")
            prompt = OptimizedMultimodalAnalyzer.create_concise_prompt(visual_result, transcript, text_analysis)
            gemini_result = OptimizedMultimodalAnalyzer.analyze_with_gemini_fast(prompt)
            
            safety_score = OptimizedMultimodalAnalyzer.extract_safety_score(gemini_result.get('analysis', ''))
            formatted_analysis = OptimizedMultimodalAnalyzer.format_analysis_for_display(gemini_result.get('analysis', ''))
            
            processing_time = time.time() - start_time
            
            result = {
                "index": index,
                "video_id": video_id,
                "url": video_url,
                "title": video_info.get('title', 'Bilinmiyor'),
                "thumbnail": video_info.get('thumbnail'),
                "duration": video_info.get('duration', 0),
                "channel": video_info.get('channel', 'Bilinmiyor'),
                "watch_date": video_data.get('date').strftime('%Y-%m-%d %H:%M:%S') if video_data.get('date') else 'Bilinmiyor',
                "analysis": {
                    "visual_summary": {
                        "total_frames": visual_result.get('total_frames', 0),
                        "sample_captions": visual_result.get('captions', [])[:5],
                        "safety_classifications": visual_result.get('classifications', [])[:3]
                    },
                    "audio_text_summary": {
                        "transcript_length": len(transcript),
                        "transcript_preview": transcript[:500],
                        "sentiment": text_analysis.get('sentiment'),
                        "toxic_content": text_analysis.get('toxic_content'),
                        "keywords": text_analysis.get('keywords')
                    },
                    "multimodal_evaluation": {
                        "gemini_analysis": formatted_analysis,
                        "report": formatted_analysis,
                        "raw_response": gemini_result.get('analysis', ''),
                        "safety_score": safety_score,
                        "analysis_success": gemini_result.get('success', False)
                    },
                    "metadata": {
                        "processing_time_seconds": round(processing_time, 2),
                        "analysis_timestamp": datetime.datetime.now().isoformat(),
                        "transcript_source": "youtube_subtitle" if OptimizedAudioProcessor.get_youtube_transcript(video_url) else "whisper"
                    }
                }
            }
            
            logger.info(f"✅ [{index}] Tamamlandı ({processing_time:.1f}s)")
            
            self._cleanup_video_files(video_file, audio_file, frames_dir)
            
            return result
            
        except Exception as e:
            logger.error(f"❌ [{index}] Analiz hatası: {str(e)}")
            logger.error(traceback.format_exc())
            return {
                "index": index,
                "video_id": video_data.get('video_id', f'error_{index}'),
                "url": video_url,
                "title": "Analiz Hatası",
                "error": str(e),
                "analysis": {
                    "multimodal_evaluation": {
                        "gemini_analysis": f"Hata: {str(e)}",
                        "report": f"Hata: {str(e)}",
                        "safety_score": 0,
                        "analysis_success": False
                    }
                }
            }
    
    def _cleanup_video_files(self, video_file: str, audio_file: str, frames_dir: str):
        if not app.config['AUTO_DELETE_TEMP_FILES']:
            return
        try:
            for path in [video_file, audio_file]:
                if os.path.exists(path):
                    os.remove(path)
            if os.path.exists(frames_dir):
                shutil.rmtree(frames_dir)
        except:
            pass


@app.errorhandler(404)
def not_found(error):
    return jsonify({'error': 'Endpoint bulunamadı'}), 404

@app.errorhandler(500)
def internal_error(error):
    logger.error(f"Sunucu hatası: {str(error)}")
    return jsonify({'error': 'Sunucu hatası', 'details': str(error)}), 500

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.datetime.now().isoformat(),
        'models_loaded': model_manager.initialized,
        'device': model_manager.device,
        'version': '3.0.0-fixed'
    })

@app.route('/analyze', methods=['POST'])
@rate_limit
def analyze():
    request_start = time.time()
    temp_dir = None
    
    try:
        if 'file' not in request.files:
            return jsonify({'error': 'Dosya yüklenmedi'}), 400
        
        file = request.files['file']
        if not file.filename or not file.filename.lower().endswith('.zip'):
            return jsonify({'error': 'Geçersiz dosya'}), 400
        
        target_date_str = request.form.get('target_date') or request.form.get('date')
        if not target_date_str:
            return jsonify({'error': 'Tarih gerekli'}), 400
        
        try:
            target_date = datetime.datetime.strptime(target_date_str, '%Y-%m-%d')
        except ValueError:
            return jsonify({'error': 'Geçersiz tarih formatı (YYYY-MM-DD)'}), 400
        
        temp_dir = tempfile.mkdtemp(dir=app.config['TEMP_FOLDER'])
        zip_path = os.path.join(temp_dir, secure_filename(file.filename))
        file.save(zip_path)
        
        logger.info("📦 Takeout ayrıştırılıyor...")
        video_records = TakeoutParser.parse_takeout_zip(zip_path)
        
        unique_videos = {}
        for record in video_records:
            url = record.get('url', '')
            video_id = VideoDownloader.extract_video_id(url)
            if video_id and video_id not in unique_videos:
                unique_videos[video_id] = {
                    'url': f"https://www.youtube.com/watch?v={video_id}",
                    'date': record.get('date')
                }
        
        filtered_videos = [
            v for v in unique_videos.values() 
            if v.get('date') and v['date'].date() == target_date.date()
        ]
        
        if not filtered_videos:
            return jsonify({
                'error': f'{target_date.strftime("%Y-%m-%d")} için video bulunamadı',
                'total_videos_found': len(video_records),
                'unique_videos': len(unique_videos)
            }), 404
        
        videos_to_analyze = filtered_videos[:app.config['MAX_VIDEOS_TO_ANALYZE']]
        
        logger.info(f"🚀 {len(videos_to_analyze)} video paralel analiz edilecek")
        
        analyzer = OptimizedVideoAnalyzer(temp_dir)
        results = []
        failed_count = 0
        
        batch_size = app.config['BATCH_SIZE']
        total_batches = (len(videos_to_analyze) + batch_size - 1) // batch_size
        
        for batch_idx in range(total_batches):
            start_idx = batch_idx * batch_size
            end_idx = min((batch_idx + 1) * batch_size, len(videos_to_analyze))
            batch = videos_to_analyze[start_idx:end_idx]
            
            logger.info(f"📊 Batch {batch_idx + 1}/{total_batches} ({len(batch)} video)")
            
            with ThreadPoolExecutor(max_workers=app.config['MAX_WORKERS']) as executor:
                futures = {
                    executor.submit(analyzer.analyze_video_fast, video['url'], video, start_idx + idx + 1): start_idx + idx + 1
                    for idx, video in enumerate(batch)
                }
                
                for future in as_completed(futures):
                    idx = futures[future]
                    try:
                        result = future.result(timeout=app.config['ANALYSIS_TIMEOUT'] + 60)
                        results.append(result)
                    except Exception as e:
                        logger.error(f"Video {idx} başarısız: {str(e)}")
                        failed_count += 1
                        results.append({
                            'index': idx,
                            'error': str(e),
                            'analysis': {'multimodal_evaluation': {'safety_score': 0}}
                        })
        
        results.sort(key=lambda x: x.get('index', 0))
        
        total_time = time.time() - request_start
        successful_results = [r for r in results if 'error' not in r or not r.get('error')]
        avg_safety = sum(
            r.get('analysis', {}).get('multimodal_evaluation', {}).get('safety_score', 0) 
            for r in successful_results
        ) / len(successful_results) if successful_results else 0
        
        response = {
            'success': True,
            'request_id': str(uuid.uuid4()),
            'timestamp': datetime.datetime.now().isoformat(),
            'target_date': target_date.strftime('%Y-%m-%d'),
            'statistics': {
                'total_videos_in_takeout': len(video_records),
                'unique_videos': len(unique_videos),
                'date_filtered': len(filtered_videos),
                'analyzed': len(results),
                'successful': len(successful_results),
                'failed': failed_count,
                'average_safety_score': round(avg_safety, 2),
                'processing_time_seconds': round(total_time, 2),
                'average_time_per_video': round(total_time / len(results), 2) if results else 0,
            },
            'videos': results
        }
        
        logger.info(f"✅ Analiz tamamlandı: {len(successful_results)}/{len(results)} başarılı, {total_time:.2f}s")
        logger.info(f"📊 Ortalama video başına: {total_time / len(results):.2f}s")
        
        return jsonify(response)
        
    except Exception as e:
        logger.error(f"❌ Genel hata: {str(e)}")
        logger.error(traceback.format_exc())
        return jsonify({
            'error': 'Analiz sırasında hata oluştu',
            'details': str(e)
        }), 500
    
    finally:
        if temp_dir and os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)


def initialize_app():
    logger.info("=" * 80)
    logger.info("🚀 Guardify v3 - OPTIMIZED & FIXED VERSION")
    logger.info("=" * 80)
    logger.info(f"📂 Upload: {app.config['UPLOAD_FOLDER']}")
    logger.info(f"📂 Temp: {app.config['TEMP_FOLDER']}")
    logger.info(f"🖥️  Device: {model_manager.device}")
    logger.info(f"🧠 Models: {'✅' if model_manager.initialized else '❌'}")
    
    if torch.cuda.is_available():
        logger.info(f"🎮 GPU: {torch.cuda.get_device_name(0)}")
    else:
        logger.info("🖥️  CPU Mode")
    
    logger.info(f"⚡ Workers: {app.config['MAX_WORKERS']}")
    logger.info(f"📦 Batch: {app.config['BATCH_SIZE']}")
    logger.info(f"🎬 Max Videos: {app.config['MAX_VIDEOS_TO_ANALYZE']}")
    logger.info(f"🖼️  Frames: {app.config['MAX_FRAMES_PER_VIDEO']}")
    logger.info(f"🤖 Gemini: {app.config['GEMINI_MODEL']}")
    logger.info("=" * 80)
    logger.info("✅ Sistem hazır")
    logger.info("=" * 80)

if __name__ == '__main__':
    initialize_app()
    app.run(host='0.0.0.0', port=5000, debug=False, threaded=True, use_reloader=False)