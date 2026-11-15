import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/providers/core_providers.dart';
import '../../../../core/supabase/supabase_guard.dart';
import '../../domain/entities/pago.dart';
import '../../domain/entities/plan.dart';
import '../../domain/repositories/plan_repository.dart';
import '../models/plan_model.dart';

final planRepositoryProvider = Provider<PlanRepository>(
  (ref) => SupabasePlanRepository(ref.watch(supabaseClientProvider)),
);

class SupabasePlanRepository implements PlanRepository {
  SupabasePlanRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Plan>> planes() {
    return supabaseGuard(() async {
      final filas = await _client
          .from('planes')
          .select(PlanModel.columnas)
          .order('orden');
      return filas.map(PlanModel.desdeFila).toList();
    });
  }

  @override
  Future<MiPlan> miPlan() {
    return supabaseGuard(() async {
      final filas = await _client.rpc<List<dynamic>>('mi_plan');
      final fila = filas.isEmpty ? null : filas.first as Map<String, dynamic>;
      return PlanModel.miPlanDesdeFila(fila);
    });
  }

  @override
  Future<void> volverAGratis() {
    return supabaseGuard(
      () => _client.rpc<void>('suscribirse', params: {'p_plan': 'gratis'}),
    );
  }

  @override
  Future<Pago> pagar({
    required String codigo,
    required String marca,
    required String ultimos4,
  }) {
    return supabaseGuard(() async {
      final fila = await _client.rpc<Map<String, dynamic>>(
        'pagar_plan',
        params: {'p_plan': codigo, 'p_marca': marca, 'p_ultimos4': ultimos4},
      );
      return PlanModel.pagoDesdeFila(fila);
    });
  }
}
