import 'dart:io';
import 'package:equatable/equatable.dart';
import 'package:predection_desktop_app/features/predictions/domain/entities/prediction_result_entity.dart';

/// Base prediction state
abstract class PredictionState extends Equatable {
  const PredictionState();

  @override
  List<Object?> get props => [];
}

/// Initial state
class PredictionInitial extends PredictionState {}

/// File selected state
class PredictionFileSelected extends PredictionState {
  final File file;

  const PredictionFileSelected(this.file);

  @override
  List<Object> get props => [file];
}

/// Uploading state with progress
class PredictionUploading extends PredictionState {
  final double progress;

  const PredictionUploading(this.progress);

  @override
  List<Object> get props => [progress];
}

/// Success state
class PredictionSuccess extends PredictionState {
  final PredictionResultEntity result;

  const PredictionSuccess(this.result);

  @override
  List<Object> get props => [result];
}

/// Error state
class PredictionError extends PredictionState {
  final String message;

  const PredictionError(this.message);

  @override
  List<Object> get props => [message];
}
