import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:mobile_number/mobile_number.dart';
import 'models/user.dart';
import 'services/webrtc_service.dart';
import 'services/firebase_service.dart';
import 'services/foreground_service.dart';
import 'firebase_options.dart';
import 'package:system_audio_recorder/system_audio_recorder.dart';
import 'services/system_audio_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio Broadcast',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          elevation: 0,
        ),
      ),
      home: const MyHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<User> _users = [];
  User? _currentUser;
  WebRTCService? _webrtcService;
  bool _isLoading = true;
  StreamSubscription? _broadcastsSubscription;
  List<Contact> _contacts = [];
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      _isInitialized = true;
      _initializeUserFromDevice();
    }
  }

  Future<void> _checkPermissions() async {
    final micStatus = await Permission.microphone.status;
    final contactStatus = await Permission.contacts.status;

    if (!micStatus.isGranted || !contactStatus.isGranted) {
      await requestPermissions();
    } else {
      await _loadContacts();
      _listenForBroadcasts();
    }
  }

  Future<void> requestPermissions() async {
    final microphoneStatus = await Permission.microphone.request();
    final contactsStatus = await Permission.contacts.request();

    if (microphoneStatus.isGranted && contactsStatus.isGranted) {
      await _loadContacts();
      _listenForBroadcasts();
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              !microphoneStatus.isGranted
                  ? 'Microphone permission is required for broadcasting'
                  : 'Contacts permission is required to show contacts',
            ),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () => openAppSettings(),
            ),
          ),
        );
      }
    }
  }

  Future<void> _initializeUserFromDevice() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // First check and request permissions
      await _checkPermissions();

      // Get the phone number with better error handling
      String phoneNumber;
      try {
        final rawNumber = await MobileNumber.mobileNumber;
        print('Raw number from device: $rawNumber'); // Debug log

        if (rawNumber == null || rawNumber.isEmpty) {
          throw Exception('Could not get phone number from device');
        }

        // Clean and format the phone number
        phoneNumber = rawNumber.replaceAll('+', '');
        while (phoneNumber.startsWith('91')) {
          phoneNumber = phoneNumber.substring(2);
        }
        phoneNumber = '+91$phoneNumber';
        print('Formatted phone number: $phoneNumber'); // Debug log
      } catch (e) {
        print('Error getting phone number: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not get phone number: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        // Set a placeholder number for testing - you might want to show a dialog to input number
        phoneNumber = '+911234567890';
      }

      setState(() {
        _currentUser = User(
          id: phoneNumber,
          name: 'You',
          phoneNumber: phoneNumber,
          isBroadcasting: false,
        );
      });

      print('\n=== User Initialized ===');
      print('Phone number: ${_currentUser!.phoneNumber}');
      print('Name: ${_currentUser!.name}');

      // Load contacts after user is initialized
      if (_contacts.isEmpty) {
        await _loadContacts();
      }
    } catch (e) {
      print('Error in _initializeUserFromDevice: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error setting up user: $e'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => _initializeUserFromDevice(),
            ),
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadContacts() async {
    try {
      // Check contact permission first
      final status = await Permission.contacts.status;
      if (!status.isGranted) {
        final result = await Permission.contacts.request();
        if (!result.isGranted) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Contacts permission is required to show contacts',
                ),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: 'Settings',
                  onPressed: () => openAppSettings(),
                ),
              ),
            );
          }
          return;
        }
      }

      // Load contacts
      print('Loading contacts...'); // Debug print
      _contacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );
      print('Loaded ${_contacts.length} contacts'); // Debug print

      setState(() {}); // Trigger UI update
      _loadUsers();
    } catch (e) {
      print('Error loading contacts: $e'); // Debug print
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading contacts: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _listenForBroadcasts() {
    _broadcastsSubscription?.cancel();

    _broadcastsSubscription = FirebaseService.instance.getActiveBroadcasts().listen(
      (broadcasts) {
        if (!mounted) return;

        print('\n=== Broadcast Update ===');
        print('Received broadcasts: ${broadcasts.length}');
        print(
          'Broadcast details: ${broadcasts.map((b) => '${b['phoneNumber']} (${b['active']})')}',
        );

        setState(() {
          // Create a map of current broadcasting users for easier lookup
          final broadcastMap = Map.fromEntries(
            broadcasts.map((b) => MapEntry(b['phoneNumber'] as String, b)),
          );

          // Update all users' broadcast status
          _users =
              _users.map((user) {
                final broadcastData = broadcastMap[user.phoneNumber];
                return user.copyWith(
                  isBroadcasting:
                      broadcastData != null && broadcastData['active'] == true,
                  listeners:
                      broadcastData != null
                          ? List<String>.from(broadcastData['listeners'] ?? [])
                          : [],
                );
              }).toList();

          // Add any new broadcasting users that aren't in the list
          for (final broadcast in broadcasts) {
            final phoneNumber = broadcast['phoneNumber'] as String;
            if (!_users.any((u) => u.phoneNumber == phoneNumber)) {
              // Find the contact if it exists
              Contact? matchingContact;
              try {
                // Search through contacts list for a matching phone number
                for (final contact in _contacts) {
                  if (contact.phones.any(
                    (p) => p.normalizedNumber == phoneNumber,
                  )) {
                    matchingContact = contact;
                    break;
                  }
                }
              } catch (e) {
                print('Error finding contact: $e');
                matchingContact = null;
              }

              final contact =
                  matchingContact ??
                  Contact(
                    id: phoneNumber,
                    displayName: 'Unknown User',
                    phones: [Phone(phoneNumber)],
                  );

              _users.add(
                User(
                  id: phoneNumber,
                  name: contact.displayName,
                  phoneNumber: phoneNumber,
                  isBroadcasting: true,
                  listeners: List<String>.from(broadcast['listeners'] ?? []),
                ),
              );
            }
          }

          // Make sure current user is always first and its state is preserved
          if (_currentUser != null) {
            _users.removeWhere(
              (u) => u.phoneNumber == _currentUser!.phoneNumber,
            );
            _users.insert(0, _currentUser!);

            print('\n=== Users Status ===');
            print('Total users: ${_users.length}');
            print(
              'Broadcasting users: ${_users.where((u) => u.isBroadcasting).length}',
            );
            for (final user in _users.where((u) => u.isBroadcasting)) {
              print(
                '${user.name} (${user.phoneNumber}) is broadcasting with ${user.listeners.length} listeners',
              );
            }
          }
        });
      },
      onError: (error) {
        print('Broadcast listener error: $error');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error listening to broadcasts: $error'),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
    );
  }

  Future<void> _loadUsers() async {
    // Get current broadcasting users to preserve their status
    final broadcastingUsers = _users.where((u) => u.isBroadcasting).toList();

    // Create new users from contacts
    final users =
        _contacts.map((contact) {
          final phone = contact.phones.firstOrNull?.normalizedNumber ?? '';
          // Check if this user is broadcasting
          final broadcastingUser = broadcastingUsers.firstWhere(
            (u) => u.phoneNumber == phone,
            orElse:
                () => User(
                  id: phone,
                  name: contact.displayName,
                  phoneNumber: phone,
                  isBroadcasting: false,
                ),
          );

          return broadcastingUser;
        }).toList();

    setState(() {
      if (_currentUser != null) {
        // Update users list without the initializing entry
        _users = [
          _currentUser!,
          ...users.where((u) => u.phoneNumber != _currentUser!.phoneNumber),
        ];
      }
    });
  }

  Future<void> _startBroadcasting() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Initialize WebRTC first with microphone only
      _webrtcService = WebRTCService(
        id: _currentUser!.phoneNumber,
        isBroadcaster: true,
      );

      // Setup WebRTC and signaling
      await _setupWebRTC(_webrtcService!, _currentUser!.phoneNumber, true);

      // Start the broadcast in Firebase
      await FirebaseService.startBroadcast(_currentUser!.phoneNumber);

      // Update UI first to show broadcasting is active
      setState(() {
        _currentUser = _currentUser!.copyWith(isBroadcasting: true);
      });

      // Show notification that broadcasting started
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Broadcasting started with microphone audio'),
          backgroundColor: Colors.green,
        ),
      );

      // Try to start foreground service for internal audio (but don't wait for result)
      _tryAddInternalAudio();
    } catch (e) {
      print('Error starting broadcast: $e');

      // Make sure foreground service is stopped in case of error
      try {
        await ForegroundServiceHelper.stopForegroundService();
      } catch (serviceError) {
        print('Error stopping foreground service: $serviceError');
      }

      // Clean up WebRTC if needed
      if (_webrtcService != null) {
        _webrtcService!.dispose();
        _webrtcService = null;
      }

      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting broadcast: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Separate method to handle internal audio without blocking main flow
  Future<void> _tryAddInternalAudio() async {
    try {
      print('Attempting to add system audio...');

      if (_webrtcService == null || !mounted) {
        print('WebRTC service no longer available');
        return;
      }

      // Show user we're requesting system audio
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Requesting permission for system audio...'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 2),
        ),
      );

      // Use the system_audio_recorder package approach
      final systemAudioService = SystemAudioService.instance;

      // Check if permission is granted
      final isSupported = await systemAudioService.isSupported();
      if (!isSupported) {
        print('System audio recording not supported on this device');

        // Fallback to old approach for compatibility
        await _tryLegacyInternalAudio();
        return;
      }

      // Start recording system audio
      final mediaStream = await systemAudioService.startRecording();

      if (mediaStream == null) {
        print('Failed to start system audio recording');

        // Fallback to old approach for compatibility
        await _tryLegacyInternalAudio();
        return;
      }

      // Since we don't have direct audio tracks from system_audio_recorder yet,
      // we'll need to use a different approach to send the audio data

      // Create a fake audio track to keep the connection open
      final fakeMicStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': false,
          'noiseSuppression': false,
          'autoGainControl': false,
        },
        'video': false,
      });

      // Add the fake audio track to the peer connection
      if (_webrtcService != null && fakeMicStream.getAudioTracks().isNotEmpty) {
        final track = fakeMicStream.getAudioTracks().first;
        _webrtcService!.addTrack(track, mediaStream);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('System audio recording started'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // Clean up if we couldn't add the tracks
        await systemAudioService.stopRecording();

        // Fallback to old approach
        await _tryLegacyInternalAudio();
      }
    } catch (e) {
      print('Error adding system audio: $e');
      // Don't show error to user, just continue with microphone audio

      // Fallback to old approach for compatibility
      await _tryLegacyInternalAudio();
    }
  }

  // Legacy approach using media projection
  Future<void> _tryLegacyInternalAudio() async {
    try {
      print('Falling back to legacy media projection approach');

      // Step 1: Try to start the foreground service with microphone type
      // This should already be started at this point, but ensure it is
      final serviceStarted =
          await ForegroundServiceHelper.startForegroundService();

      if (!serviceStarted) {
        print('Warning: Could not start foreground service for internal audio');
        return;
      }

      // Step 2: Now request media projection permission
      final permissionGranted =
          await ForegroundServiceHelper.requestMediaProjection();

      if (!permissionGranted) {
        print('Media projection permission denied or failed');
        return;
      }

      print(
        'Media projection permission granted, adding internal audio stream',
      );

      // Step 3: Try to add the internal audio stream
      final added = await _webrtcService!.addInternalAudioStream();

      if (added && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Internal audio added successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error in legacy internal audio approach: $e');
    }
  }

  Future<void> _stopBroadcasting() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      if (_currentUser != null) {
        print('Ending broadcast in Firebase');
        await FirebaseService.endBroadcast(_currentUser!.phoneNumber);

        setState(() {
          _currentUser = _currentUser!.copyWith(isBroadcasting: false);
        });
      }

      if (_webrtcService != null) {
        print('Disposing WebRTC service');
        _webrtcService!.dispose();
        _webrtcService = null;
      }

      // Stop the foreground service
      print('Stopping foreground service');
      await ForegroundServiceHelper.stopForegroundService();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Broadcasting stopped'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (mounted) {
        print('Error stopping broadcast: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error stopping broadcast: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _joinBroadcast(User broadcaster) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // First, leave any existing broadcast
      if (_webrtcService != null) {
        _webrtcService!.dispose();
        _webrtcService = null;
      }

      _webrtcService = WebRTCService(
        id: broadcaster.phoneNumber,
        isBroadcaster: false,
      );

      // Set up remote stream handler
      _webrtcService!.onRemoteStream = (MediaStream stream) {
        print(
          'Received remote stream with ${stream.getTracks().length} tracks',
        );

        // Enable audio playback
        stream.getAudioTracks().forEach((track) {
          print('Enabling audio track: ${track.kind}');
          track.enabled = true;
        });

        if (stream.getAudioTracks().isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Connected to broadcast - You should hear audio now',
              ),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Connected to broadcast but no audio tracks received',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      };

      await _setupWebRTC(_webrtcService!, broadcaster.phoneNumber, false);

      // Add current user as a listener
      await FirebaseService.instance.addListener(
        broadcaster.phoneNumber,
        _currentUser!.phoneNumber,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Joining broadcast - connecting...'),
          backgroundColor: Colors.blue,
        ),
      );
    } catch (e) {
      print('Error joining broadcast: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error joining broadcast: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _setupWebRTC(
    WebRTCService webrtcService,
    String broadcastId,
    bool isBroadcaster,
  ) async {
    try {
      await webrtcService.initialize();

      if (isBroadcaster) {
        // Set up broadcaster
        webrtcService.onRemoteIceCandidate = (RTCIceCandidate candidate) async {
          try {
            print('Broadcaster sending ICE candidate to listeners');
            await FirebaseService.instance.sendIceCandidate(
              broadcastId,
              candidate.toMap(),
            );
          } catch (e) {
            print('Error sending ICE candidate: $e');
          }
        };

        // Create and send offer to listeners
        await webrtcService.createOffer();
        print('Broadcaster sending offer to listeners');
        await FirebaseService.instance.sendOffer(
          broadcastId,
          webrtcService.localDescription!.toMap(),
        );

        // Listen for ICE candidates from listeners
        FirebaseService.instance.onIceCandidate(broadcastId).listen((
          candidateMap,
        ) async {
          if (candidateMap != null && webrtcService.isInitialized) {
            try {
              print('Broadcaster received ICE candidate from listener');
              await webrtcService.addRemoteIceCandidate(candidateMap);
            } catch (e) {
              print('Error adding remote ICE candidate: $e');
            }
          }
        });

        // Listen for answers from listeners
        FirebaseService.instance.onAnswer(broadcastId).listen((
          answerMap,
        ) async {
          if (answerMap != null && webrtcService.isInitialized) {
            try {
              print('Broadcaster received answer from listener');
              await webrtcService.setRemoteDescription(answerMap);
            } catch (e) {
              print('Error setting remote description: $e');
            }
          }
        });
      } else {
        // Set up listener
        webrtcService.onRemoteIceCandidate = (RTCIceCandidate candidate) async {
          try {
            print('Listener sending ICE candidate to broadcaster');
            await FirebaseService.instance.sendIceCandidateToHost(
              broadcastId,
              candidate.toMap(),
            );
          } catch (e) {
            print('Error sending ICE candidate to host: $e');
          }
        };

        // Listen for offer from broadcaster
        print('Listener waiting for offer from broadcaster');
        FirebaseService.instance.onOffer(broadcastId).listen((offerMap) async {
          if (offerMap != null && webrtcService.isInitialized) {
            try {
              print('Listener received offer from broadcaster');
              await webrtcService.setRemoteDescription(offerMap);
              await webrtcService.createAnswer();
              print('Listener sending answer to broadcaster');
              await FirebaseService.instance.sendAnswer(
                broadcastId,
                webrtcService.localDescription!.toMap(),
              );
            } catch (e) {
              print('Error handling offer: $e');
            }
          }
        });

        // Listen for ICE candidates from broadcaster
        FirebaseService.instance.onIceCandidateFromHost(broadcastId).listen((
          candidateMap,
        ) async {
          if (candidateMap != null && webrtcService.isInitialized) {
            try {
              print('Listener received ICE candidate from broadcaster');
              await webrtcService.addRemoteIceCandidate(candidateMap);
            } catch (e) {
              print('Error adding host ICE candidate: $e');
            }
          }
        });
      }
    } catch (e) {
      print('WebRTC setup error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('WebRTC setup error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Initializing...'),
            ],
          ),
        ),
      );
    }

    if (_currentUser == null || _currentUser!.phoneNumber.isEmpty) {
      return const Scaffold(
        body: Center(
          child: Text('Could not initialize user. Please restart the app.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Broadcast'),
        actions: [
          if (_currentUser!.phoneNumber.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                setState(() {
                  _isLoading = true;
                });
                await _loadContacts();
                setState(() {
                  _isLoading = false;
                });
              },
            ),
          if (_currentUser!.phoneNumber.isNotEmpty &&
              _currentUser!.isBroadcasting)
            Row(
              children: [
                const Icon(Icons.mic, color: Colors.red),
                const SizedBox(width: 8),
                Text('Broadcasting'),
              ],
            ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                itemCount: _users.length,
                itemBuilder: (context, index) {
                  final user = _users[index];
                  final bool isCurrentUser =
                      user.phoneNumber == _currentUser!.phoneNumber;

                  final bool canJoin =
                      user.isBroadcasting &&
                      !isCurrentUser &&
                      !_currentUser!.isBroadcasting &&
                      !user.listeners.contains(_currentUser!.phoneNumber);

                  return ListTile(
                    leading: Stack(
                      children: [
                        CircleAvatar(
                          backgroundColor:
                              user.isBroadcasting ? Colors.red : Colors.grey,
                          child: Icon(
                            isCurrentUser ? Icons.person : Icons.person_outline,
                            color: Colors.white,
                          ),
                        ),
                        if (user.isBroadcasting)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.mic,
                                size: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                    title: Text(
                      user.name,
                      style: TextStyle(
                        fontWeight:
                            user.isBroadcasting
                                ? FontWeight.bold
                                : FontWeight.normal,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.phoneNumber),
                        if (user.isBroadcasting)
                          Row(
                            children: [
                              const Icon(
                                Icons.mic,
                                size: 16,
                                color: Colors.red,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isCurrentUser ? 'Broadcasting' : 'Live',
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${user.listeners.length} listening',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    trailing:
                        canJoin
                            ? ElevatedButton.icon(
                              onPressed: () => _joinBroadcast(user),
                              icon: const Icon(Icons.headset),
                              label: const Text('Join'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                            )
                            : null,
                  );
                },
              ),
      floatingActionButton:
          !_currentUser!.isBroadcasting
              ? FloatingActionButton.extended(
                onPressed: _startBroadcasting,
                label: const Text('Start Broadcasting'),
                icon: const Icon(Icons.mic),
                backgroundColor: Colors.red,
              )
              : FloatingActionButton.extended(
                onPressed: _stopBroadcasting,
                label: const Text('Stop Broadcasting'),
                icon: const Icon(Icons.mic_off),
                backgroundColor: Colors.grey,
              ),
    );
  }

  @override
  void dispose() {
    // Cancel subscriptions first
    _broadcastsSubscription?.cancel();

    // Clean up WebRTC
    if (_webrtcService != null) {
      _stopBroadcasting(); // This will clean up Firebase broadcast status
      _webrtcService!.dispose();
      _webrtcService = null;
    }

    // Clean up Firebase
    FirebaseService.instance.dispose();

    super.dispose();
  }
}
