class User {
  final String id;
  final String name;
  final bool isBroadcasting;

  User({required this.id, required this.name, required this.isBroadcasting});

  User copyWith({String? id, String? name, bool? isBroadcasting}) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      isBroadcasting: isBroadcasting ?? this.isBroadcasting,
    );
  }

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      isBroadcasting: map['isBroadcasting'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name, 'isBroadcasting': isBroadcasting};
  }

  @override
  String toString() {
    return 'User(id: $id, name: $name, isBroadcasting: $isBroadcasting)';
  }
}
