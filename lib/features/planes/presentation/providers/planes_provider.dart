import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/async_guard.dart';
import '../../../auth/presentation/providers/sesion_provider.dart';
import '../../../perfil_puntos/presentation/providers/perfil_tecnico_provider.dart';
import '../../../solicitudes/presentation/providers/feed_provider.dart';
import '../../data/repositories/supabase_plan_repository.dart';
import '../../domain/entities/pago.dart';
import '../../domain/entities/plan.dart';

final planesProvider = FutureProvider.autoDispose<List<Plan>>(
  (ref) => ref.watch(planRepositoryProvider).planes(),
);

final miPlanProvider = FutureProvider.autoDispose<MiPlan>((ref) {
  ref.watch(usuarioActualProvider.select((u) => u?.id));
  return ref.watch(planRepositoryProvider).miPlan();
});

final suscribirseProvider =
    AsyncNotifierProvider.autoDispose<SuscribirseNotifier, Pago?>(
      SuscribirseNotifier.new,
    );

/// Cambios de plan: pagar uno (pasarela simulada) o volver a Gratis. Al
/// terminar recarga el plan, el perfil (rango y oficios) y el feed.
class SuscribirseNotifier extends AsyncNotifier<Pago?> {
  @override
  FutureOr<Pago?> build() => null;

  Future<bool> volverAGratis() async {
    if (state.isLoading) return false;
    state = const AsyncLoading();
    final resultado = await asyncGuard<Pago?>(() async {
      await ref.read(planRepositoryProvider).volverAGratis();
      return null;
    });
    return _terminar(resultado, cambio: !resultado.hasError);
  }

  /// Devuelve el pago (aprobado o rechazado) o null si hubo un error.
  Future<Pago?> pagar({
    required String codigo,
    required String marca,
    required String ultimos4,
  }) async {
    if (state.isLoading) return null;
    state = const AsyncLoading();
    final resultado = await asyncGuard<Pago?>(
      () => ref
          .read(planRepositoryProvider)
          .pagar(codigo: codigo, marca: marca, ultimos4: ultimos4),
    );
    final pago = resultado.value;
    _terminar(resultado, cambio: pago?.aprobado ?? false);
    return pago;
  }

  bool _terminar(AsyncValue<Pago?> resultado, {required bool cambio}) {
    if (!ref.mounted) return !resultado.hasError;
    state = resultado;
    if (cambio) {
      ref
        ..invalidate(miPlanProvider)
        ..invalidate(perfilTecnicoProvider)
        ..invalidate(feedProvider);
    }
    return !resultado.hasError;
  }
}
