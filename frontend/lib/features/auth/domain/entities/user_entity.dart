import 'package:equatable/equatable.dart';

/// User domain entity (pure Dart, no framework dependencies)
class UserEntity extends Equatable {
  final String id;
  final String username;
  final String? role;

  const UserEntity({required this.id, required this.username, this.role});

  @override
  List<Object?> get props => [id, username, role];
}
