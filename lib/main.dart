import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:firebase_core/firebase_core.dart';
import 'models/user.dart';
import 'services/webrtc_service.dart';
import 'services/firebase_service.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
await Firebase.initializeApp(
options: DefaultFirebaseOptions.currentPlatform,
);
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WebRTC Broadcasting App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
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
  late User _currentUser;
  WebRTCService? _webrtcService;
  bool _isLoading = false;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  StreamSubscription? _broadcastsSubscription;

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _setupCurrentUser();
    requestPermissions();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  void _setupCurrentUser() {
    _currentUser = User(
      id: 'user-${DateTime.now().millisecondsSinceEpoch}',
      name: 'Me',
      isBroadcasting: false,
    );
  }

  Future<void> requestPermissions() async {
    final microphoneStatus = await Permission.microphone.request();
    if (microphoneStatus.isGranted) {
      _loadUsers();
      _listenForBroadcasts();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Microphone permission is required'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _listenForBroadcasts() {
    _broadcastsSubscription = FirebaseService.instance
        .getActiveBroadcasts()
        .listen((broadcasts) {
          final broadcastUsers =
              broadcasts
                  .map(
                    (broadcast) => User(
                      id: broadcast['userId'],
                      name:
                          'Broadcaster ${broadcast['userId'].toString().substring(0, 5)}',
                      isBroadcasting: true,
                    ),
                  )
                  .toList();

          setState(() {
            // Add broadcast users that aren't current user
            final List<User> allUsers = [_currentUser];
            for (final user in broadcastUsers) {
              if (user.id != _currentUser.id) {
                allUsers.add(user);
              }
            }
            _users = allUsers;
          });
        });
  }

  Future<void> _loadUsers() async {
    setState(() {
      _users = [_currentUser];
    });
  }

  Future<void> _startBroadcasting() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await FirebaseService.startBroadcast(_currentUser.id);

      setState(() {
        _currentUser = _currentUser.copyWith(isBroadcasting: true);
      });

      _webrtcService = WebRTCService(id: _currentUser.id, isBroadcaster: true);

      _webrtcService!.onLocalStream = (MediaStream stream) {
        setState(() {
          _localRenderer.srcObject = stream;
        });
      };

      _webrtcService!.onRemoteStream = (MediaStream stream) {
        setState(() {
          _remoteRenderer.srcObject = stream;
        });
      };

      await _setupWebRTC(_webrtcService!, _currentUser.id, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error starting broadcast: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _stopBroadcasting() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await FirebaseService.endBroadcast(_currentUser.id);

      setState(() {
        _currentUser = _currentUser.copyWith(isBroadcasting: false);
      });

      _webrtcService?.dispose();
      _webrtcService = null;

      setState(() {
        _localRenderer.srcObject = null;
        _remoteRenderer.srcObject = null;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error stopping broadcast: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _joinBroadcast(User broadcaster) async {
    setState(() {
      _isLoading = true;
    });

    try {
      _webrtcService = WebRTCService(id: broadcaster.id, isBroadcaster: false);

      _webrtcService!.onLocalStream = (MediaStream stream) {
        setState(() {
          _localRenderer.srcObject = stream;
        });
      };

      _webrtcService!.onRemoteStream = (MediaStream stream) {
        setState(() {
          _remoteRenderer.srcObject = stream;
        });
      };

      await _setupWebRTC(_webrtcService!, broadcaster.id, false);
    } catch (e) {
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
        webrtcService.onRemoteIceCandidate = (RTCIceCandidate candidate) async {
          await FirebaseService.instance.sendIceCandidate(
            broadcastId,
            candidate.toMap(),
          );
        };

        await webrtcService.createOffer();
        await FirebaseService.instance.sendOffer(
          broadcastId,
          webrtcService.localDescription!.toMap(),
        );

        FirebaseService.instance.onIceCandidate(broadcastId).listen((
          candidateMap,
        ) async {
          if (candidateMap != null) {
            await webrtcService.addRemoteIceCandidate(candidateMap);
          }
        });

        FirebaseService.instance.onAnswer(broadcastId).listen((
          answerMap,
        ) async {
          if (answerMap != null) {
            await webrtcService.setRemoteDescription(answerMap);
          }
        });
      } else {
        webrtcService.onRemoteIceCandidate = (RTCIceCandidate candidate) async {
          await FirebaseService.instance.sendIceCandidateToHost(
            broadcastId,
            candidate.toMap(),
          );
        };

        FirebaseService.instance.onOffer(broadcastId).listen((offerMap) async {
          if (offerMap != null) {
            await webrtcService.setRemoteDescription(offerMap);
            await webrtcService.createAnswer();
            await FirebaseService.instance.sendAnswer(
              broadcastId,
              webrtcService.localDescription!.toMap(),
            );
          }
        });

        FirebaseService.instance.onIceCandidateFromHost(broadcastId).listen((
          candidateMap,
        ) async {
          if (candidateMap != null) {
            await webrtcService.addRemoteIceCandidate(candidateMap);
          }
        });
      }
    } catch (e) {
      print('WebRTC setup error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('WebRTC setup error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("WebRTC Broadcasting App")),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                children: [
                  // Video renderers
                  if (_localRenderer.srcObject != null ||
                      _remoteRenderer.srcObject != null)
                    Expanded(
                      flex: 2,
                      child: Container(
                        color: Colors.black,
                        child: Stack(
                          children: [
                            if (_remoteRenderer.srcObject != null)
                              Positioned.fill(
                                child: RTCVideoView(
                                  _remoteRenderer,
                                  objectFit:
                                      RTCVideoViewObjectFit
                                          .RTCVideoViewObjectFitCover,
                                ),
                              ),
                            if (_localRenderer.srcObject != null)
                              Positioned(
                                right: 16,
                                bottom: 16,
                                width: 120,
                                height: 160,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black,
                                    border: Border.all(color: Colors.white),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: RTCVideoView(
                                      _localRenderer,
                                      objectFit:
                                          RTCVideoViewObjectFit
                                              .RTCVideoViewObjectFitCover,
                                      mirror: true,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                  // User list
                  Expanded(
                    flex: 1,
                    child: ListView.builder(
                      itemCount: _users.length,
                      itemBuilder: (context, index) {
                        final user = _users[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: ListTile(
                            title: Text(user.name),
                            subtitle: Text(
                              user.isBroadcasting
                                  ? 'Broadcasting now'
                                  : 'Not broadcasting',
                            ),
                            trailing:
                                user.id == _currentUser.id
                                    ? ElevatedButton(
                                      onPressed:
                                          _isLoading
                                              ? null
                                              : _currentUser.isBroadcasting
                                              ? _stopBroadcasting
                                              : _startBroadcasting,
                                      child: Text(
                                        _currentUser.isBroadcasting
                                            ? "Stop Broadcasting"
                                            : "Start Broadcasting",
                                      ),
                                    )
                                    : user.isBroadcasting
                                    ? ElevatedButton(
                                      onPressed:
                                          _isLoading
                                              ? null
                                              : () => _joinBroadcast(user),
                                      child: const Text("Join"),
                                    )
                                    : null,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
    );
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _webrtcService?.dispose();
    _broadcastsSubscription?.cancel();
    super.dispose();
  }
}
