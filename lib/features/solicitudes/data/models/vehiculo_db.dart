import '../../../../core/utils/json_utils.dart';
import '../../domain/entities/vehiculo.dart';

/// Columna `solicitudes_servicio.vehiculo` (jsonb).
abstract final class VehiculoDb {
  static Map<String, dynamic>? aJson(Vehiculo? v) {
    if (v == null || v.vacio) return null;
    String? limpio(String? t) => (t ?? '').trim().isEmpty ? null : t!.trim();
    return {
      'tipo': ?v.tipo?.name,
      'marca': ?limpio(v.marca),
      'modelo': ?limpio(v.modelo),
      'anio': ?v.anio,
    };
  }

  static Vehiculo? desdeJson(Object? json) {
    if (json is! Map) return null;
    final tipo = TipoVehiculo.values
        .where((t) => t.name == json['tipo'])
        .firstOrNull;
    final v = Vehiculo(
      tipo: tipo,
      marca: json['marca'] as String?,
      modelo: json['modelo'] as String?,
      anio: json['anio'] == null ? null : aInt(json['anio']),
    );
    return v.vacio ? null : v;
  }
}
