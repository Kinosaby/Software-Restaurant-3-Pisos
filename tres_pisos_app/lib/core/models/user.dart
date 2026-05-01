// lib/core/models/user.dart
class UserModel {
  final int id;
  final String username;
  final String role;

  UserModel({required this.id, required this.username, required this.role});

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
    id:       json['id'],
    username: json['username'] ?? json['usuario'] ?? '',
    role:     json['role']     ?? json['rol']     ?? '',
  );

  Map<String, dynamic> toJson() => {'id': id, 'username': username, 'role': role};
}
