import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:predection_desktop_app/features/dashboard/domain/usecases/get_dashboard_data_usecase.dart';
import 'package:predection_desktop_app/features/dashboard/presentation/cubit/dashboard_state.dart';

/// Dashboard Cubit
@injectable
class DashboardCubit extends Cubit<DashboardState> {
  final GetDashboardDataUseCase getDashboardData;

  DashboardCubit(this.getDashboardData) : super(DashboardInitial());

  /// Load dashboard data
  Future<void> loadDashboard() async {
    emit(DashboardLoading());

    final result = await getDashboardData();

    result.fold(
      (failure) => emit(DashboardError(failure.message)),
      (summary) => emit(DashboardLoaded(summary)),
    );
  }

  /// Refresh dashboard data
  Future<void> refresh() async {
    await loadDashboard();
  }
}
