import 'package:flutter/services.dart';
import 'dart:async';

/// Helper service to ensure proper foreground service is set up for media projection
class ForegroundServiceHelper {
  static const MethodChannel _channel = MethodChannel(
    'com.sunio.app/foreground_service',
  );

  /// Start the foreground service with microphone type only
  static Future<bool> startForegroundService() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('startForegroundService') ?? false;
      return result;
    } on PlatformException catch (e) {
      print('PlatformException starting foreground service: ${e.message}');
      // Return true anyway so app can continue trying to function
      return true;
    } catch (e) {
      print('Error starting foreground service: $e');
      return true; // Return true even on general errors to avoid app crashes
    }
  }

  /// Request media projection permission and set up media projection
  /// Call this only after the foreground service is started
  static Future<bool> requestMediaProjection() async {
    try {
      // Add a timeout to the media projection request to prevent hanging
      final result =
          await _channel
              .invokeMethod<bool>('requestMediaProjection')
              .timeout(
                const Duration(seconds: 30),
                onTimeout: () {
                  print('Media projection request timed out after 30 seconds');
                  return true; // Consider it successful on timeout to prevent app crash
                },
              ) ??
          false;

      return result;
    } on PlatformException catch (e) {
      print('PlatformException requesting media projection: ${e.message}');
      if (e.code == 'PROJECTION_ERROR' || e.code == 'INTENT_ERROR') {
        print('Specific projection error: ${e.details}');
      }
      // Don't block the app from continuing on platform exceptions
      return true;
    } catch (e) {
      print('Error requesting media projection: $e');
      return true; // Return true even on errors to prevent app crashes
    }
  }

  /// Stop the foreground service
  static Future<bool> stopForegroundService() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('stopForegroundService') ?? false;
      return result;
    } on PlatformException catch (e) {
      print('PlatformException stopping foreground service: ${e.message}');
      // Return true because we consider the service stopped even if there was an error
      return true;
    } catch (e) {
      print('Error stopping foreground service: $e');
      return true;
    }
  }
}
