import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/utils/formatos.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/mensajes.dart';
import '../../../../core/widgets/pantalla_secundaria.dart';
import '../../../../core/widgets/pildora.dart';
import '../../../../core/widgets/scroll_pagina.dart';
import '../../../../core/widgets/tarjeta_app.dart';
import '../../domain/entities/plan.dart';
import '../providers/planes_provider.dart';

class PlanesView extends ConsumerWidget {
  const PlanesView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planes = ref.watch(planesProvider);
    final miPlan = ref.watch(miPlanProvider).value;
    final cambiando = ref.watch(suscribirseProvider).isLoading;
    final textos = Theme.of(context).textTheme;

    Future<void> elegir(Plan plan) async {
      // Los planes pagados pasan por la pasarela (simulada).
      if (!plan.esGratis) {
        unawaited(context.push(AppRoutes.pagarPlan(plan.codigo)));
        return;
      }
      final ok = await _confirmar(context, plan);
      if (!ok || !context.mounted) return;
      final cambiado = await ref
          .read(suscribirseProvider.notifier)
          .volverAGratis();
      if (!context.mounted) return;
      if (cambiado) {
        context.mostrarMensaje(
          'Volviste al plan Gratis.',
          tipo: TipoMensaje.exito,
        );
      } else {
        final error = ref.read(suscribirseProvider).error;
        context.mostrarMensaje(
          error is AppFailure ? error.message : 'No se pudo cambiar el plan.',
          tipo: TipoMensaje.error,
        );
      }
    }

    return PantallaSecundaria(
      titulo: 'Planes',
      cuerpo: AsyncValueView<List<Plan>>(
        value: planes,
        onRetry: () => ref.invalidate(planesProvider),
        onData: (context, lista) => ListaDePagina(
          padding: const EdgeInsets.all(Espacios.l),
          children: [
            Text('Elige cómo quieres crecer', style: textos.titleLarge),
            const SizedBox(height: Espacios.xs),
            Text(
              'Chat, agenda y calificaciones están en todos los planes.',
              style: textos.bodyMedium?.copyWith(color: Colores.tintaSuave),
            ),
            if (miPlan != null) ...[
              const SizedBox(height: Espacios.m),
              _Uso(miPlan: miPlan, planes: lista),
            ],
            const SizedBox(height: Espacios.l),
            for (final plan in lista) ...[
              _TarjetaPlan(
                plan: plan,
                actual: (miPlan?.codigo ?? 'gratis') == plan.codigo,
                cambiando: cambiando,
                onElegir: () => elegir(plan),
              ),
              const SizedBox(height: Espacios.m),
            ],
            Text(
              'Los planes duran 30 días. El pago es una demostración: se usa '
              'una tarjeta de prueba y no se cobra nada.',
              style: textos.bodySmall?.copyWith(color: Colores.tintaSuave),
            ),
          ],
        ),
      ),
    );
  }

  static Future<bool> _confirmar(BuildContext context, Plan plan) async {
    final si = await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: const Text('¿Volver al plan Gratis?'),
        content: Text(
          'Pierdes los beneficios de tu plan actual. Si tienes más de '
          '${plan.oficiosMax} oficios, los que sobren quedan pausados hasta '
          'que elijas cuáles mantener.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogo).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogo).pop(true),
            child: const Text('Volver a Gratis'),
          ),
        ],
      ),
    );
    return si ?? false;
  }
}

/// "Este mes: 4 de 15 propuestas" y la fecha de vencimiento.
class _Uso extends StatelessWidget {
  const _Uso({required this.miPlan, required this.planes});

  final MiPlan miPlan;
  final List<Plan> planes;

  @override
  Widget build(BuildContext context) {
    final textos = Theme.of(context).textTheme;
    final plan = planes.where((p) => p.codigo == miPlan.codigo).firstOrNull;
    final tope = plan?.cotizacionesMes;
    final fin = miPlan.fin;
    return TarjetaApp(
      color: Colores.cieloSuave,
      conBorde: false,
      child: Row(
        children: [
          const Icon(Icons.insights_rounded, color: Colores.cieloOscuro),
          const SizedBox(width: Espacios.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tu plan: ${plan?.nombre ?? 'Gratis'}',
                  style: textos.titleSmall,
                ),
                Text(
                  [
                    tope == null
                        ? '${miPlan.cotizacionesUsadas} propuestas este mes'
                        : '${miPlan.cotizacionesUsadas} de $tope propuestas '
                              'este mes',
                    if (fin != null) 'vence el ${Formatos.fechaCorta(fin)}',
                  ].join(' · '),
                  style: textos.bodySmall?.copyWith(color: Colores.tintaSuave),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TarjetaPlan extends StatelessWidget {
  const _TarjetaPlan({
    required this.plan,
    required this.actual,
    required this.cambiando,
    required this.onElegir,
  });

  final Plan plan;
  final bool actual;
  final bool cambiando;
  final VoidCallback onElegir;

  @override
  Widget build(BuildContext context) {
    final textos = Theme.of(context).textTheme;
    final color = colorPlan(plan.codigo);
    return TarjetaApp(
      colorBorde: actual ? color : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(iconoPlan(plan.codigo), color: color),
              const SizedBox(width: Espacios.s),
              Expanded(child: Text(plan.nombre, style: textos.titleMedium)),
              if (actual) Pildora(texto: 'Tu plan', color: color),
            ],
          ),
          const SizedBox(height: Espacios.xs),
          Text(
            plan.precioTexto,
            style: textos.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: Espacios.m),
          for (final beneficio in [
            plan.cotizacionesTexto,
            plan.rangoTexto,
            plan.oficiosTexto,
            plan.posicionTexto,
            if (!plan.esGratis) 'Sello ${plan.nombre} en tu perfil',
            if (!plan.esGratis) 'Estadísticas completas de tu reputación',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: Espacios.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_rounded, size: 18, color: color),
                  const SizedBox(width: Espacios.s),
                  Expanded(child: Text(beneficio, style: textos.bodyMedium)),
                ],
              ),
            ),
          const SizedBox(height: Espacios.s),
          SizedBox(
            width: double.infinity,
            child: actual
                ? const OutlinedButton(
                    onPressed: null,
                    child: Text('Es tu plan actual'),
                  )
                : FilledButton(
                    onPressed: cambiando ? null : onElegir,
                    child: Text(
                      plan.esGratis
                          ? 'Volver a Gratis'
                          : 'Activar ${plan.nombre}',
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Color de cada plan. El sello pagado usa estos colores, distintos del
/// azul de "Verificado", para no confundirse con un sello de confianza.
Color colorPlan(String codigo) => switch (codigo) {
  'plus' => Colores.avisoOscuro,
  'pro' => Colores.primarioVivo,
  _ => Colores.tintaSuave,
};

IconData iconoPlan(String codigo) => switch (codigo) {
  'plus' => Icons.workspace_premium_rounded,
  'pro' => Icons.star_rounded,
  _ => Icons.person_outline_rounded,
};
