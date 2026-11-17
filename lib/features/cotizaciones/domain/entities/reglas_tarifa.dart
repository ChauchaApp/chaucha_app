import '../../../solicitudes/domain/entities/solicitud.dart';
import 'cotizacion.dart';

abstract final class ReglasTarifa {
  /// Precio mínimo de la visita en USD. La base lo exige también
  /// (migración `visita_minima_15`).
  static const double precioMinimoVisita = 15;

  /// Error si [precio] está por debajo del mínimo de la visita, o null.
  static String? validarPrecioVisita(double precio) =>
      precio < precioMinimoVisita
      ? 'El precio mínimo de la visita es '
            '\$${precioMinimoVisita.toStringAsFixed(0)}.'
      : null;

  /// Por qué el técnico no puede enviar el ticket, o null si puede.
  static String? motivoParaNoEnviar({
    required bool soyCliente,
    required Cotizacion? oferta,
    required EstadoSolicitud estadoSolicitud,
  }) {
    if (soyCliente) return 'Solo el técnico puede enviar el ticket.';
    if (oferta == null) return 'No encontramos tu oferta para esta solicitud.';
    if (oferta.estado != EstadoCotizacion.pendiente ||
        !estadoSolicitud.recibeCotizaciones) {
      return 'Esta solicitud ya no admite tickets.';
    }
    if (oferta.tarifaPendiente) {
      return 'Ya enviaste un ticket. Espera a que el cliente responda.';
    }
    return null;
  }

  static bool puedeEnviar({
    required bool soyCliente,
    required Cotizacion? oferta,
    required EstadoSolicitud estadoSolicitud,
  }) =>
      motivoParaNoEnviar(
        soyCliente: soyCliente,
        oferta: oferta,
        estadoSolicitud: estadoSolicitud,
      ) ==
      null;

  /// Solo el cliente confirma o rechaza, y solo un ticket pendiente de una
  /// solicitud que sigue abierta.
  static bool puedeResponder({
    required bool soyCliente,
    required Cotizacion? oferta,
    required EstadoSolicitud estadoSolicitud,
  }) =>
      soyCliente &&
      oferta != null &&
      oferta.tarifaPendiente &&
      estadoSolicitud.recibeCotizaciones;
}
