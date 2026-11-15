class Oficio {
  const Oficio({
    required this.id,
    required this.nombre,
    this.esVehiculo = false,
  });

  final int id;
  final String nombre;

  /// Mecánica, llantería...: la visita es donde está el vehículo y la
  /// solicitud puede llevar sus datos.
  final bool esVehiculo;
}
