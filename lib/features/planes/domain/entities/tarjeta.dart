/// Validación de tarjetas para la pasarela de pago simulada. Todo ocurre en
/// el teléfono: al servidor solo llegan la marca y los últimos 4 dígitos.
enum MarcaTarjeta {
  visa('visa', 'Visa'),
  mastercard('mastercard', 'Mastercard'),
  amex('amex', 'American Express'),
  diners('diners', 'Diners Club');

  const MarcaTarjeta(this.codigo, this.nombre);

  final String codigo;
  final String nombre;

  int get largoCvv => this == amex ? 4 : 3;
}

abstract final class Tarjeta {
  /// Tarjeta de prueba que siempre se aprueba.
  static const String pruebaAprobada = '4242 4242 4242 4242';

  /// Tarjeta de prueba que el banco simulado rechaza (termina en 0002).
  static const String pruebaRechazada = '4000 0000 0000 0002';

  static String soloDigitos(String texto) =>
      texto.replaceAll(RegExp(r'\D'), '');

  static MarcaTarjeta? marcaDe(String numero) {
    final n = soloDigitos(numero);
    if (n.isEmpty) return null;
    if (n.startsWith('4')) return MarcaTarjeta.visa;
    if (RegExp(r'^3[47]').hasMatch(n)) return MarcaTarjeta.amex;
    if (RegExp(r'^(36|38|30[0-5])').hasMatch(n)) return MarcaTarjeta.diners;
    if (n.length >= 2) {
      final dos = int.parse(n.substring(0, 2));
      if (dos >= 51 && dos <= 55) return MarcaTarjeta.mastercard;
    }
    if (n.length >= 4) {
      final cuatro = int.parse(n.substring(0, 4));
      if (cuatro >= 2221 && cuatro <= 2720) return MarcaTarjeta.mastercard;
    }
    return null;
  }

  /// Algoritmo de Luhn (dígito verificador de las tarjetas).
  static bool luhn(String numero) {
    final n = soloDigitos(numero);
    if (n.length < 13 || n.length > 19) return false;
    var suma = 0;
    var doble = false;
    for (var i = n.length - 1; i >= 0; i--) {
      var d = n.codeUnitAt(i) - 48;
      if (doble) {
        d *= 2;
        if (d > 9) d -= 9;
      }
      suma += d;
      doble = !doble;
    }
    return suma % 10 == 0;
  }

  /// "4242424242424242" -> "4242 4242 4242 4242" (Amex: 4-6-5).
  static String formatear(String numero) {
    final n = soloDigitos(numero);
    final grupos = marcaDe(n) == MarcaTarjeta.amex
        ? [4, 6, 5]
        : [4, 4, 4, 4, 3];
    final partes = <String>[];
    var i = 0;
    for (final g in grupos) {
      if (i >= n.length) break;
      final fin = (i + g).clamp(0, n.length);
      partes.add(n.substring(i, fin));
      i = fin;
    }
    return partes.join(' ');
  }

  static String? validarNumero(String? valor) {
    final n = soloDigitos(valor ?? '');
    if (n.isEmpty) return 'Ingresa el número de la tarjeta.';
    if (marcaDe(n) == null) return 'Aceptamos Visa, Mastercard, Amex y Diners.';
    if (!luhn(n)) return 'Revisa el número de la tarjeta.';
    return null;
  }

  /// [valor] en formato MM/AA. Vence al terminar el mes indicado.
  static String? validarVencimiento(String? valor, {DateTime? hoy}) {
    final m = RegExp(r'^(\d{2})\s*/\s*(\d{2})$')
        .firstMatch(valor?.trim() ?? '');
    if (m == null) return 'Usa el formato MM/AA.';
    final mes = int.parse(m.group(1)!);
    final anio = 2000 + int.parse(m.group(2)!);
    if (mes < 1 || mes > 12) return 'El mes no es válido.';
    final ahora = hoy ?? DateTime.now();
    final finDeMes = DateTime(anio, mes + 1);
    if (!finDeMes.isAfter(ahora)) return 'La tarjeta está vencida.';
    return null;
  }

  static String? validarCvv(String? valor, MarcaTarjeta? marca) {
    final c = soloDigitos(valor ?? '');
    final largo = marca?.largoCvv ?? 3;
    if (c.length != largo) return 'El código tiene $largo dígitos.';
    return null;
  }

  static String? validarTitular(String? valor) {
    final t = valor?.trim() ?? '';
    if (t.length < 3 || !t.contains(' ')) {
      return 'Escribe el nombre como aparece en la tarjeta.';
    }
    return null;
  }
}
