import '../../../../core/utils/json_utils.dart';
import '../../domain/entities/oficio.dart';

class OficioModel {
  const OficioModel({
    required this.id,
    required this.nombre,
    this.esVehiculo = false,
  });

  factory OficioModel.fromJson(Map<String, dynamic> json) => OficioModel(
    id: aInt(json['id']),
    nombre: json['nombre'] as String,
    esVehiculo: json['categoria'] == 'vehiculos',
  );

  final int id;
  final String nombre;
  final bool esVehiculo;

  Oficio aEntidad() => Oficio(id: id, nombre: nombre, esVehiculo: esVehiculo);
}
