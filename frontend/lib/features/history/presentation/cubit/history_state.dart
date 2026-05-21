import 'package:equatable/equatable.dart';
import 'package:predection_desktop_app/features/history/domain/entities/history_entity.dart';

/// Base history state
abstract class HistoryState extends Equatable {
  const HistoryState();

  @override
  List<Object?> get props => [];
}

/// Initial state
class HistoryInitial extends HistoryState {}

/// Loading state
class HistoryLoading extends HistoryState {}

/// Loaded state
class HistoryLoaded extends HistoryState {
  final List<HistoryEntity> history;

  const HistoryLoaded(this.history);

  @override
  List<Object> get props => [history];
}

/// Error state
class HistoryError extends HistoryState {
  final String message;

  const HistoryError(this.message);

  @override
  List<Object> get props => [message];
}
