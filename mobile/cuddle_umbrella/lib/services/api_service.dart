import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/extract_response.dart';
import '../providers/settings_provider.dart';

class ApiService {
  final String baseUrl;
  late final Dio _dio;

  ApiService(this.baseUrl) {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 60),
        headers: {
          // Required user agent to pass backend client validation checks
          'User-Agent': 'CuddleUmbrellaMobile/1.0',
          'Accept': 'application/json',
        },
      ),
    );
  }

  Future<ExtractResponse> extractVideoInfo(String url) async {
    try {
      final response = await _dio.post(
        '/api/extract',
        data: {'url': url},
      );
      
      if (response.statusCode == 200 && response.data != null) {
        return ExtractResponse.fromJson(response.data as Map<String, dynamic>);
      } else {
        throw Exception('Failed to load video info (Status: ${response.statusCode})');
      }
    } on DioException catch (e) {
      String errorMessage = 'A network error occurred';
      if (e.response != null) {
        final detail = e.response?.data?['detail'];
        errorMessage = detail?.toString() ?? 'Server returned error: ${e.response?.statusCode}';
      } else if (e.type == DioExceptionType.connectionTimeout) {
        errorMessage = 'Connection timed out. Please check your internet or server URL.';
      } else if (e.error is SocketException) {
        errorMessage = 'Cannot connect to server. Is the backend running and URL correct?';
      }
      throw Exception(errorMessage);
    } catch (e) {
      throw Exception('An unexpected error occurred: $e');
    }
  }

  String getDownloadUrl(String videoUrl, String formatId) {
    // Generate the API download URL for the streaming download proxy
    final encodedUrl = Uri.encodeQueryComponent(videoUrl);
    final encodedFormatId = Uri.encodeQueryComponent(formatId);
    return '$baseUrl/api/download?url=$encodedUrl&format_id=$encodedFormatId';
  }
}

final apiServiceProvider = Provider<ApiService>((ref) {
  final settings = ref.watch(settingsProvider);
  return ApiService(settings.apiUrl);
});
