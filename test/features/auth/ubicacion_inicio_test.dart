import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tecnicos_app/core/geo/geo_mapper.dart';
import 'package:tecnicos_app/core/geo/ubicacion_service.dart';
import 'package:tecnicos_app/core/providers/core_providers.dart';
import 'package:tecnicos_app/features/auth/domain/entities/rol.dart';
import 'package:tecnicos_app/features/auth/domain/entities/usuario.dart';
import 'package:tecnicos_app/features/auth/presentation/providers/inicio_provider.dart';
import 'package:tecnicos_app/features/auth/presentation/providers/sesion_provider.dart';

class _Gps implements UbicacionService {
  _Gps(this.punto);

  final LatLng? punto;
  int consultas = 0;

  @override
  Future<LatLng?> obtenerActual() async {
    consultas++;
    return punto;
  }
}

Usuario _usuario({LatLng? ubicacion}) => Usuario(
  id: 'c1',
  rol: Rol.cliente,
  nombres: 'Ana',
  apellidos: 'Torres',
  creadoEn: DateTime(2026),
  perfilCompleto: true,
  ubicacionRegistro: ubicacion,
);

void main() {
  const gps = LatLng(-0.18, -78.48);
  const guardada = LatLng(-0.29, -78.54);

  ProviderContainer contenedor(Usuario? usuario, _Gps servicio) =>
      ProviderContainer.test(
        overrides: [
          usuarioActualProvider.overrideWith((ref) => usuario),
          ubicacionServiceProvider.overrideWithValue(servicio),
        ],
      );

  test('usa la ubicación guardada en el perfil, sin pedir el GPS', () async {
    final servicio = _Gps(gps);
    final c = contenedor(_usuario(ubicacion: guardada), servicio);
    expect(await c.read(ubicacionInicioProvider.future), guardada);
    expect(servicio.consultas, 0);
  });

  test('sin ubicación guardada, usa el GPS', () async {
    final c = contenedor(_usuario(), _Gps(gps));
    expect(await c.read(ubicacionInicioProvider.future), gps);
  });

  test('sin ubicación guardada ni GPS, el centro de Quito', () async {
    final c = contenedor(_usuario(), _Gps(null));
    expect(await c.read(ubicacionInicioProvider.future), GeoMapper.quito);
  });
}
