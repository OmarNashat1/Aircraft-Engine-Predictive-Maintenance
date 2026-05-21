import 'dart:io';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:predection_desktop_app/core/services/prediction_storage_service.dart';
import 'package:predection_desktop_app/features/predictions/domain/usecases/run_prediction_usecase.dart';
import 'package:predection_desktop_app/features/predictions/presentation/cubit/prediction_state.dart';

/// Prediction Cubit
@injectable
class PredictionCubit extends Cubit<PredictionState> {
  final RunPredictionUseCase runPredictionUseCase;
  final PredictionStorageService storageService;

  PredictionCubit(this.runPredictionUseCase, this.storageService)
    : super(PredictionInitial());

  /// Select CSV file
  void selectFile(File file) {
    emit(PredictionFileSelected(file));
  }

  /// Run prediction
  Future<void> runPrediction(File csvFile) async {
    emit(const PredictionUploading(0.0));

    final result = await runPredictionUseCase(
      csvFile: csvFile,
      onProgress: (progress) {
        emit(PredictionUploading(progress));
      },
    );

    result.fold((failure) => emit(PredictionError(failure.message)), (
      predictionResult,
    ) {
      // Save result to storage service for persistence
      storageService.saveResult(predictionResult);
      emit(PredictionSuccess(predictionResult));
    });
  }

  /// Reset to initial state
  void reset() {
    emit(PredictionInitial());
  }
}
