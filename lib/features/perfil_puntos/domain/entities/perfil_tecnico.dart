import 'package:latlong2/latlong.dart';

class PerfilTecnico {
  const PerfilTecnico({
    required this.usuarioId,
    required this.tarifaBase,
    required this.rangoCoberturaM,
    required this.puntos,
    required this.calificacionPromedio,
    required this.totalResenas,
    required this.verificado,
    required this.nivelNombre,
    required this.comisionPorcentaje,
    required this.oficioIds,
    this.tarifas = const {},
    this.ubicacionActual,
    this.rangoBonusM = 0,
    this.planCodigo = 'gratis',
    this.rangoMaxPlanM,
    this.oficiosMaxPlan,
    this.oficiosPausados = const [],
  });

  final String usuarioId;
  final double tarifaBase;
  final int rangoCoberturaM;

  /// Bono por reseñas "excelente" de los últimos 90 días (lo calcula un
  /// job nocturno en la base). No lo puede editar el técnico.
  final int rangoBonusM;
  final LatLng? ubicacionActual;
  final int puntos;
  final double calificacionPromedio;
  final int totalResenas;
  final bool verificado;
  final String nivelNombre;
  final double comisionPorcentaje;
  final List<int> oficioIds;

  /// Plan de suscripción vigente: `gratis`, `pro` o `plus`.
  final String planCodigo;

  /// Tope de rango del plan. Null: sin tope (datos viejos).
  final int? rangoMaxPlanM;

  /// Cuántos oficios activos permite el plan. Null: sin tope.
  final int? oficiosMaxPlan;

  /// Oficios pausados al bajar de plan: no aparecen en el feed hasta que el
  /// técnico los vuelva a activar.
  final List<int> oficiosPausados;

  /// Precio de la visita por oficio (id del oficio → precio).
  final Map<int, double> tarifas;

  /// Precio de la visita para [oficioId]; sin uno propio, la tarifa base.
  double tarifaPara(int oficioId) {
    final propia = tarifas[oficioId];
    return propia != null && propia > 0 ? propia : tarifaBase;
  }

  /// Rango con el que realmente se buscan solicitudes: el elegido, con el
  /// tope del plan, más el bono por reputación (máx. 50 km).
  int get rangoEfectivoM {
    final tope = rangoMaxPlanM;
    final base = tope != null && tope < rangoCoberturaM
        ? tope
        : rangoCoberturaM;
    return (base + rangoBonusM).clamp(0, 50000);
  }

  /// Sin oficios o sin ubicación, el técnico no puede ver solicitudes.
  bool get estaCompleto => oficioIds.isNotEmpty && ubicacionActual != null;
}
