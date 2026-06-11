// Voice service for speech-to-text input and text-to-speech output.
// Uses speech_to_text for STT and flutter_tts for TTS.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

/// Manages speech-to-text and text-to-speech for the Hermes chat UI.
class VoiceService extends ChangeNotifier {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _sttAvailable = false;
  bool _isListening = false;
  bool _ttsEnabled = true;
  bool _sttEnabled = true;
  String _lastRecognizedWords = '';
  double _ttsRate = 0.5;

  bool get sttAvailable => _sttAvailable;
  bool get isListening => _isListening;
  bool get ttsEnabled => _ttsEnabled;
  bool get sttEnabled => _sttEnabled;
  String get lastRecognizedWords => _lastRecognizedWords;
  double get ttsRate => _ttsRate;

  /// Callback invoked when speech is recognised (final result).
  void Function(String text)? onSpeechResult;

  /// Callback invoked with interim recognition.
  void Function(String text)? onSpeechInterim;

  VoiceService() {
    _init();
  }

  Future<void> _init() async {
    // Initialise STT
    _sttAvailable = await _speech.initialize(
      onError: (_) => _sttAvailable = false,
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          _isListening = false;
          notifyListeners();
        }
      },
    );

    // Initialise TTS
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(_ttsRate);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    await _tts.awaitSpeakCompletion(true);

    // Load preferences
    final prefs = await SharedPreferences.getInstance();
    _ttsEnabled = prefs.getBool('voice_tts_enabled') ?? true;
    _sttEnabled = prefs.getBool('voice_stt_enabled') ?? true;
    _ttsRate = prefs.getDouble('voice_tts_rate') ?? 0.5;

    notifyListeners();
  }

  // ── Speech-to-Text ─────────────────────────────────────────────────

  /// Start listening for speech. Results are delivered via [onSpeechResult].
  Future<bool> startListening() async {
    if (!_sttAvailable || _isListening) return false;

    _lastRecognizedWords = '';
    _isListening = true;
    notifyListeners();

    await _speech.listen(
      onResult: (result) {
        _lastRecognizedWords = result.recognizedWords;
        if (result.finalResult) {
          _isListening = false;
          notifyListeners();
          if (_lastRecognizedWords.isNotEmpty) {
            onSpeechResult?.call(_lastRecognizedWords);
          }
        } else {
          onSpeechInterim?.call(result.recognizedWords);
          notifyListeners();
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      localeId: 'en_US',
      cancelOnError: true,
      listenMode: stt.ListenMode.confirmation,
    );

    return true;
  }

  /// Stop listening and return any recognised text.
  Future<void> stopListening() async {
    if (!_isListening) return;
    await _speech.stop();
    _isListening = false;
    notifyListeners();
  }

  /// Cancel listening without returning results.
  Future<void> cancelListening() async {
    if (!_isListening) return;
    await _speech.cancel();
    _isListening = false;
    _lastRecognizedWords = '';
    notifyListeners();
  }

  // ── Text-to-Speech ─────────────────────────────────────────────────

  /// Speak the given text aloud using TTS.
  Future<void> speak(String text) async {
    if (!_ttsEnabled || text.trim().isEmpty) return;
    await _tts.speak(text);
  }

  /// Stop any currently-playing TTS.
  Future<void> stopSpeaking() async {
    await _tts.stop();
  }

  // ── Preferences ────────────────────────────────────────────────────

  Future<void> setTtsEnabled(bool value) async {
    _ttsEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_tts_enabled', value);
    if (!value) await stopSpeaking();
    notifyListeners();
  }

  Future<void> setSttEnabled(bool value) async {
    _sttEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_stt_enabled', value);
    notifyListeners();
  }

  Future<void> setTtsRate(double value) async {
    _ttsRate = value;
    await _tts.setSpeechRate(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('voice_tts_rate', value);
    notifyListeners();
  }

  @override
  void dispose() {
    _speech.cancel();
    _tts.stop();
    super.dispose();
  }
}
