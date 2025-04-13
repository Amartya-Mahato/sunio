import 'dart:async';
import 'dart:io';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:system_audio_recorder/system_audio_recorder.dart';

/// Service to handle recording system audio using the system_audio_recorder package
class SystemAudioService {
  static SystemAudioService? _instance;
  bool _isRecording = false;
  StreamSubscription? _audioStreamSubscription;
  MediaStream? _audioStream;
  List<int> _audioData = [];

  // Create a singleton instance
  static SystemAudioService get instance {
    _instance ??= SystemAudioService._();
    return _instance!;
  }

  SystemAudioService._();

  /// Check if the device supports recording system audio
  Future<bool> isSupported() async {
    try {
      // The package doesn't have a specific method to check support,
      // but we can use requestRecord which returns false if not supported
      final isSupported = await SystemAudioRecorder.requestRecord(
        titleNotification: "Audio Broadcasting",
        messageNotification: "System audio is being broadcast",
      );

      return isSupported;
    } catch (e) {
      print('Error checking system audio recording support: $e');
      return false;
    }
  }

  /// Start recording system audio and return a MediaStream for WebRTC
  Future<MediaStream?> startRecording() async {
    if (_isRecording) {
      print('Already recording system audio');
      return _audioStream;
    }

    try {
      print('Requesting permission to record system audio...');

      // Request permission to record system audio
      final isConfirmed = await SystemAudioRecorder.requestRecord(
        titleNotification: "Audio Broadcasting",
        messageNotification: "Your system audio is being broadcast",
      );

      if (!isConfirmed) {
        print('Permission to record system audio denied');
        return null;
      }

      // Create a WebRTC MediaStream
      _audioStream = await createLocalMediaStream('system_audio_stream');

      // Clear any previous audio data
      _audioData.clear();

      // Start recording with streaming enabled
      final isStarted = await SystemAudioRecorder.startRecord(
        toStream: true, // We need the audio data as a stream
        toFile: false, // We don't need to save to a file
        sampleRate: 44100, // Standard audio sampling rate
        bufferSize: 4096, // Larger buffer for better quality
      );

      if (!isStarted) {
        print('Failed to start system audio recording');
        _audioStream?.dispose();
        _audioStream = null;
        return null;
      }

      print('System audio recording started successfully');
      _isRecording = true;

      // Set up the audio stream and create audio track
      _setupAudioStream();

      return _audioStream;
    } catch (e) {
      print('Error starting system audio recording: $e');
      _cleanupResources();
      return null;
    }
  }

  /// Stop recording system audio
  Future<void> stopRecording() async {
    if (!_isRecording) {
      print('Not currently recording system audio');
      return;
    }

    try {
      print('Stopping system audio recording');
      await SystemAudioRecorder.stopRecord();
      _cleanupResources();
    } catch (e) {
      print('Error stopping system audio recording: $e');
      _cleanupResources();
    }
  }

  /// Set up the audio stream from system_audio_recorder
  void _setupAudioStream() {
    try {
      // Listen to the system audio stream
      _audioStreamSubscription = SystemAudioRecorder.audioStream
          .receiveBroadcastStream({})
          .listen(
            (data) {
              // We'll receive audio data as List<int>
              final audioBytes = List<int>.from(data);

              // Collect the audio data
              _audioData.addAll(audioBytes);

              // Log the amount of audio data received
              print('Received ${audioBytes.length} bytes of system audio data');

              // Here you would typically feed this data to an audio track
              // But WebRTC doesn't support feeding raw bytes directly to tracks
              // We'd need a native implementation to convert these bytes to a proper WebRTC audio source
            },
            onError: (error) {
              print('Error receiving system audio data: $error');
            },
          );
    } catch (e) {
      print('Error setting up system audio stream: $e');
    }
  }

  /// Clean up resources
  void _cleanupResources() {
    try {
      // Cancel any subscription
      _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;

      // Clear the audio data
      _audioData.clear();

      // Clean up WebRTC resources
      _audioStream?.getTracks().forEach((track) {
        track.stop();
      });
      _audioStream?.dispose();
      _audioStream = null;

      _isRecording = false;
    } catch (e) {
      print('Error cleaning up system audio resources: $e');
    }
  }

  /// Check if currently recording
  bool get isRecording => _isRecording;

  /// Get the current audio stream (if recording)
  MediaStream? get audioStream => _audioStream;

  /// Get the collected audio data
  List<int> get audioData => List.unmodifiable(_audioData);
}
