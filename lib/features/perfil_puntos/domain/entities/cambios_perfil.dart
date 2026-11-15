import 'package:latlong2/latlong.dart';

class CambiosPerfil {
  const CambiosPerfil({
    required this.tarifaBase,
    required this.rangoCoberturaM,
    required this.oficioIds,
    this.tarifas = const {},
    this.ubicacion,
  });

  final double tarifaBase;
  final int rangoCoberturaM;

  /// Punto de partida. Si es null no se toca la zona guardada (por ejemplo,
  /// al guardar solo la tarifa y los oficios).
  final LatLng? ubicacion;
  final Set<int> oficioIds;

  /// Precio de la visita por oficio. Vacío: no se tocan los precios (los
  /// oficios nuevos toman la tarifa base).
  final Map<int, double> tarifas;
}
