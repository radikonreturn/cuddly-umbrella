import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsState {
  final String apiUrl;
  final bool darkTheme;

  SettingsState({
    required this.apiUrl,
    required this.darkTheme,
  });

  SettingsState copyWith({
    String? apiUrl,
    bool? darkTheme,
  }) {
    return SettingsState(
      apiUrl: apiUrl ?? this.apiUrl,
      darkTheme: darkTheme ?? this.darkTheme,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  static const String _keyApiUrl = 'api_url';
  static const String _keyDarkTheme = 'dark_theme';
  // Default URL is 10.0.2.2:8000 (Android Emulator standard loopback to host)
  static const String _defaultApiUrl = 'http://10.0.2.2:8000';

  SettingsNotifier() : super(SettingsState(apiUrl: _defaultApiUrl, darkTheme: true)) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final apiUrl = prefs.getString(_keyApiUrl) ?? _defaultApiUrl;
    final darkTheme = prefs.getBool(_keyDarkTheme) ?? true;
    state = SettingsState(apiUrl: apiUrl, darkTheme: darkTheme);
  }

  Future<void> setApiUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiUrl, url);
    state = state.copyWith(apiUrl: url);
  }

  Future<void> setDarkTheme(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDarkTheme, val);
    state = state.copyWith(darkTheme: val);
  }

  Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyApiUrl);
    await prefs.remove(_keyDarkTheme);
    state = SettingsState(apiUrl: _defaultApiUrl, darkTheme: true);
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier();
});
