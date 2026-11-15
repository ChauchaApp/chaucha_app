import 'package:flutter_test/flutter_test.dart';
import 'package:tecnicos_app/features/solicitudes/data/models/vehiculo_db.dart';
import 'package:tecnicos_app/features/solicitudes/domain/entities/vehiculo.dart';

void main() {
  test('resumen con todos los datos y con algunos', () {
    const completo = Vehiculo(
      tipo: TipoVehiculo.auto,
      marca: 'Toyota',
      modelo: 'Corolla',
      anio: 2015,
    );
    expect(completo.resumen, 'Auto · Toyota Corolla 2015');
    expect(const Vehiculo(tipo: TipoVehiculo.moto).resumen, 'Moto');
    expect(const Vehiculo(marca: 'Suzuki').resumen, 'Suzuki');
  });

  test('sin datos no se guarda nada', () {
    expect(VehiculoDb.aJson(const Vehiculo(marca: '  ')), isNull);
    expect(VehiculoDb.aJson(null), isNull);
  });

  test('ida y vuelta con la base', () {
    const v = Vehiculo(
      tipo: TipoVehiculo.camioneta,
      marca: ' Chevrolet ',
      modelo: 'D-Max',
      anio: 2019,
    );
    final json = VehiculoDb.aJson(v)!;
    expect(json, {
      'tipo': 'camioneta',
      'marca': 'Chevrolet',
      'modelo': 'D-Max',
      'anio': 2019,
    });
    expect(
      VehiculoDb.desdeJson(json)!.resumen,
      'Camioneta · Chevrolet D-Max 2019',
    );
    expect(VehiculoDb.desdeJson(null), isNull);
    expect(VehiculoDb.desdeJson(<String, dynamic>{}), isNull);
  });
}
