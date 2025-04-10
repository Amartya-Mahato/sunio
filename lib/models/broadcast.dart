class Broadcast {
  final String id;
  final String broadcasterId;
  final List<String> listeners;
  final bool isActive;

  Broadcast({
    required this.id,
    required this.broadcasterId,
    required this.listeners,
    required this.isActive,
  });
}