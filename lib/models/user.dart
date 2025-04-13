class User {
  final String id;
  final String name;
  final String phoneNumber;
  final bool isBroadcasting;
  final List<String> listeners;

  User({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.isBroadcasting,
    List<String>? listeners,
  }) : listeners = listeners ?? [];

  User copyWith({
    String? id,
    String? name,
    String? phoneNumber,
    bool? isBroadcasting,
    List<String>? listeners,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      isBroadcasting: isBroadcasting ?? this.isBroadcasting,
      listeners: listeners ?? this.listeners,
    );
  }

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      phoneNumber: map['phoneNumber'] ?? '',
      isBroadcasting: map['isBroadcasting'] ?? false,
      listeners: List<String>.from(map['listeners'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phoneNumber': phoneNumber,
      'isBroadcasting': isBroadcasting,
      'listeners': listeners,
    };
  }

  @override
  String toString() {
    return 'User(id: $id, name: $name, phoneNumber: $phoneNumber, isBroadcasting: $isBroadcasting, listeners: $listeners)';
  }
}
