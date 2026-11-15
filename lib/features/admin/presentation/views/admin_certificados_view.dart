import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../core/utils/refrescar.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/boton_carga.dart';
import '../../../../core/widgets/estado_mensaje.dart';
import '../../../../core/widgets/mensajes.dart';
import '../../../../core/widgets/tarjeta_app.dart';
import '../../../perfil_puntos/domain/entities/certificacion.dart';
import '../providers/certificaciones_admin_provider.dart';
import '../widgets/admin_widgets.dart';

/// Certificados que los técnicos subieron y esperan aprobación. Es lo único
/// de la cuenta del técnico que revisa una persona: la identidad se
/// verifica sola (IA y comparación facial).
class AdminCertificadosView extends ConsumerWidget {
  const AdminCertificadosView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final procesando = ref.watch(revisarCertificacionProvider).isLoading;
    return PantallaAdmin(
      titulo: 'Certificados',
      subtitulo: 'Cada certificado aprobado suma 50 puntos al técnico.',
      onRecargar: () => esperarSinError(
        ref.refresh(certificacionesPendientesProvider.future),
      ),
      children: [
        AsyncValueView<List<Certificacion>>(
          value: ref.watch(certificacionesPendientesProvider),
          onRetry: () => ref.invalidate(certificacionesPendientesProvider),
          onData: (context, lista) {
            if (lista.isEmpty) {
              return const EstadoMensaje(
                tipo: TipoEstado.exito,
                icono: Icons.workspace_premium_outlined,
                titulo: 'Todo al día',
                mensaje: 'No hay certificados por revisar.',
              );
            }
            return Column(
              children: [
                for (final c in lista)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Espacios.l),
                    child: _TarjetaCertificado(
                      certificacion: c,
                      procesando: procesando,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TarjetaCertificado extends ConsumerWidget {
  const _TarjetaCertificado({
    required this.certificacion,
    required this.procesando,
  });

  final Certificacion certificacion;
  final bool procesando;

  Future<void> _revisar(
    BuildContext context,
    WidgetRef ref, {
    required bool aprobado,
  }) async {
    final ok = await ref
        .read(revisarCertificacionProvider.notifier)
        .revisar(certificacion.id, aprobado: aprobado);
    if (!context.mounted) return;
    if (ok) {
      context.mostrarMensaje(
        aprobado ? 'Certificado aprobado.' : 'Certificado rechazado.',
        tipo: TipoMensaje.exito,
      );
    } else if (ref.read(revisarCertificacionProvider) case AsyncError(
      :final error,
    )) {
      context.mostrarMensaje(
        AsyncValueView.mensajeDe(error),
        tipo: TipoMensaje.error,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textos = Theme.of(context).textTheme;
    final c = certificacion;
    final url = c.url;
    return TarjetaApp(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Material(
                color: Colores.superficie,
                borderRadius: BorderRadius.circular(Radios.medio),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: url == null
                      ? null
                      : () => unawaited(
                          c.esPdf
                              ? launchUrl(
                                  Uri.parse(url),
                                  mode: LaunchMode.externalApplication,
                                )
                              : _ampliar(context, url, c.nombre),
                        ),
                  child: SizedBox(
                    width: 112,
                    height: 112,
                    child: url == null
                        ? const Icon(
                            Icons.image_not_supported_outlined,
                            color: Colores.tintaSuave,
                          )
                        : c.esPdf
                        ? const Icon(
                            Icons.picture_as_pdf_outlined,
                            size: 48,
                            color: Colores.primario,
                          )
                        : Image.network(
                            url,
                            fit: BoxFit.cover,
                            semanticLabel: c.nombre,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.broken_image_outlined,
                              color: Colores.tintaSuave,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: Espacios.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.tecnicoNombre ?? 'Técnico',
                      style: textos.titleMedium,
                    ),
                    const SizedBox(height: Espacios.xs),
                    Text(c.nombre, style: textos.titleSmall),
                    Text(
                      c.detalle,
                      style: textos.bodySmall?.copyWith(
                        color: Colores.tintaSuave,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Espacios.l),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: Espacios.m,
            runSpacing: Espacios.s,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colores.error,
                  side: const BorderSide(color: Colores.error),
                ),
                onPressed: procesando
                    ? null
                    : () => unawaited(_revisar(context, ref, aprobado: false)),
                icon: const Icon(Icons.close),
                label: const Text('Rechazar'),
              ),
              SizedBox(
                width: 220,
                child: BotonCarga(
                  texto: 'Aprobar',
                  icono: Icons.check,
                  cargando: procesando,
                  onPressed: () =>
                      unawaited(_revisar(context, ref, aprobado: true)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Muestra la imagen grande, con zoom.
Future<void> _ampliar(BuildContext context, String url, String etiqueta) {
  return showDialog<void>(
    context: context,
    builder: (dialogo) => Dialog(
      backgroundColor: Colores.tinta,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          InteractiveViewer(
            maxScale: 5,
            child: Image.network(
              url,
              fit: BoxFit.contain,
              semanticLabel: etiqueta,
            ),
          ),
          Positioned(
            top: Espacios.s,
            right: Espacios.s,
            child: IconButton.filledTonal(
              tooltip: 'Cerrar',
              onPressed: () => Navigator.of(dialogo).pop(),
              icon: const Icon(Icons.close),
            ),
          ),
        ],
      ),
    ),
  );
}
