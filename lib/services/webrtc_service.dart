import 'dart:math';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:audio_session/audio_session.dart';
import 'package:permission_handler/permission_handler.dart';

class WebRTCService {
  final String id;
  final bool isBroadcaster;
  MediaStream? _localStream;
  RTCPeerConnection? _peerConnection;
  RTCSessionDescription? localDescription;
  
  // Callbacks
  Function(MediaStream)? onLocalStream;
  Function(MediaStream)? onRemoteStream;
  Function(RTCIceCandidate)? onRemoteIceCandidate;

  WebRTCService({required this.id, required this.isBroadcaster});

  String generateRandomString(int length) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random.secure();
    return List.generate(
      length,
      (index) => chars[rand.nextInt(chars.length)],
    ).join();
  }

  Future<void> initialize() async {
    await _initializePeerConnection();
    await _initializeMediaStream();
  }

  Future<void> _initializePeerConnection() async {
    Map<String, dynamic> configuration = {
      'iceServers': [
        {'url': 'stun:stun.l.google.com:19302'},
        {
          'url': 'turn:numb.viagenie.ca',
          'username': 'webrtc@live.com',
          'credential': 'muazkh'
        }
      ],
      'sdpSemantics': 'unified-plan'
    };

    _peerConnection = await createPeerConnection(configuration, {});

    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      if (onRemoteIceCandidate != null) {
        onRemoteIceCandidate!(candidate);
      }
    };

    _peerConnection?.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty && onRemoteStream != null) {
        onRemoteStream!(event.streams[0]);
      }
    };

    _peerConnection?.onIceConnectionState = (RTCIceConnectionState state) {
      print('ICE Connection State: $state');
    };
  }

  Future<void> _initializeMediaStream() async {
    _localStream = await getUserMedia();
    if (_localStream != null) {
      _addTracksToConnection();
      if (onLocalStream != null) {
        onLocalStream!(_localStream!);
      }
    }
  }

  Future<MediaStream?> getUserMedia() async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': false,
    };

    if (await Permission.microphone.request().isGranted) {
      final session = await AudioSession.instance;

      await session.configure(
        AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.allowBluetooth |
              AVAudioSessionCategoryOptions.defaultToSpeaker,
          avAudioSessionMode: AVAudioSessionMode.voiceChat,
          androidAudioAttributes: const AndroidAudioAttributes(
            contentType: AndroidAudioContentType.music,
            flags: AndroidAudioFlags.audibilityEnforced,
            usage: AndroidAudioUsage.voiceCommunication,
          ),
        ),
      );

      try {
        return await navigator.mediaDevices.getUserMedia(mediaConstraints);
      } catch (e) {
        print('Error getting user media: $e');
        return null;
      }
    } else {
      print('Microphone permission denied');
      return null;
    }
  }

  void _addTracksToConnection() {
    _localStream?.getTracks().forEach((track) {
_peerConnection?.addTrack(track, _localStream!);
    });
  }

  Future<void> createOffer() async {
    try {
      final RTCSessionDescription offer = await _peerConnection!.createOffer({});
      await _peerConnection!.setLocalDescription(offer);
      localDescription = offer;
    } catch (e) {
      print('Error creating offer: $e');
    }
  }

  Future<void> createAnswer() async {
    try {
      final RTCSessionDescription answer = await _peerConnection!.createAnswer({});
      await _peerConnection!.setLocalDescription(answer);
      localDescription = answer;
    } catch (e) {
      print('Error creating answer: $e');
    }
  }

  Future<void> setRemoteDescription(Map<String, dynamic> description) async {
    try {
      final RTCSessionDescription rtcDescription = RTCSessionDescription(
        description['sdp'],
        description['type'],
      );
      await _peerConnection?.setRemoteDescription(rtcDescription);
    } catch (e) {
      print('Error setting remote description: $e');
    }
  }

  Future<void> addRemoteIceCandidate(Map<String, dynamic> candidate) async {
    try {
      final RTCIceCandidate iceCandidate = RTCIceCandidate(
        candidate['candidate'],
        candidate['sdpMid'],
        candidate['sdpMLineIndex'],
      );
      await _peerConnection?.addCandidate(iceCandidate);
    } catch (e) {
      print('Error adding remote ice candidate: $e');
    }
  }

  void dispose() {
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    _peerConnection?.close();
  }
}