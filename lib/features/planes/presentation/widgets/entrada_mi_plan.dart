import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/tarjeta_app.dart';
import '../providers/planes_provider.dart';
import '../views/planes_view.dart';

/// Tarjeta del perfil del técnico: su plan y el acceso a "Planes".
class EntradaMiPlan extends ConsumerWidget {
  const EntradaMiPlan({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textos = Theme.of(context).textTheme;
    final codigo = ref.watch(miPlanProvider).value?.codigo ?? 'gratis';
    final color = colorPlan(codigo);
    final nombre = switch (codigo) {
      'plus' => 'Plus',
      'pro' => 'Pro',
      _ => 'Gratis',
    };
    return TarjetaApp(
      onTap: () => unawaited(context.push(AppRoutes.planes)),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Radios.pequeno),
            ),
            child: Icon(iconoPlan(codigo), color: color),
          ),
          const SizedBox(width: Espacios.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Mi plan: $nombre', style: textos.titleSmall),
                Text(
                  codigo == 'gratis'
                      ? 'Más rango, más oficios y propuestas sin límite.'
                      : 'Mira tus beneficios o cambia de plan.',
                  style: textos.bodySmall?.copyWith(color: Colores.tintaSuave),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Colores.tintaSuave),
        ],
      ),
    );
  }
}
