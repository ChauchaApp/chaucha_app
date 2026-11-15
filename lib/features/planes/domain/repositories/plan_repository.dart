import '../entities/pago.dart';
import '../entities/plan.dart';

abstract interface class PlanRepository {
  /// Los planes, de menor a mayor.
  Future<List<Plan>> planes();

  Future<MiPlan> miPlan();

  /// Vuelve al plan Gratis; los oficios que sobren quedan pausados.
  Future<void> volverAGratis();

  /// Pasarela simulada: paga [codigo] con una tarjeta de la que solo se
  /// envían la marca y los últimos 4 dígitos. Si se aprueba, el plan queda
  /// activo por 30 días.
  Future<Pago> pagar({
    required String codigo,
    required String marca,
    required String ultimos4,
  });
}
