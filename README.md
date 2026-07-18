# Cuddle Umbrella - Video Downloader

Cuddle Umbrella; YouTube, Instagram, X (Twitter) gibi popüler platformlardan video bağlantılarını (URL) alarak hızlı ve verimli bir şekilde indirmeyi sağlayan full-stack bir video indirme uygulamasıdır.

Bu proje iki ana bileşenden oluşmaktadır:
1. **backend/**: Python FastAPI ve `yt-dlp` tabanlı video bilgi/bağlantı çıkartıcı API.
2. **mobile/**: Flutter tabanlı Android & iOS mobil uygulaması.

---

## Mimari Şema

Aşağıdaki şemada uygulamanın genel çalışma prensibi gösterilmiştir:

```mermaid
graph TD
    subgraph Mobile App (Flutter)
        UI[Kullanıcı Arayüzü / Input] -->|URL Yapıştırır| Client[Dio HTTP Client]
        Client -->|1. URL Analizi /extract| API[FastAPI Backend]
        API -->|2. Doğrudan Video Linki + Meta Veri| Client
        Client -->|3. İndirme Komutu| BD[background_downloader]
        BD -->|4. Arka Planda İndirme ve Progress| Storage[(Yerel Galeri / Depolama)]
    end

    subgraph Backend Service (FastAPI & Docker)
        API --> YTDL[yt-dlp Extractor]
        YTDL -->|Platform API Sorgusu| Platforms((Sosyal Medya Platformları <br> YouTube, X, Instagram vb.))
    end
```

---

## Çalıştırma Talimatları

### 1. Backend (FastAPI) Çalıştırma

Backend'i çalıştırmak için iki yöntem bulunmaktadır:

#### A. Yerel Olarak (Virtualenv)
Python 3.11+ sürümünün kurulu olduğundan emin olun.

1. Backend dizinine geçin ve sanal ortam oluşturun:
   ```bash
   cd backend
   python -m venv .venv
   ```
2. Sanal ortamı aktif edin:
   * **Windows (PowerShell):**
     ```powershell
     .venv\Scripts\Activate.ps1
     ```
   * **macOS / Linux:**
     ```bash
     source .venv/bin/activate
     ```
3. Bağımlılıkları yükleyin:
   ```bash
   pip install -r requirements.txt
   ```
4. `.env.example` dosyasını `.env` olarak kopyalayın ve yapılandırın.
5. API Sunucusunu başlatın:
   ```bash
   uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
   ```
6. API dokümantasyonuna tarayıcınızdan `http://127.0.0.1:8000/docs` adresinden erişebilirsiniz.

#### B. Docker ile Çalıştırma
Docker'ın sisteminizde kurulu ve çalışır durumda olduğundan emin olun.

1. Docker imajını oluşturun:
   ```bash
   cd backend
   docker build -t cuddle-umbrella-backend .
   ```
2. İmajı ayağa kaldırın:
   ```bash
   docker run -d -p 8000:8000 --name cuddle-backend --env-file .env cuddle-umbrella-backend
   ```
3. Uygulama `http://localhost:8000` adresinden istekleri kabul etmeye başlayacaktır.

---

### 2. Mobile (Flutter) Çalıştırma

Flutter SDK'sının sisteminizde kurulu olduğundan emin olun (`flutter doctor` ile doğrulayabilirsiniz).

1. Flutter projesinin olduğu dizine geçin:
   ```bash
   cd mobile/cuddle_umbrella
   ```
2. Bağımlılıkları çekin:
   ```bash
   flutter pub get
   ```
3. Bir emülatör/simülatör veya fiziksel cihaz bağlayın.
4. Uygulamayı başlatın:
   ```bash
   flutter run
   ```

#### Backend API Entegrasyonu (.env Yapılandırması)
Mobil uygulama, istek atacağı backend URL'sini `mobile/cuddle_umbrella` dizini altında yapılandırılmış yerel konfigürasyonlardan veya global API adreslerinden okur. Geliştirme aşamasında yerel sunucuyu (`http://10.0.2.2:8000` Android emülatörleri için) kullanabilirsiniz.

---

## Bağımlılıklar (Pinned Dependencies)

### Backend (`backend/requirements.txt`)
- `fastapi==0.111.0` - Web API Framework
- `uvicorn==0.30.1` - ASGI Server
- `yt-dlp==2024.7.15` - Video Çıkarma Motoru
- `python-dotenv==1.0.1` - Çevre Değişkenleri Yönetimi

### Mobile (`mobile/cuddle_umbrella/pubspec.yaml`)
- `dio: 5.7.0` - HTTP İstek Yönetimi
- `receive_sharing_intent: 1.9.0` - Dış uygulamalardan paylaşılan linkleri yakalama
- `share_plus: 9.0.0` - Link/Dosya paylaşım menüsü
- `path_provider: 2.1.5` - Platform bağımsız dosya yolları yönetimi
- `permission_handler: 12.0.3` - Android & iOS İzin yönetimi
- `background_downloader: 9.5.6` - Gelişmiş arka plan indirme ve progress çubuğu
- `shared_preferences: 2.5.3` - Basit verileri cihazda saklama (Key-Value)
- `cached_network_image: 3.4.1` - Görsel önbelleğe alma ve yükleme durumları yönetimi
