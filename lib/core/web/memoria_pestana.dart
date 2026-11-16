import 'memoria_pestana_otro.dart'
    if (dart.library.js_interop) 'memoria_pestana_web.dart'
    as impl;

/// Recuerda la pestaña abierta de cada inicio (/cliente, /tecnico...) mientras
/// dure la pestaña del navegador, para que al refrescar la web no se vuelva a
/// la primera. Fuera de la web no guarda nada.
abstract final class MemoriaPestana {
  static int? leer(String rutaInicio) =>
      int.tryParse(impl.leer(_clave(rutaInicio)) ?? '');

  static void guardar(String rutaInicio, int indice) =>
      impl.guardar(_clave(rutaInicio), '$indice');

  static String _clave(String rutaInicio) => 'pestana:$rutaInicio';
}
