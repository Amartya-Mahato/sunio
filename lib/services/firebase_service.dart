import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

class FirebaseService {
  static final FirebaseService instance = FirebaseService._();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, StreamSubscription> _subscriptions = {};

  FirebaseService._();

  void dispose() {
    // Cancel all active subscriptions
    for (var subscription in _subscriptions.values) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }

  // Start a broadcast session
  static Future<void> startBroadcast(String phoneNumber) async {
    await FirebaseFirestore.instance.collection('broadcasts').doc(phoneNumber).set({
      'phoneNumber': phoneNumber,
      'active': true,
      'startedAt': FieldValue.serverTimestamp(),
      'listeners': [],
    });
  }

  // End a broadcast session
  static Future<void> endBroadcast(String phoneNumber) async {
    await FirebaseFirestore.instance
        .collection('broadcasts')
        .doc(phoneNumber)
        .update({
          'active': false,
          'endedAt': FieldValue.serverTimestamp(),
          'listeners': [],
        });
  }

  // Get active broadcasts
  Stream<List<Map<String, dynamic>>> getActiveBroadcasts() {
    return _firestore
        .collection('broadcasts')
        .where('active', isEqualTo: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => {
                  'phoneNumber': doc.id,
                  'active': doc.data()['active'],
                  'listeners': doc.data()['listeners'] ?? [],
                })
            .toList());
  }

  // Add a listener to a broadcast
  Future<void> addListener(String broadcastPhoneNumber, String listenerPhoneNumber) async {
    await _firestore.collection('broadcasts').doc(broadcastPhoneNumber).update({
      'listeners': FieldValue.arrayUnion([listenerPhoneNumber]),
    });
  }

  // Remove a listener from a broadcast
  Future<void> removeListener(String broadcastPhoneNumber, String listenerPhoneNumber) async {
    await _firestore.collection('broadcasts').doc(broadcastPhoneNumber).update({
      'listeners': FieldValue.arrayRemove([listenerPhoneNumber]),
    });
  }

  // Send an offer to the broadcasting user
  Future<void> sendOffer(String broadcastId, Map<String, dynamic> offer) async {
    await _firestore
        .collection('broadcasts')
        .doc(broadcastId)
        .collection('signaling')
        .doc('offer')
        .set({
          'sdp': offer['sdp'],
          'type': offer['type'],
          'timestamp': FieldValue.serverTimestamp(),
        });
  }

  // Send an answer to the broadcasting user
  Future<void> sendAnswer(
    String broadcastId,
    Map<String, dynamic> answer,
  ) async {
    await _firestore
        .collection('broadcasts')
        .doc(broadcastId)
        .collection('signaling')
        .doc('answer')
        .set({
          'sdp': answer['sdp'],
          'type': answer['type'],
          'timestamp': FieldValue.serverTimestamp(),
        });
  }

  // Send ICE candidate to the broadcasting user
  Future<void> sendIceCandidate(
    String broadcastId,
    Map<String, dynamic> candidate,
  ) async {
    await _firestore
        .collection('broadcasts')
        .doc(broadcastId)
        .collection('signaling')
        .doc('ice_candidate')
        .set({
          'candidate': candidate['candidate'],
          'sdpMid': candidate['sdpMid'],
          'sdpMLineIndex': candidate['sdpMLineIndex'],
          'timestamp': FieldValue.serverTimestamp(),
        });
  }

  // Send ICE candidate to the host from a listener
  Future<void> sendIceCandidateToHost(
    String broadcastId,
    Map<String, dynamic> candidate,
  ) async {
    await _firestore
        .collection('broadcasts')
        .doc(broadcastId)
        .collection('signaling')
        .doc('ice_candidate_from_listener')
        .set({
          'candidate': candidate['candidate'],
          'sdpMid': candidate['sdpMid'],
          'sdpMLineIndex': candidate['sdpMLineIndex'],
          'timestamp': FieldValue.serverTimestamp(),
        });
  }

  // Listen for offer
  Stream<Map<String, dynamic>?> onOffer(String broadcastId) {
    return _firestore
        .collection('broadcasts')
        .doc(broadcastId)
        .collection('signaling')
        .doc('offer')
        .snapshots()
        .map((snapshot) => snapshot.data());
  }

  // Listen for answer
  Stream<Map<String, dynamic>?> onAnswer(String broadcastId) {
    return _firestore
        .collection('broadcasts')
        .doc(broadcastId)
        .collection('signaling')
        .doc('answer')
        .snapshots()
        .map((snapshot) => snapshot.data());
  }

  // Listen for ICE candidate
  Stream<Map<String, dynamic>?> onIceCandidate(String broadcastId) {
    return _firestore
        .collection('broadcasts')
        .doc(broadcastId)
        .collection('signaling')
        .doc('ice_candidate')
        .snapshots()
        .map((snapshot) => snapshot.data());
  }

  // Listen for ICE candidate from host
  Stream<Map<String, dynamic>?> onIceCandidateFromHost(String broadcastId) {
    return _firestore
        .collection('broadcasts')
        .doc(broadcastId)
        .collection('signaling')
        .doc('ice_candidate_from_listener')
        .snapshots()
        .map((snapshot) => snapshot.data());
  }
}
