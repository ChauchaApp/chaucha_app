import 'dart:js_interop';

@JS('sessionStorage')
external _Almacen get _almacen;

extension type _Almacen(JSObject _) implements JSObject {
  external String? getItem(String clave);
  external void setItem(String clave, String valor);
}

// El navegador puede bloquear el almacenamiento (modo privado estricto):
// entonces simplemente no se recuerda la pestaña.
String? leer(String clave) {
  try {
    return _almacen.getItem(clave);
  } catch (_) {
    return null;
  }
}

void guardar(String clave, String valor) {
  try {
    _almacen.setItem(clave, valor);
  } catch (_) {}
}
