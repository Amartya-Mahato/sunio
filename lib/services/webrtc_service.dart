import 'dart:math';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:audio_session/audio_session.dart';
import 'package:permission_handler/permission_handler.dart';

class WebRTCService {
  final String id;
  final bool isBroadcaster;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  RTCPeerConnection? _peerConnection;
  RTCSessionDescription? localDescription;
  List<RTCIceCandidate> _pendingCandidates = [];
  bool _isInitialized = false;

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

  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    try {
      final configuration = <String, dynamic>{
        'iceServers': [
          {
            'urls': [
              'stun:stun1.l.google.com:19302',
              'stun:stun2.l.google.com:19302',
            ],
          },
          {
            'urls': 'turn:numb.viagenie.ca',
            'credential': 'muazkh',
            'username': 'webrtc@live.com',
          },
        ],
        'sdpSemantics': 'unified-plan',
        'iceCandidatePoolSize': 10,
      };

      _peerConnection = await createPeerConnection(configuration);

      _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
        print('Generated ICE candidate: ${candidate.candidate}');
        if (onRemoteIceCandidate != null) {
          onRemoteIceCandidate!(candidate);
        }
      };

      _peerConnection?.onIceConnectionState = (RTCIceConnectionState state) {
        print('ICE Connection State: $state');
      };

      _peerConnection?.onConnectionState = (RTCPeerConnectionState state) {
        print('Peer Connection State: $state');
      };

      _peerConnection?.onSignalingState = (RTCSignalingState state) {
        print('Signaling State: $state');
      };

      await _initializeMediaStream();
      _isInitialized = true;

      // Add any pending candidates that were received before initialization
      for (final candidate in _pendingCandidates) {
        await _peerConnection?.addCandidate(candidate);
        print('Added pending ICE candidate');
      }
      _pendingCandidates.clear();
    } catch (e) {
      print('Error initializing WebRTC: $e');
      rethrow;
    }
  }

  Future<void> _initializeMediaStream() async {
    try {
      await Permission.microphone.request();

      // Configure audio session for voice communication
      final session = await AudioSession.instance;
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.allowBluetooth,
          avAudioSessionMode: AVAudioSessionMode.voiceChat,
          avAudioSessionRouteSharingPolicy:
              AVAudioSessionRouteSharingPolicy.defaultPolicy,
        ),
      );

      // Setup for both broadcaster and listener
      if (isBroadcaster) {
        print('Initializing broadcaster streams');

        // Get microphone stream only - we'll handle system audio separately
        try {
          final micStream = await navigator.mediaDevices.getUserMedia({
            'audio': {
              'echoCancellation': true,
              'noiseSuppression': true,
              'autoGainControl': true,
            },
            'video': false,
          });

          print('Got mic stream with ${micStream.getTracks().length} tracks');
          _localStream = micStream;

          // Add microphone tracks to peer connection
          micStream.getTracks().forEach((track) {
            print('Adding mic track: ${track.kind} to peer connection');
            _peerConnection?.addTrack(track, _localStream!);
          });

          if (onLocalStream != null) {
            onLocalStream!(_localStream!);
          }
        } catch (e) {
          print('Error getting microphone stream: $e');
          // Create an empty stream if we can't get the microphone
          _localStream = await navigator.mediaDevices.getUserMedia({
            'audio': false,
            'video': false,
          });
        }
      } else {
        // For listeners, create an empty audio stream
        print('Initializing listener with empty audio stream');
        _localStream = await navigator.mediaDevices.getUserMedia({
          'audio': false,
          'video': false,
        });
      }

      // Set up audio elements for remote stream for both broadcaster and listener
      _peerConnection?.onTrack = (RTCTrackEvent event) {
        print('Received track event: ${event.track.kind}');
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
          print(
            'Got remote stream with ${_remoteStream!.getTracks().length} tracks',
          );

          // Enable audio playback for all tracks
          _remoteStream!.getTracks().forEach((track) {
            print('Enabling track: ${track.kind}');
            track.enabled = true;
          });

          if (onRemoteStream != null) {
            onRemoteStream!(_remoteStream!);
          }
        }
      };
    } catch (e) {
      print('Critical error initializing media stream: $e');
      // Make sure we have at least an empty stream
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': false,
      });
    }
  }

  Future<bool> addInternalAudioStream() async {
    if (!isBroadcaster || _peerConnection == null) {
      print(
        'Cannot add internal audio: Not a broadcaster or peer connection not initialized',
      );
      return false;
    }

    try {
      print('Attempting to get system audio...');

      // Use a safer approach with error handling
      try {
        // This will use the media projection service initialized by the native side
        final Map<String, dynamic> mediaConstraints = {
          'audio': true,
          'video': false,
          'audioSource': 'audiooutput', // Specify we want internal audio
        };

        final systemAudioStream = await navigator.mediaDevices.getDisplayMedia(
          mediaConstraints,
        );

        final audioTracks = systemAudioStream.getAudioTracks();
        print(
          'Got system audio stream with ${audioTracks.length} audio tracks',
        );

        if (audioTracks.isEmpty) {
          print('No audio tracks found in system audio stream');
          systemAudioStream.dispose();
          return false;
        }

        // Add system audio tracks to peer connection
        audioTracks.forEach((track) {
          print('Adding system audio track: ${track.kind} to peer connection');
          _peerConnection?.addTrack(track, systemAudioStream);
        });

        print('Successfully added internal audio stream');
        return true;
      } catch (e) {
        print('Error getting display media: $e');
        // Silently continue with just microphone audio
        return false;
      }
    } catch (e) {
      print('Error adding internal audio stream: $e');
      return false;
    }
  }

  /// Add an audio track from the internal_audio_recorder to the peer connection
  Future<bool> addTrack(MediaStreamTrack track, MediaStream stream) async {
    if (!isBroadcaster || _peerConnection == null) {
      print(
        'Cannot add track: Not a broadcaster or peer connection not initialized',
      );
      return false;
    }

    try {
      print('Adding internal audio track: ${track.kind} to peer connection');
      _peerConnection?.addTrack(track, stream);
      return true;
    } catch (e) {
      print('Error adding track to peer connection: $e');
      return false;
    }
  }

  Future<void> addRemoteIceCandidate(Map<String, dynamic> candidate) async {
    try {
      print('Adding remote ICE candidate: ${candidate['candidate']}');
      final RTCIceCandidate rtcCandidate = RTCIceCandidate(
        candidate['candidate'],
        candidate['sdpMid'],
        candidate['sdpMLineIndex'],
      );

      if (_peerConnection != null) {
        await _peerConnection!.addCandidate(rtcCandidate);
        print('ICE candidate added successfully');
      } else {
        print('Storing ICE candidate for later');
        _pendingCandidates.add(rtcCandidate);
      }
    } catch (e) {
      print('Error adding ICE candidate: $e');
      rethrow;
    }
  }

  Future<void> setRemoteDescription(Map<String, dynamic> description) async {
    try {
      print('Setting remote description type: ${description['type']}');
      final RTCSessionDescription rtcDescription = RTCSessionDescription(
        description['sdp'],
        description['type'],
      );
      await _peerConnection?.setRemoteDescription(rtcDescription);
      print('Remote description set successfully');

      if (!isBroadcaster) {
        print('Creating answer as listener');
        await createAnswer();
      }
    } catch (e) {
      print('Error setting remote description: $e');
      rethrow;
    }
  }

  Future<void> createOffer() async {
    try {
      final RTCSessionDescription offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });

      print('Created offer: ${offer.type}');
      await _peerConnection!.setLocalDescription(offer);
      localDescription = offer;
    } catch (e) {
      print('Error creating offer: $e');
      rethrow;
    }
  }

  Future<void> createAnswer() async {
    try {
      // For listeners, we set sendAudio to false to prevent sending audio back to the broadcaster
      final RTCSessionDescription answer = await _peerConnection!.createAnswer({
        'offerToReceiveAudio': true, // We want to receive audio
        'offerToReceiveVideo': false,
        'sendAudio': false, // Don't send audio to broadcaster
      });

      print('Created answer: ${answer.type}');

      // Modify SDP to ensure we don't send audio back
      String modifiedSdp = answer.sdp.toString();

      // Ensure audio is receive-only for listeners
      if (!isBroadcaster) {
        // Find all audio m-lines and set direction to recvonly
        final List<String> lines = modifiedSdp.split('\r\n');
        bool inAudioMedia = false;

        for (int i = 0; i < lines.length; i++) {
          if (lines[i].startsWith('m=audio')) {
            inAudioMedia = true;
          } else if (inAudioMedia && lines[i].startsWith('a=sendrecv')) {
            // Replace sendrecv with recvonly
            lines[i] = 'a=recvonly';
            inAudioMedia = false;
          } else if (lines[i].startsWith('m=')) {
            inAudioMedia = false;
          }
        }

        modifiedSdp = lines.join('\r\n');
      }

      // Create a new answer with the modified SDP
      final RTCSessionDescription modifiedAnswer = RTCSessionDescription(
        modifiedSdp,
        answer.type,
      );

      await _peerConnection!.setLocalDescription(modifiedAnswer);
      localDescription = modifiedAnswer;
    } catch (e) {
      print('Error creating answer: $e');
      rethrow;
    }
  }

  void dispose() {
    print('Disposing WebRTC service');
    _localStream?.getTracks().forEach((track) {
      print('Stopping track: ${track.kind}');
      track.stop();
    });
    _localStream?.dispose();
    _remoteStream?.dispose();
    _peerConnection?.close();
  }
}
