// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;
import 'package:predection_desktop_app/core/network/dio_client.dart' as _i1;
import 'package:predection_desktop_app/core/services/prediction_storage_service.dart'
    as _i17;
import 'package:predection_desktop_app/features/auth/data/datasources/auth_remote_datasource.dart'
    as _i2;
import 'package:predection_desktop_app/features/auth/data/repositories/auth_repository_impl.dart'
    as _i4;
import 'package:predection_desktop_app/features/auth/domain/repositories/auth_repository.dart'
    as _i3;
import 'package:predection_desktop_app/features/auth/domain/usecases/login_usecase.dart'
    as _i5;
import 'package:predection_desktop_app/features/auth/presentation/bloc/auth_bloc.dart'
    as _i6;
import 'package:predection_desktop_app/features/dashboard/data/datasources/dashboard_remote_datasource.dart'
    as _i7;
import 'package:predection_desktop_app/features/dashboard/data/repositories/dashboard_repository_impl.dart'
    as _i9;
import 'package:predection_desktop_app/features/dashboard/domain/repositories/dashboard_repository.dart'
    as _i8;
import 'package:predection_desktop_app/features/dashboard/domain/usecases/get_dashboard_data_usecase.dart'
    as _i10;
import 'package:predection_desktop_app/features/dashboard/presentation/cubit/dashboard_cubit.dart'
    as _i11;
import 'package:predection_desktop_app/features/predictions/data/datasources/prediction_remote_datasource.dart'
    as _i12;
import 'package:predection_desktop_app/features/predictions/data/repositories/prediction_repository_impl.dart'
    as _i14;
import 'package:predection_desktop_app/features/predictions/domain/repositories/prediction_repository.dart'
    as _i13;
import 'package:predection_desktop_app/features/predictions/domain/usecases/run_prediction_usecase.dart'
    as _i15;
import 'package:predection_desktop_app/features/predictions/presentation/cubit/prediction_cubit.dart'
    as _i16;
import 'package:predection_desktop_app/features/history/data/datasources/history_remote_datasource.dart'
    as _i18;
import 'package:predection_desktop_app/features/history/data/repositories/history_repository_impl.dart'
    as _i20;
import 'package:predection_desktop_app/features/history/domain/repositories/history_repository.dart'
    as _i19;
import 'package:predection_desktop_app/features/history/domain/usecases/get_history_usecase.dart'
    as _i21;
import 'package:predection_desktop_app/features/history/presentation/cubit/history_cubit.dart'
    as _i22;

extension GetItInjectableX on _i174.GetIt {
  // initializes the registration of main-scope dependencies inside of GetIt
  _i174.GetIt init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) {
    final gh = _i526.GetItHelper(this, environment, environmentFilter);
    gh.lazySingleton<_i1.DioClient>(() => _i1.DioClient());
    gh.lazySingleton<_i17.PredictionStorageService>(
      () => _i17.PredictionStorageService(),
    );
    gh.factory<_i2.AuthRemoteDataSource>(
      () => _i2.AuthRemoteDataSource(gh<_i1.DioClient>()),
    );
    gh.lazySingleton<_i3.AuthRepository>(
      () => _i4.AuthRepositoryImpl(gh<_i2.AuthRemoteDataSource>()),
    );
    gh.factory<_i5.LoginUseCase>(
      () => _i5.LoginUseCase(gh<_i3.AuthRepository>()),
    );
    gh.factory<_i6.AuthBloc>(() => _i6.AuthBloc(gh<_i5.LoginUseCase>()));
    gh.factory<_i7.DashboardRemoteDataSource>(
      () => _i7.DashboardRemoteDataSource(gh<_i1.DioClient>()),
    );
    gh.lazySingleton<_i8.DashboardRepository>(
      () => _i9.DashboardRepositoryImpl(gh<_i7.DashboardRemoteDataSource>()),
    );
    gh.factory<_i10.GetDashboardDataUseCase>(
      () => _i10.GetDashboardDataUseCase(gh<_i8.DashboardRepository>()),
    );
    gh.factory<_i11.DashboardCubit>(
      () => _i11.DashboardCubit(gh<_i10.GetDashboardDataUseCase>()),
    );
    gh.factory<_i12.PredictionRemoteDataSource>(
      () => _i12.PredictionRemoteDataSource(gh<_i1.DioClient>()),
    );
    gh.lazySingleton<_i13.PredictionRepository>(
      () =>
          _i14.PredictionRepositoryImpl(gh<_i12.PredictionRemoteDataSource>()),
    );
    gh.factory<_i15.RunPredictionUseCase>(
      () => _i15.RunPredictionUseCase(gh<_i13.PredictionRepository>()),
    );
    gh.factory<_i16.PredictionCubit>(
      () => _i16.PredictionCubit(
        gh<_i15.RunPredictionUseCase>(),
        gh<_i17.PredictionStorageService>(),
      ),
    );
    gh.factory<_i18.HistoryRemoteDataSource>(
      () => _i18.HistoryRemoteDataSource(gh<_i1.DioClient>()),
    );
    gh.lazySingleton<_i19.HistoryRepository>(
      () => _i20.HistoryRepositoryImpl(gh<_i18.HistoryRemoteDataSource>()),
    );
    gh.factory<_i21.GetHistoryUseCase>(
      () => _i21.GetHistoryUseCase(gh<_i19.HistoryRepository>()),
    );
    gh.factory<_i22.HistoryCubit>(
      () => _i22.HistoryCubit(gh<_i21.GetHistoryUseCase>()),
    );
    return this;
  }
}
