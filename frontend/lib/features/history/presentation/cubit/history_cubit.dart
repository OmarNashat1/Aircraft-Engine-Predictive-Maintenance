import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:predection_desktop_app/features/history/domain/usecases/get_history_usecase.dart';
import 'package:predection_desktop_app/features/history/presentation/cubit/history_state.dart';

/// History Cubit
@injectable
class HistoryCubit extends Cubit<HistoryState> {
  final GetHistoryUseCase getHistory;

  HistoryCubit(this.getHistory) : super(HistoryInitial());

  /// Load history
  Future<void> loadHistory() async {
    emit(HistoryLoading());

    final result = await getHistory();

    result.fold(
      (failure) => emit(HistoryError(failure.message)),
      (history) => emit(HistoryLoaded(history)),
    );
  }

  /// Refresh history
  Future<void> refresh() async {
    await loadHistory();
  }
}
