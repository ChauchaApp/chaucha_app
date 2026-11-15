/// Plan de suscripción de los técnicos. Los límites vienen de la tabla
/// `planes`: la app no los repite a mano.
class Plan {
  const Plan({
    required this.codigo,
    required this.nombre,
    required this.precioMensual,
    required this.rangoMaxM,
    required this.oficiosMax,
    required this.prioridad,
    required this.destacado,
    this.cotizacionesMes,
  });

  final String codigo;
  final String nombre;
  final double precioMensual;

  /// Propuestas por mes calendario. Null: ilimitadas.
  final int? cotizacionesMes;
  final int rangoMaxM;
  final int oficiosMax;
  final int prioridad;

  /// Sale primero ante el cliente, con la etiqueta "Destacado".
  final bool destacado;

  bool get esGratis => precioMensual <= 0;

  String get precioTexto =>
      esGratis ? 'Gratis' : '\$${precioMensual.toStringAsFixed(0)} al mes';

  String get cotizacionesTexto => cotizacionesMes == null
      ? 'Propuestas ilimitadas'
      : '$cotizacionesMes propuestas al mes';

  String get rangoTexto => 'Hasta ${(rangoMaxM / 1000).round()} km de rango';

  String get oficiosTexto =>
      oficiosMax == 1 ? '1 oficio activo' : '$oficiosMax oficios activos';

  String get posicionTexto => switch (prioridad) {
    >= 3 => 'Sales primero y destacado ante el cliente',
    2 => 'Posición alta ante el cliente',
    _ => 'Posición normal ante el cliente',
  };
}

/// Mi plan vigente, cuándo vence y cuántas propuestas llevo este mes.
class MiPlan {
  const MiPlan({
    required this.codigo,
    required this.cotizacionesUsadas,
    this.fin,
  });

  final String codigo;
  final int cotizacionesUsadas;

  /// Fin de la suscripción. Null en Gratis.
  final DateTime? fin;
}

/// Límites del plan que el servidor puede rechazar. El código llega en el
/// HINT del error como `plan:...`.
enum LimitePlan {
  cotizaciones(
    'plan:limite_cotizaciones',
    'Pasa a Pro para enviar propuestas sin límite.',
  ),
  oficios(
    'plan:limite_oficios',
    'Pasa a un plan superior para ofrecer más oficios.',
  ),
  rango(
    'plan:fuera_de_rango',
    'Pasa a un plan superior para llegar a solicitudes más lejanas.',
  ),
  oficioPausado(
    'plan:oficio_pausado',
    'Activa este oficio en Mi perfil o pasa a un plan con más oficios.',
  );

  const LimitePlan(this.codigo, this.sugerencia);

  final String codigo;
  final String sugerencia;

  static LimitePlan? desdeCodigo(String? codigo) {
    for (final l in values) {
      if (l.codigo == codigo) return l;
    }
    return null;
  }
}
