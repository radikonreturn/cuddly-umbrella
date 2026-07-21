import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/api_service.dart';
import '../models/extract_response.dart';
import '../models/format_info.dart';
import '../providers/download_provider.dart';
import '../theme.dart';
import 'downloads_view.dart';
import 'settings_view.dart';

class HomeView extends ConsumerStatefulWidget {
  const HomeView({super.key});

  @override
  ConsumerState<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends ConsumerState<HomeView> {
  final TextEditingController _urlController = TextEditingController();
  late StreamSubscription _intentDataStreamSubscription;
  
  bool _isLoading = false;
  String? _errorMessage;
  ExtractResponse? _extractedVideo;
  FormatInfo? _selectedFormat;

  @override
  void initState() {
    super.initState();
    _initSharingIntent();
  }

  @override
  void dispose() {
    _intentDataStreamSubscription.cancel();
    _urlController.dispose();
    super.dispose();
  }

  void _initSharingIntent() {
    // Listen for shared text/links when app is in memory
    _intentDataStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen((value) {
      if (value.isNotEmpty) {
        _handleSharedUrl(value.first.path);
      }
    }, onError: (err) {
      debugPrint("Sharing intent error: $err");
    });

    // Check for shared text/links when app is launched from closed state
    ReceiveSharingIntent.instance.getInitialMedia().then((value) {
      if (value.isNotEmpty) {
        _handleSharedUrl(value.first.path);
      }
    });
  }

  void _handleSharedUrl(String url) {
    setState(() {
      _urlController.text = url;
      _errorMessage = null;
      _extractedVideo = null;
      _selectedFormat = null;
    });
    _analyzeUrl();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null) {
      setState(() {
        _urlController.text = data.text!;
      });
    }
  }

  Future<void> _analyzeUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _errorMessage = 'Lütfen geçerli bir video URL bağlantısı girin.';
      });
      return;
    }

    if (!url.startsWith(RegExp(r'https?://'))) {
      setState(() {
        _errorMessage = 'Bağlantı geçersiz. URL http:// veya https:// ile başlamalıdır.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _extractedVideo = null;
      _selectedFormat = null;
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      final response = await apiService.extractVideoInfo(url);
      
      setState(() {
        _extractedVideo = response;
        if (response.formats.isNotEmpty) {
          _selectedFormat = response.formats.first;
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _triggerDownload() async {
    if (_extractedVideo == null || _selectedFormat == null) return;

    final apiService = ref.read(apiServiceProvider);
    final downloadUrl = apiService.getDownloadUrl(_urlController.text.trim(), _selectedFormat!.formatId);

    try {
      await ref.read(downloadProvider.notifier).startDownload(
        title: _extractedVideo!.title,
        downloadUrl: downloadUrl,
        quality: _selectedFormat!.quality,
        extension: _selectedFormat!.ext,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('İndirme sıraya eklendi!'),
            backgroundColor: AppTheme.successColor,
          ),
        );
        // Navigate to downloads screen
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const DownloadsView()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('İndirme başlatılamadı: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cuddle Umbrella'),
        leading: IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'Ayarlar',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SettingsView()),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_done_outlined),
            tooltip: 'İndirilenler',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const DownloadsView()),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            const Text(
              'Sosyal Medya Video İndirici',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'YouTube, X, Instagram ve daha fazlasından kolayca video indirin',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textMediumEmphasis,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 24),
            _buildInputSection(),
            const SizedBox(height: 20),
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: CircularProgressIndicator(color: AppTheme.primaryColor),
                ),
              ),
            if (_errorMessage != null) _buildErrorSection(),
            if (_extractedVideo != null) _buildVideoPreviewSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildInputSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _urlController,
          decoration: InputDecoration(
            hintText: 'Video URL adresini yapıştırın...',
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.content_paste_outlined, color: AppTheme.primaryColor),
                  tooltip: 'Yapıştır',
                  onPressed: _pasteFromClipboard,
                ),
                if (_urlController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear, color: AppTheme.textMediumEmphasis),
                    onPressed: () {
                      setState(() {
                        _urlController.clear();
                        _errorMessage = null;
                        _extractedVideo = null;
                        _selectedFormat = null;
                      });
                    },
                  ),
              ],
            ),
          ),
          onChanged: (val) {
            if (_errorMessage != null) {
              setState(() {
                _errorMessage = null;
              });
            }
          },
        ),
        const SizedBox(height: 14),
        ElevatedButton(
          onPressed: _isLoading ? null : _analyzeUrl,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: AppTheme.primaryColor,
          ),
          child: const Text('Bağlantıyı Çözümle'),
        ),
      ],
    );
  }

  Widget _buildErrorSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.errorColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.errorColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppTheme.errorColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: AppTheme.errorColor, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPreviewSection() {
    final video = _extractedVideo!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (video.thumbnail != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: CachedNetworkImage(
                    imageUrl: video.thumbnail!,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: Colors.black12,
                      child: const Center(
                        child: CircularProgressIndicator(color: AppTheme.primaryColor),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: Colors.black12,
                      child: const Icon(Icons.image_not_supported_outlined, size: 40),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              video.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (video.duration != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 14, color: AppTheme.textMediumEmphasis),
                  const SizedBox(width: 4),
                  Text(
                    video.formattedDuration,
                    style: const TextStyle(fontSize: 12, color: AppTheme.textMediumEmphasis),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            const Text(
              'Çözünürlük Seçeneği',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 8),
            if (video.formats.isEmpty)
              const Text(
                'Uygun video formatı bulunamadı.',
                style: TextStyle(color: AppTheme.errorColor, fontSize: 13),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: video.formats.map((fmt) {
                  final isSelected = _selectedFormat?.formatId == fmt.formatId;
                  return ChoiceChip(
                    label: Text('${fmt.quality} (${fmt.ext})'),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedFormat = fmt;
                        });
                      }
                    },
                    selectedColor: AppTheme.primaryColor.withOpacity(0.2),
                    checkmarkColor: AppTheme.primaryColor,
                    labelStyle: TextStyle(
                      color: isSelected ? AppTheme.primaryColor : AppTheme.textMediumEmphasis,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: isSelected ? AppTheme.primaryColor : AppTheme.textMediumEmphasis.withOpacity(0.2),
                      ),
                    ),
                  );
                }).toList(),
              ),
            if (_selectedFormat?.filesizeApprox != null) ...[
              const SizedBox(height: 8),
              Text(
                'Yaklaşık Boyut: ${_selectedFormat!.formattedSize}',
                style: const TextStyle(fontSize: 12, color: AppTheme.textMediumEmphasis),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _selectedFormat == null ? null : _triggerDownload,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Videoyu İndir'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
