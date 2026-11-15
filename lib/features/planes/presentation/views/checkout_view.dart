import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/utils/formatos.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/boton_carga.dart';
import '../../../../core/widgets/mensajes.dart';
import '../../../../core/widgets/pantalla_secundaria.dart';
import '../../../../core/widgets/scroll_pagina.dart';
import '../../../../core/widgets/tarjeta_app.dart';
import '../../domain/entities/pago.dart';
import '../../domain/entities/plan.dart';
import '../../domain/entities/tarjeta.dart';
import '../providers/planes_provider.dart';
import 'planes_view.dart';

/// Pasarela de pago simulada: valida la tarjeta en el teléfono y al
/// servidor solo envía la marca y los últimos 4 dígitos.
class CheckoutView extends ConsumerStatefulWidget {
  const CheckoutView({super.key, required this.codigo});

  final String codigo;

  @override
  ConsumerState<CheckoutView> createState() => _CheckoutViewState();
}

class _CheckoutViewState extends ConsumerState<CheckoutView> {
  final _form = GlobalKey<FormState>();
  final _numero = TextEditingController();
  final _titular = TextEditingController();
  final _vence = TextEditingController();
  final _cvv = TextEditingController();
  bool _procesando = false;
  Pago? _comprobante;

  @override
  void initState() {
    super.initState();
    _numero.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in [_numero, _titular, _vence, _cvv]) {
      c.dispose();
    }
    super.dispose();
  }

  MarcaTarjeta? get _marca => Tarjeta.marcaDe(_numero.text);

  void _usarPrueba(String numero) {
    _numero.text = numero;
    _titular.text = 'Cliente Demo';
    final dentroDeUnAnio = DateTime.now().add(const Duration(days: 400));
    _vence.text =
        '${dentroDeUnAnio.month.toString().padLeft(2, '0')}/'
        '${(dentroDeUnAnio.year % 100).toString().padLeft(2, '0')}';
    _cvv.text = '123';
  }

  Future<void> _pagar(Plan plan) async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final digitos = Tarjeta.soloDigitos(_numero.text);
    setState(() => _procesando = true);
    // La "pasarela" tarda un momento, como una real.
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (!mounted) return;
    final pago = await ref
        .read(suscribirseProvider.notifier)
        .pagar(
          codigo: plan.codigo,
          marca: _marca!.codigo,
          ultimos4: digitos.substring(digitos.length - 4),
        );
    if (!mounted) return;
    setState(() => _procesando = false);
    if (pago == null) {
      final error = ref.read(suscribirseProvider).error;
      context.mostrarMensaje(
        AsyncValueView.mensajeDe(error ?? 'No se pudo procesar el pago.'),
        tipo: TipoMensaje.error,
      );
    } else if (!pago.aprobado) {
      context.mostrarMensaje(
        pago.motivo ?? 'El banco rechazó el pago.',
        titulo: 'Pago rechazado',
        tipo: TipoMensaje.error,
      );
    } else {
      setState(() => _comprobante = pago);
    }
  }

  @override
  Widget build(BuildContext context) {
    final planes = ref.watch(planesProvider);
    return PantallaSecundaria(
      titulo: 'Pagar plan',
      cuerpo: AsyncValueView<List<Plan>>(
        value: planes,
        onRetry: () => ref.invalidate(planesProvider),
        onData: (context, lista) {
          final plan = lista
              .where((p) => p.codigo == widget.codigo)
              .firstOrNull;
          if (plan == null || plan.esGratis) {
            return const Center(child: Text('Ese plan no requiere pago.'));
          }
          final comprobante = _comprobante;
          return ListaDePagina(
            padding: const EdgeInsets.all(Espacios.l),
            children: comprobante != null
                ? [_Comprobante(pago: comprobante, plan: plan)]
                : [
                    _Resumen(plan: plan),
                    const SizedBox(height: Espacios.l),
                    _formulario(plan),
                  ],
          );
        },
      ),
    );
  }

  Widget _formulario(Plan plan) {
    final textos = Theme.of(context).textTheme;
    final marca = _marca;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Datos de la tarjeta', style: textos.titleMedium),
          const SizedBox(height: Espacios.m),
          TextFormField(
            controller: _numero,
            enabled: !_procesando,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.creditCardNumber],
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d ]')),
              _FormatoTarjeta(),
            ],
            decoration: InputDecoration(
              labelText: 'Número de la tarjeta',
              hintText: Tarjeta.pruebaAprobada,
              prefixIcon: const Icon(Icons.credit_card_rounded),
              suffixText: marca?.nombre,
            ),
            validator: Tarjeta.validarNumero,
          ),
          const SizedBox(height: Espacios.m),
          TextFormField(
            controller: _titular,
            enabled: !_procesando,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.creditCardName],
            decoration: const InputDecoration(
              labelText: 'Nombre del titular',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            validator: Tarjeta.validarTitular,
          ),
          const SizedBox(height: Espacios.m),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _vence,
                  enabled: !_procesando,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_FormatoVencimiento()],
                  decoration: const InputDecoration(
                    labelText: 'Vence (MM/AA)',
                    hintText: '08/28',
                  ),
                  validator: Tarjeta.validarVencimiento,
                ),
              ),
              const SizedBox(width: Espacios.m),
              Expanded(
                child: TextFormField(
                  controller: _cvv,
                  enabled: !_procesando,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: const InputDecoration(labelText: 'CVV'),
                  validator: (v) => Tarjeta.validarCvv(v, marca),
                ),
              ),
            ],
          ),
          const SizedBox(height: Espacios.l),
          _AvisoDemo(
            onAprobada: _procesando
                ? null
                : () => setState(() => _usarPrueba(Tarjeta.pruebaAprobada)),
            onRechazada: _procesando
                ? null
                : () => setState(() => _usarPrueba(Tarjeta.pruebaRechazada)),
          ),
          const SizedBox(height: Espacios.l),
          BotonCarga(
            texto: _procesando
                ? 'Procesando pago…'
                : 'Pagar ${Formatos.dinero(plan.precioMensual)}',
            icono: Icons.lock_rounded,
            cargando: _procesando,
            onPressed: () => _pagar(plan),
          ),
          const SizedBox(height: Espacios.s),
          Text(
            'Tus datos se validan en tu teléfono: a ChauchaApp solo llegan la '
            'marca y los últimos 4 dígitos. Nunca guardamos el número ni el CVV.',
            textAlign: TextAlign.center,
            style: textos.bodySmall?.copyWith(color: Colores.tintaSuave),
          ),
        ],
      ),
    );
  }
}

class _Resumen extends StatelessWidget {
  const _Resumen({required this.plan});

  final Plan plan;

  @override
  Widget build(BuildContext context) {
    final textos = Theme.of(context).textTheme;
    final color = colorPlan(plan.codigo);
    return TarjetaApp(
      colorBorde: color,
      child: Row(
        children: [
          Icon(iconoPlan(plan.codigo), color: color, size: 32),
          const SizedBox(width: Espacios.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Plan ${plan.nombre}', style: textos.titleMedium),
                Text(
                  '30 días · ${plan.cotizacionesTexto.toLowerCase()} · '
                  '${plan.rangoTexto.toLowerCase()}',
                  style: textos.bodySmall?.copyWith(color: Colores.tintaSuave),
                ),
              ],
            ),
          ),
          Text(
            Formatos.dinero(plan.precioMensual),
            style: textos.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _AvisoDemo extends StatelessWidget {
  const _AvisoDemo({required this.onAprobada, required this.onRechazada});

  final VoidCallback? onAprobada;
  final VoidCallback? onRechazada;

  @override
  Widget build(BuildContext context) {
    final textos = Theme.of(context).textTheme;
    return TarjetaApp(
      color: Colores.avisoSuave,
      conBorde: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.science_outlined, color: Colores.avisoOscuro),
              const SizedBox(width: Espacios.s),
              Expanded(
                child: Text(
                  'Pasarela de demostración: no se cobra nada.',
                  style: textos.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: Espacios.xs),
          Text(
            'Usa una tarjeta de prueba. La que termina en 0002 simula un '
            'rechazo del banco.',
            style: textos.bodySmall,
          ),
          const SizedBox(height: Espacios.s),
          Wrap(
            spacing: Espacios.s,
            runSpacing: Espacios.xs,
            children: [
              ActionChip(
                avatar: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('Tarjeta aprobada'),
                onPressed: onAprobada,
              ),
              ActionChip(
                avatar: const Icon(Icons.block_rounded, size: 18),
                label: const Text('Tarjeta rechazada'),
                onPressed: onRechazada,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Comprobante extends StatelessWidget {
  const _Comprobante({required this.pago, required this.plan});

  final Pago pago;
  final Plan plan;

  @override
  Widget build(BuildContext context) {
    final textos = Theme.of(context).textTheme;
    final marca = MarcaTarjeta.values
        .where((m) => m.codigo == pago.marca)
        .firstOrNull;
    Widget fila(String etiqueta, String valor) => Padding(
      padding: const EdgeInsets.only(bottom: Espacios.s),
      child: Row(
        children: [
          Expanded(
            child: Text(
              etiqueta,
              style: textos.bodyMedium?.copyWith(color: Colores.tintaSuave),
            ),
          ),
          Text(valor, style: textos.bodyMedium),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Espacios.l),
        const Icon(Icons.check_circle_rounded, color: Colores.acento, size: 64),
        const SizedBox(height: Espacios.m),
        Text(
          '¡Pago aprobado!',
          textAlign: TextAlign.center,
          style: textos.headlineSmall,
        ),
        Text(
          'Tu plan ${plan.nombre} ya está activo por 30 días.',
          textAlign: TextAlign.center,
          style: textos.bodyMedium?.copyWith(color: Colores.tintaSuave),
        ),
        const SizedBox(height: Espacios.l),
        TarjetaApp(
          child: Column(
            children: [
              fila('Comprobante', pago.referencia),
              fila('Plan', plan.nombre),
              fila('Monto', Formatos.dinero(pago.monto)),
              fila(
                'Tarjeta',
                '${marca?.nombre ?? pago.marca} •••• ${pago.ultimos4}',
              ),
              fila('Fecha', Formatos.fecha(pago.fecha)),
            ],
          ),
        ),
        const SizedBox(height: Espacios.l),
        FilledButton(
          onPressed: () => context.go(AppRoutes.planes),
          child: const Text('Listo'),
        ),
      ],
    );
  }
}

/// Agrupa el número de la tarjeta mientras se escribe.
class _FormatoTarjeta extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digitos = Tarjeta.soloDigitos(newValue.text);
    final recortado = digitos.length > 19 ? digitos.substring(0, 19) : digitos;
    final texto = Tarjeta.formatear(recortado);
    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}

/// MM/AA: agrega la barra sola.
class _FormatoVencimiento extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var d = Tarjeta.soloDigitos(newValue.text);
    if (d.length > 4) d = d.substring(0, 4);
    final borrando = newValue.text.length < oldValue.text.length;
    final texto = d.length > 2 || (d.length == 2 && !borrando)
        ? '${d.substring(0, 2)}/${d.substring(2)}'
        : d;
    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}
