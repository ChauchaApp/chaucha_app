import '../../../../core/utils/json_utils.dart';
import '../../domain/entities/pago.dart';
import '../../domain/entities/plan.dart';

abstract final class PlanModel {
  static const String columnas =
      'codigo, nombre, precio_mensual, cotizaciones_mes, rango_max_m, '
      'oficios_max, prioridad, destacado';

  static Plan desdeFila(Map<String, dynamic> fila) => Plan(
    codigo: fila['codigo'] as String,
    nombre: fila['nombre'] as String,
    precioMensual: aDouble(fila['precio_mensual']),
    cotizacionesMes: fila['cotizaciones_mes'] == null
        ? null
        : aInt(fila['cotizaciones_mes']),
    rangoMaxM: aInt(fila['rango_max_m']),
    oficiosMax: aInt(fila['oficios_max']),
    prioridad: aInt(fila['prioridad']),
    destacado: fila['destacado'] as bool? ?? false,
  );

  static Pago pagoDesdeFila(Map<String, dynamic> fila) => Pago(
    referencia: fila['referencia'] as String? ?? '',
    planCodigo: fila['plan_codigo'] as String? ?? '',
    monto: aDouble(fila['monto']),
    marca: fila['marca'] as String? ?? '',
    ultimos4: fila['ultimos4'] as String? ?? '',
    aprobado: fila['estado'] == 'aprobado',
    motivo: fila['motivo'] as String?,
    fecha:
        DateTime.tryParse(fila['creado_en'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
  );

  static MiPlan miPlanDesdeFila(Map<String, dynamic>? fila) => MiPlan(
    codigo: fila?['codigo'] as String? ?? 'gratis',
    cotizacionesUsadas: aInt(fila?['cotizaciones_usadas']),
    fin: DateTime.tryParse(fila?['fin'] as String? ?? '')?.toLocal(),
  );
}
