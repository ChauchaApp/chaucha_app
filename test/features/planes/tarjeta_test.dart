import 'package:flutter_test/flutter_test.dart';
import 'package:tecnicos_app/features/planes/data/models/plan_model.dart';
import 'package:tecnicos_app/features/planes/domain/entities/tarjeta.dart';

void main() {
  group('Tarjeta', () {
    test('reconoce la marca por los primeros dígitos', () {
      expect(Tarjeta.marcaDe('4242 4242'), MarcaTarjeta.visa);
      expect(Tarjeta.marcaDe('5555555555554444'), MarcaTarjeta.mastercard);
      expect(Tarjeta.marcaDe('2223003122003222'), MarcaTarjeta.mastercard);
      expect(Tarjeta.marcaDe('378282246310005'), MarcaTarjeta.amex);
      expect(Tarjeta.marcaDe('36227206271667'), MarcaTarjeta.diners);
      expect(Tarjeta.marcaDe('9999'), isNull);
      expect(Tarjeta.marcaDe(''), isNull);
    });

    test('valida el dígito verificador (Luhn)', () {
      expect(Tarjeta.luhn(Tarjeta.pruebaAprobada), isTrue);
      expect(Tarjeta.luhn(Tarjeta.pruebaRechazada), isTrue);
      expect(Tarjeta.luhn('4242 4242 4242 4241'), isFalse);
      expect(Tarjeta.luhn('4242'), isFalse);
    });

    test('formatea en grupos de 4, y Amex en 4-6-5', () {
      expect(Tarjeta.formatear('4242424242424242'), '4242 4242 4242 4242');
      expect(Tarjeta.formatear('378282246310005'), '3782 822463 10005');
      expect(Tarjeta.formatear('42424'), '4242 4');
    });

    test('mensajes del número', () {
      expect(Tarjeta.validarNumero(''), isNotNull);
      expect(
        Tarjeta.validarNumero('9999 9999 9999 9995'),
        contains('Aceptamos'),
      );
      expect(Tarjeta.validarNumero('4242 4242 4242 4241'), contains('Revisa'));
      expect(Tarjeta.validarNumero(Tarjeta.pruebaAprobada), isNull);
    });

    test('vencimiento: vale hasta el fin del mes indicado', () {
      final hoy = DateTime(2026, 11, 15);
      expect(Tarjeta.validarVencimiento('11/26', hoy: hoy), isNull);
      expect(
        Tarjeta.validarVencimiento('10/26', hoy: hoy),
        contains('vencida'),
      );
      expect(Tarjeta.validarVencimiento('13/27', hoy: hoy), contains('mes'));
      expect(Tarjeta.validarVencimiento('1127', hoy: hoy), contains('MM/AA'));
    });

    test('el CVV de Amex tiene 4 dígitos y el resto 3', () {
      expect(Tarjeta.validarCvv('123', MarcaTarjeta.visa), isNull);
      expect(Tarjeta.validarCvv('1234', MarcaTarjeta.visa), isNotNull);
      expect(Tarjeta.validarCvv('1234', MarcaTarjeta.amex), isNull);
    });

    test('el titular necesita nombre y apellido', () {
      expect(Tarjeta.validarTitular('Ana'), isNotNull);
      expect(Tarjeta.validarTitular('Ana Torres'), isNull);
    });
  });

  test('lee el pago devuelto por la pasarela', () {
    final pago = PlanModel.pagoDesdeFila({
      'referencia': 'PAY-000007',
      'plan_codigo': 'pro',
      'monto': '6.00',
      'marca': 'visa',
      'ultimos4': '0002',
      'estado': 'rechazado',
      'motivo': 'El banco rechazó la tarjeta por fondos insuficientes.',
      'creado_en': '2026-11-15T15:00:00Z',
    });
    expect(pago.referencia, 'PAY-000007');
    expect(pago.monto, 6);
    expect(pago.aprobado, isFalse);
    expect(pago.motivo, contains('fondos'));
  });
}
