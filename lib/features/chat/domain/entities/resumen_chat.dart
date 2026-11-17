class ResumenChat {
  const ResumenChat({
    required this.conversacionId,
    required this.otroNombre,
    required this.esMio,
    this.otroId = '',
    this.otroVerificado = false,
    this.oficio,
    this.ultimoMensaje,
    this.enviadoEn,
    this.conversacionIds = const [],
  });

  /// Conversación que se abre al tocar el chat: la del mensaje más reciente.
  final String conversacionId;
  final String otroNombre;

  /// Id del otro usuario (técnico o cliente); vacío si no se conoce.
  final String otroId;

  /// La identidad del otro usuario está verificada.
  final bool otroVerificado;
  final String? oficio;
  final String? ultimoMensaje;
  final DateTime? enviadoEn;
  final bool esMio;

  /// Todas las conversaciones con esta persona (una por solicitud). Vacía
  /// equivale a solo [conversacionId].
  final List<String> conversacionIds;

  /// Ids de todas las conversaciones que agrupa este chat.
  List<String> get ids =>
      conversacionIds.isEmpty ? [conversacionId] : conversacionIds;

  /// Un chat por persona: junta las conversaciones con el mismo [otroId]
  /// (una por solicitud) en una sola fila. [chats] debe venir ordenada de la
  /// más reciente a la más antigua: cada fila conserva los datos de la primera
  /// conversación de esa persona y los oficios de todas, sin repetir.
  static List<ResumenChat> agruparPorPersona(List<ResumenChat> chats) {
    final grupos = <String, List<ResumenChat>>{};
    for (final c in chats) {
      final clave = c.otroId.isEmpty
          ? 'conversacion:${c.conversacionId}'
          : c.otroId;
      (grupos[clave] ??= []).add(c);
    }
    return [
      for (final grupo in grupos.values)
        if (grupo.length == 1)
          grupo.first
        else
          ResumenChat(
            conversacionId: grupo.first.conversacionId,
            otroNombre: grupo.first.otroNombre,
            esMio: grupo.first.esMio,
            otroId: grupo.first.otroId,
            otroVerificado: grupo.first.otroVerificado,
            oficio: _oficios(grupo),
            ultimoMensaje: grupo.first.ultimoMensaje,
            enviadoEn: grupo.first.enviadoEn,
            conversacionIds: [for (final c in grupo) c.conversacionId],
          ),
    ];
  }

  static String? _oficios(List<ResumenChat> grupo) {
    final oficios = {
      for (final c in grupo)
        if (c.oficio != null) c.oficio!,
    };
    return oficios.isEmpty ? null : oficios.join(', ');
  }
}
