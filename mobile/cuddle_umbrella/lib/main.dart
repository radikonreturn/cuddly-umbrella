import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_handler/share_handler.dart';
import 'screens/main_navigation_screen.dart';
import 'providers/providers.dart';
import 'providers/settings_provider.dart';

// Provider to share URL parsed from outside the app
final sharedUrlProvider = StateProvider<String>((ref) => '');

void main() {
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  StreamSubscription? _intentDataStreamSubscription;

  @override
  void initState() {
    super.initState();
    // Only initialize sharing intent on mobile platforms (Android/iOS)
    if (Platform.isAndroid || Platform.isIOS) {
      _initSharingIntent();
    }
  }

  Future<void> _initSharingIntent() async {
    // TODO: For iOS ShareExtension target setup, configure App Group and Podfile entry as per share_handler iOS docs when building on macOS.
    final handler = ShareHandlerPlatform.instance;

    // For sharing or receiving links when app is closed / launched initially
    final initialMedia = await handler.getInitialSharedMedia();
    if (initialMedia != null) {
      final content = initialMedia.content;
      if (content != null && content.isNotEmpty) {
        _handleSharedUrl(content);
      }
    }

    // For sharing or receiving links while app is running in memory
    _intentDataStreamSubscription = handler.sharedMediaStream.listen((SharedMedia media) {
      final content = media.content;
      if (content != null && content.isNotEmpty) {
        _handleSharedUrl(content);
      }
    }, onError: (err) {
      debugPrint("sharedMediaStream error: $err");
    });
  }

  void _handleSharedUrl(String? url) {
    if (url == null || url.trim().isEmpty) return;
    
    // Extract url from text (in case there's text around the url)
    final regExp = RegExp(r'(https?:\/\/[^\s]+)');
    final match = regExp.firstMatch(url);
    final cleanUrl = match != null ? match.group(0) : url.trim();

    if (cleanUrl != null && cleanUrl.startsWith(RegExp(r'https?://'))) {
      ref.read(sharedUrlProvider.notifier).state = cleanUrl;
      ref.read(extractionStateProvider.notifier).extract(cleanUrl);
      ref.read(navigationIndexProvider.notifier).state = 0; // Go to Home tab
    }
  }

  @override
  void dispose() {
    _intentDataStreamSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp(
      title: 'Cuddle Umbrella',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      home: const MainNavigationScreen(),
    );
  }
}
