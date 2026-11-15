/// Datos opcionales del vehículo en una solicitud de mecánica o llantería.
enum TipoVehiculo {
  auto('Auto'),
  camioneta('Camioneta'),
  moto('Moto'),
  otro('Otro');

  const TipoVehiculo(this.etiqueta);

  final String etiqueta;
}

class Vehiculo {
  const Vehiculo({this.tipo, this.marca, this.modelo, this.anio});

  final TipoVehiculo? tipo;
  final String? marca;
  final String? modelo;
  final int? anio;

  bool get vacio =>
      tipo == null &&
      (marca ?? '').trim().isEmpty &&
      (modelo ?? '').trim().isEmpty &&
      anio == null;

  /// "Auto · Toyota Corolla 2015".
  String get resumen {
    final nombre = [
      marca?.trim(),
      modelo?.trim(),
      anio?.toString(),
    ].whereType<String>().where((p) => p.isNotEmpty).join(' ');
    return [?tipo?.etiqueta, if (nombre.isNotEmpty) nombre].join(' · ');
  }
}
