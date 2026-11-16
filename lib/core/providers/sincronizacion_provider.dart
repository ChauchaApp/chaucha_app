import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/solicitudes/presentation/providers/agenda_provider.dart';
import '../../features/solicitudes/presentation/providers/detalle_provider.dart';
import '../../features/solicitudes/presentation/providers/feed_provider.dart';
import '../../features/solicitudes/presentation/providers/listas_provider.dart';
import '../../features/solicitudes/presentation/providers/mapa_tecnico_provider.dart';
import '../../features/solicitudes/presentation/providers/visitas_agenda_provider.dart';
import 'core_providers.dart';

final sincronizacionProvider = Provider.autoDispose<void>((ref) {
  final cliente = ref.watch(supabaseClientProvider);
  Timer? espera;

  void refrescar() {
    espera?.cancel();
    espera = Timer(const Duration(milliseconds: 400), () {
      ref
        ..invalidate(misSolicitudesProvider)
        ..invalidate(misTrabajosProvider)
        ..invalidate(feedProvider)
        ..invalidate(solicitudesEnMapaProvider)
        ..invalidate(detalleSolicitudProvider)
        ..invalidate(agendaProvider)
        ..invalidate(visitasRangoProvider)
        ..invalidate(visitasProximasProvider);
    });
  }

  final canal = cliente.channel('sincronizacion-datos');
  for (final tabla in ['solicitudes_servicio', 'cotizaciones']) {
    canal.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: tabla,
      callback: (_) => refrescar(),
    );
  }
  canal.subscribe();

  // En segundo plano el sistema corta el tiempo real y se pierden los
  // cambios: al volver a la app se recarga todo.
  final ciclo = AppLifecycleListener(onResume: refrescar);

  ref.onDispose(() {
    ciclo.dispose();
    espera?.cancel();
    cliente.removeChannel(canal);
  });
});
