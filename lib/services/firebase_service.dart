import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

class FirebaseService {
  static final FirebaseService instance = FirebaseService._internal();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  FirebaseService._internal();

  // Start a broadcast session
  static Future<void> startBroadcast(String userId) async {
    await FirebaseFirestore.instance.collection('broadcasts').doc(userId).set({
      'userId': userId,
      'active': true,
      'startedAt': FieldValue.serverTimestamp(),
    });
  }

  // End a broadcast session
  static Future<void> endBroadcast(String userId) async {
    await FirebaseFirestore.instance
        .collection('broadcasts')
        .doc(userId)
        .update({'active': false, 'endedAt': FieldValue.serverTimestamp()});
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

  // Send an ICE candidate to the host
  Future<void> sendIceCandidateToHost(
    String broadcastId,
    Map<String, dynamic> candidate,
  ) async {
    await _firestore
        .collection('broadcasts')
        .doc(broadcastId)
        .collection('signaling')
        .doc('hostCandidates')
        .collection('candidates')
        .add({...candidate, 'timestamp': FieldValue.serverTimestamp()});
  }

  // Send an ICE candidate to viewers
  Future<void> sendIceCandidate(
    String broadcastId,
    Map<String, dynamic> candidate,
  ) async {
    await _firestore
        .collection('broadcasts')
        .doc(broadcastId)
        .collection('signaling')
        .doc('viewerCandidates')
        .collection('candidates')
        .add({...candidate, 'timestamp': FieldValue.serverTimestamp()});
  }

  // Listen for offers
  Stream<Map<String, dynamic>?> onOffer(String broadcastId) {
    return _firestore
        .collection('broadcasts')
        .doc(broadcastId)
        .collection('signaling')
        .doc('offer')
        .snapshots()
        .map((snapshot) {
          if (!snapshot.exists) return null;
          final data = snapshot.data() as Map<String, dynamic>;
          return {'sdp': data['sdp'], 'type': data['type']};
        });
  }

  // Listen for answers
  Stream<Map<String, dynamic>?> onAnswer(String broadcastId) {
    return _firestore
        .collection('broadcasts')
        .doc(broadcastId)
        .collection('signaling')
        .doc('answer')
        .snapshots()
        .map((snapshot) {
          if (!snapshot.exists) return null;
          final data = snapshot.data() as Map<String, dynamic>;
          return {'sdp': data['sdp'], 'type': data['type']};
        });
  }

  // Listen for ICE candidates from viewers
  Stream<Map<String, dynamic>?> onIceCandidate(String broadcastId) {
    return _firestore
        .collection('broadcasts')
        .doc(broadcastId)
        .collection('signaling')
        .doc('viewerCandidates')
        .collection('candidates')
        .orderBy('timestamp')
        .limitToLast(1)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) return null;
          final doc = snapshot.docs.first;
          return doc.data();
        });
  }

  // Listen for ICE candidates from host
  Stream<Map<String, dynamic>?> onIceCandidateFromHost(String broadcastId) {
    return _firestore
        .collection('broadcasts')
        .doc(broadcastId)
        .collection('signaling')
        .doc('hostCandidates')
        .collection('candidates')
        .orderBy('timestamp')
        .limitToLast(1)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) return null;
          final doc = snapshot.docs.first;
          return doc.data();
        });
  }

  // Get active broadcasts
  Stream<List<Map<String, dynamic>>> getActiveBroadcasts() {
    return _firestore
        .collection('broadcasts')
        .where('active', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) => doc.data()).toList();
        });
  }
}
