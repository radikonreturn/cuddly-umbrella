import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../models/video_info.dart';

class ApiService {
  final Dio _dio;

  ApiService()
      : _dio = Dio(
          BaseOptions(
            // Read from --dart-define=BACKEND_URL or default to localhost
            baseUrl: const String.fromEnvironment(
              'BACKEND_URL',
              defaultValue: 'http://127.0.0.1:8000',
            ),
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 15),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'User-Agent': 'CuddleUmbrellaMobile/1.0',
            },
          ),
        );

  Future<VideoInfo> extractVideo(String url) async {
    try {
      debugPrint('ApiService: Connecting to ${_dio.options.baseUrl}/api/extract');
      final response = await _dio.post(
        '/api/extract',
        data: {'url': url},
      );

      if (response.statusCode == 200 && response.data != null) {
        return VideoInfo.fromJson(response.data);
      } else {
        throw Exception('Geçersiz sunucu yanıtı');
      }
    } on DioException catch (e) {
      debugPrint('ApiService: DioError: ${e.type} - ${e.message} - ${e.error}');
      if (e.response != null) {
        debugPrint('ApiService: Response data: ${e.response?.data}');
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw Exception('Sunucuya bağlanılamadı. Lütfen sunucunun çalıştığından emin olun.');
      }
      
      // Parse details from FastAPI exception
      final responseData = e.response?.data;
      if (responseData is Map) {
        final detail = responseData['detail'];
        if (detail != null) {
          throw Exception(detail.toString());
        }
      }
      throw Exception('Video bilgileri alınamadı (Hata kodu: ${e.response?.statusCode})');
    } catch (e) {
      debugPrint('ApiService: Unknown Error: $e');
      throw Exception('Bir hata oluştu. Lütfen tekrar deneyin.');
    }
  }
}
