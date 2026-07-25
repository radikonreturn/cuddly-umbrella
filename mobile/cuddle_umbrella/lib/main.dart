import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
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

  void _initSharingIntent() {
    // For sharing or receiving links when app is in memory
    _intentDataStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen((value) {
      if (value.isNotEmpty) {
        final sharedFile = value.first;
        _handleSharedUrl(sharedFile.path);
      }
    }, onError: (err) {
      debugPrint("getMediaStream error: $err");
    });

    // For sharing or receiving links when app is closed
    ReceiveSharingIntent.instance.getInitialMedia().then((value) {
      if (value.isNotEmpty) {
        final sharedFile = value.first;
        _handleSharedUrl(sharedFile.path);
      }
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
