import '../core/router/app_routes.dart';
import '../features/auth/domain/entities/rol.dart';
import '../features/auth/domain/entities/sesion_estado.dart';

String rutaInicioPara(Rol rol) => switch (rol) {
  Rol.cliente => AppRoutes.clienteInicio,
  Rol.tecnico => AppRoutes.tecnicoInicio,
  Rol.admin => AppRoutes.adminInicio,
};

/// [pendiente] es la ruta que se abrió mientras se verificaba la sesión (al
/// refrescar la web): al salir del splash se vuelve a ella si está permitida.
String? resolverRedireccion({
  required SesionEstado sesion,
  required String ubicacion,
  String? pendiente,
}) {
  if (pendiente != null &&
      ubicacion == AppRoutes.splash &&
      sesion is! SesionVerificando) {
    final ruta = Uri.parse(pendiente).path;
    if (ruta != AppRoutes.splash &&
        resolverRedireccion(sesion: sesion, ubicacion: ruta) == null) {
      return pendiente;
    }
  }
  if (AppRoutes.legales.contains(ubicacion) && sesion is! SesionVerificando) {
    return null;
  }
  return switch (sesion) {
    SesionVerificando() =>
      ubicacion == AppRoutes.splash ? null : AppRoutes.splash,
    SinSesion() =>
      AppRoutes.publicas.contains(ubicacion) ? null : AppRoutes.login,
    // El administrador no tiene cédula: nunca pasa por completar el perfil.
    ConSesion(:final usuario)
        when !usuario.perfilCompleto && usuario.rol != Rol.admin =>
      ubicacion == AppRoutes.completarPerfil ? null : AppRoutes.completarPerfil,
    ConSesion(:final usuario, rostroVerificado: false)
        when usuario.rol != Rol.admin &&
            usuario.verificado &&
            usuario.fotoRostroValidada =>
      _soloEn(AppRoutes.verificarRostro, ubicacion),
    ConSesion(:final usuario) => _redireccionConSesion(usuario.rol, ubicacion),
    SesionRecuperando() =>
      ubicacion == AppRoutes.restablecer ? null : AppRoutes.restablecer,
  };
}

String? _soloEn(String destino, String ubicacion) =>
    ubicacion == destino ? null : destino;

String? _redireccionConSesion(Rol rol, String ubicacion) {
  final inicio = rutaInicioPara(rol);
  final estaEnSuZona = ubicacion == inicio || ubicacion.startsWith('$inicio/');
  return estaEnSuZona ? null : inicio;
}
