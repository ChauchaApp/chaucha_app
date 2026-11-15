import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/router/app_routes.dart';
import '../../domain/entities/plan.dart';

/// Si [error] es un límite del plan, abre un diálogo que lleva a "Planes" y
/// devuelve true. Si no, devuelve false y el llamador muestra el error como
/// siempre.
bool ofrecerPlanSiEsLimite(BuildContext context, Object? error) {
  final limite = error is AppFailure
      ? LimitePlan.desdeCodigo(error.code)
      : null;
  if (limite == null) return false;
  unawaited(
    showDialog<void>(
      context: context,
      builder: (dialogo) => AlertDialog(
        icon: const Icon(Icons.workspace_premium_rounded),
        title: const Text('Llegaste al límite de tu plan'),
        content: Text(
          '${(error! as AppFailure).message}\n\n${limite.sugerencia}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogo).pop(),
            child: const Text('Ahora no'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogo).pop();
              unawaited(context.push(AppRoutes.planes));
            },
            child: const Text('Ver planes'),
          ),
        ],
      ),
    ),
  );
  return true;
}
