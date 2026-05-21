import 'package:predection_desktop_app/features/auth/domain/entities/user_entity.dart';

/// User data model with JSON serialization
class UserModel extends UserEntity {
  const UserModel({required super.id, required super.username, super.role});

  /// Create UserModel from JSON
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['user_id']?.toString() ?? json['id']?.toString() ?? '',
      username: json['username'] ?? '',
      role: json['role'],
    );
  }

  /// Convert UserModel to JSON
  Map<String, dynamic> toJson() {
    return {'user_id': id, 'username': username, 'role': role};
  }

  /// Convert to domain entity
  UserEntity toEntity() {
    return UserEntity(id: id, username: username, role: role);
  }
}
