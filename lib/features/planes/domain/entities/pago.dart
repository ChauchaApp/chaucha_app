/// Resultado de la pasarela de pago simulada.
class Pago {
  const Pago({
    required this.referencia,
    required this.planCodigo,
    required this.monto,
    required this.marca,
    required this.ultimos4,
    required this.aprobado,
    required this.fecha,
    this.motivo,
  });

  /// Número de comprobante, por ejemplo PAY-000012.
  final String referencia;
  final String planCodigo;
  final double monto;
  final String marca;
  final String ultimos4;
  final bool aprobado;
  final DateTime fecha;

  /// Por qué el banco rechazó el pago.
  final String? motivo;
}
